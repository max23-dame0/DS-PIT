#!/usr/bin/env python3
"""Deterministic analyzer for E2E-01 STM32F103 Cortex-M3 hardware measurements."""
import json
import math
import re
import struct
from pathlib import Path

V_NOM = 3.3
I_OFF_MA = 36.0
I_ON_MA = 50.0
HOP_S = 2.0


def percentile(vals, q):
    s = sorted(vals)
    if not s:
        return 0.0
    pos = (len(s) - 1) * q
    lo = int(math.floor(pos))
    hi = min(len(s) - 1, lo + 1)
    frac = pos - lo
    return s[lo] * (1.0 - frac) + s[hi] * frac


def stats_ms(cycles_list, clk_hz):
    ms = [c * 1e3 / clk_hz for c in cycles_list]
    return {
        "n": len(ms),
        "mean_ms": round(sum(ms) / len(ms), 4),
        "p95_ms": round(percentile(ms, 0.95), 4),
        "max_ms": round(max(ms), 4),
        "min_ms": round(min(ms), 4),
    }


def load_trace_eval(trace_path: Path):
    data = trace_path.read_bytes()
    magic, ds_id, n_win, n_eval, nb, k_dim = struct.unpack_from("<6I", data, 0)
    assert magic == 0x45324554
    n_x25 = 13000
    skip_doubles = 4 * n_x25 + 5 * n_win * nb + 4 * n_win * k_dim + n_win
    off = 24 + 8 * skip_doubles
    est_b = struct.unpack_from(f"<{n_eval}d", data, off); off += 8 * n_eval
    es_b = struct.unpack_from(f"<{n_eval}d", data, off); off += 8 * n_eval
    est_c2 = struct.unpack_from(f"<{n_eval}d", data, off); off += 8 * n_eval
    es_c2 = struct.unpack_from(f"<{n_eval}d", data, off); off += 8 * n_eval
    gt = struct.unpack_from(f"<{n_eval}d", data, off); off += 8 * n_eval
    msk = struct.unpack_from(f"<{n_eval}d", data, off)
    return {
        "est_b": est_b,
        "es_b": es_b,
        "est_c2": est_c2,
        "es_c2": es_c2,
        "gt": gt,
        "msk": msk,
    }


def parse_fw_map(map_path: Path):
    txt = map_path.read_text(encoding="utf-8", errors="replace")
    sec = None
    cur_sub = None
    sections = {}
    table_syms = {}
    for line in txt.splitlines():
        m_top = re.match(r"^(\.[A-Za-z0-9_.]+)(?:\s+0x[0-9a-fA-F]+\s+0x[0-9a-fA-F]+.*)?$", line)
        if m_top:
            sec = m_top.group(1)
            cur_sub = None
            continue
        if sec not in (".isr_vector", ".text", ".data", ".bss", ".mailbox", ".ARM.exidx"):
            continue
        m_sub = re.match(r"^\s+(\.[^\s]+)\s*$", line)
        if m_sub:
            cur_sub = m_sub.group(1)
            continue
        m_ent = re.match(r"^\s*(\.[^\s]+)?\s+0x[0-9a-fA-F]+\s+0x([0-9a-fA-F]+)\s+(.+)$", line)
        if m_ent:
            sub = m_ent.group(1) or cur_sub or ""
            sz = int(m_ent.group(2), 16)
            obj = m_ent.group(3).strip()
            cur_sub = None
            if sz == 0 or obj.startswith("*fill*"):
                continue
            if "(" in obj:
                lib = Path(obj.split("(")[0]).name
                member = obj.split("(")[1].rstrip(")")
                tag = f"{lib}:{member}"
            else:
                tag = Path(obj).name
            d = sections.setdefault(sec, {})
            d[tag] = d.get(tag, 0) + sz
            if tag == "e2e_tables.o" and sub.startswith(".rodata."):
                sym = sub[len(".rodata.") :]
                table_syms[sym] = table_syms.get(sym, 0) + sz

    text_map = sections.get(".text", {})
    isr_sz = sum(sections.get(".isr_vector", {}).values())
    data_map = sections.get(".data", {})
    bss_map = sections.get(".bss", {})
    mb_map = sections.get(".mailbox", {})

    def sum_lib(prefix):
        return sum(v for k, v in text_map.items() if k.startswith(prefix))

    s1_tbl = table_syms.get("SOS_DALIA", 0) + table_syms.get("SOS_WESAD", 0) + \
             table_syms.get("RESAMP_H_DALIA", 0) + table_syms.get("RESAMP_H_WESAD", 0)
    s2_tbl = table_syms.get("TWID_RE", 0) + table_syms.get("TWID_IM", 0)
    s3_tbl = table_syms.get("INTERP_W", 0) + table_syms.get("INTERP_IDX", 0) + table_syms.get("TAPER", 0)
    s5_tbl = table_syms.get("MCU_A", 0) + table_syms.get("MCU_G", 0)

    lib_m = sum_lib("libm.a:") + sum_lib("libgcc.a:") + sum_lib("libc_nano.a:")
    if lib_m == 0:
        lib_m = sum(v for k, v in text_map.items() if ":" in k)

    harness_flash = isr_sz + text_map.get("startup.o", 0) + text_map.get("main.o", 0) + sum(data_map.values())
    algo_flash_modules = {
        "S1_frontend": text_map.get("fe_filter.o", 0) + text_map.get("fe_resample.o", 0) + s1_tbl,
        "S2_spectral": text_map.get("spec.o", 0) + s2_tbl,
        "S3_enhance": text_map.get("enhance.o", 0) + s3_tbl,
        "S4_lbp": text_map.get("lbp.o", 0),
        "S5_viterbi": text_map.get("decode.o", 0) + s5_tbl,
        "S6_smooth": text_map.get("smooth.o", 0),
        "Coordinator_dspit_e2e": text_map.get("dspit_e2e.o", 0),
        "Shared_libm_softfloat_libc": lib_m,
    }
    algo_flash_total = sum(algo_flash_modules.values())
    total_flash = isr_sz + sum(text_map.values()) + sum(data_map.values())

    return {
        "table_rodata_bytes": table_syms,
        "algo_flash_modules_bytes": algo_flash_modules,
        "algo_flash_total_bytes": algo_flash_total,
        "harness_flash_bytes": harness_flash,
        "total_firmware_flash_bytes": total_flash,
        "bss_total_bytes": sum(bss_map.values()),
        "data_total_bytes": sum(data_map.values()),
        "mailbox_bytes": sum(mb_map.values()),
    }


def main():
    root = Path(__file__).resolve().parent
    res_dir = root / "results"
    fw_info = parse_fw_map(root / "fw" / "fw.map")

    canonical_labels = ["s1_r1", "s2", "s3", "ws1", "ws2"]
    all_labels = ["s1_r1", "s1_r2", "s1_r3", "s2", "s3", "ws1", "ws2", "s1_dense"]

    runs = {}
    for lbl in all_labels:
        p = res_dir / f"e2e_run_{lbl}.json"
        if not p.exists():
            raise FileNotFoundError(f"Missing run file: {p}")
        runs[lbl] = json.loads(p.read_text(encoding="utf-8"))

    # Repeatability check (s1_r1 vs s1_r2 vs s1_r3)
    rep_base = runs["s1_r1"]
    rep_checks = []
    for lbl in ("s1_r2", "s1_r3"):
        r = runs[lbl]
        hr_exact = (r["est"] == rep_base["est"]) and (r["es"] == rep_base["es"]) and (r["tau"] == rep_base["tau"])
        max_cyc_diff = max(
            abs(a["cyc_total"] - b["cyc_total"])
            for a, b in zip(r["blocks"], rep_base["blocks"])
        )
        mean_cyc = sum(b["cyc_total"] for b in rep_base["blocks"]) / len(rep_base["blocks"])
        rep_checks.append({
            "label": lbl,
            "hr_and_tau_identical": hr_exact,
            "max_block_cycle_diff": max_cyc_diff,
            "rel_cycle_drift_pct": round(100.0 * max_cyc_diff / mean_cyc, 4),
        })

    # Dense vs banded on s1
    s1b = runs["s1_r1"]
    s1d = runs["s1_dense"]
    steady_b = [b for b in s1b["blocks"] if b["win_ran"]]
    steady_d = [b for b in s1d["blocks"] if b["win_ran"]]
    s5_b_ms = sum(b["cyc_s"][4] for b in steady_b) / len(steady_b) * 1e3 / s1b["clk_hz"]
    s5_d_ms = sum(b["cyc_s"][4] for b in steady_d) / len(steady_d) * 1e3 / s1d["clk_hz"]
    tot_b_ms = sum(b["cyc_total"] for b in steady_b) / len(steady_b) * 1e3 / s1b["clk_hz"]
    tot_d_ms = sum(b["cyc_total"] for b in steady_d) / len(steady_d) * 1e3 / s1d["clk_hz"]
    dense_cmp = {
        "s1_est_match_banded_vs_dense": f"{sum(a == b for a, b in zip(s1b['est'], s1d['est']))}/{len(s1b['est'])}",
        "s1_es_match_banded_vs_dense": f"{sum(a == b for a, b in zip(s1b['es'], s1d['es']))}/{len(s1b['es'])}",
        "s5_banded_mean_ms": round(s5_b_ms, 4),
        "s5_dense_mean_ms": round(s5_d_ms, 4),
        "s5_speedup": round(s5_d_ms / s5_b_ms, 2),
        "total_banded_mean_ms": round(tot_b_ms, 4),
        "total_dense_mean_ms": round(tot_d_ms, 4),
    }

    # Per-record analysis for canonical 5 runs
    stage_names = ["S1_frontend", "S2_spectral", "S3_enhance", "S4_lbp", "S5_viterbi", "S6_smooth"]
    per_record = []
    pooled_steady_cyc = {k: [] for k in stage_names + ["total"]}
    dalia_steady_cyc = {k: [] for k in stage_names + ["total"]}
    wesad_steady_cyc = {k: [] for k in stage_names + ["total"]}
    cold_cyc = []
    stack_peaks = []
    tot_agree_b = 0
    tot_agree_c2 = 0
    tot_eval = 0
    tot_mcu_host_es = 0
    tot_mcu_host_est = 0
    mae_mcu_list = []
    mae_b_list = []
    mae_c2_list = []

    for lbl in canonical_labels:
        r = runs[lbl]
        tag = r["tag"]
        clk = r["clk_hz"]
        tr = load_trace_eval(root / "golden" / f"{tag}_trace_f64.bin")
        n_ev = len(r["es"])
        tot_eval += n_ev

        # Host f32 exact check
        mh_est = int(r["host_match_est"].split("/")[0])
        mh_es = int(r["host_match_es"].split("/")[0])
        tot_mcu_host_est += mh_est
        tot_mcu_host_es += mh_es

        # Check B & C comparisons
        ag_b = sum(1 for a, b in zip(r["es"], tr["es_b"]) if a == b)
        ag_c2 = sum(1 for a, b in zip(r["es"], tr["es_c2"]) if a == b)
        max_d_c2 = max(abs(a - b) for a, b in zip(r["es"], tr["es_c2"]))
        tot_agree_b += ag_b
        tot_agree_c2 += ag_c2

        valid_idx = [i for i, m in enumerate(tr["msk"]) if m > 0.5]
        mae_mcu = sum(abs(tr["gt"][i] - r["es"][i]) for i in valid_idx) / len(valid_idx)
        mae_b = sum(abs(tr["gt"][i] - tr["es_b"][i]) for i in valid_idx) / len(valid_idx)
        mae_c2 = sum(abs(tr["gt"][i] - tr["es_c2"][i]) for i in valid_idx) / len(valid_idx)
        mae_mcu_list.append(mae_mcu)
        mae_b_list.append(mae_b)
        mae_c2_list.append(mae_c2)

        steady_blks = [b for b in r["blocks"] if b["win_ran"]]
        cold_blks = [b for b in r["blocks"] if not b["win_ran"]]
        cold_cyc.extend([b["cyc_total"] for b in cold_blks])
        stack_peaks.append(r["stack_peak_bytes"])

        rec_stages = {}
        for si, sname in enumerate(stage_names):
            vals = [b["cyc_s"][si] for b in steady_blks]
            rec_stages[sname] = stats_ms(vals, clk)
            pooled_steady_cyc[sname].extend(vals)
            (dalia_steady_cyc if r["ds_id"] == 0 else wesad_steady_cyc)[sname].extend(vals)
        tot_vals = [b["cyc_total"] for b in steady_blks]
        rec_stages["total"] = stats_ms(tot_vals, clk)
        pooled_steady_cyc["total"].extend(tot_vals)
        (dalia_steady_cyc if r["ds_id"] == 0 else wesad_steady_cyc)["total"].extend(tot_vals)

        per_record.append({
            "label": lbl,
            "tag": tag,
            "dataset": "PPG-DaLiA" if r["ds_id"] == 0 else "WESAD",
            "clk_hz": clk,
            "n_blocks": r["n_blocks"],
            "n_steady_hops": len(steady_blks),
            "n_cold_hops": len(cold_blks),
            "host_match_est": r["host_match_est"],
            "host_match_es": r["host_match_es"],
            "host_tau_maxdiff": r["host_tau_maxdiff"],
            "vs_SOS_f64_es_agree": f"{ag_b}/{n_ev}",
            "vs_cache2_es_agree": f"{ag_c2}/{n_ev}",
            "vs_cache2_es_agree_pct": round(100.0 * ag_c2 / n_ev, 2),
            "vs_cache2_max_abs_diff_bpm": round(max_d_c2, 3),
            "mae_mcu_f32_bpm": round(mae_mcu, 4),
            "mae_sos_f64_bpm": round(mae_b, 4),
            "mae_cache2_bpm": round(mae_c2, 4),
            "mae_diff_vs_cache2_bpm": round(mae_mcu - mae_c2, 4),
            "stack_peak_bytes": r["stack_peak_bytes"],
            "stages_steady": rec_stages,
        })

    def agg_stages(cyc_dict, clk_hz=72000000):
        out = {}
        tot_mean = sum(cyc_dict["total"]) / len(cyc_dict["total"]) * 1e3 / clk_hz
        for k in stage_names + ["total"]:
            st = stats_ms(cyc_dict[k], clk_hz)
            st["pct_of_total"] = round(100.0 * st["mean_ms"] / tot_mean, 2)
            out[k] = st
        out["total"]["duty_factor_pct_at_2s"] = round(100.0 * out["total"]["mean_ms"] / 2000.0, 2)
        return out

    pooled_timing = agg_stages(pooled_steady_cyc)
    dalia_timing = agg_stages(dalia_steady_cyc)
    wesad_timing = agg_stages(wesad_steady_cyc)

    # Energy estimate (ESTIMATE ONLY, datasheet typical currents at 72 MHz)
    t_s = pooled_timing["total"]["mean_ms"] * 1e-3
    e_lo_mj = V_NOM * I_OFF_MA * t_s
    e_hi_mj = V_NOM * I_ON_MA * t_s
    p_lo_mw = e_lo_mj / HOP_S
    p_hi_mw = e_hi_mj / HOP_S

    # RAM attribution using s_sizes from MCU
    sz = runs["s1_r1"]["s_sizes"]
    algo_static_ram = runs["s1_r1"]["algo_ram_bytes"]
    stack_max = max(stack_peaks)
    ram_breakdown = {
        "S1_frontend_bytes": sz[0],
        "S2_spectral_bytes": sz[1],
        "S3_enhance_bytes": sz[2],
        "S4_lbp_bytes": sz[3],
        "S5_viterbi_bytes": sz[4],
        "S6_smooth_bytes": sz[5],
        "Coordinator_and_interstage_buffers_bytes": sz[6],
        "algorithm_static_ram_bytes": algo_static_ram,
        "algorithm_static_ram_kb_1024": round(algo_static_ram / 1024.0, 2),
        "stack_high_water_bytes": stack_max,
        "stack_high_water_kb_1024": round(stack_max / 1024.0, 2),
        "algorithm_peak_ram_bytes": algo_static_ram + stack_max,
        "algorithm_peak_ram_kb_1024": round((algo_static_ram + stack_max) / 1024.0, 2),
        "harness_mailbox_and_libc_data_bytes": fw_info["mailbox_bytes"] + fw_info["data_total_bytes"],
        "total_firmware_sram_bytes": algo_static_ram + fw_info["mailbox_bytes"] + fw_info["data_total_bytes"] + stack_max,
    }

    summary = {
        "experiment": "E2E-01",
        "date": "2026-11-24",
        "scope": "Complete DS-PIT DSP chain (IIR bandpass SOS, polyphase resampling, 1024-pt real-packed FFT, two-branch ratio enhancement, causal LBP reliability temperature, fixed-lag banded Viterbi W=13 D=3, 3-pt median smoothing) in float32 soft-float on STM32F103 Cortex-M3 @72 MHz, fed replayed benchmark recordings via SWD (excluding live optical/ACC acquisition and wireless radio).",
        "platform": {
            "board": "STM32-Mini V3.1 (Mcudev)",
            "mcu": "STM32F103-compatible, Cortex-M3 r1p1, no FPU",
            "clk_hz": runs["s1_r1"]["clk_hz"],
            "cfgr": runs["s1_r1"]["cfgr"],
            "flash_kib": 256,
            "sram_measured_kib": 64,
        },
        "latency_delay_accounting": {
            "front_end_resample_group_delay_s": 0.4,
            "wesad_acc_interp_lag_s": 0.03125,
            "decoder_lookahead_s": 4.0,
            "median3_lookahead_s": 2.0,
            "total_causal_algorithmic_lookahead_s": 6.4,
            "nominal_initial_window_wait_with_centered_median_s": 14.4,
        },
        "memory_and_flash": {
            "ram": ram_breakdown,
            "flash": fw_info,
        },
        "timing_pooled_5rec": pooled_timing,
        "timing_dalia_3rec": dalia_timing,
        "timing_wesad_2rec": wesad_timing,
        "timing_cold_start_buffering_only": stats_ms(cold_cyc, 72000000),
        "energy_estimate_datasheet_72mhz": {
            "status": "ESTIMATE ONLY (NOT measured; V=3.3V * I_typ[36..50mA] * measured_t)",
            "t_mean_ms": pooled_timing["total"]["mean_ms"],
            "e_per_hop_lo_mj": round(e_lo_mj, 2),
            "e_per_hop_hi_mj": round(e_hi_mj, 2),
            "p_avg_lo_mw_at_2s": round(p_lo_mw, 2),
            "p_avg_hi_mw_at_2s": round(p_hi_mw, 2),
        },
        "fidelity_summary": {
            "mcu_vs_host_f32_est": f"{tot_mcu_host_est}/{tot_eval}",
            "mcu_vs_host_f32_es": f"{tot_mcu_host_es}/{tot_eval}",
            "mcu_vs_sos_f64_es": f"{tot_agree_b}/{tot_eval} ({100.0*tot_agree_b/tot_eval:.2f}%)",
            "mcu_vs_cache2_es": f"{tot_agree_c2}/{tot_eval} ({100.0*tot_agree_c2/tot_eval:.2f}%)",
            "mean_5rec_mae_mcu_f32_bpm": round(sum(mae_mcu_list) / len(mae_mcu_list), 4),
            "mean_5rec_mae_sos_f64_bpm": round(sum(mae_b_list) / len(mae_b_list), 4),
            "mean_5rec_mae_cache2_bpm": round(sum(mae_c2_list) / len(mae_c2_list), 4),
            "mean_5rec_mae_diff_vs_cache2_bpm": round(sum(mae_mcu_list) / len(mae_mcu_list) - sum(mae_c2_list) / len(mae_c2_list), 4),
        },
        "repeatability_s1_x3": rep_checks,
        "banded_vs_dense_s1": dense_cmp,
        "per_record": per_record,
    }

    out_path = res_dir / "results_summary_e2e.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Wrote {out_path}")
    print(f"MCU vs Host f32: est={summary['fidelity_summary']['mcu_vs_host_f32_est']}, es={summary['fidelity_summary']['mcu_vs_host_f32_es']}")
    print(f"MCU vs cache2:   {summary['fidelity_summary']['mcu_vs_cache2_es']} | MAE {summary['fidelity_summary']['mean_5rec_mae_mcu_f32_bpm']} vs {summary['fidelity_summary']['mean_5rec_mae_cache2_bpm']} BPM")
    print(f"Pooled steady total: mean={pooled_timing['total']['mean_ms']} ms, P95={pooled_timing['total']['p95_ms']} ms, max={pooled_timing['total']['max_ms']} ms (duty={pooled_timing['total']['duty_factor_pct_at_2s']}%)")
    print(f"DaLiA total mean={dalia_timing['total']['mean_ms']} ms | WESAD total mean={wesad_timing['total']['mean_ms']} ms")
    print(f"Algo static RAM={ram_breakdown['algorithm_static_ram_kb_1024']} KiB, Stack={ram_breakdown['stack_high_water_kb_1024']} KiB, Algo Flash={fw_info['algo_flash_total_bytes']/1024:.2f} KiB, Total Flash={fw_info['total_firmware_flash_bytes']/1024:.2f} KiB")


if __name__ == "__main__":
    main()

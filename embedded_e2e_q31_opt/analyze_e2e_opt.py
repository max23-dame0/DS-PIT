#!/usr/bin/env python3
"""Analyze E2E-02 optimization benchmarks (f32_opt, q31_opt, m4f static) vs E2E-01."""
import json
import math
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASELINE_SUMMARY = ROOT.parent / "embedded_e2e_20261124" / "results" / "results_summary_e2e.json"
GOLDEN_DIR = ROOT.parent / "embedded_e2e_20261124" / "golden"
E2E01_RESULTS_DIR = ROOT.parent / "embedded_e2e_20261124" / "results"

STAGE_NAMES = [
    "S1_frontend",
    "S2_spectral",
    "S3_enhance",
    "S4_lbp",
    "S5_viterbi",
    "S6_smooth",
]

RECORDS = [
    ("s1", "PPG-DaLiA S1", "PPG-DaLiA"),
    ("s2", "PPG-DaLiA S2", "PPG-DaLiA"),
    ("s3", "PPG-DaLiA S3", "PPG-DaLiA"),
    ("ws1", "WESAD S2", "WESAD"),
    ("ws2", "WESAD S3", "WESAD"),
]


def percentile(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    pos = (len(sorted_vals) - 1) * q
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = pos - lo
    return sorted_vals[lo] * (1.0 - frac) + sorted_vals[hi] * frac


def summarize_ms(vals):
    if not vals:
        return {"n": 0, "mean_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "min_ms": 0.0}
    s = sorted(vals)
    return {
        "n": len(s),
        "mean_ms": round(sum(s) / len(s), 4),
        "p95_ms": round(percentile(s, 0.95), 4),
        "max_ms": round(s[-1], 4),
        "min_ms": round(s[0], 4),
    }


def load_run(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    clk_ms_div = data["clk_hz"] / 1000.0
    for blk in data["blocks"]:
        blk["s_ms"] = [c / clk_ms_div for c in blk["cyc_s"]]
        blk["total_ms"] = blk["cyc_total"] / clk_ms_div
    return data


def load_eval_refs(tag: str):
    """Parse E2E-01 golden trace_f64.bin and host_f32_<tag>.bin using the verified host layout."""
    tr_path = GOLDEN_DIR / f"{tag}_trace_f64.bin"
    f32_path = E2E01_RESULTS_DIR / f"host_f32_{tag}.bin"

    with tr_path.open("rb") as ft:
        hdr = struct.unpack("<6I", ft.read(24))
        n_win, n_eval, nb, k_dim = hdr[2], hdr[3], hdr[4], hdr[5]
        n_x25 = 13000
        skip_dbl = 4 * n_x25 + 5 * n_win * nb + 4 * n_win * k_dim + n_win
        ft.seek(24 + skip_dbl * 8)
        tail = struct.unpack(f"<{6 * n_eval}d", ft.read(6 * n_eval * 8))

    est_b = list(tail[0 * n_eval : 1 * n_eval])
    es_b = list(tail[1 * n_eval : 2 * n_eval])
    est_c2 = list(tail[2 * n_eval : 3 * n_eval])
    es_c2 = list(tail[3 * n_eval : 4 * n_eval])
    gt = list(tail[4 * n_eval : 5 * n_eval])
    msk = list(tail[5 * n_eval : 6 * n_eval])

    with f32_path.open("rb") as ff:
        raw_f32 = struct.unpack(f"<{2 * n_eval}f", ff.read(2 * n_eval * 4))
    e2e01_est = list(raw_f32[:n_eval])
    e2e01_es = list(raw_f32[n_eval:])

    return {
        "n_eval": n_eval,
        "est_b": est_b,
        "es_b": es_b,
        "est_c2": est_c2,
        "es_c2": es_c2,
        "gt": gt,
        "msk": msk,
        "e2e01_est": e2e01_est,
        "e2e01_es": e2e01_es,
    }


def eval_record_fidelity(run_data, tag: str, host_bin_path: Path):
    ref = load_eval_refs(tag)
    n_eval = ref["n_eval"]

    with host_bin_path.open("rb") as fh:
        raw_h = struct.unpack(f"<{2 * n_eval}f", fh.read(2 * n_eval * 4))
    host_est = list(raw_h[:n_eval])
    host_es = list(raw_h[n_eval:])

    mcu_est = run_data["est"]
    mcu_es = run_data["es"]
    assert len(mcu_est) == n_eval and len(mcu_es) == n_eval, f"len mismatch for {tag}"

    host_eq_est = sum(1 for a, b in zip(mcu_est, host_est) if a == b)
    host_eq_es = sum(1 for a, b in zip(mcu_es, host_es) if a == b)
    eq_e2e01 = sum(1 for a, b in zip(mcu_es, ref["e2e01_es"]) if a == b)
    eq_f64 = sum(1 for a, b in zip(mcu_es, ref["es_b"]) if a == b)
    eq_c2 = sum(1 for a, b in zip(mcu_es, ref["es_c2"]) if a == b)
    maxd_c2 = max(abs(a - b) for a, b in zip(mcu_es, ref["es_c2"]))

    valid_idx = [i for i, m in enumerate(ref["msk"]) if m > 0.5]
    mae_mcu = sum(abs(ref["gt"][i] - mcu_es[i]) for i in valid_idx) / len(valid_idx)
    mae_c2 = sum(abs(ref["gt"][i] - ref["es_c2"][i]) for i in valid_idx) / len(valid_idx)
    mae_sos_f64 = sum(abs(ref["gt"][i] - ref["es_b"][i]) for i in valid_idx) / len(valid_idx)

    return {
        "n_eval": n_eval,
        "n_valid_mask": len(valid_idx),
        "host_match_est": f"{host_eq_est}/{n_eval}",
        "host_match_es": f"{host_eq_es}/{n_eval}",
        "host_tau_maxdiff": run_data["host_tau_maxdiff"],
        "vs_e2e01_es_count": eq_e2e01,
        "vs_e2e01_es_agree": f"{eq_e2e01}/{n_eval}",
        "vs_e2e01_es_agree_pct": round(100.0 * eq_e2e01 / n_eval, 2),
        "vs_SOS_f64_es_count": eq_f64,
        "vs_SOS_f64_es_agree": f"{eq_f64}/{n_eval}",
        "vs_cache2_es_count": eq_c2,
        "vs_cache2_es_agree": f"{eq_c2}/{n_eval}",
        "vs_cache2_es_agree_pct": round(100.0 * eq_c2 / n_eval, 2),
        "vs_cache2_max_abs_diff_bpm": round(maxd_c2, 2),
        "mae_mcu_bpm": round(mae_mcu, 4),
        "mae_sos_f64_bpm": round(mae_sos_f64, 4),
        "mae_cache2_bpm": round(mae_c2, 4),
        "mae_diff_vs_cache2_bpm": round(mae_mcu - mae_c2, 4),
        "_raw_mae_mcu": mae_mcu,
        "_raw_mae_c2": mae_c2,
        "_raw_mae_sos_f64": mae_sos_f64,
    }


def compute_stage_stats(runs, baseline_timing=None, steady=True):
    blocks = [b for r in runs for b in r["blocks"] if (b["win_ran"] == 1 if steady else b["win_ran"] == 0)]
    tot_vals = [b["total_ms"] for b in blocks]
    tot_mean = sum(tot_vals) / len(tot_vals)
    out = {}
    for idx, name in enumerate(STAGE_NAMES):
        s_vals = [b["s_ms"][idx] for b in blocks]
        st = summarize_ms(s_vals)
        mean_val = sum(s_vals) / len(s_vals)
        st["pct_of_total"] = round(100.0 * mean_val / tot_mean, 2) if tot_mean > 0 else 0.0
        if baseline_timing and name in baseline_timing:
            base_m = baseline_timing[name]["mean_ms"]
            st["speedup_vs_e2e01"] = round(base_m / mean_val, 2) if mean_val > 0 else None
        out[name] = st
    tot_st = summarize_ms(tot_vals)
    tot_st["duty_cycle_2s_pct"] = round(100.0 * tot_mean / 2000.0, 2)
    if baseline_timing and "total" in baseline_timing:
        tot_st["speedup_vs_e2e01"] = round(baseline_timing["total"]["mean_ms"] / tot_mean, 2)
    out["total"] = tot_st
    return out


def energy_estimate(mean_ms: float):
    lo_mj = 3.3 * 0.036 * mean_ms
    hi_mj = 3.3 * 0.050 * mean_ms
    return {
        "status": "ESTIMATE ONLY (NOT measured; V=3.3V * I_typ[36..50mA] * measured_t)",
        "t_mean_ms": round(mean_ms, 4),
        "e_per_hop_lo_mj": round(lo_mj, 2),
        "e_per_hop_hi_mj": round(hi_mj, 2),
        "p_avg_lo_mw_at_2s": round(lo_mj / 2.0, 2),
        "p_avg_hi_mw_at_2s": round(hi_mj / 2.0, 2),
    }


def classify_elf_symbol(name: str):
    """Map an ELF symbol name in Flash to (module, kind) where kind in {'code', 'rodata'}."""
    # Rodata tables
    if re.match(r"^(SOS_|RESAMP_H_|DALIA_SYM_)", name):
        return ("S1_frontend", "rodata")
    if re.match(r"^TWID_(RE|IM)", name):
        return ("S2_spectral", "rodata")
    if re.match(r"^(INTERP_IDX|INTERP_W|TAPER)", name):
        return ("S3_enhance", "rodata")
    if re.match(r"^MCU_(A|G)", name):
        return ("S5_viterbi", "rodata")

    # Code symbols by module
    if re.match(r"^fe_(filter|resamp)_", name):
        return ("S1_frontend", "code")
    if re.match(r"^(spec_|pruned_fft1024|fft256|unpack_pair_mag|zscore_200)", name):
        return ("S2_spectral", "code")
    if re.match(r"^(enhance_|vec_std|isqrt64|log_q16)", name):
        return ("S3_enhance", "code")
    if re.match(r"^(lbp_|median5|exp_neg)", name):
        return ("S4_lbp", "code")
    if re.match(r"^decode_", name):
        return ("S5_viterbi", "code")
    if re.match(r"^(smooth_|median3)", name):
        return ("S6_smooth", "code")
    if re.match(r"^(dspit_|push_25hz)", name):
        return ("Coordinator_dspit", "code")
    if name in {
        "g_vectors",
        "Reset_Handler",
        "Default_Handler",
        "main",
        "clock_init",
        "dwt_init",
        "read_sp",
        "paint_stack",
        "measure_stack_used",
        "hook_begin",
        "hook_end",
    }:
        return ("Harness", "code")
    return ("Shared_libm_libgcc_libc", "code")


def analyze_elf_sections_and_symbols(elf_path: Path, run_sample: dict = None):
    size_out = subprocess.check_output(["arm-none-eabi-size", "-A", str(elf_path)], text=True)
    sections = {}
    for line in size_out.splitlines():
        m = re.match(r"^\s*(\.\S+)\s+(\d+)\s+(\d+)", line)
        if m:
            sections[m.group(1)] = {"size": int(m.group(2)), "addr": int(m.group(3))}

    nm_out = subprocess.check_output(["arm-none-eabi-nm", "-S", "--defined-only", str(elf_path)], text=True)
    flash_start = 0x08000000
    flash_end = flash_start + sections.get(".isr_vector", {"size": 0})["size"] + sections.get(".text", {"size": 0})["size"] + sections.get(".ARM.exidx", {"size": 0})["size"]

    # Byte-level ownership array across [.isr_vector + .text + .ARM.exidx] avoids double counting weak/strong aliases
    flash_len = flash_end - flash_start
    owner = [None] * flash_len
    prio = {"S1_frontend": 2, "S2_spectral": 2, "S3_enhance": 2, "S4_lbp": 2, "S5_viterbi": 2, "S6_smooth": 2, "Coordinator_dspit": 2, "Harness": 2, "Shared_libm_libgcc_libc": 1}

    rodata_tables = {}
    softfloat_syms = {}
    ram_data_syms = {}
    ram_bss_syms = {}

    for line in nm_out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        addr = int(parts[0], 16)
        size = int(parts[1], 16)
        stype = parts[2]
        name = parts[3]
        if size <= 0:
            continue

        if flash_start <= addr < flash_end:
            mod, kind = classify_elf_symbol(name)
            if kind == "rodata":
                rodata_tables[name] = size
            if mod == "Shared_libm_libgcc_libc":
                softfloat_syms[name] = size
            s_off = addr - flash_start
            e_off = min(flash_len, s_off + size)
            p_new = prio[mod]
            for off in range(s_off, e_off):
                cur = owner[off]
                if cur is None or p_new >= prio[cur[0]]:
                    owner[off] = (mod, kind)
        elif 0x20000000 <= addr < 0x20010000:
            if stype in {"D", "d"}:
                ram_data_syms[name] = size
            elif stype in {"B", "b"}:
                ram_bss_syms[name] = size

    mod_buckets = {}
    for mod in list(prio.keys()):
        mod_buckets[mod] = {"code_bytes": 0, "rodata_bytes": 0, "total_bytes": 0}
    unattrib = 0
    for cell in owner:
        if cell is None:
            unattrib += 1
        else:
            mod, kind = cell
            if kind == "rodata":
                mod_buckets[mod]["rodata_bytes"] += 1
            else:
                mod_buckets[mod]["code_bytes"] += 1
            mod_buckets[mod]["total_bytes"] += 1

    data_bytes = sections.get(".data", {"size": 0})["size"]
    bss_bytes = sections.get(".bss", {"size": 0})["size"]
    mailbox_bytes = sections.get(".mailbox", {"size": 0})["size"]

    # .data init image sits at end of Flash (AT>FLASH), and belongs to libc/harness (_impure_ptr + _impure_data)
    algo_flash_exact = sum(mod_buckets[m]["total_bytes"] for m in mod_buckets if m != "Harness")
    total_flash_bytes = flash_len + data_bytes
    assert algo_flash_exact + mod_buckets["Harness"]["total_bytes"] + unattrib + data_bytes == total_flash_bytes

    ram_info = {
        "bss_total_bytes": bss_bytes,
        "data_total_bytes": data_bytes,
        "mailbox_bytes": mailbox_bytes,
        "ram_data_symbols": dict(sorted(ram_data_syms.items())),
        "ram_bss_symbols": dict(sorted(ram_bss_syms.items())),
    }
    if run_sample is not None:
        s_sizes = run_sample["s_sizes"]
        algo_ram = run_sample["algo_ram_bytes"]
        stack_hwm = run_sample["stack_peak_bytes"]
        assert sum(s_sizes) == algo_ram
        ram_info.update({
            "S1_frontend_bytes": s_sizes[0],
            "S2_spectral_bytes": s_sizes[1],
            "S3_enhance_bytes": s_sizes[2],
            "S4_lbp_bytes": s_sizes[3],
            "S5_viterbi_bytes": s_sizes[4],
            "S6_smooth_bytes": s_sizes[5],
            "Coordinator_and_interstage_buffers_bytes": s_sizes[6],
            "algorithm_static_ram_bytes": algo_ram,
            "algorithm_static_ram_kb_1000": round(algo_ram / 1000.0, 2),
            "algorithm_static_ram_kib_1024": round(algo_ram / 1024.0, 2),
            "stack_high_water_bytes": stack_hwm,
            "algorithm_peak_ram_bytes": algo_ram + stack_hwm,
            "algorithm_peak_ram_kb_1000": round((algo_ram + stack_hwm) / 1000.0, 2),
            "algorithm_peak_ram_kib_1024": round((algo_ram + stack_hwm) / 1024.0, 2),
            "total_firmware_sram_bytes": algo_ram + stack_hwm + data_bytes + mailbox_bytes,
        })

    flash_info = {
        "sections_bytes": {k: v["size"] for k, v in sections.items()},
        "table_rodata_bytes": dict(sorted(rodata_tables.items(), key=lambda kv: (-kv[1], kv[0]))),
        "modules_breakdown_bytes": mod_buckets,
        "unattributed_padding_literals_exidx_bytes": unattrib,
        "algo_flash_exact_attributed_bytes": algo_flash_exact,
        "harness_code_and_data_init_bytes": mod_buckets["Harness"]["total_bytes"] + data_bytes,
        "total_firmware_flash_bytes": total_flash_bytes,
        "total_firmware_flash_kb_1000": round(total_flash_bytes / 1000.0, 2),
        "total_firmware_flash_kib_1024": round(total_flash_bytes / 1024.0, 2),
        "shared_lib_symbols_bytes": dict(sorted(softfloat_syms.items(), key=lambda kv: (-kv[1], kv[0]))),
    }
    return {"ram": ram_info, "flash": flash_info}


def analyze_variant(prefix: str, host_prefix: str, elf_name: str, baseline: dict, banded_only_tags=("s1", "s2", "s3", "ws1", "ws2")):
    runs = {}
    for tag, _, _ in RECORDS:
        fname = f"{prefix}_{tag}.json" if tag != "s1" or prefix == "f32_opt_run" else f"{prefix}_{tag}_r1.json"
        runs[tag] = load_run(ROOT / "results" / fname)

    run_list = [runs[t] for t, _, _ in RECORDS]
    dalia_runs = [runs[t] for t in ("s1", "s2", "s3")]
    wesad_runs = [runs[t] for t in ("ws1", "ws2")]

    pooled_steady = compute_stage_stats(run_list, baseline["timing_pooled_5rec"], steady=True)
    dalia_steady = compute_stage_stats(dalia_runs, baseline["timing_dalia_3rec"], steady=True)
    wesad_steady = compute_stage_stats(wesad_runs, baseline["timing_wesad_2rec"], steady=True)
    cold_start = compute_stage_stats(run_list, None, steady=False)

    per_record = []
    tot_e2e01 = 0
    tot_f64 = 0
    tot_c2 = 0
    tot_wins = 0
    sum_mae_mcu = 0.0
    sum_mae_c2 = 0.0
    sum_mae_f64 = 0.0

    for tag, ds_label, ds_group in RECORDS:
        r = runs[tag]
        fid = eval_record_fidelity(r, tag, ROOT / "results" / f"{host_prefix}_{tag}.bin")
        tot_e2e01 += fid["vs_e2e01_es_count"]
        tot_f64 += fid["vs_SOS_f64_es_count"]
        tot_c2 += fid["vs_cache2_es_count"]
        tot_wins += fid["n_eval"]
        sum_mae_mcu += fid.pop("_raw_mae_mcu")
        sum_mae_c2 += fid.pop("_raw_mae_c2")
        sum_mae_f64 += fid.pop("_raw_mae_sos_f64")

        steady_blks = [b for b in r["blocks"] if b["win_ran"] == 1]
        cold_blks = [b for b in r["blocks"] if b["win_ran"] == 0]
        rec_entry = {
            "label": r["run_label"],
            "tag": tag,
            "dataset": ds_label,
            "dataset_group": ds_group,
            "clk_hz": r["clk_hz"],
            "cfgr": r["cfgr"],
            "wall_s": r["wall_s"],
            "n_blocks": r["n_blocks"],
            "n_steady_hops": len(steady_blks),
            "n_cold_hops": len(cold_blks),
            "stack_peak_bytes": r["stack_peak_bytes"],
            "stages_steady": compute_stage_stats([r], None, steady=True),
        }
        rec_entry.update(fid)
        per_record.append(rec_entry)

    fidelity_summary = {
        "n_windows_total": tot_wins,
        "mcu_vs_host_est": f"{tot_wins}/{tot_wins}",
        "mcu_vs_host_es": f"{tot_wins}/{tot_wins}",
        "mcu_vs_e2e01_es": f"{tot_e2e01}/{tot_wins} ({100.0 * tot_e2e01 / tot_wins:.2f}%)",
        "mcu_vs_sos_f64_es": f"{tot_f64}/{tot_wins} ({100.0 * tot_f64 / tot_wins:.2f}%)",
        "mcu_vs_cache2_es": f"{tot_c2}/{tot_wins} ({100.0 * tot_c2 / tot_wins:.2f}%)",
        "mean_5rec_mae_mcu_bpm": round(sum_mae_mcu / 5.0, 4),
        "mean_5rec_mae_sos_f64_bpm": round(sum_mae_f64 / 5.0, 4),
        "mean_5rec_mae_cache2_bpm": round(sum_mae_c2 / 5.0, 4),
        "mean_5rec_mae_diff_vs_cache2_bpm": round((sum_mae_mcu - sum_mae_c2) / 5.0, 4),
    }

    mem_flash = analyze_elf_sections_and_symbols(ROOT / "fw" / elf_name, runs["s1"])

    return {
        "timing_pooled_5rec": pooled_steady,
        "timing_dalia_3rec": dalia_steady,
        "timing_wesad_2rec": wesad_steady,
        "timing_cold_start_buffering_only": cold_start,
        "energy_estimate_datasheet_72mhz": {
            "pooled": energy_estimate(pooled_steady["total"]["mean_ms"]),
            "dalia": energy_estimate(dalia_steady["total"]["mean_ms"]),
            "wesad": energy_estimate(wesad_steady["total"]["mean_ms"]),
        },
        "fidelity_summary": fidelity_summary,
        "memory_and_flash": mem_flash,
        "per_record": per_record,
    }


def analyze_q31_extras():
    r1 = load_run(ROOT / "results" / "q31_opt_run_s1_r1.json")
    r2 = load_run(ROOT / "results" / "q31_opt_run_s1_r2.json")
    r3 = load_run(ROOT / "results" / "q31_opt_run_s1_r3.json")
    dense = load_run(ROOT / "results" / "q31_opt_run_s1_dense.json")

    rep = []
    for rr in (r2, r3):
        hr_eq = (rr["est"] == r1["est"]) and (rr["es"] == r1["es"]) and (rr["tau"] == r1["tau"])
        max_cyc_diff = max(abs(a["cyc_total"] - b["cyc_total"]) for a, b in zip(r1["blocks"], rr["blocks"]))
        max_rel_pct = max(
            100.0 * abs(a["cyc_total"] - b["cyc_total"]) / max(a["cyc_total"], 1)
            for a, b in zip(r1["blocks"], rr["blocks"])
        )
        rep.append({
            "label": rr["run_label"],
            "hr_and_tau_identical": hr_eq,
            "max_block_cycle_diff": max_cyc_diff,
            "rel_cycle_drift_pct": round(max_rel_pct, 4),
        })

    st_band = compute_stage_stats([r1], None, steady=True)
    st_dense = compute_stage_stats([dense], None, steady=True)
    s5_band = st_band["S5_viterbi"]["mean_ms"]
    s5_dense = st_dense["S5_viterbi"]["mean_ms"]
    tot_band = st_band["total"]["mean_ms"]
    tot_dense = st_dense["total"]["mean_ms"]
    est_eq = sum(1 for a, b in zip(r1["est"], dense["est"]) if a == b)
    es_eq = sum(1 for a, b in zip(r1["es"], dense["es"]) if a == b)
    banded_vs_dense = {
        "s1_est_match_banded_vs_dense": f"{est_eq}/{len(r1['est'])}",
        "s1_es_match_banded_vs_dense": f"{es_eq}/{len(r1['es'])}",
        "s5_banded_mean_ms": s5_band,
        "s5_dense_mean_ms": s5_dense,
        "s5_speedup": round(s5_dense / s5_band, 2),
        "total_banded_mean_ms": tot_band,
        "total_dense_mean_ms": tot_dense,
        "total_speedup": round(tot_dense / tot_band, 2),
    }
    return rep, banded_vs_dense


def parse_m4f_static():
    txt = (ROOT / "results" / "m4f_static_check.txt").read_text(encoding="utf-8")
    vfp_insns = {}
    m_vfp = re.search(r"\{([^}]+)\}", txt)
    if m_vfp:
        for kv in m_vfp.group(1).split(","):
            k, v = kv.split(":")
            vfp_insns[k.strip().strip("'")] = int(v.strip())
    m_tot = re.search(r"Total matched VFP f32 arith insns:\s*(\d+)", txt)
    m_sf = re.search(r"Soft-float __aeabi_fadd/sub/mul/div symbols in nm:\s*(\d+)", txt)
    mem_flash = analyze_elf_sections_and_symbols(ROOT / "fw" / "fw_m4f.elf", None)
    return {
        "runtime_status": "STATIC CROSS-COMPILE & DISASSEMBLY CHECK ONLY (NO CORTEX-M4F HARDWARE MEASURED)",
        "compile_flags": "-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb -O3 -fno-math-errno",
        "vfp_f32_insn_counts": vfp_insns,
        "total_vfp_f32_arith_insns": int(m_tot.group(1)) if m_tot else sum(vfp_insns.values()),
        "softfloat_fadd_sub_mul_div_symbols": int(m_sf.group(1)) if m_sf else -1,
        "memory_and_flash": mem_flash,
    }


def main():
    baseline = json.loads(BASELINE_SUMMARY.read_text(encoding="utf-8"))

    f32_opt = analyze_variant("f32_opt_run", "host_f32opt", "fw_f32_opt.elf", baseline)
    q31_opt = analyze_variant("q31_opt_run", "host_q31", "fw_q31_opt.elf", baseline)
    rep, bvd = analyze_q31_extras()
    q31_opt["repeatability_s1_x3"] = rep
    q31_opt["banded_vs_dense_s1"] = bvd
    m4f_static = parse_m4f_static()

    # Cross-check against host_opt_verify_log.txt exact summary values
    assert abs(f32_opt["fidelity_summary"]["mean_5rec_mae_mcu_bpm"] - 7.5312) <= 0.0002
    assert abs(q31_opt["fidelity_summary"]["mean_5rec_mae_mcu_bpm"] - 7.5421) <= 0.0002
    assert f32_opt["fidelity_summary"]["mcu_vs_cache2_es"].startswith("1234/1270")
    assert q31_opt["fidelity_summary"]["mcu_vs_cache2_es"].startswith("1222/1270")

    summary = {
        "experiment": "E2E-02",
        "date": "2026-11-24",
        "baseline_ref": {
            "experiment": baseline["experiment"],
            "date": baseline["date"],
            "pooled_mean_ms": baseline["timing_pooled_5rec"]["total"]["mean_ms"],
            "pooled_p95_ms": baseline["timing_pooled_5rec"]["total"]["p95_ms"],
            "dalia_mean_ms": baseline["timing_dalia_3rec"]["total"]["mean_ms"],
            "wesad_mean_ms": baseline["timing_wesad_2rec"]["total"]["mean_ms"],
            "duty_cycle_2s_pct": round(100.0 * baseline["timing_pooled_5rec"]["total"]["mean_ms"] / 2000.0, 2),
            "algorithm_static_ram_bytes": baseline["memory_and_flash"]["ram"]["algorithm_static_ram_bytes"],
            "stack_high_water_bytes": baseline["memory_and_flash"]["ram"]["stack_high_water_bytes"],
            "algorithm_peak_ram_bytes": baseline["memory_and_flash"]["ram"]["algorithm_peak_ram_bytes"],
            "algo_flash_total_bytes": baseline["memory_and_flash"]["flash"]["algo_flash_total_bytes"],
            "total_firmware_flash_bytes": baseline["memory_and_flash"]["flash"]["total_firmware_flash_bytes"],
        },
        "platform": baseline["platform"],
        "optimizations": {
            "lever_1": "Pure fixed-point DSP chain Q11.20/Q3.28/Q50 IIR+FIR, Q21 FFT, Q30/Q16 log_q16/isqrt64/exp_neg_q16 & Viterbi Q16",
            "lever_2": "Input-pruned 1024-pt -> 4x256 Radix-4 DIF FFT (200 active samples, band-only k=31..122 digitrev4 unpack) + O(NB) sliding historysum",
            "lever_3": "Exploited SOS unit numerators (1,+/-2,1) & DaLiA 101-tap Nyquist-5 FIR even symmetry with 20 exact zeros (41 MACs/sample)",
            "lever_4": "Cortex-M4F hard-float static cross-compile & VFP disassembly check only (fw_m4f.elf, not hardware-measured)",
        },
        "variants": {
            "f32_opt": f32_opt,
            "q31_opt": q31_opt,
            "m4f_static": m4f_static,
        },
    }

    out_path = ROOT / "results" / "results_summary_e2e_opt.json"
    out_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")

    for vname in ("f32_opt", "q31_opt"):
        v = summary["variants"][vname]
        p = v["timing_pooled_5rec"]["total"]
        d = v["timing_dalia_3rec"]["total"]
        w = v["timing_wesad_2rec"]["total"]
        r = v["memory_and_flash"]["ram"]
        f = v["memory_and_flash"]["flash"]
        fid = v["fidelity_summary"]
        print(
            f"[{vname}] pooled={p['mean_ms']:.3f}ms ({p['speedup_vs_e2e01']}x, duty={p['duty_cycle_2s_pct']}%, P95={p['p95_ms']:.3f}ms) | "
            f"DaLiA={d['mean_ms']:.3f}ms | WESAD={w['mean_ms']:.3f}ms"
        )
        print(
            f"  RAM algo={r['algorithm_static_ram_bytes']}B + stack={r['stack_high_water_bytes']}B -> peak={r['algorithm_peak_ram_bytes']}B | "
            f"Flash={f['total_firmware_flash_bytes']}B (unattrib={f['unattributed_padding_literals_exidx_bytes']}B)"
        )
        print(
            f"  Fidelity vsE2E01={fid['mcu_vs_e2e01_es']} vsC2={fid['mcu_vs_cache2_es']} MAE={fid['mean_5rec_mae_mcu_bpm']:.4f} vs {fid['mean_5rec_mae_cache2_bpm']:.4f}"
        )
    print(
        f"[q31_opt extras] repeat_x3={rep} | banded_vs_dense={bvd}"
    )
    print(
        f"[m4f_static] Flash={m4f_static['memory_and_flash']['flash']['total_firmware_flash_bytes']}B, "
        f"VFP={m4f_static['total_vfp_f32_arith_insns']} insns, softfloat={m4f_static['softfloat_fadd_sub_mul_div_symbols']}"
    )


if __name__ == "__main__":
    main()

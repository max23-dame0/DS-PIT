#!/usr/bin/env python3
"""Aggregate enriched real-STM32F103 Q31-opt results (30-subject prefixes + 2 multi-hour endurance runs)."""
import json
import re
from pathlib import Path

from analyze_e2e_opt import STAGE_NAMES, summarize_ms

OPT_ROOT = Path(__file__).resolve().parent
ENRICHED_DIR = OPT_ROOT / "results" / "mcu_q31_enriched"
FULL30_PATH = OPT_ROOT / "results" / "full30_host_eval.json"
OUT_PATH = OPT_ROOT / "results" / "results_summary_q31_enriched.json"


def natural_subj_key(name: str):
    m = re.search(r"S(\d+)", name)
    return int(m.group(1)) if m else 0


def pool_prefix_group(runs):
    all_total_ms = []
    all_stage_ms = [[] for _ in range(6)]
    all_cold_ms = []
    per_subj = []
    match_wins = 0
    match_den = 0
    stack_peaks = []
    wall_total = 0.0

    for r in runs:
        clk_ms = r["clk_hz"] / 1000.0
        tot_ms = [c / clk_ms for c in r["steady_cyc_total"]]
        all_total_ms.extend(tot_ms)
        for si in range(6):
            all_stage_ms[si].extend([c / clk_ms for c in r["steady_cyc_s"][si]])
        all_cold_ms.extend([c / clk_ms for c in r["cold_cyc_total"]])

        mc, md = map(int, r["host_match_es"].split("/"))
        match_wins += mc
        match_den += md
        stack_peaks.append(r["stack_peak_bytes"])
        wall_total += float(r["wall_s"])

        per_subj.append({
            "subject": r["subject"],
            "n_blocks": r["n_blocks_streamed"],
            "n_steady": r["n_steady"],
            "mean_ms": r["timing_total"]["mean_ms"],
            "p95_ms": r["timing_total"]["p95_ms"],
            "max_ms": r["timing_total"]["max_ms"],
            "duty_pct": r["duty_cycle_2s_pct"],
            "cold_mean_ms": r["timing_cold_start"]["mean_ms"],
            "stack_peak_bytes": r["stack_peak_bytes"],
            "host_match_es": r["host_match_es"],
            "wall_s": r["wall_s"],
        })

    tot_sum = summarize_ms(all_total_ms)
    tot_mean = tot_sum["mean_ms"]
    stages_sum = {}
    for si, sname in enumerate(STAGE_NAMES):
        st = summarize_ms(all_stage_ms[si])
        st["pct_of_total"] = round(100.0 * st["mean_ms"] / tot_mean, 2) if tot_mean > 0 else 0.0
        stages_sum[sname] = st

    subj_means = [x["mean_ms"] for x in per_subj]
    duty_pct = round(100.0 * tot_mean / 2000.0, 2)
    e_lo_mj = round(3.3 * 36.0 * tot_mean / 1000.0, 2)
    e_hi_mj = round(3.3 * 50.0 * tot_mean / 1000.0, 2)

    return {
        "n_subjects": len(runs),
        "n_steady_steps": len(all_total_ms),
        "n_cold_steps": len(all_cold_ms),
        "total_wall_s": round(wall_total, 2),
        "stack_peak_max_bytes": max(stack_peaks) if stack_peaks else 0,
        "host_match_es": f"{match_wins}/{match_den}",
        "all_subjects_exact_match": (match_wins == match_den) and all(
            x["host_match_es"].split("/")[0] == x["host_match_es"].split("/")[1] for x in per_subj
        ),
        "duty_cycle_2s_pct": duty_pct,
        "datasheet_energy_mj_per_step_est": [e_lo_mj, e_hi_mj],
        "datasheet_power_mw_est": [round(e_lo_mj / 2.0, 2), round(e_hi_mj / 2.0, 2)],
        "subject_mean_range_ms": [min(subj_means), max(subj_means)] if subj_means else [0.0, 0.0],
        "timing_total": tot_sum,
        "timing_stages": stages_sum,
        "timing_cold_start": summarize_ms(all_cold_ms),
        "per_subject": per_subj,
    }


def summarize_endurance(r: dict, host_eval_ds: list):
    href = next(x for x in host_eval_ds if x["subject"] == r["subject"])
    hq = href["variants"]["q31opt"]
    acc = r["accuracy_endurance"]
    q1 = r["quartiles"]["Q1"]
    q4 = r["quartiles"]["Q4"]
    tot_mean = r["timing_total"]["mean_ms"]
    e_lo = round(3.3 * 36.0 * tot_mean / 1000.0, 2)
    e_hi = round(3.3 * 50.0 * tot_mean / 1000.0, 2)
    dur_h = round(r["n_blocks_raw"] * 2.0 / 3600.0, 2)

    return {
        "dataset": r["dataset"],
        "subject": r["subject"],
        "recording_hours_raw": dur_h,
        "n_blocks_raw": r["n_blocks_raw"],
        "n_blocks_streamed": r["n_blocks_streamed"],
        "n_steady": r["n_steady"],
        "clk_hz": r["clk_hz"],
        "cfgr": r["cfgr"],
        "wall_s": r["wall_s"],
        "algo_ram_bytes": r["algo_ram_bytes"],
        "stack_peak_bytes": r["stack_peak_bytes"],
        "host_match_es": r["host_match_es"],
        "duty_cycle_2s_pct": r["duty_cycle_2s_pct"],
        "datasheet_energy_mj_per_step_est": [e_lo, e_hi],
        "timing_total": r["timing_total"],
        "timing_stages": r["timing_stages"],
        "timing_cold_start": r["timing_cold_start"],
        "quartiles": r["quartiles"],
        "q4_minus_q1_mean_ms": round(q4["mean_ms"] - q1["mean_ms"], 4),
        "q4_minus_q1_p95_ms": round(q4["p95_ms"] - q1["p95_ms"], 4),
        "accuracy_mcu": acc,
        "accuracy_host_q31_ref": hq,
        "matlab_a2_mae": href["matlab_a2_mae"],
        "mae_diff_mcu_vs_host": round(acc["mae"] - hq["mae"], 4),
        "mae_diff_mcu_vs_matlab": round(acc["mae"] - href["matlab_a2_mae"], 4),
    }


def main():
    dalia_files = sorted(ENRICHED_DIR.glob("dalia15_S*.json"), key=lambda p: natural_subj_key(p.name))
    wesad_files = sorted(ENRICHED_DIR.glob("wesad15_S*.json"), key=lambda p: natural_subj_key(p.name))
    end_dalia_path = ENRICHED_DIR / "endurance_dalia_S1.json"
    end_wesad_path = ENRICHED_DIR / "endurance_wesad_S2.json"

    if len(dalia_files) != 15 or len(wesad_files) != 15:
        raise RuntimeError(f"Expected 15+15 prefix JSONs, found {len(dalia_files)}+{len(wesad_files)}")
    if not end_dalia_path.exists() or not end_wesad_path.exists():
        raise RuntimeError("Missing one or both endurance JSON files.")

    dalia_runs = [json.loads(p.read_text(encoding="utf-8")) for p in dalia_files]
    wesad_runs = [json.loads(p.read_text(encoding="utf-8")) for p in wesad_files]
    end_dalia = json.loads(end_dalia_path.read_text(encoding="utf-8"))
    end_wesad = json.loads(end_wesad_path.read_text(encoding="utf-8"))
    full30 = json.loads(FULL30_PATH.read_text(encoding="utf-8"))

    out = {
        "experiment": "E2E-02-Q31-ENRICHED",
        "date": "2026-11-24",
        "firmware": "fw_q31_opt.elf (unchanged STM32F103 Cortex-M3 @ 72 MHz, -O3)",
        "prefix_30_subjects": {
            "dalia15": pool_prefix_group(dalia_runs),
            "wesad15": pool_prefix_group(wesad_runs),
            "pooled30": pool_prefix_group(dalia_runs + wesad_runs),
        },
        "endurance_full_recordings": {
            "dalia_S1": summarize_endurance(end_dalia, full30["per_subject"]["dalia"]),
            "wesad_S2": summarize_endurance(end_wesad, full30["per_subject"]["wesad"]),
        },
    }
    OUT_PATH.write_text(json.dumps(out, indent=2), encoding="utf-8")

    p30 = out["prefix_30_subjects"]["pooled30"]
    d15 = out["prefix_30_subjects"]["dalia15"]
    w15 = out["prefix_30_subjects"]["wesad15"]
    ed = out["endurance_full_recordings"]["dalia_S1"]
    ew = out["endurance_full_recordings"]["wesad_S2"]
    print(f"Saved {OUT_PATH}")
    print(
        f"Pooled-30 prefixes (n={p30['n_steady_steps']}): mean={p30['timing_total']['mean_ms']:.3f}ms "
        f"p95={p30['timing_total']['p95_ms']:.3f}ms max={p30['timing_total']['max_ms']:.3f}ms "
        f"duty={p30['duty_cycle_2s_pct']}% stack={p30['stack_peak_max_bytes']}B match={p30['host_match_es']}"
    )
    print(
        f"  DaLiA-15: {d15['timing_total']['mean_ms']:.3f}ms (range {d15['subject_mean_range_ms']}) "
        f"| WESAD-15: {w15['timing_total']['mean_ms']:.3f}ms (range {w15['subject_mean_range_ms']})"
    )
    print(
        f"Endurance DaLiA S1 ({ed['n_blocks_raw']} blk): mean={ed['timing_total']['mean_ms']:.3f}ms "
        f"Q4-Q1={ed['q4_minus_q1_mean_ms']:+.4f}ms match={ed['host_match_es']} MAE={ed['accuracy_mcu']['mae']:.4f}"
    )
    print(
        f"Endurance WESAD S2 ({ew['n_blocks_raw']} blk): mean={ew['timing_total']['mean_ms']:.3f}ms "
        f"Q4-Q1={ew['q4_minus_q1_mean_ms']:+.4f}ms match={ew['host_match_es']} MAE={ew['accuracy_mcu']['mae']:.4f}"
    )


if __name__ == "__main__":
    main()

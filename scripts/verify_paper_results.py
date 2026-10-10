#!/usr/bin/env python3
"""
Automated Paper & Supplementary Material Consistency Verifier for DS-PIT.

Checks that all pre-computed experimental logs, CSVs, JSONs, and MCU hardware
captures in this repository match the exact figures and tables reported in:
  - Main Manuscript (JBHI-01577-2026: "A Dual-Scale Tracking Framework for Robust
    PPG-based Heart Rate Estimation in Daily Life and Exercise")
  - Supplementary Materials (Sections S1-S6, Tables S1-S8, Figures S1-S3)

Usage:
    python scripts/verify_paper_results.py
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


class VerificationSuite:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.details = []
        self.checks = []

    def check_float(self, label: str, actual: float, expected: float, tol: float = 0.02):
        ok = abs(actual - expected) <= tol
        status = "PASS" if ok else "FAIL"
        detail = f"actual={actual:.4f}, expected={expected:.4f} (tol={tol})"
        msg = f"[{status}] {label}: {detail}"
        self.details.append(msg)
        self.checks.append((label, ok, detail))
        if ok:
            self.passed += 1
        else:
            self.failed += 1


def extract_regex_float(text: str, pattern: str) -> float:
    m = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not m:
        raise ValueError(f"Pattern not found: {pattern}")
    return float(m.group(1))


def run_all_checks() -> VerificationSuite:
    suite = VerificationSuite()

    # 1. Main Table I: Dataset & HR distribution statistics (matlab/results/table1_stats_log.txt)
    t1_path = ROOT / "matlab" / "results" / "table1_stats_log.txt"
    t1_txt = t1_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Table I: IEEE SPC all-23 total windows (3203)",
        extract_regex_float(t1_txt, r"IEEE SPC \(all 23\)\s+(\d+)"),
        3203.0,
        tol=0.1,
    )
    suite.check_float(
        "Main Table I: PPG-DaLiA total windows (64697)",
        extract_regex_float(t1_txt, r"DALIA\s+(\d+)\s+mean=\s*89\.43"),
        64697.0,
        tol=0.1,
    )
    suite.check_float(
        "Main Table I: PPG-DaLiA HR < 60 BPM share (5.79%)",
        extract_regex_float(t1_txt, r"DALIA\s+64697.*?<60=\s*([\d.]+)%"),
        5.79,
        tol=0.05,
    )
    suite.check_float(
        "Main Table I: WESAD total windows (22478)",
        extract_regex_float(t1_txt, r"WESAD\s+(\d+)\s+mean=\s*77\.24"),
        22478.0,
        tol=0.1,
    )
    suite.check_float(
        "Main Table I: WESAD HR < 60 BPM share (10.80%)",
        extract_regex_float(t1_txt, r"WESAD\s+22478.*?<60=\s*([\d.]+)%"),
        10.80,
        tol=0.05,
    )

    # 2. Main Table III & Section III-B.1: IEEE SPC Standard Protocol
    v1_path = ROOT / "ieee_spc_standard" / "results_v1_summary.txt"
    v1_txt = v1_path.read_text(encoding="utf-8", errors="replace")
    box_path = ROOT / "matlab" / "results" / "a2_fig_boxplot_macro_lbp_log.txt"
    box_txt = box_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Table III: IEEE SPC 12-Train MAE (0.78 BPM)",
        extract_regex_float(v1_txt, r"ksrc=trainall train=([\d.]+)"),
        0.7756,
        tol=0.01,
    )
    suite.check_float(
        "Main Table III: IEEE SPC 10-Test MAE (2.10 BPM)",
        extract_regex_float(box_txt, r"test 10:\s*([\d.]+)"),
        2.10,
        tol=0.01,
    )
    suite.check_float(
        "Main Table III: IEEE SPC 11-Test MAE (2.16 BPM)",
        extract_regex_float(v1_txt, r"ksrc=trainall train=[\d.]+ test=([\d.]+)"),
        2.1637,
        tol=0.01,
    )
    suite.check_float(
        "Main Table III: IEEE SPC All-23 MAE (1.50 BPM)",
        extract_regex_float(v1_txt, r"kernel= train=0\.8744 test=2\.1833 all=([\d.]+)"),
        1.5004,
        tol=0.01,
    )

    # 3. Main Table IV & Section III-B.2: Unified Cross-Dataset Generalization (matlab/results/a2_core_log.txt)
    core_path = ROOT / "matlab" / "results" / "a2_core_log.txt"
    core_txt = core_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Table IV: PPG-DaLiA Unified MAE (5.83 BPM)",
        extract_regex_float(core_txt, r"######## DALIA ########\s*\[headline\] MAE=([\d.]+)"),
        5.8302,
        tol=0.01,
    )
    suite.check_float(
        "Main Table IV: PPG-DaLiA Unified SD (2.18 BPM)",
        extract_regex_float(core_txt, r"######## DALIA ########\s*\[headline\] MAE=[\d.]+ SD=([\d.]+)"),
        2.1847,
        tol=0.01,
    )
    suite.check_float(
        "Main Table IV: WESAD Unified MAE (5.76 BPM)",
        extract_regex_float(core_txt, r"######## WESAD ########\s*\[headline\] MAE=([\d.]+)"),
        5.7569,
        tol=0.01,
    )
    suite.check_float(
        "Main Table IV: WESAD Unified SD (3.24 BPM)",
        extract_regex_float(core_txt, r"######## WESAD ########\s*\[headline\] MAE=[\d.]+ SD=([\d.]+)"),
        3.2355,
        tol=0.01,
    )
    suite.check_float(
        "Supp Table S3: IEEE SPC Unified Zero-Retuning All-23 MAE (6.77 BPM)",
        extract_regex_float(core_txt, r"ALL23\s+n=23 MAE=([\d.]+)"),
        6.7659,
        tol=0.01,
    )

    # 4. Supp Section S2.1: 2x2 Prior Factorial on IEEE SPC (matlab/results/ieee_prior_split_log.txt)
    prior_path = ROOT / "matlab" / "results" / "ieee_prior_split_log.txt"
    prior_txt = prior_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Supp Section S2.1: Empirical LOXO kernel without causal moving average (16.49 BPM)",
        extract_regex_float(prior_txt, r"v1 config : truth-kernel \+ band 1\.0-3\.0, no taper\s+MAE=([\d.]+)"),
        16.4921,
        tol=0.01,
    )
    suite.check_float(
        "Supp Section S2.1: Analytic kernel on [1.0, 3.0] Hz without taper (5.28 BPM)",
        extract_regex_float(prior_txt, r"analytic\s+\+ band 1\.0-3\.0, no taper\s+MAE=([\d.]+)"),
        5.2779,
        tol=0.01,
    )

    # 5. Main Fig. 6 & Section III-C: Four-Arm Factorial Ablation (matlab/results/a2_fig_boxplot_macro_lbp_log.txt)
    suite.check_float(
        "Main Fig. 6 (PPG-DaLiA): Baseline MAE (11.01 BPM)",
        extract_regex_float(box_txt, r"PPG-DaLiA.*?Baseline\s+:\s*mean =\s*([\d.]+)"),
        11.01,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 6 (PPG-DaLiA): Baseline + SSC MAE (8.69 BPM)",
        extract_regex_float(box_txt, r"PPG-DaLiA.*?Baseline \+ SSC\s*:\s*mean =\s*([\d.]+)"),
        8.69,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 6 (PPG-DaLiA): Baseline + LBP MAE (8.22 BPM)",
        extract_regex_float(box_txt, r"PPG-DaLiA.*?Baseline \+ LBP\s*:\s*mean =\s*([\d.]+)"),
        8.22,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 6 (WESAD): Baseline MAE (8.28 BPM)",
        extract_regex_float(box_txt, r"WESAD.*?Baseline\s+:\s*mean =\s*([\d.]+)"),
        8.28,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 6 (WESAD): Baseline + SSC MAE (7.83 BPM)",
        extract_regex_float(box_txt, r"WESAD.*?Baseline \+ SSC\s*:\s*mean =\s*([\d.]+)"),
        7.83,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 6 (WESAD): Baseline + LBP MAE (6.54 BPM)",
        extract_regex_float(box_txt, r"WESAD.*?Baseline \+ LBP\s*:\s*mean =\s*([\d.]+)"),
        6.54,
        tol=0.02,
    )

    # 6. Main Fig. 7 & Section III-D: Representative Trajectory Cases (matlab/results/a2_fig_traj_arms_log.txt)
    traj_path = ROOT / "matlab" / "results" / "a2_fig_traj_arms_log.txt"
    traj_txt = traj_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Fig. 7(b): PPG-DaLiA S5 Baseline+SSC MAE (21.11 BPM)",
        extract_regex_float(traj_txt, r"S5\s*:\s*base\s+([\d.]+)"),
        21.11,
        tol=0.02,
    )
    suite.check_float(
        "Main Fig. 7(b): PPG-DaLiA S5 Full DS-PIT MAE (5.22 BPM)",
        extract_regex_float(traj_txt, r"S5\s*:\s*base\s+[\d.]+\s*\|\s*LBP-only\s+[\d.]+\s*\|\s*full\s+([\d.]+)"),
        5.22,
        tol=0.02,
    )

    # 7. Main Fig. 8, Section III-E & Supp Tables S2, S4, S5, S7, S8 (a2_tables_log.txt, a2_nestedcv_log.txt, a2_extra_log.txt)
    tab_path = ROOT / "matlab" / "results" / "a2_tables_log.txt"
    tab_txt = tab_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Section III-C: PPG-DaLiA Removing Second Wiener Filter MAE (31.82 BPM)",
        extract_regex_float(tab_txt, r"- second Wiener\s+MAE=([\d.]+)"),
        31.8201,
        tol=0.02,
    )
    suite.check_float(
        "Supp Table S4: PPG-DaLiA Zero-Lag (D=1, 0s) MAE (6.34 BPM)",
        extract_regex_float(tab_txt, r"D=\s*1 wait=\s*0s MAE=([\d.]+)"),
        6.3358,
        tol=0.02,
    )

    ncv_path = ROOT / "matlab" / "results" / "a2_nestedcv_log.txt"
    ncv_txt = ncv_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Section III-E & Supp Table S2: PPG-DaLiA Nested-CV Outer Mean MAE (5.86 BPM)",
        extract_regex_float(ncv_txt, r"DALIA.*?nested CV \(outer\) mean=([\d.]+)"),
        5.860,
        tol=0.02,
    )
    suite.check_float(
        "Main Section III-E & Supp Table S2: WESAD Nested-CV Outer Mean MAE (6.42 BPM)",
        extract_regex_float(ncv_txt, r"WESAD.*?nested CV \(outer\) mean=([\d.]+)"),
        6.416,
        tol=0.02,
    )

    extra_path = ROOT / "matlab" / "results" / "a2_extra_log.txt"
    extra_txt = extra_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Section III-E & Supp Table S8: PPG-DaLiA Stairs MAE (16.49 BPM)",
        extract_regex_float(extra_txt, r"Stairs\s+n=\s*\d+\s+share=\s*[\d.]+%\s+MAE=\s*([\d.]+)"),
        16.493,
        tol=0.02,
    )
    suite.check_float(
        "Main Section III-E & Supp Table S8: WESAD Stress MAE (13.85 BPM)",
        extract_regex_float(extra_txt, r"Stress\s+n=\s*\d+\s+share=\s*[\d.]+%\s+MAE=\s*([\d.]+)"),
        13.849,
        tol=0.02,
    )

    # 8. Supp Section S1.1: 25-Hz vs. 125-Hz IEEE SPC Control (supplementary_controls/ieee25_control/results.json)
    ieee25_path = ROOT / "supplementary_controls" / "ieee25_control" / "results.json"
    ieee25_data = json.loads(ieee25_path.read_text(encoding="utf-8"))
    suite.check_float(
        "Supp Section S1.1: IEEE SPC 25-Hz All-23 MAE (6.76 BPM)",
        float(ieee25_data["splits"]["ALL23"]["mae_mean_25hz"]),
        6.7579,
        tol=0.01,
    )
    suite.check_float(
        "Supp Section S1.1: IEEE SPC 125-Hz All-23 MAE (6.77 BPM)",
        float(ieee25_data["splits"]["ALL23"]["mae_mean_125hz"]),
        6.7659,
        tol=0.01,
    )
    suite.check_float(
        "Supp Section S1.1: IEEE SPC 25-Hz vs 125-Hz Delta (-0.01 BPM)",
        float(ieee25_data["splits"]["ALL23"]["delta_mean_25minus125"]),
        -0.0080,
        tol=0.005,
    )

    # 9. Main Section III-F & Supp Section S6: Embedded STM32F103 Cortex-M3 Profiling
    mcu_path = ROOT / "embedded_cortex_m3" / "results" / "mcu_check_summary.txt"
    mcu_txt = mcu_path.read_text(encoding="utf-8", errors="replace")
    suite.check_float(
        "Main Section III-F & Supp Section S6: STM32F103 Dense K^2 Mean Cycles (4,733,299.4)",
        extract_regex_float(mcu_txt, r"dense K\^2 ---\s*cycles:.*?mean=([\d.]+)"),
        4733299.4,
        tol=1.0,
    )
    suite.check_float(
        "Main Section III-F & Supp Section S6: STM32F103 Dense K^2 Mean Latency (65.740 ms)",
        extract_regex_float(mcu_txt, r"dense K\^2 ---.*?time\s*:.*?mean=([\d.]+)\s*ms"),
        65.740,
        tol=0.01,
    )
    suite.check_float(
        "Main Section III-F & Supp Section S6: STM32F103 Banded K*W Mean Cycles (423,853.8)",
        extract_regex_float(mcu_txt, r"banded K\*W \(W=13\) ---\s*cycles:.*?mean=([\d.]+)"),
        423853.8,
        tol=1.0,
    )
    suite.check_float(
        "Main Section III-F & Supp Section S6: STM32F103 Banded K*W Mean Latency (5.887 ms)",
        extract_regex_float(mcu_txt, r"banded K\*W \(W=13\) ---.*?time\s*:.*?mean=([\d.]+)\s*ms"),
        5.887,
        tol=0.01,
    )
    suite.check_float(
        "Main Section III-F & Supp Section S6: STM32F103 Dense/Banded Speedup Ratio (11.17x)",
        extract_regex_float(mcu_txt, r"dense/banded mean-cycle ratio =\s*([\d.]+)"),
        11.17,
        tol=0.01,
    )

    return suite


def verify_all():
    suite = run_all_checks()
    return suite.passed, suite.passed + suite.failed, suite.checks


def main():
    suite = run_all_checks()
    print("=" * 78)
    print("DS-PIT Reproducibility & Paper-Consistency Verification Report")
    print("=" * 78)
    for line in suite.details:
        print(" ", line)
    print("-" * 78)
    print(f"Summary: {suite.passed} passed, {suite.failed} failed (total {suite.passed + suite.failed} checks)")
    print("=" * 78)
    sys.exit(0 if suite.failed == 0 else 1)


if __name__ == "__main__":
    main()

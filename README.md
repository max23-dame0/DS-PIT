# DS-PIT: A Dual-Scale Tracking Framework for Robust PPG-based Heart Rate Estimation in Daily Life and Exercise

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2021a%2B-orange.svg)](https://www.mathworks.com/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-green.svg)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/MCU-STM32F103%20Cortex--M3-red.svg)](embedded_cortex_m3/)

Official open-source implementation, experimental drivers, statistical analyzers, embedded ARM Cortex-M3 firmware, and full reproducibility suite for the **IEEE Journal of Biomedical and Health Informatics (JBHI)** manuscript:

> **A Dual-Scale Tracking Framework for Robust PPG-based Heart Rate Estimation in Daily Life and Exercise**  
> *Manuscript ID: JBHI-01577-2026*

---

## 1. Overview & Architecture

Wrist-worn photoplethysmography (PPG) heart rate (HR) monitoring in daily life and intensive physical exercise suffers from severe non-stationary motion artifacts (MAs) that frequently overlap with the cardiac fundamental band and induce abrupt harmonic jumps or spectral lock-in.

**DS-PIT (Dual-Scale Physiological Interval Tracker)** addresses this challenge via a training-free, two-stage architecture:
1. **Stage 1 — Dual-Stage Spectral Wiener Filtering & Harmonic-Sum Ratio Scoring**:
   - Processes 8-s sliding windows (2-s shift, $N_{\text{FFT}}=4096$ zero-padded FFT) of dual-channel PPG and tri-axial accelerometer signals.
   - Employs a cascaded dual-stage Wiener filter (`WF1 + WF2` with $L_{\text{WF}}=15$) to suppress broadband and narrowband motion spectra while preserving cardiac harmonics.
   - Computes an energy-normalized fundamental-plus-harmonic spectral ratio score over $K=161$ discrete HR states ($40\text{--}200\text{ BPM}$, $1\text{-BPM}$ resolution).
2. **Stage 2 — Dual-Scale Joint MAP State-Space Tracker**:
   - **Macro-Scale Long-Term Physiological Baseline Prior (LBP)**: Restricts candidate spectral evidence to a physiologically valid support $[0.75, 3.0]\text{ Hz}$ with a 30-BPM raised-cosine lower-edge taper (suppressing low-frequency motion dominance) and dynamically modulates the observation temperature $\tau_t \in [0.7, 1.3]$ using a 30-frame (~1-min) causal exponential moving average of spectral peak prominence $R_t$.
   - **Micro-Scale Short-Term Smoothness Constraint (SSC)**: Enforces beat-to-beat continuity via a zero-drift random-walk Gaussian transition kernel ($\sigma_{\text{SSC}}=2\text{ BPM}$), decoded globally by a causal fixed-lag ($D=3$, 4-s wait) max-product Viterbi smoother followed by a 3-point causal median filter.

---

## 2. Headline Experimental Results

All results below are 100% reproducible via the scripts and pre-computed logs included in this repository:

### A. Controlled Treadmill & Exercise Benchmark (IEEE SPC 2015, 23 Recordings)
Under the standard IEEE Signal Processing Cup (SPC) 2015 competition partition protocol (`ieee_spc_standard/`):
| Split | Recordings | Subject-Macro MAE $\pm$ SD (BPM) | Median MAE (BPM) |
|:---|:---:|:---:|:---:|
| **12-Recording Training Set** | S01–S12 | **0.78 $\pm$ 0.44** | 0.72 |
| **10-Recording Test Set** (excl. `S03_T02`) | 10 Test | **2.10 $\pm$ 1.96** | 1.31 |
| **Full 11-Recording Test Set** | 11 Test | **2.16 $\pm$ 1.87** | 1.56 |
| **All 23 Recordings Combined** | All 23 | **1.50 $\pm$ 1.54** | 1.00 |

### B. Unconstrained Multi-Hour Daily-Life Generalization (Unified Zero-Retuning Configuration)
Evaluated across **87,175 sliding windows** (30 subjects, $>48\text{ hours}$ total) using a single frozen, training-free parameter set (`matlab/a2_cfg.m`, no subject-specific tuning or ground-truth transition training):
| Dataset | Subjects / Windows | Subject-Macro MAE $\pm$ SD (BPM) | Median (IQR) MAE (BPM) | Subject-Macro RMSE (BPM) | Coverage |
|:---|:---:|:---:|:---:|:---:|:---:|
| **PPG-DaLiA** | 15 subjects / 64,697 windows | **5.83 $\pm$ 2.18** | **5.22 (2.61)** | 11.11 | 99.93% |
| **WESAD** | 15 subjects / 22,478 windows | **5.76 $\pm$ 3.24** | **4.97 (4.27)** | 9.86 | 100.00% |
| **IEEE SPC (Zero-Retuning)** | 23 recordings / 3,203 windows | **6.77 $\pm$ 9.22** | **3.17 (2.67)** | 10.28 | 97.81% |

### C. Real-Hardware Embedded MCU Profiling (STM32F103C8T6, 72-MHz ARM Cortex-M3)
Cycle-accurate DWT hardware profiling (`embedded_cortex_m3/`, bare-metal C99 without hardware FPU):
| Decoder Implementation | Complexity | Mean Cycles / Hop | Mean Latency @ 72 MHz | Duty Cycle (2-s Hop) | Flash / SRAM / Stack | Numerical Parity vs. MATLAB |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Dense Viterbi** | $\mathcal{O}(K^2)$ ($161 \times 161$) | 4,733,299 | 65.740 ms | 3.29% | 17.55 KB / 8.08 KB / 256 B | **254/254 exact (0.000 BPM)** |
| **Banded Viterbi** | $\mathcal{O}(KW)$ ($W=13$, $\pm 3\sigma_{\text{SSC}}$) | **423,854** | **5.887 ms** (**11.17$\times$ speedup**) | **0.29%** | **17.55 KB / 8.08 KB / 256 B** | **254/254 exact (0.000 BPM)** |

---

## 3. Repository Structure

```text
DS-PIT/
├─ README.md                         # Project overview, quickstart, and paper mapping
├─ REPRODUCIBILITY_GUIDE.md          # Step-by-step dataset setup & full reproduction guide
├─ LICENSE                           # MIT License
├─ run_all_experiments.m             # Master MATLAB entry point (live verification & full re-run)
│
├─ matlab/                           # Core DS-PIT MATLAB implementation & experiment drivers
│  ├─ ds5.m                          # Core DS-PIT tracker & ablation engine
│  ├─ a2_cfg.m                       # Frozen unified parameter configuration (Table II)
│  ├─ prep_dump2.m / prep_ieee.m     # Dataset preprocessing & spectral cache builders
│  ├─ prep_winlen.m                  # Window-length sensitivity cache builder (6s, 8s, 10s, 12s)
│  ├─ build_dalia_act.m              # PPG-DaLiA activity label alignment helper
│  ├─ exp_table1_stats.m             # Main Table I dataset & HR distribution statistics
│  ├─ exp_a2_core.m                  # Main Table IV & Supp Table S3 headline cross-dataset metrics
│  ├─ exp_a2_fig_boxplot.m           # Main Fig. 6 four-arm factorial ablation (Baseline, +SSC, +LBP, Full)
│  ├─ exp_a2_fig_traj_arms.m         # Main Fig. 7 representative trajectory comparisons
│  ├─ exp_a2_fig_sens.m              # Main Fig. 8 sensitivity to sigma_SSC and fixed lag D
│  ├─ exp_a2_tables.m                # Supp Tables S4, S5, S7 & Section III-C/E ablations
│  ├─ exp_a2_extra.m                 # Supp Tables S6, S8 (3-axis ACC & activity-stratified MAE)
│  ├─ exp_a2_nestedcv.m              # Supp Table S2 Leave-One-Subject-Out nested cross-validation
│  ├─ exp_ieee_prior_split.m         # Supp Section S2.1 2x2 transition-prior vs. support factorial
│  ├─ exp_lbp_temp_t3.m              # Supp Section S2.2 dynamic temperature tau_t significance test
│  ├─ exp_a2_heatmap.m               # Supp Fig. S1 2D hyperparameter surface (f_min x W_taper)
│  └─ results/                       # Pre-computed .mat outputs, execution logs, and CSV tables
│
├─ ieee_spc_standard/                # Standard IEEE SPC 2015 competition protocol (Main Table III)
│  ├─ WFPV_OVD_PISC.m                # Standard partition protocol driver
│  ├─ trans_prob.m / moving.m        # Empirical transition matrix & causal moving filter
│  ├─ results_v1_summary.txt         # Summary MAE across 12-Train, 10-Test, 11-Test, and All-23
│  └─ Results/                       # Saved per-recording predictions (Result_1.mat .. Result_23.mat)
│
├─ supplementary_controls/           # Isolated supplementary control experiments
│  ├─ ieee25_control/                # Supp Section S1.1: 25-Hz vs. 125-Hz sampling rate control
│  └─ pv_factorial/                  # Supp Section S3 & Table S5: Phase Vocoder 2x2 factorial
│
├─ embedded_cortex_m3/               # STM32F103C8T6 (72-MHz ARM Cortex-M3) real-hardware benchmark
│  ├─ fw/                            # Bare-metal C99 firmware (main.c, startup.c, stm32f103.ld, Makefile)
│  ├─ check_results.py               # Binary capture verifier & cycle/latency statistics
│  ├─ energy_estimate.py             # Datasheet-bounded energy & average power calculator
│  ├─ analyze_matrix.py              # Multi-clock (24/48/72 MHz) & multi-bandwidth (W=7/13/25) analyzer
│  └─ results/                       # Hardware SWD RAM dumps (fw_results.bin, matrix/*.bin) & summaries
│
├─ scripts/                          # Python statistical analyzers & automated paper verifier
│  ├─ verify_paper_results.py        # 38-point automated consistency check against paper & supplement
│  ├─ analyze_predictions.py         # Nonparametric bootstrap CI, exact sign-flip, and Holm-Bonferroni CLI
│  └─ four_arm_stats.py              # Four-arm factorial paired contrast & Monte Carlo analyzer
│
├─ tests/                            # Automated Python unit & reproducibility test suite (18 tests)
└─ figures/                          # Vector PDF figures & TikZ/PGFPlots LaTeX sources
```

---

## 4. Quickstart Verification (Under 5 Seconds)

### A. Verify All 38 Paper & Supplementary Metrics via Python (No MATLAB Required)
Run the automated consistency verifier and unit test suite using standard Python 3 (zero third-party dependencies required):

```bash
python scripts/verify_paper_results.py
python -m unittest discover -s tests -v
```

- `scripts/verify_paper_results.py` checks **38 headline metrics** across Main Tables I, III, IV, Main Figs. 6–8, Main Sections III-C through III-F, and Supplementary Sections S1–S6 against the saved experimental outputs (`38 passed, 0 failed`).
- `unittest discover` runs **18 unit and reproducibility tests** verifying the exact sign-flip permutation engine, Holm-Bonferroni step-down correction, cluster bootstrap confidence intervals, and paper-to-log numerical identity.

### B. Live MATLAB Reproduction
In MATLAB (R2021a or later), run from the repository root:

```matlab
run_all_experiments('verify')        % Verifies IEEE SPC Table III + runs ds5.m live on cache2/
run_all_experiments('recompute_all') % Re-executes all experiment drivers and regenerates logs/figures
```

---

## 5. Paper Table & Figure $\leftrightarrow$ Script Mapping

| Paper / Supplement Target | Description | Driver Script | Output Log / Artifact |
|:---|:---|:---|:---|
| **Main Table I** | Dataset characteristics & HR distribution ($<60$ / $>180$ BPM share) | `matlab/exp_table1_stats.m` | `matlab/results/table1_stats_log.txt` |
| **Main Table II** | Unified frozen hyperparameter table | `matlab/a2_cfg.m` | `matlab/a2_cfg.m` |
| **Main Table III & Sec. III-B.1** | IEEE SPC 2015 standard competition benchmark ($0.78 / 2.10 / 2.16 / 1.50$ BPM) | `ieee_spc_standard/WFPV_OVD_PISC.m` | `ieee_spc_standard/results_v1_summary.txt` |
| **Main Table IV & Sec. III-B.2** | Unified generalization on PPG-DaLiA ($5.83 \pm 2.18$) & WESAD ($5.76 \pm 3.24$) | `matlab/exp_a2_core.m` | `matlab/results/a2_core_log.txt` |
| **Main Fig. 6 & Sec. III-C** | Four-arm factorial ablation (Baseline, +SSC, +LBP, Full DS-PIT) | `matlab/exp_a2_fig_boxplot.m` | `matlab/results/a2_fig_boxplot_macro_lbp_log.txt` |
| **Main Fig. 7 & Sec. III-D** | Representative HR tracking trajectories (IEEE SPC Rec. 22 & PPG-DaLiA S5) | `matlab/exp_a2_fig_traj_arms.m` | `matlab/results/a2_fig_traj_arms_log.txt` |
| **Main Fig. 8 & Sec. III-E** | Sensitivity to transition bandwidth $\sigma_{\text{SSC}}$ & smoother lag $D$ | `matlab/exp_a2_fig_sens.m` | `matlab/results/a2_tables_log.txt` |
| **Main Sec. III-F & Supp Sec. S6** | STM32F103 Cortex-M3 cycle-accurate latency, memory, and energy profiling | `embedded_cortex_m3/check_results.py` | `embedded_cortex_m3/results/mcu_check_summary.txt` |
| **Supp Sec. S1.1** | Isolated 25-Hz vs. 125-Hz sampling rate control on IEEE SPC | `supplementary_controls/ieee25_control/run_ieee25_isolated.m` | `supplementary_controls/ieee25_control/results.json` |
| **Supp Sec. S1.2** | Window length sensitivity ($6, 8, 10, 12\text{ s}$) on PPG-DaLiA & WESAD | `matlab/prep_winlen.m` | `matlab/results/SUPPLEMENTARY_STATISTICS_20261007.csv` |
| **Supp Sec. S2.1 & Table S3** | $2 \times 2$ transition prior vs. spectral support factorial on IEEE SPC | `matlab/exp_ieee_prior_split.m` | `matlab/results/ieee_prior_split_log.txt` |
| **Supp Sec. S2.2 & Fig. S1** | Dynamic temperature $\tau_t$ contrast & $f_{\min} \times W_{\text{taper}}$ surface | `matlab/exp_lbp_temp_t3.m`, `exp_a2_heatmap.m` | `matlab/results/lbp_temp_t3_log.txt` |
| **Supp Table S2** | Leave-One-Subject-Out (LOSO) nested cross-validation ($12 \times 15$ grid) | `matlab/exp_a2_nestedcv.m` | `matlab/results/a2_nestedcv_log.txt` |
| **Supp Table S4** | Causal fixed-lag latency sweep ($D \in \{1,2,3,4,6,10,15\}$) & causal smoothers | `matlab/exp_a2_tables.m`, `exp_a2_causal_smooth.m` | `matlab/results/a2_tables_log.txt` |
| **Supp Sec. S3 & Table S5** | Cascaded Wiener filter ablation & Phase Vocoder $2 \times 2$ factorial | `matlab/exp_a2_tables.m`, `scripts/four_arm_stats.py` | `supplementary_controls/pv_factorial/` |
| **Supp Table S6** | Tri-axial accelerometer reference channel ablation ($x, y, z, \text{PC1}, \text{sum}$) | `matlab/exp_a2_extra.m` | `matlab/results/a2_extra_log.txt` |
| **Supp Table S8 & Figs. S2–S3** | Activity-stratified & HR-band / motion-quartile error breakdown | `matlab/exp_a2_extra.m`, `exp_a2_core.m` | `matlab/results/a2_extra_log.txt`, `a2_core_log.txt` |

---

## 6. Dataset Setup (For Rebuilding Spectral Caches from Raw Signals)

Pre-computed results and logs are already included in `matlab/results/`, `ieee_spc_standard/Results/`, `supplementary_controls/`, and `embedded_cortex_m3/results/`. To rebuild the spectral cache (`matlab/cache2/`) from raw public datasets, download the three public benchmarks and set the `DSPIT_DATA_ROOT` environment variable (or place them under `./raw_data/`):

1. **IEEE Signal Processing Cup (SPC) 2015** ([IEEE DataPort / Zhilin Zhang](https://zenodo.org/record/3902710)):
   - Place `Training_data/` (`DATA_01_TYPE01.mat` … `DATA_12_TYPE02.mat`) and `Test_data/` (`TEST_S01_T01.mat` … `TEST_S08_T01.mat`, `True_S01_T01.mat` … `True_S08_T01.mat`) under `<DSPIT_DATA_ROOT>/ieee_spc/`.
2. **PPG-DaLiA** ([UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/495/ppg+dalia)):
   - Place extracted subject MAT/pkl files under `<DSPIT_DATA_ROOT>/PPG-DaLiA/S1/` … `S15/`.
3. **WESAD** ([UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/465/wesad+wearable+stress+and+affect+detection)):
   - Place extracted subject files under `<DSPIT_DATA_ROOT>/WESAD/S2/` … `S17/`.

Then in MATLAB:
```matlab
setenv('DSPIT_DATA_ROOT', '/path/to/your/datasets');
cd matlab
prep_ieee      % Generates cache2/ieee_S1..S23.mat
prep_dump2     % Generates cache2/dalia_S1..S15.mat and cache2/wesad_S1..S15.mat
```

See [REPRODUCIBILITY_GUIDE.md](REPRODUCIBILITY_GUIDE.md) for detailed step-by-step instructions.

---

## 7. License

This project is released under the [MIT License](LICENSE).

# DS-PIT Reproducibility Guide

This document provides step-by-step instructions to reproduce every table, figure, statistical test, and hardware profiling result reported in **JBHI-01577-2026** (*A Dual-Scale Tracking Framework for Robust PPG-based Heart Rate Estimation in Daily Life and Exercise*) and its **Supplementary Materials (Sections S1–S6)**.

---

## 1. Three Levels of Reproducibility

To support fast verification as well as full end-to-end recomputation, this repository supports three reproducibility tiers:

| Tier | Requirements | Execution Time | What It Verifies |
|:---|:---|:---:|:---|
| **Tier 1: Instant Log & Artifact Audit** | Python $\ge 3.8$ (standard library only) | $< 2\text{ s}$ | Verifies 38 headline numbers across Main & Supplement + 18 unit tests (`scripts/verify_paper_results.py`). |
| **Tier 2: Live Tracker & Statistical Evaluation** | MATLAB R2021a+ & Spectral Cache (`cache2/`) | $\sim 15\text{ s}$ | Executes `ds5.m` with `a2_cfg.m` across all 53 recordings/subjects (90,378 windows) and regenerates all tables/figures (`run_all_experiments.m`). |
| **Tier 3: Full Raw-Signal Preprocessing & Hardware Build** | Raw Public Datasets + `arm-none-eabi-gcc` | $\sim 10\text{ min}$ | Rebuilds `cache2/` from raw PPG/ACC/ECG waveforms (`prep_ieee.m`, `prep_dump2.m`) and compiles the bare-metal STM32F103 firmware (`embedded_cortex_m3/fw/Makefile`). |

---

## 2. Tier 1: Automated Python Consistency & Statistical Test Suite

From the repository root, run:

```bash
python scripts/verify_paper_results.py
python -m unittest discover -s tests -v
```

### Statistical Analysis CLI (`scripts/analyze_predictions.py`)
The Python post-processing engine implements:
- Subject-macro and window-pooled MAE, RMSE, Median, IQR, P95, Bland–Altman Bias and 95% Limits of Agreement ($\text{Bias} \pm 1.96\,\text{SD}$), and Pearson $r$.
- Subject-level nonparametric percentile bootstrap 95% confidence intervals ($B=10{,}000$ resamples, deterministic `--seed`).
- Exact two-sided paired sign-flip permutation test ($2^N$ exhaustive enumeration for $N=15$ subjects; exact resolution $2^{-14} = 6.10 \times 10^{-5}$) with Holm–Bonferroni step-down multiplicity adjustment.

Example invocation on the Phase Vocoder $2 \times 2$ factorial outputs:
```bash
python scripts/four_arm_stats.py
```

---

## 3. Tier 2: MATLAB Tracker & Ablation Suite

### A. Frozen Unified Configuration (`matlab/a2_cfg.m`)
All multi-hour daily-life experiments (PPG-DaLiA and WESAD) and unified zero-retuning transfers use the exact configuration returned by `a2_cfg()`:

```matlab
o.f_lo        = 40;       % Lower state grid bound (BPM)
o.f_hi        = 200;      % Upper state grid bound (BPM), K = 161 states
o.step        = 1;        % Grid spacing (1 BPM)
o.D           = 3;        % Fixed-lag Viterbi lookahead (3 windows = 4 s wait)
o.state_lo_hz = 0.75;     % Macro-scale LBP lower frequency bound (45 BPM)
o.state_hi_hz = 3.0;      % Macro-scale LBP upper frequency bound (180 BPM)
o.edge_taper  = 30;       % Raised-cosine lower-edge taper width (30 BPM)
o.smooth_mode = 'median'; % Post-decoding causal filter type
o.smooth_m    = 3;        % Causal 3-point median filter
o.sigma       = 2;        % Micro-scale SSC transition standard deviation (2 BPM)
o.obs_mode    = 'ratio';  % Energy-normalized harmonic-sum spectral ratio
o.wf_variant  = 'orig';   % Dual-stage Wiener filter (L_WF = 15)
o.lbp_temp_w  = 1;        % Dynamic observation temperature enabled
o.lbp_temp_win= 30;       % Causal EMA window for peak prominence R_t (30 frames)
o.lbp_temp_lo = 0.7;      % Minimum temperature tau_min
o.lbp_temp_hi = 1.3;      % Maximum temperature tau_max
```

### B. Running Specific Experiment Drivers
In MATLAB:
```matlab
addpath('matlab');

% 1. Main Table I: Dataset & HR distribution statistics
run('matlab/exp_table1_stats.m');

% 2. Main Table IV & Supp Table S3: Headline cross-dataset generalization
run('matlab/exp_a2_core.m');

% 3. Main Fig. 6 & Section III-C: Four-arm factorial ablation (Baseline, +SSC, +LBP, Full)
run('matlab/exp_a2_fig_boxplot.m');

% 4. Main Fig. 7 & Section III-D: Representative trajectories (IEEE SPC Rec. 22 & PPG-DaLiA S5)
run('matlab/exp_a2_fig_traj_arms.m');

% 5. Main Fig. 8 & Supp Tables S4, S5, S7: Sensitivity & component ablations
run('matlab/exp_a2_fig_sens.m');
run('matlab/exp_a2_tables.m');

% 6. Supp Table S2: Leave-One-Subject-Out (LOSO) nested cross-validation
run('matlab/exp_a2_nestedcv.m');

% 7. Supp Section S2.1: 2x2 transition prior vs. spectral support factorial on IEEE SPC
run('matlab/exp_ieee_prior_split.m');

% 8. Supp Tables S6 & S8: 3-axis ACC reference & activity-stratified MAE
run('matlab/exp_a2_extra.m');
```

### C. IEEE SPC 2015 Standard Competition Protocol (`ieee_spc_standard/`)
To reproduce the standard IEEE SPC 2015 partition results reported in Main Table III (`0.78 ± 0.44 BPM` on 12-Train, `2.10 ± 1.96 BPM` on 10-Test, `2.16 ± 1.87 BPM` on 11-Test, `1.50 ± 1.54 BPM` on All-23):
```matlab
cd ieee_spc_standard
WFPV_OVD_PISC
```

---

## 4. Tier 3: Embedded ARM Cortex-M3 Firmware & Hardware Profiling (`embedded_cortex_m3/`)

The `embedded_cortex_m3/` directory contains the bare-metal C99 implementation of the DS-PIT Stage-2 MAP tracker profiled on a physical **STM32F103C8T6** (72-MHz ARM Cortex-M3, 64-KB Flash, 20-KB SRAM, no hardware FPU) via ST-LINK/V2 SWD and the hardware DWT cycle counter (`DWT->CYCCNT`).

### A. Inspect Saved Hardware Captures (No Hardware Required)
```bash
python embedded_cortex_m3/check_results.py
python embedded_cortex_m3/energy_estimate.py
python embedded_cortex_m3/analyze_matrix.py
```

### B. Recompile Bare-Metal Firmware
Requires `arm-none-eabi-gcc` in `PATH`:
```bash
cd embedded_cortex_m3/fw
make clean && make
arm-none-eabi-size build/dspit_m3.elf
```
See [`embedded_cortex_m3/REPRODUCTION.md`](embedded_cortex_m3/REPRODUCTION.md) for OpenOCD flashing and SWD SRAM dump commands.

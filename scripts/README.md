---
doc_id: "spec-004"
title: "Window prediction analyzer"
category: "spec"
role: "[State]"
status: "published"
date: "2026-09-13"
author: "未标注（2026-09-15 治理补录）"
tags: ["readme"]
related: []
---

# Window prediction analyzer

`analyze_predictions.py` is a deterministic, standard-library Python CLI for the post-processing stage described in `revision/EXPERIMENT_PROTOCOL.md`. It accepts a complete evaluation-window manifest and raw per-window predictions. The manifest is the denominator: absent predictions are emitted as `missing_prediction`, retained in `window_metrics.csv`, and counted in `n_failed`.

Example:

```powershell
python revision/scripts/analyze_predictions.py `
  --predictions predictions.csv `
  --expected-windows expected_windows.csv `
  --output-dir revision/results/postprocess `
  --baseline-method baseline `
  --protocol-id frozen_protocol_v1 `
  --state-list states.txt `
  --expected-hop-s 2 `
  --seed 20260911
```

`states.txt` must contain the actual discrete state grid used by the frozen algorithm (one BPM state per line, or a comma/space separated list). Do not substitute an illustrative range for the archived grid.

The required columns are shown in `revision/templates/predictions.csv` and `revision/templates/expected_windows.csv`. Each prediction must match its expected row's dataset, subject, recording, window, split, window times, and reference. Duplicate windows, unknown windows, a subject appearing in multiple splits, invalid times, invalid statuses, and metadata mismatches stop the run. A zero-row input also stops the run.

Outputs are `window_metrics.csv`, `subject_metrics.csv`, `aggregate_metrics.csv`, `stratified_metrics.csv`, and `run_metadata.json`. If a state list is supplied, `range_lower_bound.csv` reports the actual discrete-grid lower bound. If `--baseline-method` is supplied, pass `--protocol-id` to assert that the compared groups share one frozen protocol; explicit baseline variant/config values may select a baseline whose config differs from a candidate. Pairing requires identical valid-window sets and complete reference-valid coverage; coverage mismatches are reported as rejected, never silently inner-joined. Small-n sign-flip tests enumerate all signs; larger n uses Monte Carlo with the +1 correction under the paired subject exchangeability/symmetric-sign assumption. Holm correction is applied within dataset.

The primary aggregate is conditional subject-macro MAE with a subject bootstrap 95% CI and `subject_macro_mae_sd` (sample SD, ddof=1; blank for fewer than two subjects). `n_missing_subjects` and `subject_macro_mae_complete` make incomplete subject coverage explicit; the complete macro is blank whenever any expected subject is incomplete. A one-subject CI is blank and marked `insufficient_subjects`. Window-pooled MAE, RMSE, median/P95 absolute error, signed bias, threshold rates, coverage, and HR/activity strata are also reported. No metric is fabricated when there are no valid predictions; MAE fields remain blank. The output directory must be empty, which prevents stale paired/range files from contaminating a rerun. Figures are generated only for groups with real valid input; matplotlib PNGs are used when installed, otherwise dependency-free SVG bar/ECDF files are produced. Synthetic fixture outputs are engineering only until raw algorithm predictions are archived and reviewed.

Passing a positive `--expected-hop-s` additionally writes `failure_episodes.csv`. For each group, expected windows are sorted by subject/recording and time. A reference-valid window without status `success` is failed; success, invalid reference, recording changes, and time gaps larger than the hop break an episode. Adjacent window ends are joined only when `math.isclose` to the supplied hop. `decision_grid_duration_s` is exactly `n_failed_windows * expected-hop-s`: it is decision-grid occupancy, not the union of overlapping windows and not physiological failure duration. Without `--expected-hop-s`, the file is intentionally absent and metadata records that it was not requested.

For a one-command PowerShell run (the wrapper defaults to `python`; set `-PythonExe` to a bundled interpreter when required):

```powershell
& revision/scripts/run_analysis.ps1 -PythonExe python -Predictions predictions.csv -ExpectedWindows expected_windows.csv -OutputDir revision/results/postprocess -BaselineMethod baseline -ProtocolId frozen_protocol_v1 -BaselineVariant default -BaselineConfigId baseline_cfg -StateList states.txt -ExpectedHopS 2
```

Use `python -m unittest discover -s revision/tests -v` for the engineering self-test. Synthetic fixtures under `revision/tests/temp` are explicitly `ENGINEERING TEST ONLY` and must not be copied into paper results. This tool does not accept a method manifest; a method with zero prediction rows cannot be inferred from these CSVs, so provide explicit failed rows for every expected method.


### 四臂保存结果补统计（2026-09-30）
`four_arm_stats.py`只接收MATLAB从`a2_fig_boxplot.mat`导出的`arm_names/datasets/per_unit/means` JSON，不运行算法。DaLiA/WESAD每库15人、四臂全部6对，共12对作为一个Holm家族；精确枚举2^15符号翻转。配对bootstrap10000次、seed默认20260930、线性插值的点位95%CI不作同时覆盖校正。事后探索性分析，不覆盖开发选择；IEEE独立性未明，排除推断。输出目录必须为空。
```powershell
py -3 revision/scripts/four_arm_stats.py --input revision/audit/four_arm_stats_20260930/saved_vectors.json --output-dir revision/audit/four_arm_stats_20260930/analysis --seed 20260930
```
数学自测并入`py -3 -m unittest discover -s revision/tests -v`；输出须经科学复核后才可进入论文。

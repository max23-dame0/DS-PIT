---
doc_id: "e2e-01-log"
title: "E2E-01 日志：STM32F103 Cortex-M3 完整端到端处理链片上实测（2026-11-24）"
category: "audit"
role: "[Delta]"
status: "in-progress"
date: "2026-11-24"
author: "R2 小修会话"
---

# E2E-01 日志：完整 DS-PIT 处理链片上实测

> **纪律**：本日志只追加、不改写历史条目；禁止写入本机数据集绝对路径；数字入稿前须经交叉校验。
> **测量目标**：论文评估配置（`exp_paper_v3` base + `a2_cfg`）完整处理链（S1 带通滤波与重采样、S2 窗缓冲/z-score/FFT、S3 双分支幅值比增强与对数似然映射、S4 因果 LBP 可靠性温度更新、S5 固定滞后带状 Viterbi 解码、S6 3 点中值输出滤波）在 72-MHz ARM Cortex-M3（STM32F103，无 FPU，float32 软浮点）上的真实片上耗时与逐模块内存开销。

## [2026-11-23 / 2026-11-24] 条目 1：有效路径与非激活分支审计

依据 `revision/audit/method_dev/prep_dump2.m`、`ds5.m`、`a2_cfg.m`、`exp_paper_v3.m` 逐行核查，论文配置的有效代码路径如下（全部严格因果）：

1. **前端调理与重采样（`prep_dump2.m`）**：
   - 4 阶 Butterworth 0.4–4 Hz 带通（8 阶 IIR 传递函数），`filter(b, a, x)` 因果滤波（C 实现采用 4 级二阶节 SOS 级联保证 float32 数值稳定）。
   - 多相重采样至 25 Hz：DaLiA 原始 125 Hz（PPG + 3 轴 ACC，抽取因子 $p=1, q=5$）；WESAD BVP 原始 64 Hz、ACC 原始 32 Hz 先线性插值（`interp1(..., 'linear', 'extrap')`）至 64 Hz 后以 $p=25, q=64$ 重采样至 25 Hz。
2. **谱分析（`prep_dump2.m` + `ds5.m`）**：
   - 8 s 滑窗（200 样点 @ 25 Hz），2 s 步长（50 样点），每步零均值除样本标准差（$N-1$）标准化，1024 点 FFT，截取 `fb >= 0.75 & fb <= 3.0` Hz（92 频点）。
3. **双分支谱增强与似然映射（`ds5.m:obs_vec` + `ds5.m:191-256`）**：
   - `obs_mode = 'ratio'`、`wf_variant = 'orig'`、`acc_axes = 'sum'`。
   - `W1h` 与 `W2h` 为同一 15 帧归一化 PPG 幅度谱队列（合并存储数学等价）；三轴归一化 ACC 均值求 `base = accn / (W1n + eps)`，`WF1 = 1 - base`（`<0` 截为 `-1`），`c1 = |sp| * WF1`、`c2 = |sp| * W2n / (accn + W2n + eps)`，各自除样本标准差后相加 `ob.v = c1 + c2`。
   - 线性插值到状态网格 $40:1:200$ BPM（$K=161$），乘以 $[45, 180]$ BPM 区间 30-BPM 线性边缘渐变，min-max 归一后令 `L = (L - min)/(max - min + eps) + 1e-6`，`logL = log(L)`（`obs_gamma = 1`）。
4. **因果 LBP 可靠性温度（`ds5.m:168-189, 259-265, 317-356`）**：
   - `lbp_vel_L = 5`、`lbp_temp_w = 1`、`lbp_temp_win = 30`（$\tau \in [0.7, 1.3]$，初始 $R_{\text{rel}} = 0.5$）。
   - `hist_g` 长度达 15 帧前 `tau_c = NaN`（温度保持 1.0）；满 15 帧后，基于最近 6 帧解码输出 `veh` 计算速度 $\hat{v}_t = \operatorname{round}(\operatorname{clip}(\operatorname{median}(\Delta \text{veh}), \pm 2))$，锚 $a_t = \operatorname{mean}(\text{hist\_g}) + \hat{v}_t$，$d_{\text{obs}} = |60 f_{\arg\max(\text{ob.v})} - a_t|$，$\text{rel} = \exp(-(d_{\text{obs}}/20)^2)$，$R_{\text{rel}}$ EMA 更新后 $\tau_t = 0.7 + 0.6 R_{\text{rel}}$，`logL = tau_t * logL`。
5. **固定滞后 Viterbi 与输出平滑（`ds5.m:290-366`）**：
   - 静态高斯转移核 $\sigma_{SSC} = 2$ BPM（$K=161$），主路径固定滞后 $D=3$、嵌入式带状半宽 6（$W_{\text{band}} = 13$）；`t >= D` 时回溯 $D-1=2$ 步发射 `est(t-D+1)`，更新 `hist_g`（上限 15）与 `veh`（上限 6）。
   - `es = movmedian(est, 3)`（默认 `includenan` 语义，流式等价滞后 1 帧 = 2 s）。

**确认未启用分支（不移植，且确认有效路径无整记录非因果统计）**：
- `obs_mix = 0`（故 `ds5.m:108` 的整记录中位数 `qN` 未被调用）、`q_flat = 0`、`ma_pen = 0`、`ac_w = 0`、`acc_int_w = 0`、`q_feat = 'off'`（`qn` 未用）、`rc_mode = 'off'`、`lbp_gate = 'off'`、`lbp_prior_w = 0`、`lbp_vel_use = 'off'`（`TS` 为空）、`lbp_cand_g = 0`、`lbp_harm_w = 0`、`lbp_spec_w = 0`、`lbp_sel_g = 0`、`islocalmax` 仅用于未消费的 `cand_pk`。

## [2026-11-23] 条目 2：MATLAB 金标准导出与主机双精度/单精度验证完成

1. **MATLAB 金标准与回归门禁（`exp_export_e2e.m` -> `results/e2e_export_log.txt`）**：
   - 注入只读 `dump_trace` 与 `F_data` 后回归精确复现：`base = (5.9584, 5.7836)`，`a2_cfg = (5.8302, 5.7569)`。
   - **Check A**（全长直接型 `filter(b,a) + resample` vs `cache2` 92 频点 `S/A`）：`s1, s2, s3, ws1, ws2` 五条记录全部 `relErr_S = 0.000e+00`、`relErr_A = 0.000e+00`（阈值 $\le 10^{-10}$）。
   - **Check B vs C**（257 窗 SOS `double` 前缀 vs 全长 `cache2`，评估 254 有效 `es` 窗）：`s2/s3/ws1/ws2` 均 `254/254`（`MAE diff = 0.0000`）；`s1` 为 `est 251/254`、`es 250/254`（`MAE 7.2474 vs 7.2190`，`|diff| = 0.0284`）。
2. **主机 C99 逐模块隔离与端到端验证（`host_test/` -> `results/host_verify_log.txt`）**：
   - `-Wall -Wextra -std=c99` 零警告编过 `test_f64.exe` 与 `test_f32.exe`。
   - **分模块隔离 `REAL_DOUBLE` 验证全通过（PASS）**：
     * `S1`: `x25` 最大误差 `<= 4.55e-11`；
     * `S2`（两路实信号打包 1024-pt FFT）: 相对误差 `<= 2.62e-14`；
     * `S3`（合并单 `15x92` 历史队列）: 非阈值点 `obv <= 6.22e-15`、`logL <= 1.87e-11`（`s3`/`ws1` 各 1 窗跨越 `WF1 < 0 -> -1` 硬阶跃）；
     * `S4`: `tau <= 2.22e-16`、`logL_post <= 3.55e-15`；
     * `S5` + `S6`: 全部 5 条记录 `254/254 (100%)` 精确一致。
   - **端到端 `float32`（`banded W=13` 与 `dense` 完全一致）**：
     * `ws1`: `254/254` (`100.0%`), `MAE 3.6272 vs 3.6272` (`|diff|=0.0000`)；
     * `ws2`: `254/254` (`100.0%`), `MAE 11.7574 vs 11.7574` (`|diff|=0.0000`)；
     * `s2`: `249/254` (`98.0%`), `MAE 4.8966 vs 4.8769` (`|diff|=0.0197`)；
     * `s3`: `252/254` (`99.2%`), `MAE 10.8070 vs 11.1525` (`|diff|=0.3454`)；
     * `s1`: `225/254` (`88.6%`), `MAE 6.5678 vs 7.2190` (`|diff|=0.6512`) —— 静坐段 ACC 标准差降至 `3.5e-12` 附近时 `float32` 滤波噪声经 z-score 放大并跨越 `WF1 < 0 -> -1` 跳变；
     * 5 记录合并（1270 窗）：`es` 一致率 `97.17%`（1234/1270），合并同窗 MAE `7.5312` vs `7.7266` BPM（未劣化）。按规划裁决继续采用纯 `float32` 端到端管线推进真机实测并透明披露。

## [2026-11-23] 条目 3：STM32F103 完整端到端板级实测与汇总验收完成

1. **固件构建（`fw/fw.elf` / `fw.bin` / `fw.map`）**：
   - 使用 `arm-none-eabi-gcc 14.2.Rel1`（`-mcpu=cortex-m3 -mthumb -O2 -fno-math-errno --specs=nano.specs`）零警告编过。
   - 经 `fw.map` 精确解析：总 Flash `22,771 B`（22.8 kB / 22.24 KiB，其中算法 21,799 B，测试桩 972 B）；算法静态 RAM `26,556 B`（26.6 kB / 25.93 KiB），实测栈高水位 `2,192 B`（2.2 kB / 2.14 KiB），算法峰值 RAM `28,748 B`（28.7 kB / 28.07 KiB）；加上邮箱与 `libc` `impure` 后总 SRAM 占 `32,964 B`（远低于 64 KiB 上限）。
2. **真机流式运行矩阵（`host_driver/stream_e2e.py` @ 72 MHz）**：
   - **5 条规范记录（`s1_r1, s2, s3, ws1, ws2`, banded $W=13$）**：真机输出与主机 `float32` 参照 **1,270/1,270 窗（100.00%）**逐字节一致（`tau_diff = 0.0`）。
   - **5 记录合并稳态耗时**：总均值 `208.435 ms`（P95 `224.011 ms`、max `224.182 ms`，相对 2-s 步占空比 **10.42%**），其中 DaLiA 均值 `223.713 ms`（11.19%）、WESAD 均值 `185.520 ms`（9.28%）。各阶段均大幅低于 2,000 ms 步长。
   - **可重复性（`s1` ×3）**：`s1_r1`/`s1_r2`/`s1_r3` HR 与 $\tau_t$ 输出完全一致，单块最大周期差 $\le 2$ 周期（相对波动 0.000%）。
   - **Dense 对照（`s1_dense`）**：banded 与 dense 输出 254/254 一致，S5 均值由 `69.001 ms` 降至 `6.336 ms`（10.89× 加速），端到端总均值由 `286.324 ms` 降至 `223.659 ms`。
3. **产物归档**：`analyze_e2e.py` 与 `make_manifest_e2e.py` 生成 `results/results_summary_e2e.json`、`E2E-01_REPORT.md`、`REPRODUCTION.md`、`INDEX.md` 与 `MANIFEST_SHA256.txt`。


---
doc_id: "reference-001"
title: "实验代码与结果总索引"
category: "reference"
role: "[State]"
status: "published"
date: "2026-09-15"
author: "未标注（2026-09-15 治理补录）"
tags: ["index"]
related: []
---

# 实验代码与结果总索引

最后更新：2026-09-17
目录：`revision/audit/method_dev/`
上层文档：`revision/*.md`

> **用途**：把所有实验代码、结果、缓存、文档对应起来，避免后续找不到。
> 缓存体积约 7.7 GB，已在 `.gitignore` 中排除，可由 `prep_*.m` 重建。

---

## A. 快速定位

| 我要找… | 文件 |
|---|---|
| **主方法实现** | `ds5.m` |
| **论文 headline（DaLiA 5.958 / WESAD 5.784，$D=3$ + 固定 σ=2）** | `exp_paper_v3` → `results/paper_v3.mat` + `paper_v3_log.txt`；配置与口径见 `../../../EXPERIMENT_SUMMARY_20260916.md` §0 |
| **嵌套交叉验证结果** | `exp_nestedcv(3)` → `results/nestedcv_D3.mat`（**固定 σ=2**）；配对日志为 `nestedcv_sigma2_log.txt`——`nestedcv_D3_log.txt` 是已被取代的自适应 σ 旧运行 |
| 活动分层分析 | `exp_r3c05_v2(3)` + `build_dalia_act.m` → `results/dalia_activity.mat`（**旧脚本 `exp_r3c05.m` / `exp_r3c05_unified.m` 硬编码 $D=15$ 且用 `movmean(4)` 平滑，与统一配置不符，勿用**） |
| 转移带宽对照 | `exp_sigma_ablation.m` → `results/sigma_ablation.mat`（无配对检验）；**现行以 `exp_paper_v3` → `paper_v3.mat` §3 为准** |
| ACC 合成对照（R3-C04） | `exp_r3c04.m` → `results/r3c04_*.mat` |
| 窗长对照（R3-C19） | `prep_winlen.m` → `cache_w40/`、`cache_w60/`；**比较脚本 `exp_winlen_cmp.m` → `results/winlen.mat` + `winlen_log.txt`** |
| Table I 三库统计 | `exp_table1_stats` → `results/table1_stats.mat` + `table1_stats_log.txt`（2026-09-17 起落盘） |
| IEEE v1 复核（1.50） | `verify_ieee_150` → `results/verify_ieee_150_log.txt`（2026-09-17 修复列广播 bug，输出 1.50036 / 1.54004） |
| 自适应 σ 均值证据 | `exp_sigma_mean` → `results/sigma_mean.mat`（2.45 / 2.51） |
| 补充指标（RMSE / >5%，R3-C14） | `exp_extra_metrics` → `results/extra_metrics.mat` + `extra_metrics_log.txt`（三库 subject-macro；pooled 对照同存） |
| 统一配置 gate 复核（E1，BLK-1a） | `exp_gate_unified` → `results/gate_unified.mat` + `gate_unified_log.txt`（2026-09-18；含 `ds5` 默认关闭的 `lbp_gate` 注入点，off 时 headline 逐位复现） |
| IEEE 逐记录 + 区间（E2，BLK-2b/2c） | `exp_ieee_per_record` → `results/ieee_per_record.mat` + `ieee_per_record_log.txt`（2026-09-18；top-3 占 53.9% 总绝对误差，CI [3.75, 11.05]） |
| 偏置拆分 + HR 带分层（E3/E5，CM2a/CM4a） | `exp_bias_strata` → `results/bias_strata.mat` + `bias_strata_log.txt`（2026-09-18；taper 移除→11.53/9.24；分层见日志） |
| 前端消融·统一配置（E4，CM1a/b） | `exp_fe_unified` → `results/fe_unified.mat` + `fe_unified_log.txt`（2026-09-18；WF2 关键，WF1 边际） |
| 窗口级运动协变量（E6，CM3a） | `exp_motion_covariate` → `results/motion_covariate.mat` + `motion_covariate_log.txt`（2026-09-18；r=0.24/0.33，四分位 MAE 3.1→9.3） |
| 加速度参考 MAE 级对照（M-20，R3-m7） | `exp_acc_mae` → `results/acc_mae.mat` + `acc_mae_log.txt`（2026-09-18；sum 最优，PC1 +0.17/+0.33） |
| 输出替换式门控（G1，PD-1 路线 A） | `exp_gate_hard` → `results/gate_hard.mat` + `gate_hard_log.txt`（2026-09-18；三变体均退化 +0.65~+1.44） |
| 路线 A · T1 机制诊断（PD-1） | `exp_gate_diag` → `results/gate_diag.mat` + `gate_diag_log.txt`（2026-09-18；keep 语义缓冲冻结→锁定；替换帧 Δerr +25/+48 BPM） |
| 路线 A · T2 候选快筛 | `exp_lbp_screen` → `results/lbp_screen.mat` + `lbp_screen_log.txt`（2026-09-18；CF-2 +0.007；V2 先验全退化） |
| 路线 A · T3 验收 | `exp_lbp_v2` → `results/lbp_v2.mat` + `lbp_v2_log.txt`（2026-09-18；两库全局/regime 全 Holm=1.0；判级不成立） |
| 路线 A · 滞后诊断 | `diag_lag_probe` → `results/diag_lag_probe.mat` + `diag_lag_probe_log.txt`（2026-09-18；τ*≈2 窗，全局上界 0.32/0.17 BPM） |
| 路线 A · 观测峰诊断 | `diag_obs_peak` → `results/diag_obs_peak.mat` + `diag_obs_peak_log.txt`（2026-09-18；高 HR 带为观测级限制） |
| 路线 A · 第二批 T2/T3（M-LBP-V） | `exp_lbp_vel_screen` / `exp_lbp_vel_t3` → `results/lbp_vel_{screen,t3}.mat` + 日志（2026-09-18；V-kernel 否决；V-lead 字面强成立/实践无） |
| 路线 A · top-3 上限诊断 | `diag_obs_topk` → `results/diag_obs_topk.mat` + 日志（2026-09-18；oracle 4.86/4.21，命中 78.7%/79.4%） |
| 路线 A · 第三批 T2/T3（M-C） | `exp_lbp_cand_screen` / `exp_lbp_cand_t3` → `results/lbp_cand_{screen,t3}.mat` + 日志（2026-09-18；DALiA Q4 −0.59 n.s.；WESAD 反向 → 非稳健，总收口） |
| 路线 A · 第四批 T2（A1/A2/B/C） | `exp_lbp_obs4_screen` → `results/lbp_obs4_screen.mat` + 日志（2026-09-18；仅 C 改善） |
| 路线 A · 第四批 T3/剂量/控制（C 机制） | `exp_lbp_temp_t3` / `exp_lbp_temp_dose` / `exp_lbp_temp_ctrl` → `results/lbp_temp_{t3,dose,ctrl}.mat` + 日志（2026-09-18；**弱成立**：WESAD 90–150 带 Holm 0.0208；剂量单调；常数 τ 对照） |
| **A′ 执行（评估配置 = C1；正文已按此改写）** | `a2_cfg.m` + `exp_a2_{core,tables,bandtaper,nestedcv,extra,strata,heatmap,prior}` → `results/a2_*.mat` + 日志；headline **5.8302/5.7569/6.7659**；热力图资产 `figures/Error_Heatmap_DSPIT_A2.pdf`（2026-09-18/19；2026-09-21 由仓库根迁入） |
| **IEEE 高尾定位（A′）** | `diag_ieee_tail` → `results/diag_ieee_tail.mat` + 日志（2026-09-19；记录 10/17 为 >150 BPM 高 HR 记录，**半频锁定**占 40%/9%；去斜坡后记录 10 43.02→4.69、全集 6.77→4.42；WESAD 去斜坡代价 +3.38 → 斜坡为权衡） |
| **v1 参考实现复刻（IEEE 口径）** | `../v1_repro_20260920/`（**独立工作区**，非 `method_dev`）：参考实现副本 + `all_data` 只读 junction；原样复现 1.5004（训练 0.874/测试 2.183）、协议内核（仅 12 条训练记录）训练 0.806/测试 **2.164**/全集 **1.455**、解析核训练 0.88–0.94/测试 7.44–7.50；证据 `results_v1_{summary,per_record}.txt` + `results_v1_full_log.txt`（2026-09-20；D018/D019） |
| 延迟–精度折中（R3-C08） | `../../../FINAL_UNIFIED_20260915.md` §七（$D=1\ldots15$ 实测表） |
| 预计算主缓存 | `prep_dump2.m` → `cache2/` |
| CurToSS 复现 | `curtoss2.m` … `curtoss8.m` + `CURTOSS_ANALYSIS.md` |
| 灾难受试者诊断 | `diag_catastrophic.m` |
| 误差构成诊断 | `diag_errtype.m` |
| 早期实验日志 | `PROGRESS.md`（P-01…P-11） |

---

## B. 代码索引

### B1. 主方法（最终成果）

| 文件 | 作用 | 状态 |
|---|---|---|
| **`ds5.m`** | **主方法 v5**：v4 + 质量自适应带宽 + 证据带扩展/带边斜坡 + 完整指标。含全部新选项（`edge_taper`、`q_feat`、`q_dir`、`sigma_lo/hi`、`wf_variant`、`smooth_mode`、`obs_mode`、`cachedir`） | ✅ 最终 |
| `ds4.m` | v4：SSC 高斯 + 可选重捕获 + 观测混合 | 历史（基线来源） |
| `ds3.m` | v3：更早实现 | 历史 |
| `dspit2.m` | 最早的 DS-PIT 实现 | 历史 |

### B2. 评估与实验脚本

| 文件 | 作用 | 对应意见 | 状态 |
|---|---|---|---|
| **`exp_final_unified.m`** | 统一配置的完整指标评估（MAE/Med/P95/bias/LoA/r/覆盖率） | 主结果 | ✅ |
| **`exp_nestedcv.m`** | 回顾性嵌套受试者交叉验证（5 折，内层选参） | AE-1、R3-C02 | ✅ |
| `exp_r3c05_unified.m` | 统一配置确认（含活动分层早期版） | — | ✅ |
| `exp_r3c05.m` | 活动分层分析（真实标签） | R3-C05 | ✅ |
| `exp_r3c04.m` | PPG–ACC 跨频相关：逐轴 / 三轴和 / PCA-1 | R3-C04 | ✅ |
| `exp_stats.m` | 完整指标集 + 全指标表输出；**`results/stats_all.mat` 的真正来源**（CurToSS 机制吸收 G0–G7） | R3-C14/C15 | ✅ |
| **`exp_paper_v3.m`** | **论文最终数字**：headline 全指标 + 延迟表 + 带宽对照与配对检验（固定 σ=2、D=3）→ `results/paper_v3.mat` | R3-C08/C15、AE-1 | ✅ **现行主脚本** |
| `exp_sigma_ablation.m` | 转移带宽对照（无配对检验）→ `results/sigma_ablation.mat` | R3-C15 的一部分 | ✅ |
| `exp_ieee_unified.m` | IEEE SPC 统一协议重算（23 条）→ `results/ieee_unified.mat` | 表 III v2 的 IEEE 格 | ✅ |
| `exp_table1_stats.m` | Table I 三库统计量（12 格）→ `results/table1_stats.mat` | 表 I | ✅（2026-09-17 起落盘） |
| `exp_winlen_cmp.m` | 窗长对照 4/6/8 s 复现 → `results/winlen.mat` | R3-C19 | ✅（2026-09-17 新增） |
| `exp_sigma_mean.m` | 自适应 σ_t 均值证据 → `results/sigma_mean.mat` | 记录审计 RA-14 | ✅（2026-09-17 新增） |
| `exp_extra_metrics.m` | 三库 subject-macro RMSE 与 >5%（pooled 对照同存）→ `results/extra_metrics.mat` | R3-C14 | ✅（2026-09-17 新增） |
| `exp_gate_unified.m` | 统一配置 gate on/off 复核（`ds5` 新增默认关闭 `lbp_gate` 注入点；off 逐位复现 headline）→ `results/gate_unified.mat` | BLK-1a / E1 | ✅（2026-09-18 新增） |
| `exp_ieee_per_record.m` | IEEE 23 条逐记录 MAE/份额 + recording-level bootstrap CI → `results/ieee_per_record.mat` | BLK-2b/2c / E2 | ✅（2026-09-18 新增） |
| `exp_bias_strata.m` | taper×输出滤波 2×2 + 参考 HR 带分层 + coverage 缺口核验 → `results/bias_strata.mat` | CM2a / CM4a / E3+E5 | ✅（2026-09-18 新增） |
| `exp_fe_unified.m` | 统一配置前端消融（WF1/WF2/raw + 配对检验）→ `results/fe_unified.mat` | CM1a/b / E4 | ✅（2026-09-18 新增） |
| `exp_motion_covariate.m` | 窗口级误差-运动量相关与四分位分箱（含 MAE 核验）→ `results/motion_covariate.mat` | CM3a / E6 | ✅（2026-09-18 新增） |
| `exp_acc_mae.m` | 加速度参考 MAE 级对照（ds5 新增 `acc_axes`，默认 sum 逐位兼容）→ `results/acc_mae.mat` | M-20 / R3-m7 | ✅（2026-09-18 新增） |
| `exp_gate_hard.m` | 输出替换式门控复测（ds5 新增 `lbp_gate='hard'` + `lbp_buf_mode`）→ `results/gate_hard.mat` | G1 / PD-1 路线 A | ✅（2026-09-18 新增） |
| `exp_gate_diag.m` | T1 门控机制诊断（ds5 新增默认关闭 `lbp_diag`；4 配置重跑 + 事件落盘 + 归因）→ `results/gate_diag.mat` | 路线 A T1 | ✅（2026-09-18 新增） |
| `exp_lbp_screen.m` | T2 候选快筛（CF-1/2/3、V2 先验三档；DALiA + 配对检验）→ `results/lbp_screen.mat` | 路线 A T2 | ✅（2026-09-18 新增） |
| `exp_lbp_v2.m` | T3 验收（CF-2/CF-3；两库、全局 + Q4 + 恢复段；配对 + Holm + CI）→ `results/lbp_v2.mat` | 路线 A T3 | ✅（2026-09-18 新增） |
| `diag_lag_probe.m` | 滞后诊断（时移扫描 + 分带偏差 + 导数相关）→ `results/diag_lag_probe.mat` | 路线 A 机制设计 | ✅（2026-09-18 新增） |
| `diag_obs_peak.m` | 观测峰诊断（obs_pk vs est vs ref；2×2 + 分带）→ `results/diag_obs_peak.mat` | 路线 A 机制设计 | ✅（2026-09-18 新增） |
| `exp_lbp_vel_screen.m` | M-LBP-V 快筛（V-kernel / V-lead 三档 / both / L=3；DALiA）→ `results/lbp_vel_screen.mat` | 路线 A 第二批 T2 | ✅（2026-09-18 新增） |
| `exp_lbp_vel_t3.m` | M-LBP-V 的 V-lead 家族两库 T3（全局 + 90–150 带 + Q4 + 恢复段；家族 Holm）→ `results/lbp_vel_t3.mat` | 路线 A 第二批 T3 | ✅（2026-09-18 新增） |
| `diag_obs_topk.m` | top-3 峰上限诊断（oracle 误差 + 命中率 + 谐波比例分布）→ `results/diag_obs_topk.mat` | 路线 A 第三批设计 | ✅（2026-09-18 新增） |
| `exp_lbp_cand_screen.m` | M-C 候选峰先验快筛（γ/σh/趋势对照；DALiA）→ `results/lbp_cand_screen.mat` | 路线 A 第三批 T2 | ✅（2026-09-18 新增） |
| `exp_lbp_cand_t3.m` | M-C 家族两库 T3（家族 Holm=12）→ `results/lbp_cand_t3.mat` | 路线 A 第三批 T3 | ✅（2026-09-18 新增） |
| `exp_lbp_obs4_screen.m` | 第四批快筛（A1 谐波 / A2 长时谱 / B 投票选择 / C 自适应温度；DALiA）→ `results/lbp_obs4_screen.mat` | 路线 A 第四批 T2 | ✅（2026-09-18 新增） |
| `exp_lbp_temp_t3.m` | C 家族两库 T3（τ∈[0.7,1.3]，W=30/15；4 指标家族 Holm）→ `results/lbp_temp_t3.mat` | 路线 A 第四批 T3 | ✅（2026-09-18 新增） |
| `exp_lbp_temp_dose.m` | τ 幅度剂量–响应（[0.6,1.4]/[0.5,1.5]）→ `results/lbp_temp_dose.mat` | 路线 A 第四批机制 | ✅（2026-09-18 新增） |
| `exp_lbp_temp_ctrl.m` | 极端剂量 τ∈[0.4,1.6] + 常数 τ 消融 → `results/lbp_temp_ctrl.mat` | 路线 A 第四批控制 | ✅（2026-09-18 新增） |
| `a2_cfg.m` | A′ 共享注入（`lbp_vel_L=5, lbp_temp_w=1, lbp_temp_win=30`）；关闭即回旧口径 5.9584/5.7836 | A′ / D016 | ✅（2026-09-18 新增） |
| `exp_a2_core.m` | A′ 核心指标（两库 + IEEE 三口径；含 HR 带与运动四分位）→ `results/a2_core.mat` | A′ | ✅（2026-09-18 新增） |
| `exp_a2_tables.m` | A′ 表格复算（带宽/延迟/前端/ACC/bias 2×2/门控复测）→ `results/a2_tables.mat` | A′ | ✅（2026-09-18 新增） |
| `exp_a2_bandtaper.m` | A′ 证据带 × 斜坡 2×2 → `results/a2_bandtaper.mat` | A′ | ✅（2026-09-18 新增） |
| `exp_a2_nestedcv.m` | A′ 嵌套 CV（5 外折，带边/斜坡折内选）→ `results/a2_nestedcv_D3.mat` | A′ | ✅（2026-09-18 新增） |
| `exp_a2_extra.m` | A′ 补充：IEEE 窄带对照/池化与记录级统计/记录份额、ACC 配对 p、活动分层全表 → `results/a2_extra.mat` | A′ 正文 | ✅（2026-09-19 新增） |
| `exp_a2_strata.m` | A′ 分层：运动四分位（含 >5%/>10%）+ 实测温度 τ 分布（依赖 `ds5` 诊断字段 `evd.tau`）→ `results/a2_strata.mat` | A′ 正文 | ✅（2026-09-19 新增） |
| `exp_a2_heatmap.m` | A′ 活动 × HR 带热力图（9×6，含窗数）→ `results/a2_heatmap.mat` + `figures/Error_Heatmap_DSPIT_A2.pdf`（2026-09-21 由仓库根迁入） | A′ 正文 | ✅（2026-09-19 新增） |
| `exp_a2_prior.m` | A′ 下 v1→v2 差距分解（原带无斜坡：解析核 5.3552 / 真值核 16.6431、15.1320）→ `results/a2_prior.mat` | A′ 正文（表注 f/Limitations） | ✅（2026-09-19 新增） |
| `exp_a2_ieee_sigma.m` | IEEE SPC 的 σ 扫描（8 档）+ 三库对照 → `results/a2_ieee_sigma.mat` | **留档，不入正文**（D027 已撤回；本阶段范围为排版/正文/图表） | ⛔ 不采用（2026-09-21） |
| `exp_a2_heatmap_plot.m` | Fig. 5 重绘（只读 `results/a2_heatmap.mat`；新配色 + 自适应字色）| A′ 图件 | ✅（2026-09-21） |
| `diag_ieee_tail.m` | IEEE 高尾定位：逐记录 MAE/bias/半频占比/斜坡滞留/最长常数段 + v1 归档对照；去斜坡同记录复测 → `results/diag_ieee_tail.mat` | A′ 正文（§III-B 高尾段 + Limitations 权衡句） | ✅（2026-09-19 新增） |
| `exp_a2_causal_smooth.m` | **输出滤波因果性对照**（median 居中 14 s / mediancausal 尾随 12 s / off 无滤波 12 s）：复用同一次 `ds5` 调用的 raw `est`（与 `smooth_mode` 无关）离线重算三种规则 + 配对符号翻转 + Holm → `results/a2_causal_smooth.mat`；**护栏**：先复核 median 逐位复现 5.8302/5.7569 | 审查 V2 P0-2 选项 (b) 前置评估 | ✅（2026-09-23 新增） |
| `exp_a2_latency_causal.m` | **延迟扫描 · 居中 vs 尾随中值**（`Dl=[1 2 3 4 6 10 15]`，与 `exp_a2_tables.m` §[2] 同口径）：每个 (数据集, D) 一次 `ds5`，两规则离线重算；含与 `a2_tables.mat` 的逐位交叉复核 → `results/a2_latency_causal.mat`；结论：尾随全档劣化 +0.20~+0.37 BPM（Holm m=7 → 0.0007~0.0008），需 D=10 才追平居中 D=3 | 审查 V2 P0-2 / §B.7（支撑作者选定的路线 (a)） | ✅（2026-09-23 新增） |
| `verify_ieee_150.m` / `probe_ieee_smooth.m` | IEEE v1 复核（1.50036/1.54004）与定位探针；**2026-09-17 修复列广播 bug + addpath** | 表 III v1 行 | ✅ |
| `exp_abl_stats.m` | 消融与配对统计（bootstrap / sign-flip / Holm）；**用 ds3，非 R3-C15 的现行证据**（现行 = `exp_paper_v3.m`） | — | 历史 |
| `exp_B.m` | 路线 A 组件全面扫描（12 组） | — | ✅ |
| `exp_A.m`、`exp_dsweep.m`、`exp_fe_abl.m`、`exp_final1.m`、`exp_dev1.m`、`exp_dev2.m`、`exp_full1.m`、`exp_lab1–3.m`、`exp_curtoss.m`、`run_exp.m` | 各阶段实验 | — | 历史 |
| `tracker_lab.m` | 离线跟踪器实验室（固定前端换跟踪器） | — | ✅ |

### B3. 缓存生成器

| 文件 | 生成 | 受试者 | 体积 |
|---|---|---|---|
| **`prep_dump2.m`** | `cache2/`——主缓存（8 s 窗、25 Hz、含时域窗与逐通道 RMS） | 30 | 1.7 GB |
| `prep_dump.m` | `cache/`——早期版本 | 30 | 1.2 GB |
| **`prep_winlen.m`** | `cache_w40/`、`cache_w60/`——受控窗长对照（4 s / 6 s） | 各 30 | 1.4 + 1.6 GB |
| `curtoss_prep.m` | `cache3/`——CurToSS 稀疏谱图像（FOCUSS，max-pooling） | 30 | 462 MB |
| `prep_front.m` | `cache3f/`——常规谱对照（6 受试者） | 6 | 96 MB |
| `prep_focuss.m` | `cache4/`——FOCUSS 观测（供 ds5 切换前端） | 30 | 1.2 GB |

### B4. CurToSS 复现（未达成，保留备查）

| 文件 | 说明 |
|---|---|
| `focuss_troika.m` | TROIKA 式 Regularized M-FOCUSS（修正版：负频镜像 + 按 M/Np 分支 + λ 正则化） |
| `test_focuss_synth.m` | 合成信号校验（暴露过实现错误） |
| `curtoss2.m` – `curtoss8.m` | 追踪器 7 代迭代，`curtoss8.m` 为最优（局部窗口解耦版） |
| `curtoss.m` | 最早的峰级简化版 |
| `diag_eig.m` | 真值脊线在特征值图像中的排名（45/146 → 7/146） |
| `diag_front.m` | 不同谱前端的 peakHit 对照 |
| `diag_focuss.m` | FOCUSS 参数扫描 |
| `curtoss_paper.txt`、`troika_paper.txt` | 两篇原文全文提取 |

### B5. 诊断脚本

| 文件 | 诊断内容 |
|---|---|
| `diag_catastrophic.m` | 灾难受试者：连续错误事件、活动、边界、运动强度、误差符号 |
| `diag_errtype.m` | 误差构成：倍频/半频 vs 其它；>10 BPM 窗的 MAE 贡献 |
| `diag_align.m` | 时间对齐诊断 |
| `diag_fe.m` | 前端诊断 |
| `ac2.m` | 自相关周期证据（**负结果**，保留备查） |

### B6. 工具

| 文件 | 作用 |
|---|---|
| **`build_dalia_act.m`** | 从 `S*_activity.csv` 重建 DaLiA 逐窗活动标签（修复 `prep_dump2.m` 的硬编码 bug） |

---

## C. 结果索引（`results/`，共 33 个文件，约 2.9 MB）

### C1. 关键结果（返修稿直接引用）

| 文件 | 大小 | 内容 | 产生脚本 |
|---|---:|---|---|
| **`paper_v3.mat`** | 4.3 KB | **论文 headline / 延迟表 / 带宽对照 + 配对检验**（固定 σ=2、D=3） | `exp_paper_v3.m` |
| **`nestedcv_D3.mat`** | 3.4 KB | 嵌套 CV（固定 σ=2、D=3）：(配置 × 受试者) MAE 矩阵、每折选参与外层 MAE | `exp_nestedcv.m` |
| `nestedcv.mat` | 3.5 KB | 嵌套 CV **旧包（D=15、自适应 σ）**：仅作演进记录 | `exp_nestedcv.m`（旧版） |
| `sigma_ablation.mat` | — | 转移带宽对照（无配对检验；现以 `paper_v3.mat` 为准） | `exp_sigma_ablation.m` |
| `ieee_unified.mat` | 1.2 KB | IEEE SPC 统一协议重算（23 条） | `exp_ieee_unified.m` |
| `winlen.mat` | 1.5 KB | 窗长对照 4/6/8 s（D=15 + 自适应 σ 口径） | `exp_winlen_cmp.m`（2026-09-17 新增） |
| `sigma_mean.mat` | 0.7 KB | 自适应 σ_t 均值证据（2.45 / 2.51） | `exp_sigma_mean.m`（2026-09-17 新增） |
| `table1_stats.mat` | 0.7 KB | Table I 三库统计量（12 格） | `exp_table1_stats.m`（2026-09-17 起落盘） |
| `mcu_profile.mat` | 0.8 KB | PC 逐帧耗时 / 操作计数 / 内存估算（**未被论文采纳**，决策见 `DECISIONS.md` D010） | `exp_mcu_profile.m` |
| **`final_unified.mat`** | 1.43 MB | 统一配置完整评估（含逐受试者估计序列）——**D=15 演进记录** | `exp_final_unified.m` |
| `stats_base_dalia.mat` | 1.10 MB | 基线逐受试者结果（含逐窗误差） | `exp_stats.m` |
| `stats_base_wesad.mat` | 403 KB | 同上 | `exp_stats.m` |
| `dalia_activity.mat` | 1.5 KB | DaLiA 逐窗活动标签（15 受试者） | `build_dalia_act.m` |
| `r3c04_dalia.mat` / `r3c04_wesad.mat` | 各 896 B | ACC 合成方式的跨频相关系数矩阵 | `exp_r3c04.m` |
| `stats_all.mat` | 2.0 KB | **CurToSS 机制吸收结果（G0–G7）**，由 `exp_stats.m` 写出；**不是** Table I 的产物（Table I 见 `table1_stats.mat`） | `exp_stats.m` |

### C2. 历史阶段结果（保留备查）

| 文件组 | 内容 | 产生脚本 |
|---|---|---|
| `A_dalia/wesad.mat`、`A2_dalia/wesad.mat` | 路线 A 组件实验（观测混合、重捕获） | `exp_A.m` |
| `abl_dalia/wesad.mat` | 消融与配对统计 | `exp_abl_stats.m` |
| `expB.mat` | 路线 B 配置扫描 | `exp_B.m` |
| `dsweep_dalia/wesad.mat` | D（延迟）扫描 | `exp_dsweep.m` |
| `final1_dalia/wesad.mat` | 早期最终评估（含全指标表） | `exp_final1.m` |
| `dev1_*.mat/.csv`、`dev2_*.mat/.csv` | 开发集两轮结果 | `exp_dev1/2.m` |
| `full1_*.mat/.csv` | 全受试者首轮结果 | `exp_full1.m` |
| `lab_dalia/wesad.mat` | 离线跟踪器实验室 | `tracker_lab.m` / `exp_lab1–3.m` |

### C3. 日志（`results/*_log.txt`）与配对口径

> 配对陷阱（记录审计 RA-04）：嵌套 CV 的**现行配对是 `nestedcv_sigma2_log.txt` ↔ `nestedcv_D3.mat`**（固定 σ=2）；
> `nestedcv_D3_log.txt` 为 09-15 自适应 σ 旧运行，**不对应任何现存 .mat**（文件末尾有追加注记，原行号不变）。

| 日志 | 内容 | 配对产物 |
|---|---|---|
| `paper_v3_log.txt` | headline / 延迟表 / 带宽对照 + 配对检验（固定 σ=2、D=3） | `paper_v3.mat` |
| `nestedcv_sigma2_log.txt` | 嵌套 CV（固定 σ=2、D=3）：外层 6.063 / 6.417 | `nestedcv_D3.mat` |
| `nestedcv_D3_log.txt` | 嵌套 CV **自适应 σ（09-15）**：外层 5.909 / 6.464；**已被取代** | 无 |
| `r3c05_sigma2_log.txt` | 活动分层（D=3） | —（数值入论文 `tab:activity`） |
| `ieee_unified_log.txt` | IEEE SPC 统一协议逐记录 MAE | `ieee_unified.mat` |
| `table1_stats_log.txt`、`winlen_log.txt`、`sigma_mean_log.txt` | 2026-09-17 新增证据 | 对应 `.mat` |
| `verify_ieee_150_log.txt`、`probe_ieee_smooth_log.txt` | IEEE v1 复核与探针（1.50036 / 1.54004） | —（作者存档 `X:\Results`） |

> 各日志的（再）生成命令见 `../../../EXPERIMENT_SUMMARY_20260916.md` §1.1。

---

## D. 文档索引

### D1. 本轮返修文档（`revision/`）

| 文件 | 内容 |
|---|---|
| **`WORKLOG_20260915.md`** | **完整工作记录**：时间线、方法改动、13 个 bug 清单、全部实验、文件改动、局限 |
| **`REVIEWER_STATUS_20260915.md`** | 33 条审稿意见逐条对照 + 完成证据 + 剩余缺口 + 优先级 |
| **`FINAL_UNIFIED_20260915.md`** | 最终统一配置、主结果、嵌套 CV、与 CurToSS 对照 |
| `EXP_R3C05_R3C19_20260915.md` | 活动分层与窗长实验（含受控设计说明） |
| `METHOD_V2_AND_PAPER_PATCH_20260914.md` | 方法详情 + `main.tex` 修改规格 P-1…P-9 |
| `CURTOSS_AND_ALGORITHM_REVIEW_20260914.md` | 外部复核意见 |
| `METHODOLOGY_REVIEW_20260914.md` | 方法论复核 |

### D2. 方法开发文档（`method_dev/`）

| 文件 | 内容 |
|---|---|
| **`INDEX.md`** | **本文件** |
| `PROGRESS.md` | 项目全程日志 P-01…P-11（含全部负结果） |
| `RESULTS_FINAL.md` | 前一阶段的正式结果包 |
| `CURTOSS_ANALYSIS.md` | CurToSS 复现全记录（含 §5.5 重要更正） |
| `ABSORB_RESULTS.md` | CurToSS 机制吸收实验 |
| `METHOD_IMPROVE_RESULTS.md` | 早期方法改进实验 |
| `REVIEW_REQUEST.md` | 交给外部审查的文档 |
| `FINAL_UNIFIED_RESULT.md` | 统一配置早期记录 |
| `RESULT.md`、`DECISION.md` | 早期决策记录 |
| `abl_log.txt` | 消融日志 |

### D3. 上层台账

| 文件 | 内容 |
|---|---|
| `revision/decision-letter.txt` | 决定信与全部审稿意见原文（33 条） |
| `REVISION_PLAN.md`、`REVISION_SUMMARY.md`、`REVISION_LOG.md` | 返修台账 |
| `REVIEWER_RESPONSE_DRAFT.md` | 逐点回复草稿 |
| `NEED_AUTHOR_DECISION.md`、`MANUAL_ACTIONS.md` | 待作者事项 |

---

## E. 缓存与重建

| 目录 | 体积 | 重建命令 | 必要性 |
|---|---|---|---|
| `cache2/` | 1.7 GB | `prep_dump2('dalia'); prep_dump2('wesad')` | **必需**（主结果依赖） |
| `cache3/` | 462 MB | `curtoss_prep('dalia',1:15); curtoss_prep('wesad',1:15)` | CurToSS 复现用 |
| `cache4/` | 1.2 GB | `prep_focuss('dalia',1:15); prep_focuss('wesad',1:15)` | FOCUSS 前端对照 |
| `cache_w40/`、`cache_w60/` | 1.4 + 1.6 GB | `prep_winlen('dalia',4); prep_winlen('wesad',4)` 等 | R3-C19 对照 |
| `cache/` | 1.2 GB | `prep_dump.m` | 早期，可弃 |
| `cache3f/` | 96 MB | `prep_front('dalia',1:6); prep_front('wesad',1:6)` | 前端对照 |

**重建前置条件**：
1. DaLiA 原始数据已通过 `subst X: D:\小论文\实验代码\PPG-master` 挂载为 `X:` 盘（MATLAB 无法穿透 junction）
2. 先运行 `build_dalia_act.m` 生成活动标签，否则 `prep_dump2` 会告警并退回全 1
3. `prep_dump2` 遇同名文件会跳过——**修改源码后需先删除对应缓存**

---

## F. 复现主结果的完整步骤

```matlab
cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/method_dev')

% 1) 一次性前置
build_dalia_act;                      % 生成 DaLiA 活动标签
prep_dump2('dalia'); prep_dump2('wesad');   % 生成 cache2（约 10 分钟）

% 2) 论文 headline（固定 σ=2，D=3，全 15 人）+ 延迟表 + 带宽配对检验
exp_paper_v3;                         % -> results/paper_v3.mat（headline 5.958 / 5.784）
%   建议同时捕获日志：-batch "diary('results/paper_v3_log.txt'); exp_paper_v3; diary off"

% 3) 嵌套 CV（固定 σ=2，D=3）
exp_nestedcv(3);                      % -> results/nestedcv_D3.mat（约 10 分钟）
%   配对日志：results/nestedcv_sigma2_log.txt（外层 6.063 / 6.417）
%   注意：exp_final_unified.m 为历史脚本（硬编码 D=15 且两库观测构造不同），勿用于复现 headline。

% 4) 活动分层与带宽/ACC 对照
exp_r3c05_v2(3);                      % -> 论文 tab:activity（DaLiA 9 类 / WESAD 4 类）
exp_sigma_ablation;                   % -> 论文 tab:sigma（配对检验以 paper_v3 为准）
exp_r3c04('dalia'); exp_r3c04('wesad');     % ACC 合成对照

% 5) 附：窗长对照 / Table I / IEEE v1 复核（2026-09-17 起均有落盘）
exp_winlen_cmp;                       % -> results/winlen.mat（需 cache_w40 / cache_w60）
exp_table1_stats;                     % -> results/table1_stats.mat
verify_ieee_150;                      % -> IEEE v1 1.50036 / 1.54004（需 X:\ 与 X:\moving.m）
```

**统一配置（两库相同，2026-09-16 晚起）**：
`state_lo_hz=0.75, state_hi_hz=3.0, edge_taper=30, obs_mode='ratio', wf_variant='orig', sigma=2（固定，q_feat='off'）, D=3, smooth_mode='median', smooth_m=3, 状态空间 40–200 BPM`

> ⚠️ `ds5.m` 的**函数默认值不是上述配置**（默认 σ=5、0.6–3.4 Hz、`smooth_m=4`、`sigma_lo=3/sigma_hi=8`、`edge_taper=0`）；
> 必须显式传入配置（`exp_paper_v3.m:14-18`）。

---

## G. 已知遗留问题

| # | 问题 | 影响 |
|---|---|---|
| 1 | ~~`main.bbl` 陈旧~~ | ✅ 已解决（2026-09-16 已重跑 `bibtex`） |
| 2 | `prep_winlen.m`、`verify_ieee_150.m` 的 `X:` 盘依赖 | 需先 `subst X: D:\小论文\实验代码\PPG-master` |
| 3 | ~~R3-C16 相位声码器消融未做~~ | ✅ 已完成（论文 `tab:fontend_ablation`） |
| 4 | R1-C02 的 2–3 条近期文献未纳入 | 无法核实作者元数据，不编造（唯一开放写作项） |
| 5 | ~~质量特征含未来信息~~ | ✅ 现行配置 `q_feat='off'`（固定 σ=2）后该机制已移除；自适应对照的说明见 `PARAMETER_TRANSPARENCY` §四 |
| 6 | `main.tex` Table I 的 Subjects 行曾为 "Pending" | ✅ 2026-09-17 已填（23 recordings, 12 train / 11 test, 8 test IDs） |

### 2026-09-24 Fig6保存轨迹重绘
`exp_a2_fig_traj_replot.m`：只读a2_fig_traj_arms.mat与S5缓存，保持原选段/预测，补raw标识和宽核命名，轴界涵盖所有预测；输出figures/fig_traj_arms_A2.pdf，不覆写mat。

- `diag_cache_protocol_20260927.m`: 全53份缓存只读频率轴/窗长/保存配置核查；输出audit/PARAM_CACHE_ALL_20260927.json，不运行算法、不修改缓存。

- `diag_ieee_saved_replay_20260927.m`: 针对新发现125Hz差异，用保存A′配置诊断重放23记录，对比原per-record MAE；只写IEEE_SAVED_REPLAY审计，不替换任何原结果。


2026-09-30补充统计登记：`../four_arm_stats_20260930/`只读导出`results/a2_fig_boxplot.mat`，脚本`../../scripts/four_arm_stats.py`分析两库12对，IEEE不纳入推断。未重跑ds5，结果需复核，进度见`../BOOTSTRAP_CI_RECONCILIATION_20260929.md`。

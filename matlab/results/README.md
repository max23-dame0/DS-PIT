---
doc_id: "delta-021"
title: "results/ 产物溯源清单（关闭记录缺口 G7）"
category: "delta"
role: "[Index]"
status: "published"
date: "2026-09-17"
tags: ["record-keeping", "provenance", "reproduction", "results"]
related:
  - "../INDEX.md"
  - "../../EXPERIMENT_SUMMARY_20260916.md"
---

# `results/` 产物溯源清单

> **用途**：关闭记录缺口 **G7**（"`results/` 中若干中间产物无对应脚本名，溯源困难"）。
> 2026-09-17 逐一追查后确认：**本目录所有 52 个文件都有具名的生成脚本**（2026-09-17 晚新增 `extra_metrics.mat` / `extra_metrics_log.txt`；2026-09-18 新增 `gate_unified`、`ieee_per_record`、`bias_strata`、`fe_unified`、`motion_covariate` 五组共 10 个，现共 64 个），其中 5 类需要经 `run_exp.m` / `tracker_lab.m` 间接落盘，此前未被识别。
>
> **复现所有产物请先读 `../INDEX.md` 的 F 节。**

---

## 1. 现行证据（论文数值直接依赖）

| 产物 | 生成脚本 | 用途 |
|---|---|---|
| `paper_v3.mat` / `paper_v3_log.txt` | `exp_paper_v3.m` | **headline、延迟表、σ 消融与配对检验** |
| `perf_table.mat` / `perf_table_log.txt` | `exp_perf_table.m` | **表 III v2 行**（G1 专用脚本，2026-09-17 新增） |
| `ieee_unified.mat` / `ieee_unified_log.txt` | `exp_ieee_unified.m` | 表 III v2 行的 IEEE 格（统一协议） |
| `nestedcv_D3.mat` / `nestedcv_sigma2_log.txt` | `exp_nestedcv.m(3)` | 嵌套 CV（固定 σ=2：6.063 / 6.417） |
| `r3c05_sigma2_log.txt` | `exp_r3c05_v2.m(3)` | 活动分层表 `tab:activity` |
| `sigma_ablation.mat` | `exp_sigma_ablation.m` | 带宽消融（无配对检验版；以 `paper_v3.mat` 为准） |
| `table1_stats.mat` / `table1_stats_log.txt` | `exp_table1_stats.m` | 表 I 三库统计（12 格） |
| `sigma_mean.mat` / `sigma_mean_log.txt` | `exp_sigma_mean.m` | σ_t 实测均值 2.45 / 2.51 |
| `winlen.mat` / `winlen_log.txt` | `exp_winlen_cmp.m` | 窗长 4/6/8 s 对照 |
| `mcu_profile.mat` | `exp_mcu_profile.m` | PC profiling + MCU 周期估算（**未写入论文**，见 `DECISIONS.md` D010） |
| `r3c04_dalia.mat` / `r3c04_wesad.mat` | `exp_r3c04.m` | ACC 参考对照 `tab:accref` |
| `dalia_activity.mat` | `build_dalia_act.m` | DaLiA 逐窗活动标签（供 `exp_r3c05_v2`） |
| `ieee_history.mat` | `check_ieee_history.m` | 作者存档 `myErrorN` 数组摘录 |
| `verify_ieee_150_log.txt` | `verify_ieee_150.m` | IEEE v1 复核 1.50036 / 1.94162 |
| `probe_ieee_smooth_log.txt` | `probe_ieee_smooth.m` | `moving(x,4)` 广播 bug 定位日志 |
| `perf_table.mat` / `perf_table_log.txt` | `exp_perf_table.m` | **表 III v2 行**（G1 专用脚本，2026-09-17 新增） |
| `ieee_prior_split.mat` / `ieee_prior_split_log.txt` | `exp_ieee_prior_split.m` | **§8#3** IEEE v1→v2 差距的 2×2 消融（核 × 带宽） |
| `ieee_prior_arm2_log.txt` | `exp_ieee_prior_arm2.m` | **§8#3** 忠实还原 v1 核构造（计数 → `moving(4)` → log）的对照臂 |
| `extra_metrics.mat` / `extra_metrics_log.txt` | `exp_extra_metrics.m` | **R3-C14 补充指标**：三库 subject-macro RMSE 与 >5%（pooled 对照值同存于 `.mat`；2026-09-17 新增） |
| `gate_unified.mat` / `gate_unified_log.txt` | `exp_gate_unified.m` | **E1 统一配置 gate 复核**（DaLiA 5.958→7.378、WESAD 5.784→7.286；配对检验 + Holm；2026-09-18 新增） |
| `ieee_per_record.mat` / `ieee_per_record_log.txt` | `exp_ieee_per_record.m` | **E2 IEEE 逐记录统计**（23 条 MAE/份额、recording-level bootstrap CI [3.75, 11.05]；2026-09-18 新增） |
| `bias_strata.mat` / `bias_strata_log.txt` | `exp_bias_strata.m` | **E3+E5**：taper×输出滤波 2×2 拆分 + 参考 HR 带分层 + coverage 缺口核验（2026-09-18 新增） |
| `fe_unified.mat` / `fe_unified_log.txt` | `exp_fe_unified.m` | **E4**：统一配置前端消融（WF1/WF2/raw；PV 行不可重跑已注明；2026-09-18 新增） |
| `motion_covariate.mat` / `motion_covariate_log.txt` | `exp_motion_covariate.m` | **E6**：窗口级 \|误差\| vs 运动量（相关 + 四分位分箱；含 MAE 逐位核验；2026-09-18 新增） |
| `acc_mae.mat` / `acc_mae_log.txt` | `exp_acc_mae.m` | **M-20**：加速度参考 MAE 级对照（sum/x/y/z/pc1；sum 逐位复现 headline；2026-09-18 新增） |
| `gate_hard.mat` / `gate_hard_log.txt` | `exp_gate_hard.m` | **G1**：输出替换式门控统一配置复测（keep/append × N=15 / 8–30；全部退化；2026-09-18 新增） |
| `gate_diag.mat` / `gate_diag_log.txt` | `exp_gate_diag.m` | **T1** 路线 A 机制诊断：门控事件（替换帧/μ/门控前输出/缓冲长度）+ 运动四分位/恢复段/μ 质量/反事实瞬时误差；日志追加式（定稿 block = 每库最后一块）（2026-09-18 新增） |
| `lbp_screen.mat` / `lbp_screen_log.txt` | `exp_lbp_screen.m` | **T2** 候选快筛（DALiA）：CF-1/2/3 与 V2 先验 λ=0.05/0.1/0.2；CF-2 +0.0069、V2 全退化（2026-09-18 新增） |
| `lbp_v2.mat` / `lbp_v2_log.txt` | `exp_lbp_v2.m` | **T3** 验收：CF-2/CF-3 两库全受试者（全局 + Q4 + 恢复段；配对 + Holm + CI；判级"不成立"）（2026-09-18 新增） |
| `diag_lag_probe.mat` / `diag_lag_probe_log.txt` | `diag_lag_probe.m` | 诊断：off 口径时移扫描（τ*≈2 窗）与分带偏差/导数相关（2026-09-18 新增） |
| `diag_obs_peak.mat` / `diag_obs_peak_log.txt` | `diag_obs_peak.m` | 诊断：观测峰 vs 最终输出（高 HR 带为观测级限制；需 `ds5.lbp_diag` 的 `obs_pk` 字段）（2026-09-18 新增） |
| `lbp_vel_screen.mat` / `lbp_vel_screen_log.txt` | `exp_lbp_vel_screen.m` | **T2**：M-LBP-V 快筛（V-kernel 否决；V-lead 三档 + L=3）（2026-09-18 新增） |
| `lbp_vel_t3.mat` / `lbp_vel_t3_log.txt` | `exp_lbp_vel_t3.m` | **T3**：V-lead 家族两库验收（字面强成立/实践无；90–150 带 Holm 显著）（2026-09-18 新增） |
| `diag_obs_topk.mat` / `diag_obs_topk_log.txt` | `diag_obs_topk.m` | 诊断：观测 top-3 峰上限分析（oracle 4.86/4.21；命中 78.7%/79.4%）（2026-09-18 新增） |
| `lbp_cand_screen.mat` / `lbp_cand_screen_log.txt` | `exp_lbp_cand_screen.m` | **T2**：M-C 候选峰先验快筛（γ=0.3/0.6/1.0、σh=8/12、含无趋势对照）（2026-09-18 新增） |
| `lbp_cand_t3.mat` / `lbp_cand_t3_log.txt` | `exp_lbp_cand_t3.m` | **T3**：M-C 家族两库验收（DALiA Q4 −0.59 n.s.、WESAD 反向 → 非稳健，判级不成立）（2026-09-18 新增） |
| `lbp_obs4_screen.mat` / `lbp_obs4_screen_log.txt` | `exp_lbp_obs4_screen.m` | **T2**：第四批 A1/A2/B/C 快筛（A1/A2/B 否决；C −0.1282 进入 T3）（2026-09-18 新增） |
| `lbp_temp_t3.mat` / `lbp_temp_t3_log.txt` | `exp_lbp_temp_t3.m` | **T3**：C 家族两库验收（WESAD 90–150 带 −0.1596，Holm 0.0208 → 弱成立；8/8 格改善）（2026-09-18 新增） |
| `lbp_temp_dose.mat` / `lbp_temp_dose_log.txt` | `exp_lbp_temp_dose.m` | **剂量–响应**：τ∈[0.6,1.4]/[0.5,1.5]（DALiA 全项与 WESAD 90–150 带单调）（2026-09-18 新增） |
| `lbp_temp_ctrl.mat` / `lbp_temp_ctrl_log.txt` | `exp_lbp_temp_ctrl.m` | **控制**：τ∈[0.4,1.6]（DALiA 全局 −0.2001）+ 常数 τ≡1.15 / 0.85（平坦化有害）→ 自适应方向为有效成分（2026-09-18 新增） |
| `a2_core.mat` / `a2_core_log.txt` | `exp_a2_core.m` | **A′ 核心指标**（评估配置 = C1，`a2_cfg`）：headline **5.8302/5.7569/6.7659**、bootstrap CI、MedAE/P95/RMSE/>5%/>10%/bias/LoA/r/coverage、HR 带、运动四分位、IEEE 三口径（2026-09-18 新增） |
| `a2_tables.mat` / `a2_tables_log.txt` | `exp_a2_tables.m` | A′ 表格复算：带宽消融 + 配对、延迟扫描、前端消融（31.82/27.38）、ACC 参考、bias 2×2、门控复测（soft +1.70/+1.53；hard keep +1.18/+0.77） |
| `a2_bandtaper.mat` / `a2_bandtaper_log.txt` | `exp_a2_bandtaper.m` | A′ 证据带 × 斜坡 2×2（5.830/11.470/8.033/8.605 与 5.757/9.140/9.424/7.773） |
| `a2_nestedcv_D3.mat` / `a2_nestedcv_log.txt` | `exp_a2_nestedcv.m` | A′ 嵌套 CV（DaLiA 5.860 / optimism 0.124；WESAD 6.416 / 0.660） |
| `a2_extra.mat` / `a2_extra_log.txt` | `exp_a2_extra.m` | A′ 补充：IEEE 窄带对照（6.7659 vs 7.6985）+ 池化/记录级统计 + 记录 10/17/14 占 54.0% + ACC 配对 p + 活动分层全表（2026-09-19 新增） |
| `a2_strata.mat` / `a2_strata_log.txt` | `exp_a2_strata.m` | A′ 分层：运动四分位（2.97→9.11 / 2.86→9.75，>10% 5.1%→26.4% / 4.3%→28.6%）+ 实测温度 τ 分布（τ<1 窗 MAE 11.70/16.52 vs 4.40/4.39）（2026-09-19 新增） |
| `a2_heatmap.mat` / `a2_heatmap_log.txt`（+ `figures/Error_Heatmap_DSPIT_A2.pdf`，2026-09-21 由仓库根迁入） | `exp_a2_heatmap.m` | A′ 活动 × HR 带热力图（9×6，单元格含窗数；最大格 TableSoccer 120–140 = 30.41，n=282）（2026-09-19 新增） |
| `a2_prior.mat` / `a2_prior_log.txt` | `exp_a2_prior.m` | A′ 下 v1→v2 差距分解：原带无斜坡 5.3552（解析核）/16.6431/15.1320（真值核）；带放宽 −0.9326、斜坡 +2.3493（IEEE 上斜坡净负）（2026-09-19 新增） |
| `diag_ieee_tail.mat` / `diag_ieee_tail_log.txt` | `diag_ieee_tail.m` | **IEEE 高尾定位**：记录 10/17（真值均值 160.3/156.5 BPM）半频锁定占窗口 40%/9%、bias −41.4/−20.9；`sid` 字段同时确认 cache2 记录序与 v1 归档一致；去斜坡后记录 10 43.02→4.69、全集 6.77→4.42（WESAD 反价 +3.38）（2026-09-19 新增） |
| `a2_latency_causal.mat` / `a2_latency_causal_log.txt` | `exp_a2_latency_causal.m` | **延迟扫描 · 居中 vs 尾随中值**（`Dl=[1 2 3 4 6 10 15]`）：**居中行与 `a2_tables.mat` 逐位一致（最大差 0.00e+00）**；居中 D=3 = 5.8302/5.7569（总等待 14 s）；尾随全档劣化 **+0.20~+0.37 BPM**（Holm m=7 → 0.0007~0.0008），需 **D=10（26 s）** 才追平居中 D=3（2026-09-23 新增） |
| `a2_causal_smooth.mat` / `a2_causal_smooth_log.txt` | `exp_a2_causal_smooth.m` | **输出滤波因果性对照**（median 逐位复核 PASS 5.8302/5.7569，CI 同）：**median（居中，14 s）5.8302/5.7569**；**mediancausal（尾随窗，12 s）6.1646/6.0283**（+0.3344/+0.2714，raw p=0.0002，Holm m=2 → 0.0004）；**off（无滤波，12 s）5.8376/5.7629**（+0.0075/+0.0060；Holm 0.0241/0.0859）；有效窗 median=medcausal=64652、off=64667（+15）（2026-09-23 新增） |

## 2. 历史产物（09-13 ～ 09-14，仍可溯源但不再用于论文）

| 产物 | 生成脚本 | 说明 |
|---|---|---|
| `A_dalia.mat`、`A_wesad.mat` | `exp_A.m`（`tag='A'`） | 消融矩阵 `M`/`met`/`cfgs` |
| `A2_dalia.mat`、`A2_wesad.mat` | `exp_A.m`（`tag='A2'`） | 同上，第二次运行 |
| `abl_dalia.mat`、`abl_wesad.mat` | `exp_abl_stats.m` | 消融 + 配对统计 |
| `expB.mat` | `exp_B.m` | 参数扫描 `M`/`P`/`cs` |
| `stats_all.mat` | `exp_stats.m` | 全配置统计汇总 |
| `stats_base_dalia.mat`、`stats_base_wesad.mat` | `exp_stats.m`（`i==1` 分支） | 基线统计 |
| `final_unified.mat` | `exp_final_unified.m` | **演进档 #5**（D=15、自适应 σ：5.537/5.583） |
| `final1_dalia.mat`、`final1_wesad.mat` | `exp_final1.m` | 早期配置族扫描 |
| `dsweep_dalia.mat`、`dsweep_wesad.mat` | `exp_dsweep.m` | D × σ 网格扫描 |
| `dev1_*.mat`、`dev1_*.csv` | `exp_dev1.m` → **`run_exp.m:15,16`** | 开发期配置对照（前 4 名受试者） |
| `dev2_*.mat`、`dev2_*.csv` | `exp_dev2.m` → **`run_exp.m:15,16`** | 同上 |
| `full1_*.mat`、`full1_*.csv` | `exp_full1.m` → **`run_exp.m:15,16`** | 同上，全 15 人 |
| `lab_dalia.mat`、`lab_wesad.mat` | `exp_lab1/2/3.m` → **`tracker_lab.m:44`** | 跟踪器标签对照 |
| `nestedcv.mat` | `exp_nestedcv.m`（**D=15 旧口径，5.428 / 6.016**） | ⚠️ 见 `EXPERIMENT_SUMMARY` §2-G3 的配对陷阱 |
| `nestedcv_D3_log.txt` | `exp_nestedcv.m`（09-15 运行，**自适应 σ 旧口径 5.909 / 6.464**） | ⚠️ 末尾已追加注记；**不对应任何现存 `.mat`**（同名 mat 已被覆盖） |

---

## 3. 间接落盘的三个入口（此前未被识别）

| 入口 | 落盘目标 | 调用者 |
|---|---|---|
| `run_exp.m:15` | `results/<tag>_<dataset>.mat` | `exp_dev1 / exp_dev2 / exp_full1` |
| `run_exp.m:16` | `results/<tag>_<dataset>.csv` | 同上 |
| `tracker_lab.m:44` | `results/lab_<dataset>.mat` | `exp_lab1 / exp_lab2 / exp_lab3` |

**教训**：脚本自身没有 `save(` 不等于没有落盘——要追调用链。这正是 G7 此前误判为"孤儿"的原因。

---

## 4. 无产物的脚本（纯诊断/校验，属正常）

`diag_*.m`（8 个）、`ac2.m`、`test_focuss_synth.m`、`check_ieee_history.m`（→ `ieee_history.mat` 除外）、`curtoss*.m`（复现尝试，结论见 `CURTOSS_ANALYSIS.md`）——这些是诊断脚本，不回写 `results/`。

---

## 5. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | 初版：52 个产物全部建立脚本映射，G7 关闭；识别出 3 个间接落盘入口 |

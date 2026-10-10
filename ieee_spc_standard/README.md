---
doc_id: "RPT-2026-0921-002"
title: "v1 复刻工作区（2026-09-20）— IEEE SPC"
category: "report"
role: "[Delta]"
status: "published"
date: "2026-09-20"
author: "v1 复刻会话（2026-09-21 补元数据）"
tags: ["v1-repro", "ieee", "reproducibility"]
related:
  - "../method_dev/INDEX.md"
  - "../../EXPERIMENT_SUMMARY_20260916.md"
  - "../../../DECISIONS.md"
---

# v1 复刻工作区（2026-09-20）— IEEE SPC

> 目的：用**参考实现原始代码**回答两件事——(1) 1.50 能否被我们自己复现（可追溯性）；(2) IEEE 数值对"训练集转移先验"的依赖程度，以及**协议内**（核只用官方 12 条训练记录）与**training-free**（解析核）版本的差异。
> 证据：`results_v1_summary.txt`（ASCII 汇总，逐臂）、`results_v1_per_record.txt`（逐记录 AAE）、`results_v1_full_log.txt` / `results_v1_probe_log.txt`（diary）。

## 1. 工作区构成

| 文件/目录 | 说明 |
|---|---|
| `WFPV_OVD_PISC.m` | 参考实现副本（**唯一改动**：加运行配置读取 + 数值护栏，见 §4） |
| `trans_prob.m`、`moving.m` | 参考实现依赖（逐字复制） |
| `all_data` | **只读 junction** → `revision/external/WFPV_OVD_PISC/all_data`（37.9 MB；PPG_data 23 + BPM_data 23） |
| `Results/` | 本复刻的输出（**不写回** `external/`，遵守"不改 external"约束） |
| `v1_opts.txt` | 运行配置：`kernel=<''｜analytic｜analytic_max｜analytic_norm｜analytic_v2>`、`ksrc=<''｜train>` |

## 2. 结果

| # | 转移核 | 核来源 | 训练集(1–12) | 测试集(13–23) | 全集(23) | SD |
|---|---|---|---|---|---|---|
| 1 | 真值核（v1 原样） | 跨 23 条 LOSO | 0.8744 | 2.1833 | **1.5004** | 2.2662 |
| 2 | 真值核（**协议内**） | **仅 12 条训练记录**（训练记录内 LOSO） | 0.8057 | **2.1637** | **1.4552** | 2.0969 |
| 3 | 解析高斯核（行归一，v2 约定） | — | 0.9317 | 7.5030 | 4.0745 | 3.3102 |
| 4 | 解析高斯核（尺度=计数中位） | 跨 23 条 LOSO | 0.9365 | 7.4531 | 4.0532 | 3.3111 |
| 5 | 解析高斯核（尺度=计数最大） | 跨 23 条 LOSO | 0.9317 | 7.4531 | 4.0506 | 3.3098 |
| 6 | 解析核（v2 约定 + 1e-6 底） | 跨 23 条 LOSO | 0.8838 | 7.4390 | 4.0189 | 3.1729 |

- **第 1 行逐记录与归档一致**（例：记录 10 = 1.55 对归档 1.5452；全集 1.5004 对 REPRO-01 的 1.50036）→ 1.50 的复现无问题。
- **第 2 行是关键**：把核严格限制在官方 12 条训练记录内拟合，**测试集 2.16 / 全集 1.46**，甚至略优于跨 23 条 LOSO → **1.50 不是靠"用了其他测试记录的真值"得来的**，可以按 IEEE 官方 train/test 协议如实报告。
- **第 3–6 行**：去掉训练先验（任何尺度的解析核）后，**训练集几乎不变（0.88–0.94）而测试集掉到 7.44–7.50** → IEEE 的测试集性能主要由训练集拟合的转移先验承载；同时说明 v2 统一配置的 6.77 已优于"v1 实现 + 解析核"的 7.50。

## 3. 运行方式（每次全 23 条约 3.3 s）

```powershell
# 例：协议内核
D:\matlab\bin\matlab.exe -batch "cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/v1_repro_20260920'); fid=fopen('v1_opts.txt','w'); fprintf(fid,'kernel=%s\nksrc=%s\n','','train'); fclose(fid); WFPV_OVD_PISC"
```

## 4. 对参考实现的改动清单（仅本副本，`external/` 未动）

1. 顶部读 `v1_opts.txt`（kernel / ksrc）；子集运行可用环境变量 `V1_SEL`。
2. `V1_KERNEL_SRC=train` 时核来源改为 `1:12`（测试记录）或训练集内 LOSO（训练记录）。
3. 解析核替换分支（尺度过三档 + v2 行归一档）。
4. **数值护栏**（稀疏核下 `(-Inf)×0=NaN` 会让回溯索引变 0 而崩溃）：
   - 首窗初始化：`diag(logTR)` 非有限项置 `-1e300`，观测非有限项置 `0`；
   - 前向更新：跳过 `NaN`、`bestPTR==0` 时自持（`-1e300`）。
   回归验证：护栏后第 1 行仍**逐位复现 1.5004**（说明护栏不改变正常情形结果）。
5. 末尾 ASCII 汇总行 + `results_v1_summary.txt` / `results_v1_per_record.txt` 落盘；`BlandAltman`（快照缺失的绘图辅助）加容错跳过。

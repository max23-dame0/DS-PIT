---
doc_id: "emb-00"
title: "embedded_mcu_20260921 目录索引：STM32F103 板级实测"
category: "audit"
role: "[State]"
status: "published"
date: "2026-09-22"
author: "返修会话产出"
---

# embedded_mcu_20260921 目录索引

> 主题：为 R2-C04 / R3-C10 补**真实硅片**证据（决策层板级实测：延迟 / 内存 / 代码量 / 理论能量）。
> 目录命名遵循 `revision/audit/<主题>_<YYYYMMDD>/`。
> **范围声明（D031）**：测量覆盖决策层（SSC 转移 + 固定延迟 Viterbi + 中值输出滤波）on-device；**前端离线**。论文措辞须按此限定。

## 实测摘要（2026-09-21 完成；2026-09-22 汇总加固）

- 平台：Cortex-M3（无 FPU）72 MHz；每段 256 窗；5 段记录（DaLiA S1/S2/S3、WESAD S1/S2）
- **banded K·W（W=13）每窗 5.887 ms（mean）、dense K² 65.740 ms，比值 11.17**
- 输出保真：全部 **254/254** 逐窗与 MATLAB 完全一致（0 BPM 差）
- 重复性 ×3 逐字节一致；时钟缩放 24/48/72 MHz、带宽缩放 W=7/13/25 已验证（支持 K·W 复杂度）
- 内存：算法静态 RAM 3.2 KB + 栈 ≤0.25 KB；决策层代码 ≈4.7 KB
- 能量：**ESTIMATE**（数据手册电流 × 实测时间）：72 MHz/W13 单窗 0.699–0.971 mJ
- **可复现性**：干净重建 fw.bin/elf 逐字节一致；端到端回放结果 blob 与权威运行逐字节一致（`FD9DC30D…`）

## 文件清单

| 文档 / 产物 | 说明 | 状态 |
|---|---|---|
| **`EMB-01_REPORT.md`** | **汇总报告**：平台、方法、全部结果、可复现性验证、与论文关系、局限、证据索引 | ✅ |
| **`REPRODUCTION.md`** | **复现手册**：L1 结果级 / L2 固件级 / L3 全链级 + 排障 + 归档边界 | ✅ |
| **`MANIFEST_SHA256.txt`** | 全产物 SHA-256 清单（71 文件；13 条标 `[local-only]`） | ✅ |
| `EMB-01_LOG.md` | 过程日志：接线、器件识别、逐项结果、复现命令（只追加） | ✅ |
| `results/results_summary.json` | 机器可读结果汇总（`make_manifest.py` 自 blob 重算） | ✅ |
| `make_manifest.py` | 清单/汇总生成器（全部数字可追溯） | ✅ |
| `exp_export_mcu.m` / `exp_export_extra.m` / `exp_export_extra2.m` | MATLAB 导出（S1 / S2+ws1 / S3+ws2；含 headline 门槛） | ✅ |
| `gen_mcu_tables.m` | 由导出 mat 生成固件转移核表头 | ✅ |
| `fw/` | 裸机固件（源码 + `fw.elf/bin/map`；`CLK_MHZ`/`BAND_HW` 可配） | ✅ |
| `results/matrix/` | 原始结果 blob 12 份（时钟/带宽/重复 ×3/跨记录 ×4/回放） | ✅ |
| `results/{matrix_summary,cross_check,energy_estimate}.txt` | 汇总结论（分析脚本输出） | ✅ |
| `results/mcu_logL_*.bin`、`mcu_export.mat` | 大派生数据（≈15 MB，**本地保留不入库**，可重建） | 本地 |
| `flash_backup/original_flash.bin` | 烧录前整片备份（256 KiB） | ✅ |
| `evidence_photos/` | 过程照片 4 张（≈10.5 MB，**本地保留不入库**） | 本地 |
| `run_cfg.ps1` / `run_ext.ps1` / `repeat_run.ps1` | 自动化：编译→烧录→运行→回读 | ✅ |
| `check_results.py` / `check_ext.py` / `analyze_matrix.py` / `energy_estimate.py` / `build_data.py` / `slice_ref.py` | 分析与数据处理脚本 | ✅ |

**关联文档**：`../method_dev/INDEX.md`、`../../REVIEWER_STATUS_20260915.md`（R2-C04 / R3-C10）、根级 `DECISIONS.md` D031（范围与能量口径）。

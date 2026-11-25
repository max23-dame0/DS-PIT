---
doc_id: "e2e-01-index"
title: "E2E-01 索引：STM32F103 完整端到端板级实测（2026-11-24）"
category: "audit"
role: "[State]"
status: "published"
date: "2026-11-24"
author: "R2 小修会话"
---

# E2E-01 完整端到端板级实测目录索引

> 本目录存放 JBHI-01577-2026.R2 小修中为回应 AE、R1-1、R2-1、R2-2、R2-3 而完成的 **DS-PIT 完整端到端 DSP 流水线**（S1–S6 全阶段）在 STM32F103 Cortex-M3 @72 MHz 上的真实片上时间、内存、Flash 与跨平台一致率证据链。

| 文件 / 目录 | 说明 | 入库 |
|---|---|---|
| `E2E-01_LOG.md` | 审计日志（有效路径核查、主机隔离/端到端验证、板级运行日志，只追加） | ✅ |
| `E2E-01_REPORT.md` | 完整实测报告（平台、口径边界、逐阶段耗时、逐模块 RAM/Flash、一致率与能量估算） | ✅ |
| `REPRODUCTION.md` | L1 结果级 / L2 固件板级 / L3 MATLAB 导出全复现手册 | ✅ |
| `MANIFEST_SHA256.txt` | 全部入库文件 SHA-256 校验清单 | ✅ |
| `exp_export_e2e.m` | MATLAB 端到端金标准与 `src/e2e_tables.h` 导出脚本（通过环境变量 `DSPIT_DATA_ROOT` 读数据） | ✅ |
| `src/` | 可移植 C99 模块（`fe_filter.c`, `fe_resample.c`, `spec.c`, `enhance.c`, `lbp.c`, `decode.c`, `smooth.c`, `dspit_e2e.c`, `e2e_tables.c/h`, `e2e_config.h`, `dspit_e2e.h`） | ✅ |
| `host_test/` | MinGW 主机双精度（隔离+E2E）与单精度验证工程（`*.exe`/`*.o` 已 `.gitignore`） | ✅（源码） |
| `fw/` | STM32F103 裸机流式固件（`main.c`, `startup.c`, `stm32f103.ld`, `Makefile`, `fw.elf`, `fw.bin`, `fw.map`；`*.o` 已 `.gitignore`） | ✅ |
| `host_driver/stream_e2e.py` | 仅标准库 Python OpenOCD TCL 流式测试驱动 | ✅ |
| `analyze_e2e.py` / `make_manifest_e2e.py` | 确定性结果汇总（生成 `results/results_summary_e2e.json`）与 SHA-256 清单生成器 | ✅ |
| `results/` | 汇总 `results_summary_e2e.json`、日志（`ds5_regression_log.txt`, `e2e_export_log.txt`, `host_verify_log.txt`）、主机参照 `host_f32_*.bin` 与片上原始运行记录 `e2e_run_*.json` | ✅ |
| `golden/` | MATLAB 导出的大体积原始块与逐窗金标准 `*.bin`（可由 `exp_export_e2e.m` 重建） | 本地（`.gitignore`） |

**关联文件**：`../embedded_mcu_20260921/EMB-01_REPORT.md`（EMB-01 独立解码核基线）、`../../REVIEWER_STATUS_20260915.md`、`../../../minor_revision_R2/R2_COMMENT_MATRIX_20261124.md`。

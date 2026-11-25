---
doc_id: "e2e-01-reproduction"
title: "E2E-01 复现手册：STM32F103 完整端到端板级实测（2026-11-24）"
category: "audit"
role: "[Delta]"
status: "published"
date: "2026-11-24"
author: "R2 小修会话"
---

# E2E-01 复现手册

## 1. 复现等级与依赖

- **L1（结果重算，无需硬件/MATLAB，约 5 秒）**：由入库的 `results/e2e_run_*.json`、`fw/fw.map` 与 `results/host_f32_*.bin` 重算 `results/results_summary_e2e.json`。
- **L2（固件编译 + 主机测试 + 板级运行，需 GCC / ARM GCC / OpenOCD / STM32 板）**：需本地 `golden/`（由 L3 生成）。
- **L3（MATLAB 导出金标准与表格头文件）**：需 MATLAB 及原始数据集目录（通过环境变量 `DSPIT_DATA_ROOT` 传入）。

## 2. L1：结果级复现

```powershell
py -3 revision\audit\embedded_e2e_20261124\analyze_e2e.py
py -3 revision\audit\embedded_e2e_20261124\make_manifest_e2e.py
```

## 3. L3：MATLAB 导出与回归校验

```powershell
$env:DSPIT_DATA_ROOT = "<原始数据集根目录>"
$absDir = (Resolve-Path "revision\audit\embedded_e2e_20261124").Path
matlab -batch "addpath('$absDir'); exp_export_e2e();"
```

## 4. L2：主机验证、固件编译与 STM32 流式实测

```powershell
# 1) 主机双精度（隔离+E2E）与单精度验证
Push-Location revision\audit\embedded_e2e_20261124\host_test
make clean; make
.\test_f64.exe
.\test_f32.exe
Pop-Location

# 2) STM32F103 固件编译
$env:Path = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin;" + $env:Path
Push-Location revision\audit\embedded_e2e_20261124\fw
make clean; make
Pop-Location

# 3) 烧录并运行完整 8 组矩阵
py -3 revision\audit\embedded_e2e_20261124\host_driver\stream_e2e.py --runs s1:s1_r1:1 s2:s2:1 s3:s3:1 ws1:ws1:1 ws2:ws2:1 --speed 1800
py -3 revision\audit\embedded_e2e_20261124\host_driver\stream_e2e.py --runs s1:s1_r2:1 s1:s1_r3:1 s1:s1_dense:0 --skip-flash --speed 1800
```

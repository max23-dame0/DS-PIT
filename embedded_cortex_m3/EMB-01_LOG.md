---
doc_id: "emb-01"
title: "EMB-01 日志：板级实测环境建立与器件识别（2026-09-21）"
category: "audit"
role: "[Delta]"
status: "in-progress"
date: "2026-09-21"
author: "返修会话产出（硬件连接与器件识别；未改动任何论文数值）"
tags: ["embedded", "mcu", "stm32f103", "on-device", "R2-C04", "R3-C10"]
---

# EMB-01 日志：板级实测环境建立与器件识别

> **用途**：为 R2-C04 / R3-C10（"wearable ready 缺硬件实测"）建立**真实硅片**证据链。
> **纪律**：本目录日志只追加、不改写；任何数值进入论文/回复信前须经作者复核。
> **范围声明（重要）**：计划中的板级测量覆盖**决策层**（SSC 转移 + 固定延迟 Viterbi + 中值输出滤波）；前端（双 Wiener / 相位声码器谱增强）离线执行。该范围将如实写进论文措辞，不冒充"全流程板级实测"。

---

## 1. 2026-09-21 会话记录：连接成功与器件识别

### 1.1 接线（最终可用方案）

| ST-Link 克隆棒（外壳丝印针号） | 信号 | 目标板 STM32-Mini V3.1 |
|---|---|---|
| 2 | SWCLK | PA14 |
| 4 | SWDIO | PA13 |
| 6 | GND | GND |
| 8 | 3.3V | 3V3 |
| 10 | 5.0V | **不接** |

> 失败教训：该克隆棒丝印为 2×5 排布（RST/SWCLK、SWIM/SWDIO、GND/GND、3.3V/3.3V、5.0V/5.0V），奇数列（1/3/5/7/9）不含 SWDIO/SWCLK，按 odd 排接线必然 `init mode failed`。

### 1.2 器件识别（openocd，ST-Link 克隆棒固件 V2J45S7）

| 项 | 读值 | 来源 |
|---|---|---|
| SWD DPIDR | 0x1ba01477 | openocd |
| 内核 | Cortex-M3 r1p1（无 FPU） | openocd |
| DBGMCU_IDCODE | 0x10036414（DEV_ID 0x414） | `mdw 0xE0042000` |
| Flash 容量 | 256 KiB | `mdw 0x1FFFF7E0`（低半字 0x0100）+ `flash probe` |
| SRAM 容量（实测） | 64 KiB（0x2000FFF0 写读一致；0x20010000 写失败） | 写读探测 |
| 唯一 ID（UID） | 0x622CFF36-39384834-43107637 | `mdw 0x1FFFF7E8 3` |
| 目标电压 | ~3.12 V | openocd |

### 1.3 工具链（本机，可复现）

- `openocd`：xpack-dev-tools.openocd-xpack **0.12.0-7**（winget 安装）
- `arm-none-eabi-gcc`：Arm.GnuArmEmbeddedToolchain **14.2.Rel1**（winget 安装）
- ST-Link 驱动：Zadig 2.9 → WinUSB（克隆棒 VID:PID 0483:3748）
- MATLAB：本机已装（用于导出逐窗似然向量，见下一步 1）

### 1.4 记录到的问题

1. 板载 MCU 为 F103 类 **Cortex-M3（无 FPU，最高 72 MHz）**，比论文估算假设的 Cortex-M4 更保守：软浮点开销将计入实测。措辞按"保守平台"口径撰写。
2. Flash 容量寄存器报 256 KiB、SRAM 实测 64 KiB，与标准 xC（48 KiB SRAM）不符，疑为兼容/复刻芯片。论文只写**实测值**与器件 ID，不写具体型号后缀。

---

## 2. 实测结果（最终固件，canonical）

> 平台：Cortex-M3（无 FPU，72 MHz）；每段 256 窗；内嵌数据为论文配置导出的逐窗似然。
> **canonical 结果**来自含 volatile magic 修复的最终固件；重复性 ×3 完全一致。
> 历史说明：首次运行（修复前固件）录得 dense 64.29 / banded 5.71 ms，比最终固件低约 2–3%（代码布局差异），以本表为准。

### 2.1 主结果（f72w13_r1/r2/r3，三次重复完全相同）

| 版本 | mean | P95 | max | 周期均值 |
|---|---|---|---|---|
| dense K² | 65.740 ms | 66.324 ms | 66.419 ms | 4,733,299 |
| **banded K·W (W=13)** | **5.887 ms** | 5.916 ms | 5.956 ms | 423,854 |

- dense/banded 实测比值 **11.17**（理论 K/W = 12.38；差值来自稠密版无边界钳位开销与两版共有的固定开销）
- est 一致性：dense **254/254**、banded **254/254** 与 MATLAB 完全相同（0 BPM 差）
- 栈高水位 ≤ 256 B（涂漆下限）；静态 RAM 3.2 KB（.bss）+ 结果区 4.0 KB
- 证据：`results/matrix/f72w13_r{1,2,3}.bin`、`results/mcu_check_summary.txt`

### 2.2 时钟缩放（同一算法，24/48/72 MHz）

| 时钟 | dense mean | banded mean | banded 周期数 |
|---|---|---|---|
| 24 MHz | 138.500 ms | 12.122 ms | 290,928 |
| 48 MHz | 79.703 ms | 7.004 ms | 336,192 |
| 72 MHz | 65.740 ms | 5.887 ms | 423,854 |

- 时间随频率单调下降（banded：72 MHz 比 24 MHz 快 2.06×，非 3×——因 Flash 等待周期随频率增加，
  DWT 周期数由 24 MHz 的 290,928 升至 72 MHz 的 423,854；属真实硅片特性，如实记录）
- 所有配置 est 均 254/254 一致；证据：`results/matrix/f{24,48,72}w13*.bin`

### 2.3 带宽缩放（W=7/13/25，72 MHz）

| W | banded mean | 相对 W=13 |
|---|---|---|
| 7 | 3.499 ms | 0.59× |
| **13（论文配置）** | **5.887 ms** | 1.00× |
| 25 | 10.527 ms | 1.79× |

- 时间与 W 近似线性（范围 3.5–25），验证 K·W 复杂度项；证据：`results/matrix/f72w0{7,25}.bin`

### 2.4 跨记录/跨数据集验证（保真性，72 MHz W=13）

| 记录 | 段长 | dense est | banded est | banded mean |
|---|---|---|---|---|
| DaLiA S1 | 256 窗 | 254/254 | 254/254 | 5.887 ms |
| DaLiA S2 | 256 窗 | 254/254 | 254/254 | 5.908 ms |
| DaLiA S3 | 256 窗 | 254/254 | 254/254 | 5.900 ms |
| WESAD S1 | 256 窗 | 254/254 | 254/254 | 5.904 ms |
| WESAD S2 | 256 窗 | 254/254 | 254/254 | 5.903 ms |

- 五段记录全部逐窗完全一致（0 BPM 差），单窗耗时跨记录波动 < 0.4%
- 证据：`results/cross_check.txt`、`results/matrix/{s2,s3,ws1,ws2}.bin`

### 2.5 能量理论估算（ESTIMATE，非实测）

方法 `E = V·I·t`：V=3.3 V（板上轨，名义）、I=数据手册 Run 模式典型电流（Flash 执行）、t=实测每窗时间。

| 配置 | t (banded) | E 下限 | E 上限 | 等效平均功率@2s（上下限） |
|---|---|---|---|---|
| 72 MHz, W=13 | 5.887 ms | 0.699 mJ | 0.971 mJ | 0.350 / 0.486 mW |
| 48 MHz, W=13 | 7.004 ms | 0.555 mJ | 0.786 mJ | 0.277 / 0.393 mW |
| 24 MHz, W=13 | 12.122 ms | 0.480 mJ | 0.680 mJ | 0.240 / 0.340 mW |
| 72 MHz, W=7 | 3.499 ms | 0.416 mJ | 0.577 mJ | 0.208 / 0.289 mW |

- 下限=外设全关（本固件即如此，未启用任何外设）；上限=外设全开（保守）
- 有趣的推论：**降频到 24 MHz 时每窗能量更低**（时间增 2×、电流降 3×）；所有配置单窗能量均 < 1 mJ 量级
- ⚠️ 状态：纯 ESTIMATE。真实能量需分流电阻/功耗仪实测；进论文前必须复核数据手册原表数值
- 证据：`results/energy_estimate.txt`

---

## 3. 已执行清单（原计划 → 状态）

1. ✅ **导出逐窗似然向量**：`exp_export_mcu.m`（headline 复现 5.9584/5.7836 后导出 S1）；额外记录由 `exp_export_extra.m`（S2/ws1）、`exp_export_extra2.m`（S3/ws2）导出。
2. ✅ **裸机固件**：C 实现决策层，转移核可分离压缩（`g[|i-j|] + a[i]`，σ=2）；DWT 周期计数；dense K² 与 banded K·W（W=7/13/25）对照；`CLK_MHZ` 支持 24/48/72 MHz。
3. ✅ **烧录前备份**：`flash_backup/original_flash.bin`（262,144 B）。
4. ✅ **测量**：每窗周期数（min/mean/P95/max）、栈高水位、静态 RAM/Flash；五段记录逐窗比对（全部 254/254）。
5. ✅ **能量（理论估算）**：`energy_estimate.py` 输出 `results/energy_estimate.txt`——数据手册典型电流 × 实测时间，**标注 ESTIMATE**；真实测量仍 requires instrument。

---

## 4. 证据索引

| 产物 | 位置 | 状态 |
|---|---|---|
| 本日志 | `EMB-01_LOG.md` | ✅ |
| 主导出脚本 | `exp_export_mcu.m` | ✅ |
| 额外记录导出 | `exp_export_extra.m`、`exp_export_extra2.m` | ✅ |
| 固件源码 | `fw/main.c`、`fw/emb_config.h`、`fw/startup.c`、`fw/stm32f103.ld`、`fw/Makefile` | ✅ |
| 固件二进制 | `fw/fw.elf`、`fw/fw.bin`、`fw/fw.map` | ✅ |
| Flash 备份 | `flash_backup/original_flash.bin` | ✅ |
| 解析/汇总脚本 | `check_results.py`、`analyze_matrix.py`、`check_ext.py`、`energy_estimate.py`、`build_data.py`、`slice_ref.py` | ✅ |
| 自动化脚本 | `run_cfg.ps1`、`run_ext.ps1`、`repeat_run.ps1` | ✅ |
| 权威结果 | `results/mcu_check_summary.txt`（= f72w13_r1）、`results/matrix/*.bin`（11 份）、`results/matrix_summary.txt`、`results/cross_check.txt`、`results/energy_estimate.txt` | ✅ |
| 导出参考数据 | `results/mcu_logL_{s1,s2,s3,ws1,ws2}.bin`、`results/mcu_ref_est_*.txt`、`results/mcu_export*.mat/log` | ✅ |

### 4.1 复现命令

```powershell
# 单配置（编译→烧录→运行→回读）
powershell -ExecutionPolicy Bypass -File run_cfg.ps1 -Tag f72w13 -Defs "" -WaitSec 32
# 重复性 ×3
powershell -ExecutionPolicy Bypass -File repeat_run.ps1 -Tag f72w13 -N 3 -WaitSec 32
# 跨记录（先切片再烧录运行）
powershell -ExecutionPolicy Bypass -File run_ext.ps1 -Tag s2 -SrcBin results/mcu_logL_s2.bin -WaitSec 32
# 汇总与分析
py -3 analyze_matrix.py ; py -3 check_ext.py ; py -3 energy_estimate.py
```

---

## 5. 2026-09-22 汇总与复现加固（本轮补充）

1. **重建一致性**：删除全部 `.o/elf/bin/map` 后干净重编译 → `fw.bin`/`fw.elf` 的 SHA-256 **逐字节一致**
   （`0930234D…F515F` / `EEC783AD…0FC31F`）。
2. **端到端回放**：用干净重建的固件重新烧录、运行 34 s、回读 → 结果 blob 与权威运行 `f72w13_r1.bin`
   **逐字节一致**（`FD9DC30D1BB09F65198929D2EC0F5E6C6B04AFF1BE316783FE0A2DC8E1BD4E0A`）→ 存为 `results/matrix/replay_clean.bin`。
3. **机器可读汇总**：新增 `make_manifest.py` → `results/results_summary.json`（7 配置 + 4 跨记录，全部数字自 blob 重算）
   + `MANIFEST_SHA256.txt`（**71 文件**，其中 13 条标 `[local-only]`）。
4. **报告与复现文件**：`EMB-01_REPORT.md`（汇总报告）、`REPRODUCTION.md`（L1/L2/L3 复现手册 + 排障）、
   `evidence_photos/`（用户提供的 4 张过程照片，≈10.5 MB，本地保留）。
5. **归档边界**：`.gitignore` 新增 EMB-01 块——`results/mcu_logL_*.bin`（≈12.5 MB）、`results/mcu_export.mat`、
   `fw/*.o`、`evidence_photos/` 不入库；**入库部分 58 文件 ≈0.96 MB**，且 L1/L2 复现**不依赖**被排除文件。
6. **脚本修复**：`run_cfg.ps1` / `repeat_run.ps1` 支持 `-Defs NONE` 哨兵——修复"空字符串在嵌套调用中被丢弃"
   导致的静默失败（历史两次 `-Defs ""` 无输出即此因）。

**本轮新增**：`replay_clean.bin`、`results_summary.json`、`MANIFEST_SHA256.txt`、`EMB-01_REPORT.md`、
`REPRODUCTION.md`、`make_manifest.py`、`evidence_photos/`；`run_cfg.ps1`/`repeat_run.ps1` 小改。

---

## 6. 2026-09-22 结果入稿（论文与记录同步）

按 D031 口径把实测数字写入正文与记录；补丁可审计（`patch_manuscript.py`、`patch_records.py`，每处替换均带唯一性断言后才写入）：

| 目标 | 处数 | 内容要点 |
|---|---|---|
| `main.tex` | 7 | 摘要；Table IV 行（"MCU NR" → on-device 数字）；Table IV 注（范围=仅决策层、能量未测）；§III-F 资源段（5.89 ms/窗、P95 5.92 ms、3.2 kB、≈4.7 kB、五段逐窗一致、能量估算 0.70–0.97 mJ）；§III-F 运算量段尾（区分全流水线界与实测延迟）；Limitations；Conclusion |
| `RESPONSE_LETTER_20260920.md` | 6 | 摘要清单第 7 条（硬件声明）；AE-5；Comment 4；Comment 10；页数口径 12→13；三处 Changes 行补 "Limitations" |
| `REVIEWER_STATUS_20260915.md` | 3 | R2-C04 / R3-C10 行升级为"已获真实硅片实测"（附证据指针与 commit `a90291e`）；追加 2026-09-22 变更记录段 |

**编译验证**：`latexmk` 全流程 → **13 页 / 982,973 B / 0 未定义引用 / 1 Overfull / 6 Underfull**（页数与基线一致）。

> 状态：以上入稿改动**未提交**（等待作者审阅措辞后决定）；本审计目录内 `patch_manuscript.py`、
> `patch_records.py` 与更新的 `MANIFEST_SHA256.txt` 随同未提交。

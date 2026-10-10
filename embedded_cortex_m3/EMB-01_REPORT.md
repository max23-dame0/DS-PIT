---
doc_id: "emb-03"
title: "EMB-01 汇总报告：STM32F103 板级决策层实测（2026-09-22）"
category: "audit"
role: "[Delta]"
status: "published"
date: "2026-09-22"
author: "返修会话产出（数字全部由脚本自原始 blob 重算，见 make_manifest.py）"
---

# EMB-01 汇总报告：板级决策层实测

> **一句话**：在真实硅片（Cortex-M3，无 FPU，72 MHz）上实测了 DS-PIT **决策层**的每窗延迟与内存占用，
> 输出与 MATLAB `ds5` **逐窗完全一致（5 段记录 × 254/254）**，并通过时钟/带宽缩放与重复性实验交叉验证。
> **能量为数据手册估算（ESTIMATE）**，非实测。
> **范围**：决策层（SSC 转移 + 固定延迟 Viterbi + 中值输出滤波）on-device；前端离线（D031 口径）。

---

## 1. 平台与器件

| 项 | 值 | 来源 |
|---|---|---|
| 板 | STM32-Mini V3.1（Mcudev） | 实物 |
| MCU | STM32F103 兼容片，**Cortex-M3 r1p1，无 FPU** | openocd `DPIDR 0x1ba01477` |
| DEV_ID | `0x414`（IDCODE `0x10036414`） | `mdw 0xE0042000` |
| Flash / SRAM | 256 KiB / **64 KiB（实测，标准 xC 为 48 KiB——疑兼容片，论文只写实测值）** | 寄存器 + 写读探测 |
| 时钟 | 72 MHz（HSE 8 MHz × 9）；另测 48/24 MHz | `CFGR = 0x001D040A` |
| 调试链路 | 克隆 ST-Link V2（`V2J45S7`）+ openocd xpack 0.12.0-7 | 日志 |

## 2. 方法（测量定义）

- **被测对象**：论文配置的决策层——转移核 `logT(i,j)=g[|i-j|]+a[i]`（σ=2）+ 固定延迟 Viterbi（D=3）+ 中值输出滤波；逐窗似然向量由 MATLAB 离线导出并内嵌（**前端不参与板级计时**）。
- **延迟**：DWT 周期计数器逐窗包围（`DWT->CYCCNT`），换算 `t = cycles / f_clk`；报 mean/P95/max。
- **内存**：链接 map（.text/.bss）+ 栈涂漆水位法（≤ 分辨率上限）。
- **保真**：MCU 输出序列 vs MATLAB `ds5` 参考序列逐窗比对（完全一致计数）。
- **能量**：`E = V·I·t`，V=3.3 V 名义、I=数据手册 Run 模式典型电流（Flash 执行、外设关/开为界）、t=**实测**——**估算，非实测**。

## 3. 结果

### 3.1 主结果（72 MHz，W=13；canonical = f72w13_r1）

| 版本 | mean | P95 | max | 周期均值 |
|---|---|---|---|---|
| dense K² | 65.7403 ms | 66.324 ms | 66.419 ms | 4,733,299 |
| **banded K·W (W=13)** | **5.8869 ms** | 5.916 ms | 5.956 ms | 423,854 |

比值 11.17（理论 K/W = 12.38）；重复运行 ×3 **逐字节一致**。

### 3.2 时钟缩放（每窗时间 / 周期数）

| 时钟 | dense | banded | banded 周期数 |
|---|---|---|---|
| 24 MHz | 138.500 ms | 12.122 ms | 290,928 |
| 48 MHz | 79.703 ms | 7.004 ms | 336,192 |
| 72 MHz | 65.740 ms | 5.887 ms | 423,854 |

时间随频率**次线性**下降（72/24 = 2.06×，非 3×）：Flash 等待周期随频率增加（周期数 290,928→423,854），真实硅片特性。

### 3.3 带宽缩放（72 MHz）

| W | banded | 相对 W=13 |
|---|---|---|
| 7 | 3.499 ms | 0.59× |
| 13 | 5.887 ms | 1.00× |
| 25 | 10.527 ms | 1.79× |

近似线性 → 实测支持 **K·W 复杂度**（R3-C09 论据）。三种 W 的 est 均为 254/254（本记录上带宽截断未改变输出）。

### 3.4 跨记录/跨数据集保真（72 MHz，W=13）

| 记录 | dense est | banded est | banded mean |
|---|---|---|---|
| DaLiA S1 | 254/254 | 254/254 | 5.887 ms |
| DaLiA S2 | 254/254 | 254/254 | 5.908 ms |
| DaLiA S3 | 254/254 | 254/254 | 5.900 ms |
| WESAD S1 | 254/254 | 254/254 | 5.904 ms |
| WESAD S2 | 254/254 | 254/254 | 5.903 ms |

跨记录耗时波动 < 0.4%；全部**0 BPM 差**。

### 3.5 内存与 Flash（实测）

| 项 | 值 |
|---|---|
| 决策层算法静态 RAM（.bss：u/vold/vnew/gt/pring） | **3,220 B** |
| 栈高水位 | **≤ 256 B**（涂漆分辨率上限）→ 算法峰值 RAM ≤ ~3.5 KB |
| 决策层代码（text − 回放数据） | **≈ 4.7 KB**（169,608 − 164,864 B） |
| 测量载荷（161 KB 回放数据 + 4,116 B 结果区） | 仅测量用，部署时可去除 |
| 烧录镜像 fw.bin | 173,724 B |

### 3.6 能量（ESTIMATE，非实测）

| 配置 | t (banded) | E（外设关→开） | 等效平均功率 @2 s 步长 |
|---|---|---|---|
| 72 MHz, W=13 | 5.887 ms | 0.699 → 0.971 mJ | 0.350 → 0.486 mW |
| 48 MHz, W=13 | 7.004 ms | 0.555 → 0.786 mJ | 0.277 → 0.393 mW |
| 24 MHz, W=13 | 12.122 ms | 0.480 → 0.680 mJ | 0.240 → 0.340 mW |
| 72 MHz, W=7 | 3.499 ms | 0.416 → 0.577 mJ | 0.208 → 0.289 mW |

**降频到 24 MHz 单窗能量更低**（时间 ×2.06、电流 ×1/3）——可作为功耗-延迟折中的讨论点。
⚠️ 数据手册电流值（DocID 14611，72 MHz≈36/50 mA）进论文前须复核原表。

## 4. 可复现性验证（2026-09-22 实测）

| 验证 | 方法 | 结果 |
|---|---|---|
| 构建可复现 | 干净重编译后比 SHA-256 | **fw.bin/elf 逐字节一致**（`0930234D…` / `EEC783AD…`） |
| 端到端回放 | 重编译 → 烧录 → 运行 → 回读 | **结果 blob 与权威运行逐字节一致**（`FD9DC30D…`） |
| 运行内确定性 | 同固件重置运行 ×3 | 三次 blob 逐字节一致 |
| 数字可追溯 | 全部结果由 `make_manifest.py` 自 blob 重算 | `results/results_summary.json` |

完整步骤与预期值：见 **`REPRODUCTION.md`**；全文件哈希：**`MANIFEST_SHA256.txt`**。

## 5. 与论文的关系（供写作使用，尚未写入正文）

- **对应意见**：R2-C04 / R3-C10（"wearable ready 依据为桌面剖析与估算"）。
- **可用数字**（须带范围声明）：决策层每窗 **5.89 ms**（mean，Cortex-M3 72 MHz、W=13、软浮点）；算法静态 RAM **3.2 KB** + 栈 ≤0.25 KB；代码 **≈4.7 KB**；输出与 MATLAB 逐窗一致。
- **必须携带的口径**（D031）：**"decision-layer on-device measurement; spectral front-end computed offline"**；不得表述为全流水线板级部署；能量只能写 estimate 或留待实测。
- **候选表述**（示例，最终由作者定稿）：
  > "The decoding stage was executed on a Cortex-M3 at 72 MHz (no FPU, soft-float) with per-window latency of 5.89 ms (mean; 5.92 ms P95) at the paper configuration, using 3.2 KB of static RAM plus ≤0.25 KB of stack; the on-device output sequence matches the MATLAB reference window-for-window on five recordings from two datasets. Energy was not measured; a datasheet-based projection gives 0.70–0.97 mJ per decode at 72 MHz."

## 6. 局限

1. **仅决策层**：前端（双 Wiener/相位声码器）离线；论文与回复信须按此限定。
2. **能量为估算**：无功耗仪；真实值需 INA226/PPK2 类仪器。
3. **平台保守**：Cortex-M3 无 FPU（软浮点），非论文曾提及的 M4 类；实测数字对 M4 而言是**保守上界**。
4. **芯片疑兼容片**：SRAM 64 KiB 与标准件不符；论文只写器件 ID 与实测资源。
5. **记录范围**：每段 256 窗（约 8.5 分钟数据），非全记录；跨 5 段记录验证了数据依赖性可忽略。

## 7. 证据索引（关键结论 → 文件）

| 结论 | 证据文件 | SHA-256（前 16 位） |
|---|---|---|
| 主结果（canonical） | `results/matrix/f72w13_r1.bin`（= `results/fw_results.bin`） | `FD9DC30D1BB09F65` |
| 重复性 ×3 | `results/matrix/f72w13_r{1,2,3}.bin` | 三者同哈希 |
| 时钟/带宽缩放 | `results/matrix/f{24,48,72}w13.bin`、`f72w0{7,25}.bin` | 见清单 |
| 跨记录保真 | `results/matrix/{s2,s3,ws1,ws2}.bin` + `results/cross_check.txt` | 见清单 |
| 端到端回放 | `results/matrix/replay_clean.bin` | `FD9DC30D…`（同 canonical） |
| 固件构建 | `fw/fw.elf`、`fw/fw.bin`、`fw/fw.map`、`fw/*.c/h/ld/Makefile` | `EEC783AD…` / `0930234D…` |
| 数据来源（L3） | `results/mcu_logL_*.bin`、`mcu_ref_est_*.txt`、`mcu_export*.log` | 见清单（大文件不入库，本地保留） |
| 台账与过程 | `EMB-01_LOG.md`（接线/识别/全部结果）、`REPRODUCTION.md`、`INDEX.md` | — |
| 照片证据（辅助） | `evidence_photos/`（4 张） | 见清单 |

## 8. 文件导航

```
embedded_mcu_20260921/
├─ EMB-01_REPORT.md       ← 本报告（结论与证据索引）
├─ REPRODUCTION.md        ← 复现手册（L1/L2/L3 + 排障）
├─ EMB-01_LOG.md          ← 过程日志（接线、识别、逐项结果）
├─ INDEX.md               ← 目录索引
├─ MANIFEST_SHA256.txt    ← 全部产物哈希清单（make_manifest.py 生成）
├─ fw/                    ← 固件源码与构建产物
├─ results/               ← 原始 blob（matrix/ 12 份）、汇总、跨验证、能量、汇总 JSON
├─ flash_backup/          ← 烧录前整片备份（256 KiB）
├─ evidence_photos/       ← 过程照片（本地保留）
└─ *.py / *.ps1 / *.m     ← 导出、自动化、分析与清单脚本
```

## 9. 勘误（2026-09-23 追加；不回写历史）

> 依据 [`../REVISION_STATE_REVIEW_20260922_V2.md`](../REVISION_STATE_REVIEW_20260922_V2.md) 与 [`../REVISION_ALIGNMENT_20260923.md`](../REVISION_ALIGNMENT_20260923.md) §A.3。本节**只追加更正**，不修改上文任何历史条目。

**更正内容**：本报告的实测范围应表述为「**离线观测输入下、可靠性温度关闭的 raw 解码核（SSC 高斯转移 + 固定延迟 Viterbi）回放**」，而非"含中值输出滤波的决策层"。

| # | 原表述（保留在历史中） | 更正 |
|:--:|------|------|
| 1 | `results/results_summary.json` 的 `scope` 写 "median-3 output filter" | 已在该 JSON 追加 `scope_correction` 字段；固件 `fw/main.c` 的 `run_variant` 不含输出滤波（三点中值仅存在于 `ds5.m:359-360`） |
| 2 | `DECISIONS.md` D031 写"中值输出滤波" | 追加更正条目（**不回写** D031 原文） |
| 3 | 回复信 Comment 4 写 "median output filter" | 已同步为「SSC transition and fixed-lag Viterbi, with the reliability temperature disabled」 |
| 4 | 本报告 §1/§6 的范围表述 | 以本节为准：**不实现 A′ 的可靠性温度状态更新**；导出配置为温度关闭（`exp_export_mcu.m` 以 5.9584/5.7836 回归，未启用 `a2_cfg`） |

**技术根因**：`ds5.m:257` 的 `dump_logL` 在 `ds5.m:259-264` 的温度乘法**之前**保存逐窗似然；因此**仅在导出脚本加 `a2_cfg` 也不足以**让导出的观测自动包含温度效应。

**未受影响（原结论全部有效，数值无需修改）**：实测计时（canonical 72 MHz、W=13、mean 5.8869 ms；另四片段 5.900–5.908 ms）、逐窗保真（`254/254`）、字节级重建/回放一致（`FD9DC30D…`）、静态阵列 3,220 B 与 ≈4.7 kB 代码口径、能量为 ESTIMATE。

**对外表述上限**：板级数字不得与 5.83 BPM 的最终性能混为同一板级验证对象；若要声称"完整 A′ on-device"，须把温度反馈与输出规则纳入被测边界并重测（属 `EXPERIMENT REQUIRED`，见 [`../REVISION_ACTION_CHECKLIST_20260923.md`](../REVISION_ACTION_CHECKLIST_20260923.md) §3.1 ER-2）。

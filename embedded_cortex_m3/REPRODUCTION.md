---
doc_id: "emb-02"
title: "EMB-01 复现手册：STM32F103 板级决策层实测（2026-09-22）"
category: "audit"
role: "[Delta]"
status: "published"
date: "2026-09-22"
author: "返修会话产出"
---

# EMB-01 复现手册

> **目标**：任何人（或未来的自己）按本文可从零复现全部板级实测结果。
> **三个复现等级**：**L1 结果级**（无硬件，10 秒）→ **L2 固件级**（需板子，约 3 分钟）→ **L3 全链级**（需 MATLAB + 本地数据缓存）。
> **完整性校验**：所有产物 SHA-256 见 `MANIFEST_SHA256.txt`；机器可读结果见 `results/results_summary.json`。

---

## 1. 硬件与接线（L2 前置）

| 项 | 值 |
|---|---|
| 目标板 | STM32-Mini V3.1（Mcudev）；MCU：STM32F103 兼容片 |
| 器件 ID | DBGMCU_IDCODE `0x10036414`（DEV_ID 0x414）；Flash 256 KiB；SRAM 实测 64 KiB |
| 调试器 | 金壳克隆 ST-Link V2（固件 `V2J45S7`，VID:PID `0483:3748`） |
| 供电 | 3.3 V（目标电压实测 ~3.12 V） |

**接线表（工作配置）**：

| ST-Link 外壳丝印针号 | 信号 | 目标板 |
|---|---|---|
| 2 | SWCLK | PA14 |
| 4 | SWDIO | PA13 |
| 6 | GND | GND |
| 8 | 3.3 V | 3V3 |
| 10 | 5.0 V | **不接** |

> ⚠️ 该克隆棒丝印为 2×5 排布（RST/SWCLK、SWIM/SWDIO、GND/GND、3.3V/3.3V、5.0V/5.0V）。
> **偶数列（2/4/6/8/10）才是 SWD 需要的信号**；按奇数列（1/3/5/7/9）接线必然 `init mode failed`（历史故障根因）。
> 过程照片见 `evidence_photos/`（辅助证据）。

## 2. 工具链（版本固定）

| 工具 | 版本 | 安装 | 备注 |
|---|---|---|---|
| openocd | xpack 0.12.0-7 | `winget install xpack-dev-tools.openocd-xpack` | 0.12 已移除 `hla_swd`，克隆棒走 `dapdirect` 正常 |
| arm-none-eabi-gcc | 14.2.Rel1 | `winget install Arm.GnuArmEmbeddedToolchain` | PATH：`C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin` |
| ST-Link 驱动 | Zadig 2.9 → WinUSB | `winget install akeo.ie.Zadig` | 首次需在 Zadig 选 `STM32 STLink` 装 WinUSB |
| Python | 3.12（`py -3` 或完整解释器路径） | 系统已装 | `py` 启动器会打印 "Could not find platform independent libraries"——无害 |
| MATLAB（仅 L3） | 本机 `D:\matlab\bin\matlab.exe` | — | 需要 `revision/audit/method_dev/` 与本地 `cache2/` |

## 3. L1：结果级复现（无硬件，约 10 秒）

```powershell
cd revision\audit\embedded_mcu_20260921
py -3 analyze_matrix.py     # -> results/matrix_summary.txt
py -3 check_ext.py          # -> results/cross_check.txt
py -3 energy_estimate.py    # -> results/energy_estimate.txt
py -3 make_manifest.py      # 重算 results_summary.json + 重建 SHA-256 清单
```

**预期**（与 `results_summary.json` 一致）：
- matrix：7 个配置，全部 `magic=0x3142FFFF`、`est 254/254`；
- 关键值：`f72w13` = dense 65.7403 ms / banded 5.8869 ms（比值 11.17）；
- cross：S2/S3/WS1/WS2 全部 254/254；
- energy：72 MHz/W13 单窗 0.699–0.971 mJ（ESTIMATE）。

## 4. L2：固件级复现（需板子，约 3 分钟）

### 4.1 构建（字节级可复现）

```powershell
$env:Path = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin;" + $env:Path
cd revision\audit\embedded_mcu_20260921\fw
Remove-Item *.o, fw.elf, fw.bin, fw.map -ErrorAction SilentlyContinue
make
```

**预期**：`text 169608 / data 4116 / bss 3220`；
**SHA-256**：`fw.bin = 0930234D…F515F`、`fw.elf = EEC783AD…0FC31F`（完整值见 `MANIFEST_SHA256.txt`）。
（2026-09-22 已实测：干净重编译与先前构建**逐字节一致**。）

### 4.2 烧录 → 运行 → 回读

```powershell
cd ..     # 回到 embedded_mcu_20260921
powershell -ExecutionPolicy Bypass -File .\run_cfg.ps1 -Tag replay -Defs NONE -WaitSec 32
```

> `-Defs NONE` 表示默认配置（72 MHz / W=13）；**不要传 `-Defs ""`**（空字符串在嵌套调用中会被丢弃）。
> 其它配置：`-Defs "-DCLK_MHZ=24"`、`-Defs "-DBAND_HW=3"` 等。

**预期**：`** Verified OK **` → 等待期间固件自动运行 → `0x20000c94: 3142ffff`（magic=DONE）→ `dumped 4116 bytes`。

### 4.3 与权威结果比对

```powershell
py -3 check_results.py results/matrix/replay.bin results/mcu_ref_est_s1.txt results/replay_summary.txt
Get-FileHash results\matrix\replay.bin, results\matrix\f72w13_r1.bin -Algorithm SHA256
```

**预期**：`est dense 254/254`、`est banded 254/254`；两个 blob 的 SHA-256 应为
**`FD9DC30D…4E0A`**（2026-09-22 端到端回放实测与权威运行**逐字节一致**）。

## 5. L3：全链级复现（需 MATLAB + 本地 cache2）

```powershell
# 5.1 导出（含 headline 复现门槛：dalia 5.9584 / wesad 5.7836）
D:\matlab\bin\matlab.exe -batch "cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/embedded_mcu_20260921'); exp_export_mcu"
D:\matlab\bin\matlab.exe -batch "cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/embedded_mcu_20260921'); exp_export_extra"
D:\matlab\bin\matlab.exe -batch "cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/embedded_mcu_20260921'); exp_export_extra2"
D:\matlab\bin\matlab.exe -batch "cd('d:/小论文/manuscript_JBHI_IEEEtran/revision/audit/embedded_mcu_20260921'); gen_mcu_tables"

# 5.2 切出固件数据（示例：S1 前 256 窗）
py -3 build_data.py results/mcu_logL_s1.bin 0 256 161 fw/win_data.bin
# 然后回到 §4.1 构建与 §4.2 运行
```

**门槛**：`exp_export_mcu` 的 diary（`results/mcu_export_log.txt`）必须先打印
`[headline] dalia mean = 5.9584` / `wesad mean = 5.7836`，否则停止（说明注入点或环境已变）。
**依赖**：`ds5.m` 的 `dump_logL` 注入点（默认关闭）+ 本地 `cache2/`（不入库、不重建）。

## 6. 全矩阵重跑（可选）

| tag | 命令 | 预期 banded mean |
|---|---|---|
| f72w13 | `.\run_cfg.ps1 -Tag f72w13 -Defs NONE -WaitSec 32` | 5.8869 ms |
| f48w13 | `.\run_cfg.ps1 -Tag f48w13 -Defs "-DCLK_MHZ=48" -WaitSec 45` | 7.0036 ms |
| f24w13 | `.\run_cfg.ps1 -Tag f24w13 -Defs "-DCLK_MHZ=24" -WaitSec 75` | 12.1216 ms |
| f72w07 | `.\run_cfg.ps1 -Tag f72w07 -Defs "-DBAND_HW=3" -WaitSec 32` | 3.4991 ms |
| f72w25 | `.\run_cfg.ps1 -Tag f72w25 -Defs "-DBAND_HW=12" -WaitSec 32` | 10.5266 ms |
| 重复性 | `.\repeat_run.ps1 -Tag f72w13 -Defs NONE -N 3 -WaitSec 32` | 三次应逐字节一致 |
| 跨记录 | `.\run_ext.ps1 -Tag s2 -SrcBin results/mcu_logL_s2.bin -WaitSec 32` | 5.908 ms |

**等待时间口径**：每配置总运行 = dense 总时长 + banded 总时长 =
72 MHz 约 18.3 s、48 MHz 约 22.2 s、24 MHz 约 38.6 s、W=7 约 17.7 s、W=25 约 19.5 s → WaitSec 分别取 32 / 45 / 75 / 32 / 32（含余量）。

## 7. 故障排查

| 症状 | 原因 | 处置 |
|---|---|---|
| `init mode failed` | 接线错（最常为按奇数列接） | 按 §1 接线表；或万用表锚定 5V/3.3V/GND 针位 |
| `Debug adapter doesn't support 'hla_swd'` | openocd ≥0.12 已移除 hla | 忽略；`stlink.cfg` 默认 `dapdirect_swd` 即可 |
| `dump_image` 静默失败 | 路径为反斜杠且带引号 | 用**正斜杠、不加引号**的路径 |
| magic 非 `0x3142FFFF` | 等待不足（配置越慢需越长）/ 固件被改 | 按 §6 时间表加余量；确认固件含 volatile magic 写入 |
| 参数绑定报错 "Missing an argument for parameter 'Defs'" | `-Defs ""` 空串被丢弃 | 用 `-Defs NONE` 或省略该参数 |
| `py` 打印 "platform independent libraries" | `py` 启动器环境噪音 | 无害；或直接用完整解释器路径 |

## 8. 归档边界（哪些文件入库、哪些本地保留）

| 类别 | 处理 | 说明 |
|---|---|---|
| 脚本 / 文档 / 小结果（`*.py`、`*.ps1`、`*.m`、`*.md`、`matrix/*.bin` 4 KB×12、`mcu_ref_est_*.txt`、`fw/fw.bin|elf|map`、`win_data.bin`、`flash_backup/`） | **入库** | 合计约 1.3 MB，构成自洽证据包 |
| 大派生数据：`results/mcu_logL_*.bin`（≈12.5 MB）、`results/mcu_export.mat`（2.3 MB） | 本地保留，`.gitignore` 排除 | 可由 §5 从本地 cache2 重建；SHA-256 已入清单 |
| 编译中间产物 `fw/*.o` | 本地保留，`.gitignore` 排除 | `make` 可重建 |
| `evidence_photos/`（4 张，≈10.5 MB） | 本地保留，`.gitignore` 排除 | 辅助过程照片；接线关系以 §1 文本表为准 |

> 复现**不依赖**被排除的大文件：L1/L2 用入库文件即可完整跑通；只有 L3（重新导出）需要本地 cache2。
>
> **哈希注明**：`MANIFEST_SHA256.txt` 中**文本文件**的哈希按当前工作区（Windows CRLF）计算；git 检出或跨平台可能规范化行尾，
> 届时文本文件哈希可能变化——**二进制文件（`fw.bin`/`fw.elf`、`results/matrix/*.bin`）的哈希不受影响，是权威校验对象**。

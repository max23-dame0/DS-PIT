---
doc_id: "e2e-02-log"
title: "E2E-02 审计执行日志：R2 检查点封存与 STM32F103 四抓手优化全程"
category: "audit"
role: "[Delta]"
status: "published"
date: "2026-11-24"
author: "R2 小修会话"
---

# E2E-02 审计执行日志（只追加，不改写历史）

> **目的**：按时间顺序完整记录从 R2 小修基线本地检查点封存，到在隔离工作区 `revision/audit/embedded_e2e_opt_20261124/` 执行四项加速优化、主机数值门禁校验、STM32F103 真机 SWD 实测及 Cortex-M4F 静态验证的全过程。

---

## 条目 1（Stage A）：R2 交付件与 E2E-01 基线本地 Git 检查点封存

- 核对 [../embedded_e2e_float32/MANIFEST_SHA256.txt](../embedded_e2e_float32/MANIFEST_SHA256.txt) 存在且工作树无残留临时文件。
- 于分支 `jbhi_minor_revision_kernel` 执行 `git add -A && git commit -m "checkpoint(R2): freeze minor revision deliverables and E2E-01 float32 Cortex-M3 baseline (208.44 ms)"`，生成检查点提交 `79d6b9d72633d38f5cb0a91f47ebc0fa0859f138`，并确认 `git status --short` 为空（严格遵守 Rule 11，未执行 `git push`）。
- 更新根级 `.gitignore`，忽略 `revision/audit/embedded_e2e_opt_20261124/{fw/*.o,host_test/*.exe,host_test/*.o,results/*_raw*.bin}` 构建与临时二进制产物。

## 条目 2（Stage B）：离线查找表生成、定点预仿真与工程除错

- 编写并执行 [gen_opt_tables.py](gen_opt_tables.py) 生成 [src_f32_opt/e2e_f32opt_tables.h](src_f32_opt/e2e_f32opt_tables.h) 与 [src_q31_opt/e2e_opt_tables.h](src_q31_opt/e2e_opt_tables.h)：
  - 校验抓手 2 剪枝 `1024 -> 4x256` Radix-4 DIF FFT + `k=31..122` 对称共轭频点 `digitrev4` 解包公式与直接 1024 点参考之最大误差为 `4.183e-12`。
  - 仿真检验 `Q11.20 / Q50` DF-II-T SOS 与对称剪枝 FIR 在 `s1`/`ws1` 上的最大误差分别为 `1.502e-03` 与 `1.906e-04`。
  - 核实 DaLiA 101-tap Nyquist-5 重采样 FIR 含 40 个非零对称系数对 + 中心抽头 `idx=50` 及 20 个精确零值（每样本乘法从 `101` 降至 `41`）。
- 分别在 [src_f32_opt/](src_f32_opt/)（抓手 2 + 3）与 [src_q31_opt/](src_q31_opt/)（抓手 1 + 2 + 3）完成 C99 模块化实现，期间在主机实测阶段定位并修复了三项工程缺陷：
  1. 修复 [gen_opt_tables.py](gen_opt_tables.py) 中 `q_round(1.0, 31)` 饱和溢出与 `fmt_f32` 小数点格式。
  2. 修复 `q31_opt` 中 [spec_q31.c](src_q31_opt/spec_q31.c) 的 `zscore_200_q21`：针对高幅值 PPG 下 `uint64_t` 方差溢出及 DaLiA 静止段极微弱 ACC 方差精度丢失，改用 `max_abs` + `__builtin_clz` 动态自适应归一化；同时在 [dspit_q31opt.c](src_q31_opt/dspit_q31opt.c) 中将 `[-2,+2] G` DaLiA ACC 缩放至 `Q3.28`（`<< 8`）保留 S1 状态精度。
  3. 将 [dspit_q31opt.c](src_q31_opt/dspit_q31opt.c) 中 `on_window` 的大型 `double` 宿主 trace 局部缓冲包裹在 `#ifdef DSPIT_ENABLE_TRACE` 内，消除 MCU 侧无谓栈空间消耗。

## 条目 3（Stage C）：主机端双精度 trace 对齐与精度门禁验证（PASS）

- 用 `gcc -O2 -Wall -Wextra -std=c99` 零警告编译并运行 [host_test/test_f32opt.exe](host_test/) 与 `test_q31opt.exe`（输出存 [results/host_opt_verify_log.txt](results/host_opt_verify_log.txt) 与 `results/host_{f32opt,q31}_<tag>.bin`）：
  - **`f32opt`**（`sizeof algo = 26,280 B`）：5 条记录相对 `E2E-01` 达成 `1,270/1,270 (100.00%)` 一致，相对 `cache2` `float64` 为 `1,234/1,270 (97.17%)`，平均 MAE `7.5312 vs 7.7266 BPM`（差 `-0.1954`），`s1` dense 与 banded `254/254` 一致 -> **PASS**。
  - **`q31`**（`sizeof algo = 26,416 B`）：S1 误差比 `f32opt` 降低 **6x–22x**，消除了 `s3` `48.00` BPM 单窗离群跳变（`s3` 对 `cache2` 达 `253/254, maxd=1.00`）；汇总相对 `E2E-01` 为 `1,245/1,270 (98.03%)`，相对 `cache2` `1,222/1,270 (96.22%)`，平均 MAE `7.5421 vs 7.7266 BPM`（差 `-0.1845`），`s1` dense 与 banded 一致 -> **PASS**。

## 条目 4（Stage D）：STM32F103 @ 72 MHz 真机烧录、13 次 SWD 回放与 Cortex-M4F 静态编译

- 于 [fw/](fw/) 通过 `arm-none-eabi-gcc -O3` 零警告生成三份目标固件：
  - `fw_f32_opt.elf`（`.isr_vector=64, .text=27264, .data=80, .bss=26280, .mailbox=4136`）
  - `fw_q31_opt.elf`（`.isr_vector=64, .text=27696, .ARM.exidx=8, .data=0, .bss=26416, .mailbox=4136`）
  - `fw_m4f.elf`（`.isr_vector=64, .text=24148, .data=80, .bss=26280, .mailbox=4136`）
- 经 OpenOCD SWD 对真机 STM32F103（72 MHz）运行 5 轮 `f32_opt`（`s1`–`s3`, `ws1`–`ws2`）与 8 轮 `q31_opt`（`s1_r1/r2/r3`, `s2`, `s3`, `ws1`, `ws2`, `s1_dense`），全部 13 次运行均获 `host_match_est = 254/254`、`host_match_es = 254/254` 及 `host_tau_maxdiff <= 1.2e-7`。
  - `f32_opt` 实测 `s1` `177.189 ms`、`s2` `177.251 ms`、`s3` `177.277 ms`、`ws1` `154.181 ms`、`ws2` `154.202 ms`（栈高水位 `9,088 B`，源自 `dspit_f32opt.c` 未受条件宏隔离的 `double` trace 数组在 `-O3` 下的栈帧分配）。
  - `q31_opt` 实测 `s1_r1/r2/r3` 均为 `28.470 ms`、`s2` `28.741 ms`、`s3` `28.696 ms`、`ws1` `24.705 ms`、`ws2` `24.693 ms`、`s1_dense` `37.721 ms`（栈高水位仅 `1,528 B`）。
- 生成 [results/m4f_static_check.txt](results/m4f_static_check.txt)：验证 `fw_m4f.elf` 含 `317` 条硬件 VFP `*.f32` 指令且 `__aeabi_fadd/sub/mul/div` 符号为 `0`（仅作静态检查）。

## 条目 5（Stage E）：汇总分析、SHA256 清单与审计报告封存

- 编写并执行 [analyze_e2e_opt.py](analyze_e2e_opt.py)，基于全部运行 JSON、ELF `arm-none-eabi-size -A` / `arm-none-eabi-nm -S`（字节级区间归属去重）及 `golden/*_trace_f64.bin` 重算写入 [results/results_summary_e2e_opt.json](results/results_summary_e2e_opt.json)，且与 `results/host_opt_verify_log.txt` 断言 100% 匹配。
- 编写本日志与 [E2E-02_REPORT.md](E2E-02_REPORT.md)，并通过 [make_manifest_opt.py](make_manifest_opt.py) 生成全量产物校验清单 [MANIFEST_SHA256.txt](MANIFEST_SHA256.txt)。
- 检查点 `79d6b9d7` 冻结的 `E2E-01` 与 `main_R2.*`、`Supplementary_Material_R2.*`、`minor_revision_R2/` 保持零改动；`E2E-02` 成果保留未提交工作区等待作者决策。

## 条目 6（Stage F）：全库 30 人完整长序列宿主 C99 核验（`108,172` 步 / `60.10 h`）

- 依据用户需求，验证 `E2E-01`、`f32-opt` 与 `q31-opt` 在全库 30 名受试者（PPG-DaLiA `S1`–`S15` + WESAD `S2`–`S17`）完整长度记录上是否保持论文主结果 `5.83 / 5.76 BPM`，并评估全库在 MCU 上运行的耗时规模：
  - 若在真机 STM32F103 SWD 回放全库 `108,172` 块（`60.10 h` 信号），纯计算 + SWD 墙钟分别需要约 `7.55 h`（`e2e01`）、`6.33 h`（`f32opt`）与 `2.02 h`（`q31opt`）；而在 PC 宿主用 `-O3 -std=c99` 运行三套完全一致的片上源码（[host_test/run_full30.c](host_test/run_full30.c) + [host_test/eval_full30.py](host_test/eval_full30.py)）仅耗时 `4.61 s`、`3.18 s` 与 `7.50 s`。
  - 结果写入 [results/full30_host_eval.json](results/full30_host_eval.json)（经检验不含本机绝对路径）：
    - **PPG-DaLiA（15 人，64,652 有效窗，`cov = 0.9993`）**：MATLAB `f64` `5.8302 ± 2.1847`，`e2e01` `5.8272 ± 2.1862`（`-0.0030`），`f32opt` `5.8273 ± 2.1862`（`-0.0029`），`q31opt` **`5.8206 ± 2.1814`**（`-0.0095`，最大单人差 `0.0581` @ `S12`）。
    - **WESAD（15 人，22,478 有效窗，`cov = 1.0000`）**：MATLAB `f64` `5.7569 ± 3.2355`，`e2e01` `5.7603 ± 3.2339`（`+0.0034`），`f32opt` `5.7603 ± 3.2339`（`+0.0034`），`q31opt` **`5.7583 ± 3.2337`**（`+0.0014`，最大单人差 `0.0255` @ `S10`）。
- 重跑 [make_manifest_opt.py](make_manifest_opt.py) 更新 [MANIFEST_SHA256.txt](MANIFEST_SHA256.txt)。


## 条目 7（Stage G）：`fw_q31_opt.elf` 真实 STM32F103 扩展实测（30 人前缀 + 2 条多小时完整耐力回放）

- 检查点 `4e05e28b`（Phase 1：将 `E2E-02` `Q31` 与 30 人 C99 核验并入 R2 全套稿件与答复件）提交并推送至 `origin/jbhi_minor_revision_kernel` 后，严格保持 `fw/fw_q31_opt.elf` 零改动，编写并运行 [host_driver/stream_q31_enriched.py](host_driver/stream_q31_enriched.py) 对真机 STM32F103（72 MHz，`adapter speed 1800`，通过环境变量 `DSPIT_DATA_ROOT` 读取数据，OpenOCD 临时日志写入系统临时目录并清理）完成三组实测，单次运行产物存 [results/mcu_q31_enriched/](results/mcu_q31_enriched/)：
  1. **`--part dalia15`**（PPG-DaLiA `S1`–`S15` 各前 261 块，共 `3,855` 稳态步）：15/15 通过，均值 `28.641 ms`（范围 `28.470`–`28.797 ms`，占空比 `1.43%`，P95 `28.957 ms`），栈 HWM 全 `1,528 B`，与 `run_full30_q31opt.exe` 一致 **`3,810/3,810 (100%)`**。
  2. **`--part wesad15`**（WESAD `S2`–`S11, S13`–`S17` 各前 261 块，共 `3,855` 稳态步）：15/15 通过，均值 `24.633 ms`（范围 `24.364`–`24.705 ms`，占空比 `1.23%`，P95 `24.817 ms`），栈 HWM 全 `1,528 B`，与宿主一致 **`3,810/3,810 (100%)`**；30 人合并均值 `26.637 ms`（P95 `28.890 ms`，占空比 `1.33%`，`7,620/7,620` 一致）。
  3. **`--part endurance2`**（`DaLiA S1` 完整 `4,607` 块 / `2.56 h` + `WESAD S2` 完整 `3,041` 块 / `1.69 h`）：均实现与宿主完整序列 `100%` 逐窗匹配（`4,600/4,600` @ `MAE = 5.0737 BPM`，`3,033/3,033` @ `MAE = 3.4923 BPM`，vs 宿主误差均 `0.0000 BPM`）；均值耗时 `28.697 ms` / `24.605 ms`，`Q4 - Q1` 稳态均值漂移 `-0.0361 ms` / `-0.1862 ms`，栈 HWM 恒定 `1,528 B`。
- 运行 [analyze_q31_enriched.py](analyze_q31_enriched.py) 写入 [results/results_summary_q31_enriched.json](results/results_summary_q31_enriched.json)，追加 [E2E-02_REPORT.md](E2E-02_REPORT.md) 第 7 节，并重新生成 [MANIFEST_SHA256.txt](MANIFEST_SHA256.txt)。

# Optimized & Fixed-Point End-to-End DS-PIT C99 Pipeline (`Q31` & `float32-opt`)

This folder contains the optimized C99 STM32F103 Cortex-M3 firmware (`src_f32_opt/` and `src_q31_opt/`), Cortex-M4F hard-float static cross-compile check (`fw/fw_m4f.elf`), full 30-subject host C99 evaluation harness (`host_test/run_full30.c`, `host_test/eval_full30.py`), and enriched 30-subject + multi-hour hardware endurance suite (`host_driver/stream_q31_enriched.py`).

## Key Hardware Results (`fw_q31_opt.elf`, STM32F103 Cortex-M3 @ 72 MHz)
1. **5-Recording Benchmark Prefixes (`n = 1,285` steady hops, `1,270` eval windows)**:
   - **Pooled Latency**: **`27.061 ms`** / 2-s hop (**`7.70x` speedup** vs. `float32` `208.435 ms`, **`1.35%` duty**, P95 `28.884 ms`, Max `29.049 ms`; DaLiA `28.636 ms` / WESAD `24.699 ms`).
   - **Memory Footprint**: `26,416 B` (`26.4 kB`) algorithm static RAM + `1,528 B` (`1.5 kB`) measured runtime stack (`27,944 B` peak algorithm RAM, `.data = 0 B`); `26,762 B` (`26.8 kB`) algorithm+alignment flash (`27,768 B` / `27.8 kB` total firmware flash).
2. **Full 30-Subject Host C99 Parity (`108,172` blocks / `60.10 h` / `87,130` valid windows)**:
   - **PPG-DaLiA (15 subj., 64,652 windows)**: **`5.8206 ± 2.1814` BPM** (vs. MATLAB `5.8302 ± 2.1847`, max per-subject diff `0.0581` BPM).
   - **WESAD (15 subj., 22,478 windows)**: **`5.7583 ± 3.2337` BPM** (vs. MATLAB `5.7569 ± 3.2355`, max per-subject diff `0.0255` BPM).
3. **Expanded Real-STM32F103 Hardware Run (`fw_q31_opt.elf` unmodified)**:
   - **All 30 Subjects (`n = 7,710` steady hops)**: `26.637 ms` pooled (P95 `28.890 ms`, `1.33%` duty), `1,528 B` constant stack, **`7,620/7,620` (`100.00%`)** exact match vs. host C99 `Q31`.
   - **Full Continuous Endurance Runs (`4.25 h` continuous signals)**: `DaLiA S1` (`4,606` blocks, `28.697 ms`, `MAE 5.0737 BPM`, `4,600/4,600`) and `WESAD S2` (`3,039` blocks, `24.605 ms`, `MAE 3.4923 BPM`, `3,033/3,033`), `Q4 - Q1` mean drift `-0.0361 ms` / `-0.1862 ms`, constant `1,528 B` stack.

## Build & Run Commands

### 1. Cross-Compile STM32F103 / M4F ELF Firmware (`arm-none-eabi-gcc`)
```bash
cd fw
make clean && make
```

### 2. Build & Run Full 30-Subject C99 Parity Suite (`gcc` + Python 3 + `numpy`/`scipy`)
Requires `DSPIT_DATA_ROOT` pointing to downloaded raw PPG-DaLiA and WESAD directories:
```bash
cd host_test
make
make run_full30
export DSPIT_DATA_ROOT=/path/to/datasets
python eval_full30.py
```

### 3. Re-Aggregate Enriched Hardware Captures
```bash
python analyze_q31_enriched.py
```

See [`E2E-02_REPORT.md`](E2E-02_REPORT.md) and [`E2E-02_LOG.md`](E2E-02_LOG.md) for module-by-module memory accounting, Cortex-M4F static disassembly verification (static check only, not hardware-measured), and explicit SWD replay scope disclosures.

# End-to-End DS-PIT C99 Pipeline (`float32` Soft-Float Baseline)

This folder implements and benchmarks the **complete six-stage DS-PIT DSP chain (S1–S6)** on a **72-MHz STM32F103 ARM Cortex-M3 MCU** (no hardware FPU) in IEEE-754 single precision (`float32` soft-float, `-O2`):

1. **S1 Front-end**: 4th-order Butterworth IIR SOS bandpass (`[0.4, 4.0] Hz`) + 25-Hz polyphase/decimation resampling (`0.4 s` group delay).
2. **S2 Spectral transform**: 1024-pt real-packed radix-2 FFT + causal z-score normalization (`4` PPG+ACC channels).
3. **S3 Two-branch spectral enhancement**: Peak-normalized 3-axis acceleration reference + 15-frame historical ratio weighting + spectral taper & min-max likelihood normalization.
4. **S4 Causal LBP temperature ($\tau_t$)**: Dynamic likelihood temperature $\tau_t \in [0.7, 1.3]$.
5. **S5 Banded Viterbi decoder ($W_{band}=13, D=3$)**: Fixed-lag ($4\text{ s}$) max-product decoder.
6. **S6 Output smoother**: Centered 3-point median filter (`+2.0 s` lookahead; `6.4 s` total algorithmic lookahead / `14.4 s` nominal wait).

## Measured Hardware Summary (STM32F103 @ 72 MHz, 5 Prefixes / 1,285 Steady Hops)
- **Pooled Latency**: `208.44 ms` / 2-s hop (P95 `224.01 ms`, `10.42%` duty factor; DaLiA `223.71 ms`, WESAD `185.52 ms`).
- **Memory Footprint**: `26,556 B` (`26.6 kB`) algorithm static RAM + `2,192 B` (`2.2 kB`) measured runtime stack (`28,748 B` peak algorithm RAM); `21,799 B` (`21.8 kB`) algorithm flash (`22,771 B` / `22.8 kB` total firmware flash).
- **Numerical Parity**: `1,270/1,270 (100%)` window-exact match vs. host C99 `float32`; full 30-subject C99 MAE: **PPG-DaLiA `5.8272` BPM**, **WESAD `5.7603` BPM**.

## Build Instructions

### Firmware (`arm-none-eabi-gcc`)
```bash
cd fw
make clean && make
```
Outputs `fw.elf`, `fw.bin`, and `fw.map`.

### Host Reference Verifier (`gcc`)
```bash
cd host_test
make
```
Builds `test_f64.exe` (`-DREAL_DOUBLE`) and `test_f32.exe` (`float32`). See [`E2E-01_REPORT.md`](E2E-01_REPORT.md) and [`REPRODUCTION.md`](REPRODUCTION.md) for complete protocols and boundary disclosures (SWD memory replay excludes live optical/IMU drivers, wireless radio, and direct energy measurement).

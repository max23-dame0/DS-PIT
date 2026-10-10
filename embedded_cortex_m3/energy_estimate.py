#!/usr/bin/env python3
"""EMB-01 energy estimate (THEORETICAL, datasheet-based).

Method: E_per_window = V * I_run(f_clk) * t_window, where
  V       = 3.3 V nominal board rail (ST-Link target-voltage reading ~3.12 V)
  I_run   = datasheet TYPICAL run-mode current, code from Flash,
            all peripherals disabled  (low bound)  /  enabled (high bound)
  t_window= measured per-window decision-layer time (from results/matrix)

Datasheet currents (STM32F103xC/D/E, Doc ID 14611, Run mode, Flash):
  f=72 MHz: ~36 mA (periph off) / ~50 mA (periph on)
  f=48 MHz: ~24 mA (off) / ~34 mA (on)
  f=24 MHz: ~12 mA (off) / ~17 mA (on)
NOTE: values transcribed from the datasheet table; re-verify against the
      official PDF before any manuscript use (marked as ESTIMATE).

This is an ESTIMATE, not a measurement: no ammeter/power profiler was used.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from check_results import parse_blob, stats  # noqa: E402

RES = os.path.join(HERE, "results")
MAT = os.path.join(RES, "matrix")

V_NOM = 3.3           # V, board rail (nominal)
I_OFF = {72: 36e-3, 48: 24e-3, 24: 12e-3}   # A, peripherals disabled
I_ON = {72: 50e-3, 48: 34e-3, 24: 17e-3}    # A, peripherals enabled
HOP_S = 2.0           # s, decoder step (paper configuration)


def main() -> int:
    lines = ["=== EMB-01 energy estimate (THEORETICAL, datasheet-based, NOT measured) ===",
             "V = %.2f V nominal;  I from datasheet typical run-mode, code from Flash" % V_NOM,
             "",
             "tag        clk   W  t_banded_ms  E_lo_mJ  E_hi_mJ  P_avg_lo_mW(@2s)  P_avg_hi_mW"]
    rows = []
    for path in sorted(glob.glob(os.path.join(MAT, "*.bin"))):
        tag = os.path.splitext(os.path.basename(path))[0]
        mm = re.match(r"f(\d+)w(\d+)", tag)
        if not mm:
            continue
        clk = int(mm.group(1))
        if clk not in I_OFF:
            continue
        r = parse_blob(path)
        t = stats(r["cyc_b"])["mean"] / r["clk"]      # s, banded, per window
        e_lo = V_NOM * I_OFF[clk] * t                 # J
        e_hi = V_NOM * I_ON[clk] * t                  # J
        p_lo = e_lo / HOP_S * 1e3                     # mW average at 0.5 Hz decode
        p_hi = e_hi / HOP_S * 1e3
        lines.append("%-10s %4d %3s %10.3f  %8.3f  %8.3f  %16.3f  %10.3f" %
                     (tag, clk, int(mm.group(2)), t * 1e3,
                      e_lo * 1e3, e_hi * 1e3, p_lo, p_hi))
        rows.append((tag, clk, t, e_lo, e_hi))

    lines.append("")
    lines.append("Notes:")
    lines.append("- E = V*I*t uses MEASURED t (SWD-read DWT cycle count / measured clk); I is datasheet-typical.")
    lines.append("- Low bound = all peripherals disabled (this firmware enables none);")
    lines.append("  high bound = all peripherals enabled (conservative).")
    lines.append("- P_avg assumes one decode per %.0f s hop and ignores sleep current." % HOP_S)
    lines.append("- STATUS: ESTIMATE ONLY.  A real energy number requires a shunt/profiler measurement.")
    out = "\n".join(lines) + "\n"
    with open(os.path.join(RES, "energy_estimate.txt"), "w", encoding="utf-8") as f:
        f.write(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

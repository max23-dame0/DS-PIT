#!/usr/bin/env python3
"""EMB-01: parse fw_results.bin from the STM32F103 run and compare with MATLAB.

Usage:
  py -3 check_results.py [blob] [ref] [out]
Defaults: results/fw_results.bin, results/mcu_ref_est_s1.txt, results/mcu_check_summary.txt

Binary layout (little-endian):
  u32 magic, u32 clk_hz, u32 cfgr, u32 stack_used, u32 n_win
  u32 cycles_dense[N], u32 cycles_banded[N]
  f32 est_dense[N],    f32 est_banded[N]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")
N = 256


def parse_blob(path):
    with open(path, "rb") as f:
        blob = f.read()
    if len(blob) < 20 + 4 * N * 4:
        raise ValueError("results blob too small: %d" % len(blob))
    magic, clk, cfgr, stack, n_win = struct.unpack_from("<5I", blob, 0)
    off = 20
    cyc_d = list(struct.unpack_from("<%dI" % N, blob, off)); off += 4 * N
    cyc_b = list(struct.unpack_from("<%dI" % N, blob, off)); off += 4 * N
    est_d = list(struct.unpack_from("<%df" % N, blob, off)); off += 4 * N
    est_b = list(struct.unpack_from("<%df" % N, blob, off)); off += 4 * N
    return dict(magic=magic, clk=clk, cfgr=cfgr, stack=stack, n_win=n_win,
                cyc_d=cyc_d, cyc_b=cyc_b, est_d=est_d, est_b=est_b)


def stats(vals):
    s = sorted(vals)
    m = len(s)

    def pct(p):
        return s[min(m - 1, int(p * (m - 1)))]
    return dict(mean=sum(s) / m, min=s[0], p50=pct(0.50), p95=pct(0.95), max=s[-1])


def main() -> int:
    blob_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RES, "fw_results.bin")
    ref_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(RES, "mcu_ref_est_s1.txt")
    out_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(RES, "mcu_check_summary.txt")

    r = parse_blob(blob_path)
    with open(ref_path, "r", encoding="utf-8") as f:
        ref = [float(line.strip()) for line in f if line.strip()]

    lines = []
    add = lines.append
    add("=== EMB-01 MCU run summary ===")
    add("blob        = %s" % os.path.basename(blob_path))
    add("magic       = 0x%08X %s" % (r["magic"],
        "(DONE)" if r["magic"] == 0x3142FFFF else
        ("(AFTER_DS)" if r["magic"] == 0x31420002 else "(unexpected)")))
    add("clk_hz      = %d" % r["clk"])
    add("cfgr        = 0x%08X" % r["cfgr"])
    add("stack_used  = %d bytes (paint floor 256 B)" % r["stack"])
    add("n_win       = %d" % r["n_win"])
    add("")

    for tag, cyc in (("dense K^2", r["cyc_d"]), ("banded K*W (W=13)", r["cyc_b"])):
        st = stats(cyc)
        add("--- %s ---" % tag)
        add("cycles: min=%d  p50=%d  mean=%.1f  p95=%d  max=%d" %
            (st["min"], st["p50"], st["mean"], st["p95"], st["max"]))
        add("time  : min=%.3f ms  mean=%.3f ms  p95=%.3f ms  max=%.3f ms  (at %.0f MHz)" %
            (st["min"] * 1e3 / r["clk"], st["mean"] * 1e3 / r["clk"],
             st["p95"] * 1e3 / r["clk"], st["max"] * 1e3 / r["clk"], r["clk"] / 1e6))
        add("total : %.3f s for %d windows" % (sum(cyc) / r["clk"], len(cyc)))
        add("")

    ratio = stats(r["cyc_d"])["mean"] / stats(r["cyc_b"])["mean"]
    add("dense/banded mean-cycle ratio = %.2f  (K/W = %d/13 = %.2f)" % (ratio, 161, 161 / 13))
    add("")

    m = min(len(ref), N - 2)
    for tag, est in (("dense", r["est_d"]), ("banded", r["est_b"])):
        exact = 0
        worst = 0.0
        first_bad = None
        for i in range(m):
            e = est[i]
            if e < 0:
                continue
            d = abs(e - ref[i])
            if d < 1e-4:
                exact += 1
            else:
                if first_bad is None:
                    first_bad = (i, e, ref[i])
                worst = max(worst, d)
        add("est %-6s vs MATLAB: %d/%d exact, worst |diff| = %.3f BPM, first mismatch = %s" %
            (tag, exact, m, worst, str(first_bad)))
    add("")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""EMB-01 matrix analysis: summarize all results/matrix/*.bin runs in one table.

Tag convention: f<clk>w<band>  e.g. f72w13, f48w13, f24w13, f72w07, f72w25
  - dense est must match the MATLAB reference in every run (W-independent);
  - banded est is compared only for W = 13 (the paper configuration).
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


def main() -> int:
    with open(os.path.join(RES, "mcu_ref_est_s1.txt"), "r", encoding="utf-8") as f:
        ref = [float(line.strip()) for line in f if line.strip()]

    lines = ["=== EMB-01 experiment matrix ===",
             "tag        clk  W   magic     stack  dense_ms  banded_ms  ratio  dense_est_ok  banded_est_ok"]
    for path in sorted(glob.glob(os.path.join(MAT, "*.bin"))):
        tag = os.path.splitext(os.path.basename(path))[0]
        mm = re.match(r"f(\d+)w(\d+)", tag)
        if not mm:
            continue
        r = parse_blob(path)
        sd, sb = stats(r["cyc_d"]), stats(r["cyc_b"])
        td, tb = sd["mean"] / r["clk"] * 1e3, sb["mean"] / r["clk"] * 1e3

        def exact(est):
            n = 0
            for i in range(min(len(ref), 254)):
                if est[i] >= 0 and abs(est[i] - ref[i]) < 1e-4:
                    n += 1
            return "%d/254" % n

        ok_d = exact(r["est_d"])
        ok_b = exact(r["est_b"])
        lines.append("%-10s %4s %3s 0x%08X %5d  %8.3f  %9.3f  %5.2f  %-12s %s" %
                     (tag, mm.group(1), int(mm.group(2)), r["magic"], r["stack"],
                      td, tb, sd["mean"] / sb["mean"], ok_d, ok_b))
    out = "\n".join(lines) + "\n"
    with open(os.path.join(RES, "matrix_summary.txt"), "w", encoding="utf-8") as f:
        f.write(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

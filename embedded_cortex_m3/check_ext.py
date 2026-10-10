#!/usr/bin/env python3
"""EMB-01: cross-record verification (DaLiA S2, WESAD S1) against their own refs."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from check_results import parse_blob, stats  # noqa: E402

RES = os.path.join(HERE, "results")
MAT = os.path.join(RES, "matrix")
N = 256

JOBS = [("s2", "mcu_ref_est_s2.txt"), ("ws1", "mcu_ref_est_ws1.txt"),
        ("s3", "mcu_ref_est_s3.txt"), ("ws2", "mcu_ref_est_ws2.txt")]
lines = ["=== EMB-01 cross-record verification ==="]
for tag, refname in JOBS:
    r = parse_blob(os.path.join(MAT, "%s.bin" % tag))
    with open(os.path.join(RES, refname), "r", encoding="utf-8") as f:
        ref = [float(l.strip()) for l in f if l.strip()]
    sd, sb = stats(r["cyc_d"]), stats(r["cyc_b"])
    lines.append("--- %s ---" % tag)
    lines.append("magic=0x%08X clk=%d stack=%d" % (r["magic"], r["clk"], r["stack"]))
    lines.append("dense : mean=%.3f ms  banded: mean=%.3f ms" %
                 (sd["mean"] / r["clk"] * 1e3, sb["mean"] / r["clk"] * 1e3))
    m = min(len(ref), N - 2)
    for vtag, est in (("dense", r["est_d"]), ("banded", r["est_b"])):
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
        lines.append("est %-6s: %d/%d exact, worst |diff|=%.3f BPM, first mismatch=%s" %
                     (vtag, exact, m, worst, str(first_bad)))
    lines.append("")
out = "\n".join(lines) + "\n"
with open(os.path.join(RES, "cross_check.txt"), "w", encoding="utf-8") as f:
    f.write(out)
print(out)

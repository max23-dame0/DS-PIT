#!/usr/bin/env python3
"""Slice a window range out of an exported logL file into fw/win_data.bin.

Usage: py -3 build_data.py <src.bin> <start_window> <count> <K> <dst.bin>
"""
import sys

src, start, count, K, dst = (sys.argv[1], int(sys.argv[2]), int(sys.argv[3]),
                             int(sys.argv[4]), sys.argv[5])
need = count * K * 4
with open(src, "rb") as f:
    f.seek(start * K * 4)
    data = f.read(need)
if len(data) != need:
    raise SystemExit("short read: %d != %d" % (len(data), need))
with open(dst, "wb") as f:
    f.write(data)
print("wrote %d bytes -> %s (windows %d..%d)" % (len(data), dst, start, start + count - 1))

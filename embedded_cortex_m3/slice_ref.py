#!/usr/bin/env python3
"""Slice reference est lines for a window segment.

Usage: py -3 slice_ref.py <src.txt> <start_1based> <count> <dst.txt>
"""
import sys

src, start, count, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
with open(src, "r", encoding="utf-8") as f:
    lines = [l for l in f if l.strip()]
seg = lines[start - 1:start - 1 + count]
with open(dst, "w", encoding="utf-8") as f:
    f.writelines(seg)
print("wrote %d lines -> %s" % (len(seg), dst))

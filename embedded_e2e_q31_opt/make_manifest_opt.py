#!/usr/bin/env python3
"""Generate MANIFEST_SHA256.txt for E2E-02 optimization audit artifacts."""
import hashlib
from pathlib import Path

EXCLUDE_DIRS = {"__pycache__"}
EXCLUDE_EXTS = {".o", ".exe"}


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def main():
    root = Path(__file__).resolve().parent
    lines = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(root)
        if any(part in EXCLUDE_DIRS for part in rel.parts):
            continue
        if p.name == "MANIFEST_SHA256.txt":
            continue
        if p.suffix in EXCLUDE_EXTS:
            continue
        if p.name.endswith(".log") and rel.parts[0] == "results":
            continue
        lines.append(f"{sha256_file(p)}  {rel.as_posix()}")
    out = root / "MANIFEST_SHA256.txt"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} ({len(lines)} entries)")


if __name__ == "__main__":
    main()

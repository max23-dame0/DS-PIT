"""STM32F103 E2E SWD streaming runner via OpenOCD TCL server (stdlib only)."""
import argparse
import json
import shutil
import os
import re
import socket
import struct
import subprocess
import tempfile
import time
from pathlib import Path

OPENOCD_DEFAULT = os.environ.get(OPENOCD_EXE, shutil.which(openocd) or openocd)
ARM_NM_DEFAULT = os.environ.get(ARM_NM_EXE, shutil.which(arm-none-eabi-nm) or arm-none-eabi-nm)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin"
    r"\arm-none-eabi-nm.exe"
)


class OpenOcdTcl:
    """Persistent client for OpenOCD TCL server (port 6666, 0x1A delimited)."""

    def __init__(self, host="127.0.0.1", port=6666, timeout=15.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buf = bytearray()

    def cmd(self, text: str) -> str:
        self.sock.sendall(text.encode("utf-8") + b"\x1a")
        while True:
            idx = self.buf.find(b"\x1a")
            if idx >= 0:
                resp = bytes(self.buf[:idx]).decode("utf-8", errors="replace")
                del self.buf[: idx + 1]
                return resp.strip()
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("OpenOCD TCL socket closed unexpectedly")
            self.buf.extend(chunk)

    def read_u32(self, addr: int, count: int = 1):
        out = self.cmd(f"read_memory 0x{addr:08x} 32 {count}")
        vals = [int(tok, 0) for tok in out.split()]
        if len(vals) != count:
            raise RuntimeError(f"read_memory 0x{addr:08x} x{count} got {len(vals)}: {out!r}")
        return vals

    def write_u32(self, addr: int, vals):
        joined = " ".join(f"0x{v & 0xffffffff:08x}" for v in vals)
        self.cmd(f"write_memory 0x{addr:08x} 32 {{{joined}}}")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def find_mailbox_addr(elf_path: Path, nm_exe: str) -> int:
    res = subprocess.run(
        [nm_exe, str(elf_path)], capture_output=True, text=True, check=True
    )
    for line in res.stdout.splitlines():
        m = re.match(r"^([0-9a-fA-F]+)\s+[bBdD]\s+mb$", line.strip())
        if m:
            return int(m.group(1), 16)
    raise RuntimeError(f"Symbol 'mb' not found in {elf_path}")


def u32_to_f32(u: int) -> float:
    return struct.unpack("<f", struct.pack("<I", u & 0xFFFFFFFF))[0]


def load_raw_golden(raw_path: Path):
    data = raw_path.read_bytes()
    magic, ds_id, n_ppg, n_acc, n_win, n_eval = struct.unpack_from("<6I", data, 0)
    if magic != 0x45324552:
        raise RuntimeError(f"Bad raw magic 0x{magic:08x} in {raw_path}")
    off = 24
    ppg = struct.unpack_from(f"<{n_ppg}f", data, off)
    off += 4 * n_ppg
    ax = struct.unpack_from(f"<{n_acc}f", data, off)
    off += 4 * n_acc
    ay = struct.unpack_from(f"<{n_acc}f", data, off)
    off += 4 * n_acc
    az = struct.unpack_from(f"<{n_acc}f", data, off)
    return {
        "ds_id": ds_id,
        "n_ppg": n_ppg,
        "n_acc": n_acc,
        "n_win": n_win,
        "n_eval": n_eval,
        "ppg": ppg,
        "ax": ax,
        "ay": ay,
        "az": az,
    }


def run_streaming(
    tag: str,
    run_label: str,
    banded: int,
    root: Path,
    tcl: OpenOcdTcl,
    mb_addr: int,
    seq_start: int,
    max_blocks: int = 0,
):
    raw = load_raw_golden(root / "golden" / f"{tag}_raw_f32.bin")
    ds_id = raw["ds_id"]
    blk_ppg = 250 if ds_id == 0 else 128
    blk_acc = 250 if ds_id == 0 else 64
    n_blocks = raw["n_ppg"] // blk_ppg
    if max_blocks > 0:
        n_blocks = min(n_blocks, max_blocks)

    seq = seq_start

    def exec_cmd(cmd_id: int, np_val: int, na_val: int):
        nonlocal seq
        seq += 1
        # Write cmd, mode, banded, n_ppg, n_acc (offsets +0x0C, +0x18..+0x24)
        tcl.write_u32(mb_addr + 0x0C, [cmd_id])
        tcl.write_u32(mb_addr + 0x18, [ds_id, banded, np_val, na_val])
        tcl.write_u32(mb_addr + 0x10, [seq])
        deadline = time.monotonic() + 10.0
        while True:
            done_val = tcl.read_u32(mb_addr + 0x14, 1)[0]
            if done_val == seq:
                return
            if time.monotonic() > deadline:
                magic_now = tcl.read_u32(mb_addr, 1)[0]
                raise TimeoutError(
                    f"MCU timeout on seq={seq} cmd={cmd_id} (done={done_val}, magic=0x{magic_now:08x})"
                )
            time.sleep(0.001)

    # Read boot info + struct sizes
    hdr = tcl.read_u32(mb_addr, 3)
    clk_hz, cfgr = hdr[1], hdr[2]
    sz_words = tcl.read_u32(mb_addr + 0x68, 8)
    algo_ram_sz = sz_words[0]
    s_sizes = sz_words[1:8]

    # CMD_INIT
    exec_cmd(1, 0, 0)

    tmp_slab = Path(tempfile.gettempdir()) / f"e2e_slab_{os.getpid()}.bin"
    tmp_posix = str(tmp_slab).replace("\\", "/")

    est_list = [None] * raw["n_eval"]
    es_list = [None] * raw["n_eval"]
    tau_list = [None] * raw["n_win"]
    blocks = []
    win_idx = 0
    stack_peak = 0
    t_wall0 = time.monotonic()

    try:
        for b in range(n_blocks):
            p_slice = raw["ppg"][b * blk_ppg : (b + 1) * blk_ppg]
            ax_slice = raw["ax"][b * blk_acc : (b + 1) * blk_acc]
            ay_slice = raw["ay"][b * blk_acc : (b + 1) * blk_acc]
            az_slice = raw["az"][b * blk_acc : (b + 1) * blk_acc]
            slab_bytes = struct.pack(
                f"<{blk_ppg + 3 * blk_acc}f",
                *p_slice,
                *ax_slice,
                *ay_slice,
                *az_slice,
            )
            tmp_slab.write_bytes(slab_bytes)
            tcl.cmd(f"load_image {tmp_posix} 0x{mb_addr + 0x88:08x} bin")

            exec_cmd(2, blk_ppg, blk_acc)

            # Read outputs +0x28 .. +0x64 (16 uint32 words)
            w = tcl.read_u32(mb_addr + 0x28, 16)
            win_ran = w[0]
            has_est = w[1]
            has_es = w[2]
            est_index = w[3]
            es_index = w[4]
            est_bpm = u32_to_f32(w[5])
            es_bpm = u32_to_f32(w[6])
            tau = u32_to_f32(w[7])
            cyc_s = w[8:14]
            cyc_total = w[14]
            stack_used = w[15]
            if stack_used > stack_peak:
                stack_peak = stack_used

            if win_ran and win_idx < raw["n_win"]:
                tau_list[win_idx] = tau
                win_idx += 1
            if has_est and est_index < raw["n_eval"]:
                est_list[est_index] = est_bpm
            if has_es and es_index < raw["n_eval"]:
                es_list[es_index] = es_bpm

            blocks.append(
                {
                    "b": b,
                    "win_ran": win_ran,
                    "has_est": has_est,
                    "has_es": has_es,
                    "est_index": est_index,
                    "es_index": es_index,
                    "est_bpm": est_bpm if has_est else None,
                    "es_bpm": es_bpm if has_es else None,
                    "tau": tau if win_ran else None,
                    "cyc_s": cyc_s,
                    "cyc_total": cyc_total,
                    "stack_used": stack_used,
                }
            )
    finally:
        if tmp_slab.exists():
            tmp_slab.unlink()

    wall_s = time.monotonic() - t_wall0

    # Compare against host_f32_<tag>.bin if full run
    host_match_est = None
    host_match_es = None
    host_tau_maxdiff = None
    if max_blocks == 0:
        host_bin = (root / "results" / f"host_f32_{tag}.bin").read_bytes()
        n_ev = raw["n_eval"]
        n_wn = raw["n_win"]
        h_est = struct.unpack_from(f"<{n_ev}f", host_bin, 0)
        h_es = struct.unpack_from(f"<{n_ev}f", host_bin, 4 * n_ev)
        h_tau = struct.unpack_from(f"<{n_wn}f", host_bin, 8 * n_ev)
        host_match_est = sum(1 for a, b in zip(est_list, h_est) if a == b)
        host_match_es = sum(1 for a, b in zip(es_list, h_es) if a == b)
        host_tau_maxdiff = max(abs(a - b) for a, b in zip(tau_list, h_tau))

    out = {
        "tag": tag,
        "run_label": run_label,
        "ds_id": ds_id,
        "banded": banded,
        "clk_hz": clk_hz,
        "cfgr": f"0x{cfgr:08x}",
        "n_blocks": n_blocks,
        "wall_s": round(wall_s, 3),
        "algo_ram_bytes": algo_ram_sz,
        "s_sizes": s_sizes,
        "stack_peak_bytes": stack_peak,
        "host_match_est": f"{host_match_est}/{raw['n_eval']}" if host_match_est is not None else None,
        "host_match_es": f"{host_match_es}/{raw['n_eval']}" if host_match_es is not None else None,
        "host_tau_maxdiff": host_tau_maxdiff,
        "est": est_list,
        "es": es_list,
        "tau": tau_list,
        "blocks": blocks,
    }
    return out, seq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", nargs="+", default=["s1:s1_r1:1"])
    ap.add_argument("--max-blocks", type=int, default=0)
    ap.add_argument("--skip-flash", action="store_true")
    ap.add_argument("--speed", type=int, default=1800)
    ap.add_argument("--openocd", default=OPENOCD_DEFAULT)
    ap.add_argument("--nm", default=ARM_NM_DEFAULT)
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    elf = root / "fw" / "fw.elf"
    mb_addr = find_mailbox_addr(elf, args.nm)
    print(f"[driver] mb_addr=0x{mb_addr:08x} elf={elf.name}")

    elf_posix = str(elf).replace("\\", "/")
    ocd_args = [
        args.openocd,
        "-f", "interface/stlink.cfg",
        "-f", "target/stm32f1x.cfg",
        "-c", f"adapter speed {args.speed}",
        "-c", "tcl_port 6666",
        "-c", "gdb_port disabled",
        "-c", "telnet_port disabled",
        "-c", "init",
    ]
    if not args.skip_flash:
        ocd_args += [
            "-c", "reset halt",
            "-c", f"program {elf_posix} verify",
            "-c", "reset run",
        ]

    ocd_log_path = root / "results" / "openocd_stream.log"
    ocd_log_f = open(ocd_log_path, "w", encoding="utf-8")
    proc = subprocess.Popen(
        ocd_args, stdout=ocd_log_f, stderr=subprocess.STDOUT, text=True
    )
    tcl = None
    try:
        # Wait for TCL port 6666
        for _ in range(50):
            try:
                tcl = OpenOcdTcl("127.0.0.1", 6666, timeout=15.0)
                break
            except OSError:
                if proc.poll() is not None:
                    ocd_log_f.close()
                    out_log = ocd_log_path.read_text(encoding="utf-8", errors="replace")
                    raise RuntimeError(f"OpenOCD exited early:\n{out_log}")
                time.sleep(0.1)
        if tcl is None:
            raise RuntimeError("Failed to connect to OpenOCD TCL port 6666")

        # Wait for MCU boot MAGIC_READY
        deadline = time.monotonic() + 5.0
        while True:
            magic = tcl.read_u32(mb_addr, 1)[0]
            if magic in (0xE2E00001, 0xE2E0D00E):
                break
            if time.monotonic() > deadline:
                raise TimeoutError(f"MCU boot magic timeout (0x{magic:08x})")
            time.sleep(0.02)

        seq = tcl.read_u32(mb_addr + 0x10, 1)[0]
        for spec in args.runs:
            tag, label, banded_s = spec.split(":")
            banded = int(banded_s)
            res, seq = run_streaming(
                tag, label, banded, root, tcl, mb_addr, seq, args.max_blocks
            )
            out_json = root / "results" / f"e2e_run_{label}.json"
            out_json.write_text(json.dumps(res, indent=2), encoding="utf-8")
            steady = [b["cyc_total"] for b in res["blocks"] if b["win_ran"]]
            mean_ms = (sum(steady) / len(steady)) * 1e3 / res["clk_hz"]
            print(
                f"[{label}] clk={res['clk_hz']/1e6:.0f}MHz banded={banded} "
                f"wall={res['wall_s']:.1f}s steady_mean={mean_ms:.3f}ms "
                f"stack={res['stack_peak_bytes']}B "
                f"match_est={res['host_match_est']} match_es={res['host_match_es']} "
                f"tau_diff={res['host_tau_maxdiff']}"
            )
        tcl.cmd("shutdown")
    finally:
        if tcl is not None:
            tcl.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        ocd_log_f.close()


if __name__ == "__main__":
    main()

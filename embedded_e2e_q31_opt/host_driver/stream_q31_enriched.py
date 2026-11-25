#!/usr/bin/env python3
"""Enriched real-STM32F103 SWD hardware runner for fw_q31_opt.elf:
- dalia15: PPG-DaLiA S1..S15 522-s prefixes (261 blocks/subj = 3,915 blocks)
- wesad15: WESAD S2..S11,S13..S17 522-s prefixes (261 blocks/subj = 3,915 blocks)
- endurance2: Full unsegmented DaLiA S1 (4,606 blocks) + WESAD S2 (3,039 blocks)

Does NOT modify or recompile fw_q31_opt.elf. Requires env DSPIT_DATA_ROOT.
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

DRIVER_DIR = Path(__file__).resolve().parent
OPT_ROOT = DRIVER_DIR.parent
HOST_TEST_DIR = OPT_ROOT / "host_test"
sys.path.insert(0, str(DRIVER_DIR))
sys.path.insert(0, str(HOST_TEST_DIR))
sys.path.insert(0, str(OPT_ROOT))

from analyze_e2e_opt import STAGE_NAMES, summarize_ms
from eval_full30 import WESAD_IDS, compute_subject_metrics, load_matlab_ref, load_subject_raw
from stream_e2e_opt import ARM_NM_DEFAULT, OPENOCD_DEFAULT, OpenOcdTcl, find_mailbox_addr, u32_to_f32

PREFIX_BLOCKS = 261
FULL30_HOST_EVAL = OPT_ROOT / "results" / "full30_host_eval.json"


def run_host_q31(host_exe: Path, ppg_f32, ax_f32, ay_f32, az_f32, mode: int, banded: int = 1):
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        raw_bin = tdp / "host_in.bin"
        out_bin = tdp / "host_out.bin"
        with raw_bin.open("wb") as f:
            f.write(struct.pack("<II", len(ppg_f32), len(ax_f32)))
            np.asarray(ppg_f32, dtype=np.float32).tofile(f)
            np.asarray(ax_f32, dtype=np.float32).tofile(f)
            np.asarray(ay_f32, dtype=np.float32).tofile(f)
            np.asarray(az_f32, dtype=np.float32).tofile(f)
        subprocess.run([str(host_exe), str(raw_bin), str(out_bin), str(mode), str(banded)], check=True)
        blob = out_bin.read_bytes()
    n_es = struct.unpack_from("<I", blob, 0)[0]
    es_list = list(struct.unpack_from(f"<{n_es}f", blob, 4)) if n_es > 0 else []
    return es_list


def make_chunks(ppg_f32, ax_f32, ay_f32, az_f32, mode: int, add_flush: bool):
    blk_ppg = 250 if mode == 0 else 128
    blk_acc = 250 if mode == 0 else 64
    n_ppg = len(ppg_f32)
    n_acc = len(ax_f32)
    p_off = 0
    a_off = 0
    chunks = []
    while p_off < n_ppg or a_off < n_acc:
        np_val = min(blk_ppg, n_ppg - p_off)
        na_val = min(blk_acc, n_acc - a_off)
        chunks.append((
            ppg_f32[p_off : p_off + np_val],
            ax_f32[a_off : a_off + na_val],
            ay_f32[a_off : a_off + na_val],
            az_f32[a_off : a_off + na_val],
        ))
        p_off += np_val
        a_off += na_val
    if add_flush:
        fp = 50 if mode == 0 else 26
        fa = 50 if mode == 0 else 13
        zp = np.zeros(fp, dtype=np.float32)
        za = np.zeros(fa, dtype=np.float32)
        chunks.append((zp, za, za, za))
    return chunks


def float_eq_or_both_nan(a: float, b: float) -> bool:
    if math.isnan(a) and math.isnan(b):
        return True
    return a == b


def stream_subject(
    tcl: OpenOcdTcl,
    mb_addr: int,
    seq: int,
    host_exe: Path,
    dataset: str,
    rec: dict,
    prefix_only: bool,
):
    mode = int(rec["mode"])
    banded = 1
    blk_ppg = 250 if mode == 0 else 128
    blk_acc = 250 if mode == 0 else 64

    if prefix_only:
        ppg_f32 = rec["ppg_f32"][: PREFIX_BLOCKS * blk_ppg]
        ax_f32 = rec["ax_f32"][: PREFIX_BLOCKS * blk_acc]
        ay_f32 = rec["ay_f32"][: PREFIX_BLOCKS * blk_acc]
        az_f32 = rec["az_f32"][: PREFIX_BLOCKS * blk_acc]
        if len(ppg_f32) < PREFIX_BLOCKS * blk_ppg or len(ax_f32) < PREFIX_BLOCKS * blk_acc:
            raise RuntimeError(f"{dataset} {rec['sid']} shorter than {PREFIX_BLOCKS} blocks")
        chunks = make_chunks(ppg_f32, ax_f32, ay_f32, az_f32, mode, add_flush=False)
    else:
        ppg_f32 = rec["ppg_f32"]
        ax_f32 = rec["ax_f32"]
        ay_f32 = rec["ay_f32"]
        az_f32 = rec["az_f32"]
        chunks = make_chunks(ppg_f32, ax_f32, ay_f32, az_f32, mode, add_flush=True)

    host_es = run_host_q31(host_exe, ppg_f32, ax_f32, ay_f32, az_f32, mode, banded)

    def exec_cmd(cmd_id: int, ds_id: int, bnd: int, np_val: int, na_val: int) -> None:
        nonlocal seq
        seq += 1
        tcl.write_u32(mb_addr + 0x0C, [cmd_id])
        tcl.write_u32(mb_addr + 0x18, [ds_id, bnd, np_val, na_val])
        tcl.write_u32(mb_addr + 0x10, [seq])
        deadline = time.monotonic() + 10.0
        while True:
            done_val = tcl.read_u32(mb_addr + 0x14, 1)[0]
            if done_val == seq:
                return
            if time.monotonic() > deadline:
                magic_now = tcl.read_u32(mb_addr, 1)[0]
                raise TimeoutError(f"MCU timeout seq={seq} cmd={cmd_id} done={done_val} magic=0x{magic_now:08x}")
            time.sleep(0.001)

    hdr = tcl.read_u32(mb_addr, 3)
    clk_hz, cfgr = int(hdr[1]), int(hdr[2])
    sz_words = tcl.read_u32(mb_addr + 0x68, 8)
    algo_ram_sz = int(sz_words[0])
    s_sizes = [int(x) for x in sz_words[1:8]]

    exec_cmd(1, mode, banded, 0, 0)

    tmp_slab = Path(tempfile.gettempdir()) / f"q31_enriched_slab_{os.getpid()}.bin"
    tmp_posix = str(tmp_slab).replace("\\", "/")

    steady_cyc_s = [[] for _ in range(6)]
    steady_cyc_total = []
    cold_cyc_total = []
    flush_cyc_total = []
    seen_steady = False
    es_by_idx = {}
    stack_peak = 0

    t_wall0 = time.monotonic()
    try:
        for b_idx, (p_sl, ax_sl, ay_sl, az_sl) in enumerate(chunks):
            np_val = len(p_sl)
            na_val = len(ax_sl)
            if np_val + 3 * na_val > 1000:
                raise ValueError(f"Slab overflow: np={np_val} na={na_val}")
            slab_bytes = b"".join([
                p_sl.astype("<f4").tobytes(),
                ax_sl.astype("<f4").tobytes(),
                ay_sl.astype("<f4").tobytes(),
                az_sl.astype("<f4").tobytes(),
            ])
            tmp_slab.write_bytes(slab_bytes)
            tcl.cmd(f"load_image {tmp_posix} 0x{mb_addr + 0x88:08x} bin")
            exec_cmd(2, mode, banded, np_val, na_val)

            w = tcl.read_u32(mb_addr + 0x28, 16)
            win_ran, _has_est, has_es = w[0], w[1], w[2]
            _est_idx, es_idx = w[3], w[4]
            es_bpm = u32_to_f32(w[6])
            cyc_s = [int(x) for x in w[8:14]]
            cyc_tot = int(w[14])
            stack_used = int(w[15])
            if stack_used > stack_peak:
                stack_peak = stack_used

            if win_ran:
                seen_steady = True
                for si in range(6):
                    steady_cyc_s[si].append(cyc_s[si])
                steady_cyc_total.append(cyc_tot)
            elif not seen_steady:
                cold_cyc_total.append(cyc_tot)
            else:
                flush_cyc_total.append(cyc_tot)

            if has_es:
                es_by_idx[int(es_idx)] = es_bpm

            if (b_idx + 1) % 500 == 0:
                print(f"    [{dataset}:{rec['sid']}] block {b_idx + 1}/{len(chunks)} ...", flush=True)
    finally:
        if tmp_slab.exists():
            tmp_slab.unlink()

    wall_s = time.monotonic() - t_wall0
    clk_ms = clk_hz / 1000.0

    # Align emitted MCU outputs with host C99 output
    n_mcu_es = (max(es_by_idx.keys()) + 1) if es_by_idx else 0
    mcu_es = [es_by_idx.get(i, float("nan")) for i in range(n_mcu_es)]
    if prefix_only:
        host_ref_slice = host_es[:n_mcu_es]
        match_count = sum(1 for a, b in zip(mcu_es, host_ref_slice) if float_eq_or_both_nan(a, b))
        match_den = n_mcu_es
    else:
        if n_mcu_es != len(host_es):
            raise RuntimeError(
                f"Endurance {dataset} {rec['sid']} output length mismatch: MCU={n_mcu_es} vs Host={len(host_es)}"
            )
        match_count = sum(1 for a, b in zip(mcu_es, host_es) if float_eq_or_both_nan(a, b))
        match_den = len(host_es)

    if match_count != match_den or stack_peak > 1528:
        raise RuntimeError(
            f"GATE FAIL on {dataset} {rec['sid']}: match={match_count}/{match_den}, stack_peak={stack_peak}B"
        )

    total_ms = [c / clk_ms for c in steady_cyc_total]
    tot_summary = summarize_ms(total_ms)
    tot_mean = tot_summary["mean_ms"]
    stages_summary = {}
    for si, sname in enumerate(STAGE_NAMES):
        sms = [c / clk_ms for c in steady_cyc_s[si]]
        st = summarize_ms(sms)
        st["pct_of_total"] = round(100.0 * st["mean_ms"] / tot_mean, 2) if tot_mean > 0 else 0.0
        stages_summary[sname] = st

    cold_ms = [c / clk_ms for c in cold_cyc_total]
    flush_ms = [c / clk_ms for c in flush_cyc_total]

    quartiles = None
    accuracy = None
    if not prefix_only:
        q_n = len(total_ms) // 4
        quartiles = {}
        for qi in range(4):
            i0 = qi * q_n
            i1 = (qi + 1) * q_n if qi < 3 else len(total_ms)
            quartiles[f"Q{qi + 1}"] = summarize_ms(total_ms[i0:i1])
        m_subj = compute_subject_metrics(
            dataset,
            np.asarray(mcu_es, dtype=np.float64),
            rec["gt"],
            rec["act"],
        )
        m_subj.pop("_err", None)
        m_subj.pop("_g", None)
        m_subj.pop("_e", None)
        m_subj.pop("_msk", None)
        accuracy = m_subj

    return {
        "dataset": dataset,
        "subject": rec["sid"],
        "mode": mode,
        "prefix_only": prefix_only,
        "n_blocks_streamed": len(chunks),
        "n_blocks_raw": int(rec["n_blocks"]),
        "n_steady": len(steady_cyc_total),
        "n_cold": len(cold_cyc_total),
        "n_flush": len(flush_cyc_total),
        "clk_hz": clk_hz,
        "cfgr": f"0x{cfgr:08x}",
        "wall_s": round(wall_s, 3),
        "algo_ram_bytes": algo_ram_sz,
        "s_sizes": s_sizes,
        "stack_peak_bytes": stack_peak,
        "host_match_es": f"{match_count}/{match_den}",
        "host_match_ok": True,
        "duty_cycle_2s_pct": round(100.0 * tot_mean / 2000.0, 2),
        "timing_total": tot_summary,
        "timing_stages": stages_summary,
        "timing_cold_start": summarize_ms(cold_ms),
        "timing_flush_tail": summarize_ms(flush_ms) if flush_ms else None,
        "quartiles": quartiles,
        "accuracy_endurance": accuracy,
        "es": mcu_es,
        "steady_cyc_total": steady_cyc_total,
        "steady_cyc_s": steady_cyc_s,
        "cold_cyc_total": cold_cyc_total,
    }, seq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--part", choices=["dalia15", "wesad15", "endurance2"], required=True)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--speed", type=int, default=1800)
    ap.add_argument("--elf", default=str(OPT_ROOT / "fw" / "fw_q31_opt.elf"))
    ap.add_argument("--host-exe", default=str(HOST_TEST_DIR / "run_full30_q31opt.exe"))
    ap.add_argument("--openocd", default=OPENOCD_DEFAULT)
    ap.add_argument("--nm", default=ARM_NM_DEFAULT)
    args = ap.parse_args()

    data_root_str = os.environ.get("DSPIT_DATA_ROOT", "").strip()
    if not data_root_str:
        raise SystemExit("DSPIT_DATA_ROOT environment variable must be set.")
    data_root = Path(data_root_str)
    if not (data_root / "PPG-dalia").exists() or not (data_root / "PPG-WESAD").exists():
        raise SystemExit("DSPIT_DATA_ROOT must contain PPG-dalia and PPG-WESAD.")

    out_dir = OPT_ROOT / "results" / "mcu_q31_enriched"
    out_dir.mkdir(parents=True, exist_ok=True)

    _ref_matlab, dalia_act = load_matlab_ref()

    if args.part == "dalia15":
        jobs = [("dalia", si, f"dalia15_S{si}.json", True) for si in range(1, 16)]
    elif args.part == "wesad15":
        jobs = [("wesad", si, f"wesad15_{WESAD_IDS[si - 1]}.json", True) for si in range(1, 16)]
    else:
        jobs = [
            ("dalia", 1, "endurance_dalia_S1.json", False),
            ("wesad", 1, "endurance_wesad_S2.json", False),
        ]

    pending = [j for j in jobs if args.force or not (out_dir / j[2]).exists()]
    if not pending:
        print(f"[{args.part}] All {len(jobs)} result JSONs already exist (use --force to rerun).")
        return

    elf = Path(args.elf).resolve()
    host_exe = Path(args.host_exe).resolve()
    mb_addr = find_mailbox_addr(elf, args.nm)
    print(f"[{args.part}] Pending {len(pending)}/{len(jobs)} jobs | mb_addr=0x{mb_addr:08x} | elf={elf.name}", flush=True)

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
        "-c", "reset halt",
        "-c", f"program {elf_posix} verify",
        "-c", "reset run",
    ]
    ocd_log = Path(tempfile.gettempdir()) / f"openocd_q31_enriched_{args.part}_{os.getpid()}.log"
    ocd_f = open(ocd_log, "w", encoding="utf-8")
    proc = subprocess.Popen(ocd_args, stdout=ocd_f, stderr=subprocess.STDOUT, text=True)
    tcl = None
    try:
        for _ in range(50):
            try:
                tcl = OpenOcdTcl("127.0.0.1", 6666, timeout=15.0)
                break
            except OSError:
                if proc.poll() is not None:
                    ocd_f.close()
                    raise RuntimeError("OpenOCD exited early:\n" + ocd_log.read_text(encoding="utf-8", errors="replace"))
                time.sleep(0.1)
        if tcl is None:
            raise RuntimeError("Failed to connect OpenOCD TCL 6666")

        deadline = time.monotonic() + 5.0
        while True:
            magic = tcl.read_u32(mb_addr, 1)[0]
            if magic in (0xE2E00001, 0xE2E0D00E):
                break
            if time.monotonic() > deadline:
                raise TimeoutError(f"MCU boot magic timeout (0x{magic:08x})")
            time.sleep(0.02)

        seq = tcl.read_u32(mb_addr + 0x10, 1)[0]
        for idx, (ds, si, out_name, prefix_only) in enumerate(pending, 1):
            rec = load_subject_raw(data_root, ds, si, dalia_act)
            res, seq = stream_subject(tcl, mb_addr, seq, host_exe, ds, rec, prefix_only)
            out_path = out_dir / out_name
            out_path.write_text(json.dumps(res, indent=2), encoding="utf-8")
            tt = res["timing_total"]
            extra = f" mae={res['accuracy_endurance']['mae']:.4f}" if res["accuracy_endurance"] else ""
            print(
                f"[{args.part} {idx}/{len(pending)}] {ds}:{rec['sid']} "
                f"mean={tt['mean_ms']:.3f}ms p95={tt['p95_ms']:.3f}ms max={tt['max_ms']:.3f}ms "
                f"duty={res['duty_cycle_2s_pct']:.2f}% stack={res['stack_peak_bytes']}B "
                f"match={res['host_match_es']} wall={res['wall_s']:.1f}s{extra}",
                flush=True,
            )
        tcl.cmd("shutdown")
    finally:
        if tcl is not None:
            tcl.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        ocd_f.close()
        if ocd_log.exists():
            try:
                ocd_log.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    main()

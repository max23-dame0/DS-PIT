#!/usr/bin/env python3
"""Evaluate exact MCU C99 binaries (E2E-01 f32, E2E-02A f32-opt, E2E-02B q31-opt) across all 30 full-length subjects."""
import json
import os
import struct
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
import scipy.io

HERE = Path(__file__).resolve().parent
OPT_ROOT = HERE.parent
REPO_ROOT = OPT_ROOT.parents[2] if len(OPT_ROOT.parents) > 2 else OPT_ROOT.parent
RESULTS_DIR = OPT_ROOT / "results"
MDEV_RESULTS = REPO_ROOT / "revision" / "audit" / "method_dev" / "results"
E2E02_SUMMARY = RESULTS_DIR / "results_summary_e2e_opt.json"
E2E01_SUMMARY = OPT_ROOT.parent / "embedded_e2e_20261124" / "results" / "results_summary_e2e.json"

VARIANTS = [
    ("e2e01", HERE / "run_full30_e2e01.exe"),
    ("f32opt", HERE / "run_full30_f32opt.exe"),
    ("q31opt", HERE / "run_full30_q31opt.exe"),
]

WESAD_IDS = ["S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "S13", "S14", "S15", "S16", "S17"]


def matlab_prctile(vals: np.ndarray, p: float) -> float:
    s = np.sort(vals)
    n = len(s)
    if n == 0:
        return float("nan")
    ranks = (np.arange(1, n + 1) - 0.5) * (100.0 / n)
    if p <= ranks[0]:
        return float(s[0])
    if p >= ranks[-1]:
        return float(s[-1])
    return float(np.interp(p, ranks, s))


def matlab_mode_smallest(arr: np.ndarray) -> float:
    vals, counts = np.unique(arr, return_counts=True)
    return float(vals[int(np.argmax(counts))])


def load_matlab_ref():
    a2 = scipy.io.loadmat(MDEV_RESULTS / "a2_core.mat", squeeze_me=True, struct_as_record=False)
    act_mat = scipy.io.loadmat(MDEV_RESULTS / "dalia_activity.mat", squeeze_me=True)
    dalia_act = act_mat["A"]
    ref = {}
    for ds in ("dalia", "wesad"):
        rd = getattr(a2["res"], ds)
        ref[ds] = {
            "mean": float(rd.mean),
            "sd": float(rd.sd),
            "med": float(rd.med),
            "p95": float(rd.p95),
            "gt10": float(rd.gt10),
            "cov": float(rd.cov),
            "bias": float(rd.bias),
            "r": float(rd.pooledr),
            "mae": [float(x) for x in rd.mae],
        }
    return ref, dalia_act


def load_subject_raw(data_root: Path, dataset: str, subj_idx_1b: int, dalia_act):
    if dataset == "dalia":
        sid = f"S{subj_idx_1b}"
        d_mat = scipy.io.loadmat(data_root / "PPG-dalia" / "PPG_data" / f"{sid}.mat")
        sig = np.asarray(d_mat["sig"], dtype=np.float64)
        ppg = sig[0, :]
        acc = sig[2:5, :]  # shape (3, n_ppg)
        g_mat = scipy.io.loadmat(data_root / "PPG-dalia" / "BPM_data" / f"{sid}_BPMtrace.mat")
        gt = np.asarray(g_mat["BPM0"], dtype=np.float64).ravel()
        act = np.asarray(dalia_act[subj_idx_1b - 1], dtype=np.float64).ravel()
        if len(act) < len(gt):
            act = np.pad(act, (0, len(gt) - len(act)), constant_values=9.0)
        mode = 0
        n_blocks = len(ppg) // 250
    else:
        sid = WESAD_IDS[subj_idx_1b - 1]
        w_mat = scipy.io.loadmat(data_root / "PPG-WESAD" / f"{sid}.mat")
        ppg = np.asarray(w_mat["BVP"], dtype=np.float64).ravel()
        aa = np.asarray(w_mat["ACC"], dtype=np.float64)
        if aa.shape[0] == 3 and aa.shape[1] != 3:
            aa = aa.T
        acc = aa.T  # shape (3, n_acc) at 32 Hz
        bpm0 = np.asarray(w_mat["BPM0"], dtype=np.float64).ravel()
        act_r = np.asarray(w_mat["Activity"], dtype=np.float64).ravel()
        ws = 8 * 64
        hs = 2 * 64
        n_win = (len(ppg) - ws) // hs + 1
        gt = np.full(n_win, np.nan, dtype=np.float64)
        act = np.full(n_win, np.nan, dtype=np.float64)
        n_lim = min(len(bpm0), len(act_r))
        for k in range(n_win):
            i0 = k * hs
            i1 = i0 + ws
            if i1 <= n_lim:
                gt[k] = float(np.mean(bpm0[i0:i1]))
                act[k] = matlab_mode_smallest(act_r[i0:i1])
        mode = 1
        n_blocks = min(len(ppg) // 128, acc.shape[1] // 64)
    return {
        "sid": sid,
        "mode": mode,
        "n_blocks": int(n_blocks),
        "ppg_f32": np.asarray(ppg, dtype=np.float32),
        "ax_f32": np.asarray(acc[0, :], dtype=np.float32),
        "ay_f32": np.asarray(acc[1, :], dtype=np.float32),
        "az_f32": np.asarray(acc[2, :], dtype=np.float32),
        "gt": gt,
        "act": act,
    }


def run_c_binary(exe_path: Path, raw_bin: Path, out_bin: Path, mode: int, banded: int = 1):
    t0 = time.perf_counter()
    subprocess.run(
        [str(exe_path), str(raw_bin), str(out_bin), str(mode), str(banded)],
        check=True,
    )
    dt = time.perf_counter() - t0
    with out_bin.open("rb") as f:
        n_es = struct.unpack("<I", f.read(4))[0]
        es = np.fromfile(f, dtype=np.float32, count=n_es).astype(np.float64) if n_es > 0 else np.empty(0, dtype=np.float64)
    return es, dt


def compute_subject_metrics(dataset: str, es: np.ndarray, gt: np.ndarray, act: np.ndarray):
    n_ref = min(len(gt), len(act))
    if len(es) < n_ref:
        es_pad = np.pad(es, (0, n_ref - len(es)), constant_values=np.nan)
    else:
        es_pad = es[:n_ref]
    g = gt[:n_ref]
    e = es_pad[:n_ref]
    av = act[:n_ref]
    if dataset == "wesad":
        valid_ref = (~np.isnan(g)) & (av > 0) & (av < 5) & (g > 0)
        msk = (~np.isnan(e)) & valid_ref
        den = int(np.sum((~np.isnan(g)) & (av > 0) & (av < 5)))
    else:
        msk = (~np.isnan(e)) & (~np.isnan(g)) & (g > 0)
        den = int(np.sum(~np.isnan(g)))

    err = g[msk] - e[msk]
    ae = np.abs(err)
    return {
        "n_es": int(len(es)),
        "n2": int(n_ref),
        "n_valid": int(np.sum(msk)),
        "den": den,
        "cov": round(float(np.sum(msk) / max(1, den)), 6),
        "mae": round(float(np.mean(ae)), 4),
        "rmse": round(float(np.sqrt(np.mean(err ** 2))), 4),
        "med": round(float(np.median(ae)), 4),
        "p95": round(matlab_prctile(ae, 95.0), 4),
        "bias": round(float(np.mean(err)), 4),
        "gt10": round(float(np.mean(ae > 10.0)), 4),
        "_err": err,
        "_g": g[msk],
        "_e": e[msk],
        "_msk": msk,
    }


def main():
    data_root_str = os.environ.get("DSPIT_DATA_ROOT", "").strip()
    if not data_root_str:
        raise SystemExit("Environment variable DSPIT_DATA_ROOT must point to the dataset root directory.")
    data_root = Path(data_root_str)
    if not (data_root / "PPG-dalia").exists() or not (data_root / "PPG-WESAD").exists():
        raise SystemExit("DSPIT_DATA_ROOT does not contain PPG-dalia and PPG-WESAD.")

    ref_matlab, dalia_act = load_matlab_ref()
    e2e02_sum = json.loads(E2E02_SUMMARY.read_text(encoding="utf-8"))
    e2e01_sum = json.loads(E2E01_SUMMARY.read_text(encoding="utf-8"))

    per_subject = {"dalia": [], "wesad": []}
    pooled_err = {ds: {v: [] for v, _ in VARIANTS} for ds in ("dalia", "wesad")}
    pooled_g = {ds: {v: [] for v, _ in VARIANTS} for ds in ("dalia", "wesad")}
    pooled_e = {ds: {v: [] for v, _ in VARIANTS} for ds in ("dalia", "wesad")}
    pc_wall = {ds: {v: 0.0 for v, _ in VARIANTS} for ds in ("dalia", "wesad")}
    total_blocks = {"dalia": 0, "wesad": 0}
    total_ppg_samples = {"dalia": 0, "wesad": 0}

    with tempfile.TemporaryDirectory() as tmpd:
        tmp = Path(tmpd)
        for ds in ("dalia", "wesad"):
            print(f"\n=== Evaluating {ds.upper()} (15 subjects) ===")
            for si in range(1, 16):
                rec = load_subject_raw(data_root, ds, si, dalia_act)
                total_blocks[ds] += rec["n_blocks"]
                total_ppg_samples[ds] += len(rec["ppg_f32"])

                raw_bin = tmp / f"{ds}_{rec['sid']}_raw.bin"
                with raw_bin.open("wb") as f:
                    f.write(struct.pack("<II", len(rec["ppg_f32"]), len(rec["ax_f32"])))
                    rec["ppg_f32"].tofile(f)
                    rec["ax_f32"].tofile(f)
                    rec["ay_f32"].tofile(f)
                    rec["az_f32"].tofile(f)

                var_es = {}
                var_met = {}
                for vname, exe in VARIANTS:
                    out_bin = tmp / f"{ds}_{rec['sid']}_{vname}.bin"
                    es, dt = run_c_binary(exe, raw_bin, out_bin, rec["mode"], 1)
                    pc_wall[ds][vname] += dt
                    m = compute_subject_metrics(ds, es, rec["gt"], rec["act"])
                    pooled_err[ds][vname].append(m.pop("_err"))
                    pooled_g[ds][vname].append(m.pop("_g"))
                    pooled_e[ds][vname].append(m.pop("_e"))
                    var_es[vname] = es
                    var_met[vname] = m

                # Exact window agreement on shared valid mask vs e2e01
                m_e01 = var_met["e2e01"].pop("_msk")
                m_f32 = var_met["f32opt"].pop("_msk")
                m_q31 = var_met["q31opt"].pop("_msk")
                shared_len = min(len(var_es["e2e01"]), len(var_es["f32opt"]), len(var_es["q31opt"]), len(m_e01))
                sh_msk = m_e01[:shared_len] & m_f32[:shared_len] & m_q31[:shared_len]
                n_sh = int(np.sum(sh_msk))
                eq_f32 = int(np.sum(var_es["f32opt"][:shared_len][sh_msk] == var_es["e2e01"][:shared_len][sh_msk]))
                eq_q31 = int(np.sum(var_es["q31opt"][:shared_len][sh_msk] == var_es["e2e01"][:shared_len][sh_msk]))

                mat_mae = ref_matlab[ds]["mae"][si - 1]
                for vname, _ in VARIANTS:
                    var_met[vname]["diff_vs_matlab_mae"] = round(var_met[vname]["mae"] - mat_mae, 4)

                row = {
                    "subject": rec["sid"],
                    "n_blocks": rec["n_blocks"],
                    "n_gt": int(len(rec["gt"])),
                    "matlab_a2_mae": round(mat_mae, 4),
                    "f32opt_vs_e2e01_agree": f"{eq_f32}/{n_sh}",
                    "f32opt_vs_e2e01_pct": round(100.0 * eq_f32 / max(1, n_sh), 2),
                    "q31opt_vs_e2e01_agree": f"{eq_q31}/{n_sh}",
                    "q31opt_vs_e2e01_pct": round(100.0 * eq_q31 / max(1, n_sh), 2),
                    "variants": var_met,
                }
                per_subject[ds].append(row)
                print(
                    f"  [{ds} {rec['sid']:>3}] blk={rec['n_blocks']:4d} cov={var_met['e2e01']['cov']:.4f} | "
                    f"MAT={mat_mae:6.4f} | E2E01={var_met['e2e01']['mae']:6.4f} ({var_met['e2e01']['diff_vs_matlab_mae']:+.4f}) | "
                    f"F32OPT={var_met['f32opt']['mae']:6.4f} | "
                    f"Q31={var_met['q31opt']['mae']:6.4f} ({var_met['q31opt']['diff_vs_matlab_mae']:+.4f}) | "
                    f"agree(q31/e01)={row['q31opt_vs_e2e01_pct']:6.2f}%"
                )

    summary = {}
    for ds in ("dalia", "wesad"):
        summary[ds] = {"matlab_a2_f64": ref_matlab[ds], "variants": {}}
        for vname, _ in VARIANTS:
            maes = np.array([r["variants"][vname]["mae"] for r in per_subject[ds]], dtype=np.float64)
            covs = [r["variants"][vname]["cov"] for r in per_subject[ds]]
            tot_val = sum(r["variants"][vname]["n_valid"] for r in per_subject[ds])
            tot_den = sum(r["variants"][vname]["den"] for r in per_subject[ds])
            err_all = np.concatenate(pooled_err[ds][vname])
            ae_all = np.abs(err_all)
            g_all = np.concatenate(pooled_g[ds][vname])
            e_all = np.concatenate(pooled_e[ds][vname])
            r_pool = float(np.corrcoef(e_all, g_all)[0, 1])

            summary[ds]["variants"][vname] = {
                "subject_macro_mae_bpm": round(float(np.mean(maes)), 4),
                "subject_macro_sd_bpm": round(float(np.std(maes, ddof=1)), 4),
                "macro_diff_vs_matlab_bpm": round(float(np.mean(maes) - ref_matlab[ds]["mean"]), 4),
                "max_subject_abs_diff_vs_matlab_bpm": round(float(max(abs(r["variants"][vname]["diff_vs_matlab_mae"]) for r in per_subject[ds])), 4),
                "subject_macro_med_bpm": round(float(np.mean([r["variants"][vname]["med"] for r in per_subject[ds]])), 4),
                "subject_macro_p95_bpm": round(float(np.mean([r["variants"][vname]["p95"] for r in per_subject[ds]])), 4),
                "subject_macro_gt10_pct": round(100.0 * float(np.mean([r["variants"][vname]["gt10"] for r in per_subject[ds]])), 2),
                "pooled_med_bpm": round(float(np.median(ae_all)), 4),
                "pooled_p95_bpm": round(matlab_prctile(ae_all, 95.0), 4),
                "pooled_gt10_pct": round(100.0 * float(np.mean(ae_all > 10.0)), 2),
                "pooled_bias_bpm": round(float(np.mean(err_all)), 4),
                "pooled_r": round(r_pool, 4),
                "total_valid_windows": int(tot_val),
                "total_ref_valid_windows": int(tot_den),
                "pooled_cov": round(tot_val / max(1, tot_den), 6),
                "pc_host_time_s": round(pc_wall[ds][vname], 3),
                "f32opt_agree_vs_e2e01_pct": round(float(np.mean([r["f32opt_vs_e2e01_pct"] for r in per_subject[ds]])), 2) if vname == "f32opt" else None,
                "q31opt_agree_vs_e2e01_pct": round(float(np.mean([r["q31opt_vs_e2e01_pct"] for r in per_subject[ds]])), 2) if vname == "q31opt" else None,
            }

    # Exact STM32F103 @ 72 MHz compute & SWD replay time projections across 108,172 blocks (60.10 h)
    # Pure compute: 15*4=60 cold blocks (S1 only) + (n_blocks - 60) steady blocks per dataset
    rates = {
        "e2e01": {
            "dalia_steady_ms": e2e01_sum["timing_dalia_3rec"]["total"]["mean_ms"],
            "wesad_steady_ms": e2e01_sum["timing_wesad_2rec"]["total"]["mean_ms"],
            # Approximate cold start using measured per-dataset S1 mean (only 60 blocks out of 64k/43k, <1s effect)
            "dalia_cold_ms": e2e01_sum["timing_dalia_3rec"]["S1_frontend"]["mean_ms"],
            "wesad_cold_ms": e2e01_sum["timing_wesad_2rec"]["S1_frontend"]["mean_ms"],
            "swd_dalia_s_per_261blk": None,
            "swd_wesad_s_per_261blk": None,
        },
        "f32opt": {
            "dalia_steady_ms": e2e02_sum["variants"]["f32_opt"]["timing_dalia_3rec"]["total"]["mean_ms"],
            "wesad_steady_ms": e2e02_sum["variants"]["f32_opt"]["timing_wesad_2rec"]["total"]["mean_ms"],
            "dalia_cold_ms": e2e02_sum["variants"]["f32_opt"]["timing_dalia_3rec"]["S1_frontend"]["mean_ms"],
            "wesad_cold_ms": e2e02_sum["variants"]["f32_opt"]["timing_wesad_2rec"]["S1_frontend"]["mean_ms"],
            "swd_dalia_s_per_261blk": sum(r["wall_s"] for r in e2e02_sum["variants"]["f32_opt"]["per_record"] if r["dataset_group"] == "PPG-DaLiA") / 3.0,
            "swd_wesad_s_per_261blk": sum(r["wall_s"] for r in e2e02_sum["variants"]["f32_opt"]["per_record"] if r["dataset_group"] == "WESAD") / 2.0,
        },
        "q31opt": {
            "dalia_steady_ms": e2e02_sum["variants"]["q31_opt"]["timing_dalia_3rec"]["total"]["mean_ms"],
            "wesad_steady_ms": e2e02_sum["variants"]["q31_opt"]["timing_wesad_2rec"]["total"]["mean_ms"],
            "dalia_cold_ms": e2e02_sum["variants"]["q31_opt"]["timing_dalia_3rec"]["S1_frontend"]["mean_ms"],
            "wesad_cold_ms": e2e02_sum["variants"]["q31_opt"]["timing_wesad_2rec"]["S1_frontend"]["mean_ms"],
            "swd_dalia_s_per_261blk": sum(r["wall_s"] for r in e2e02_sum["variants"]["q31_opt"]["per_record"] if r["dataset_group"] == "PPG-DaLiA") / 3.0,
            "swd_wesad_s_per_261blk": sum(r["wall_s"] for r in e2e02_sum["variants"]["q31_opt"]["per_record"] if r["dataset_group"] == "WESAD") / 2.0,
        },
    }

    # Check actual E2E-01 wall_s from e2e_run_*.json for accurate SWD projection
    e2e01_res = OPT_ROOT.parent / "embedded_e2e_20261124" / "results"
    d_w, w_w = [], []
    for tag, grp in (("s1_r1", "d"), ("s2", "d"), ("s3", "d"), ("ws1", "w"), ("ws2", "w")):
        p = e2e01_res / f"e2e_run_{tag}.json"
        if p.exists():
            ws_val = json.loads(p.read_text(encoding="utf-8")).get("wall_s")
            if ws_val is not None:
                (d_w if grp == "d" else w_w).append(ws_val)
    if d_w and w_w:
        rates["e2e01"]["swd_dalia_s_per_261blk"] = sum(d_w) / len(d_w)
        rates["e2e01"]["swd_wesad_s_per_261blk"] = sum(w_w) / len(w_w)

    mcu_proj = {}
    d_blk = total_blocks["dalia"]
    w_blk = total_blocks["wesad"]
    for vname, rt in rates.items():
        comp_d_s = ((d_blk - 60) * rt["dalia_steady_ms"] + 60 * rt["dalia_cold_ms"]) / 1000.0
        comp_w_s = ((w_blk - 60) * rt["wesad_steady_ms"] + 60 * rt["wesad_cold_ms"]) / 1000.0
        comp_tot_s = comp_d_s + comp_w_s
        swd_d_s = (rt["swd_dalia_s_per_261blk"] * d_blk / 261.0) if rt["swd_dalia_s_per_261blk"] else None
        swd_w_s = (rt["swd_wesad_s_per_261blk"] * w_blk / 261.0) if rt["swd_wesad_s_per_261blk"] else None
        swd_tot_s = (swd_d_s + swd_w_s) if (swd_d_s is not None and swd_w_s is not None) else None
        pc_tot_s = pc_wall["dalia"][vname] + pc_wall["wesad"][vname]
        mcu_proj[vname] = {
            "mcu_pure_compute_s": round(comp_tot_s, 1),
            "mcu_pure_compute_min": round(comp_tot_s / 60.0, 2),
            "mcu_pure_compute_hr": round(comp_tot_s / 3600.0, 2),
            "mcu_swd_replay_wall_s": round(swd_tot_s, 1) if swd_tot_s else None,
            "mcu_swd_replay_wall_hr": round(swd_tot_s / 3600.0, 2) if swd_tot_s else None,
            "pc_host_wall_s": round(pc_tot_s, 3),
        }

    out = {
        "scope": "Full 30-subject evaluation (15 PPG-DaLiA + 15 WESAD, exact full lengths) running identical C99 MCU source implementations compiled for PC host (-O3 -std=c99) vs MATLAB float64 a2_cfg reference.",
        "dataset_totals": {
            "dalia_subjects": 15,
            "dalia_blocks_2s": total_blocks["dalia"],
            "dalia_signal_hours": round(total_blocks["dalia"] * 2.0 / 3600.0, 2),
            "wesad_subjects": 15,
            "wesad_blocks_2s": total_blocks["wesad"],
            "wesad_signal_hours": round(total_blocks["wesad"] * 2.0 / 3600.0, 2),
            "combined_blocks_2s": total_blocks["dalia"] + total_blocks["wesad"],
            "combined_signal_hours": round((total_blocks["dalia"] + total_blocks["wesad"]) * 2.0 / 3600.0, 2),
        },
        "runtime_comparison_full30": mcu_proj,
        "summary": summary,
        "per_subject": per_subject,
    }

    out_path = RESULTS_DIR / "full30_host_eval.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")

    print("\n=== FULL 30-SUBJECT SUMMARY ===")
    for ds in ("dalia", "wesad"):
        mr = summary[ds]["matlab_a2_f64"]
        print(f"[{ds.upper()}] MATLAB f64: MAE={mr['mean']:.4f} +/- {mr['sd']:.4f} | Med={mr['med']:.4f} P95={mr['p95']:.4f} >10%={mr['gt10']*100:.2f}% cov={mr['cov']:.4f}")
        for vname, _ in VARIANTS:
            vs = summary[ds]["variants"][vname]
            print(
                f"  {vname:6s}: MAE={vs['subject_macro_mae_bpm']:.4f} +/- {vs['subject_macro_sd_bpm']:.4f} "
                f"(diff={vs['macro_diff_vs_matlab_bpm']:+.4f}) | Med={vs['pooled_med_bpm']:.4f} "
                f"P95={vs['pooled_p95_bpm']:.4f} >10%={vs['pooled_gt10_pct']:.2f}% "
                f"cov={vs['pooled_cov']:.4f} | PC={vs['pc_host_time_s']:.2f}s"
            )
    print("\n=== RUNTIME ESTIMATE (ALL 30 SUBJECTS = 108,172 BLOCKS / 60.10 H SIGNAL) ===")
    for vname, rt in mcu_proj.items():
        print(
            f"  {vname:6s}: MCU compute = {rt['mcu_pure_compute_min']:.2f} min ({rt['mcu_pure_compute_hr']:.2f} h) | "
            f"MCU+SWD wall = {rt['mcu_swd_replay_wall_hr']} h | PC host = {rt['pc_host_wall_s']:.2f} s"
        )
    print(f"\nWrote {out_path}")


if __name__ == "__main__":
    main()

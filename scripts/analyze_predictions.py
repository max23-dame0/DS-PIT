#!/usr/bin/env python3
"""Protocol-compliant post-processing for window-level predictions.

The program deliberately operates only on supplied CSV files.  It never fills
missing predictions, clips references, or selects a best configuration.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


WINDOW_KEY = ("dataset", "subject_id", "recording_id", "window_id")
GROUP_KEY = ("dataset", "split", "method", "variant", "config_id")
EXPECTED_REQUIRED = WINDOW_KEY + ("window_start_s", "window_end_s", "target_time_s", "reference_bpm", "split", "activity")
PRED_REQUIRED = WINDOW_KEY + ("window_start_s", "window_end_s", "target_time_s", "available_time_s",
                              "reference_bpm", "estimate_bpm", "method", "variant", "split", "activity", "status", "config_id")
ALLOWED_STATUS = {"", "success", "failed", "error", "timeout", "missing", "excluded", "no_reference"}
MISSING = ""


class InputError(ValueError):
    """Raised for a protocol/input violation."""


def _text(value) -> str:
    return "" if value is None else str(value).strip()


def _num(value, field: str, row_no: int, allow_blank: bool = True) -> Optional[float]:
    value = _text(value)
    if not value:
        if allow_blank:
            return None
        raise InputError(f"row {row_no}: {field} is required")
    try:
        result = float(value)
    except ValueError as exc:
        raise InputError(f"row {row_no}: {field} must be numeric, got {value!r}") from exc
    if not math.isfinite(result):
        raise InputError(f"row {row_no}: {field} must be finite")
    return result


def _read_csv(path: Path, required: Sequence[str]) -> List[dict]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as exc:
        raise InputError(f"cannot open {path}: {exc}") from exc
    with handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise InputError(f"{path}: missing CSV header")
        missing = [name for name in required if name not in reader.fieldnames]
        if missing:
            raise InputError(f"{path}: missing required columns: {', '.join(missing)}")
        rows = []
        for no, raw in enumerate(reader, 2):
            row = {key: _text(value) for key, value in raw.items() if key is not None}
            row["_row_no"] = no
            rows.append(row)
    if not rows:
        raise InputError(f"{path}: zero rows; refusing to produce experimental results")
    return rows


def _window_key(row: dict) -> Tuple[str, str, str, str]:
    return tuple(row[name] for name in WINDOW_KEY)


def _group_key(row: dict) -> Tuple[str, str, str, str, str]:
    return tuple(row[name] for name in GROUP_KEY)


def _validate_expected(rows: List[dict]) -> Tuple[Dict[tuple, dict], Dict[Tuple[str, str], List[dict]]]:
    by_key = {}
    by_ds_split = defaultdict(list)
    subject_splits = {}
    for row in rows:
        no = row["_row_no"]
        key = _window_key(row)
        if any(not part for part in key) or not row["split"]:
            raise InputError(f"expected row {no}: dataset/subject/recording/window_id/split cannot be blank")
        if key in by_key:
            raise InputError(f"expected row {no}: duplicate window key {key}")
        start = _num(row["window_start_s"], "window_start_s", no, False)
        end = _num(row["window_end_s"], "window_end_s", no, False)
        target = _num(row["target_time_s"], "target_time_s", no, False)
        if end < start or target < start or target > end:
            raise InputError(f"expected row {no}: invalid window/target time ordering")
        reference = _num(row["reference_bpm"], "reference_bpm", no, True)
        if reference is not None and reference < 0:
            raise InputError(f"expected row {no}: reference_bpm cannot be negative")
        ds_subject = (row["dataset"], row["subject_id"])
        old_split = subject_splits.setdefault(ds_subject, row["split"])
        if old_split != row["split"]:
            raise InputError(f"expected row {no}: subject {ds_subject} occurs in multiple splits ({old_split}, {row['split']})")
        row = dict(row)
        row.update({"window_start_s_n": start, "window_end_s_n": end, "target_time_s_n": target,
                    "reference_bpm_n": reference})
        by_key[key] = row
        by_ds_split[(row["dataset"], row["split"])].append(row)
    return by_key, by_ds_split


def _validate_predictions(rows: List[dict], expected: Dict[tuple, dict]) -> Dict[Tuple[str, str, str, str, str], Dict[tuple, dict]]:
    groups = defaultdict(dict)
    for row in rows:
        no = row["_row_no"]
        key = _window_key(row)
        if any(not part for part in key) or not row["split"] or not row["method"] or not row["variant"] or not row["config_id"]:
            raise InputError(f"prediction row {no}: identity, split, method, variant, and config_id cannot be blank")
        if key not in expected:
            raise InputError(f"prediction row {no}: window key does not occur in expected_windows.csv: {key}")
        exp = expected[key]
        for field in ("dataset", "subject_id", "recording_id", "window_id", "split", "activity", "window_start_s", "window_end_s", "target_time_s", "reference_bpm"):
            if field == "reference_bpm":
                got = _num(row[field], field, no, True)
                want = exp["reference_bpm_n"]
                if (got is None) != (want is None) or (got is not None and not math.isclose(got, want, rel_tol=0, abs_tol=1e-9)):
                    raise InputError(f"prediction row {no}: reference mismatch for {key}")
            elif field in ("window_start_s", "window_end_s", "target_time_s"):
                got = _num(row[field], field, no, False)
                if not math.isclose(got, exp[field + "_n"], rel_tol=0, abs_tol=1e-9):
                    raise InputError(f"prediction row {no}: {field} mismatch for {key}")
            elif row[field] != exp[field]:
                raise InputError(f"prediction row {no}: {field} mismatch for {key}")
        available = _num(row["available_time_s"], "available_time_s", no, True)
        if available is not None and available < exp["target_time_s_n"]:
            raise InputError(f"prediction row {no}: available_time_s precedes target_time_s")
        status = row["status"].lower()
        if status not in ALLOWED_STATUS:
            raise InputError(f"prediction row {no}: unsupported status {status!r}")
        estimate = _num(row["estimate_bpm"], "estimate_bpm", no, True)
        if estimate is not None and estimate < 0:
            raise InputError(f"prediction row {no}: estimate_bpm cannot be negative")
        if not status:
            status = "success" if estimate is not None else "failed"
        if status == "no_reference" and exp["reference_bpm_n"] is not None:
            raise InputError(f"prediction row {no}: no_reference status requires a blank expected reference")
        if status == "success" and exp["reference_bpm_n"] is None:
            raise InputError(f"prediction row {no}: success status requires a valid expected reference")
        if status == "success" and estimate is None:
            raise InputError(f"prediction row {no}: success requires estimate_bpm")
        if status == "success" and (available is None or available < exp["window_end_s_n"]):
            raise InputError(f"prediction row {no}: success requires available_time_s >= window_end_s")
        group = _group_key(row)
        if key in groups[group]:
            raise InputError(f"prediction row {no}: duplicate prediction key {group + key}")
        clean = dict(row)
        clean.update({"available_time_s_n": available, "estimate_bpm_n": estimate, "status_n": status})
        groups[group][key] = clean
    return groups


def _percentile(values: Sequence[float], q: float) -> Optional[float]:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    pos = (len(values) - 1) * q
    lo, hi = int(math.floor(pos)), int(math.ceil(pos))
    if lo == hi:
        return values[lo]
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def _fmt(value):
    return "" if value is None or (isinstance(value, float) and not math.isfinite(value)) else value


def _bootstrap_mean(values: Sequence[float], iterations: int, seed: int) -> Tuple[Optional[float], Optional[float]]:
    if len(values) < 2:
        return None, None
    rng = random.Random(seed)
    n = len(values)
    samples = [sum(values[rng.randrange(n)] for _ in range(n)) / n for _ in range(iterations)]
    return _percentile(samples, 0.025), _percentile(samples, 0.975)


def _stats(errors: Sequence[float], signed: Sequence[float]) -> dict:
    if not errors:
        return {"n_valid": 0, "mae": None, "rmse": None, "median_ae": None, "p95_ae": None,
                "bias": None, "error_gt5": None, "error_gt10": None}
    return {"n_valid": len(errors), "mae": sum(errors) / len(errors),
            "rmse": math.sqrt(sum(x * x for x in signed) / len(signed)),
            "median_ae": _percentile(errors, 0.5), "p95_ae": _percentile(errors, 0.95),
                "bias": sum(signed) / len(signed), "error_gt5": sum(x > 5 for x in errors) / len(errors),
                "error_gt10": sum(x > 10 for x in errors) / len(errors)}


def _sample_sd(values: Sequence[float]) -> Optional[float]:
    """Sample SD (ddof=1); one or zero observations have no estimable SD."""
    if len(values) < 2:
        return None
    mean = sum(values) / len(values)
    return math.sqrt(sum((value - mean) ** 2 for value in values) / (len(values) - 1))


def _failure_episodes(group, expected_rows, predmap, hop: float) -> List[dict]:
    """Find contiguous reference-valid, non-success windows within recordings."""
    ds, split, method, variant, config_id = group
    by_recording = defaultdict(list)
    for exp in expected_rows:
        by_recording[(exp["subject_id"], exp["recording_id"])].append(exp)
    output = []
    tolerance = max(1e-9, abs(hop) * 1e-6)
    for (subject, recording), rows in sorted(by_recording.items()):
        rows.sort(key=lambda row: (row["window_end_s_n"], row["window_start_s_n"], row["window_id"]))
        current = []

        def flush():
            if not current:
                return
            output.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                           "subject_id": subject, "recording_id": recording,
                           "episode_id": f"{subject}__{recording}__F{len(output)+1:03d}",
                           "n_failed_windows": len(current),
                           "first_window_end_s": current[0]["window_end_s_n"],
                           "last_window_end_s": current[-1]["window_end_s_n"],
                           "decision_grid_duration_s": len(current) * hop})
            current.clear()

        previous = None
        previous_failed = False
        previous_reference_valid = False
        for exp in rows:
            reference_valid = exp["reference_bpm_n"] is not None
            pred = predmap.get(_window_key(exp))
            failed = reference_valid and not (pred is not None and pred["status_n"] == "success")
            contiguous = (previous is not None and previous_failed and previous_reference_valid and failed and
                           math.isclose(exp["window_end_s_n"] - previous["window_end_s_n"], hop,
                                         rel_tol=1e-6, abs_tol=tolerance))
            if failed:
                if not contiguous:
                    flush()
                current.append(exp)
            else:
                flush()
            previous = exp
            previous_failed = failed
            previous_reference_valid = reference_valid
        flush()
    return output


def _write_csv(path: Path, rows: List[dict], fieldnames: Sequence[str]):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: _fmt(row.get(field)) for field in fieldnames})


def _safe_name(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", text).strip("_") or "group"


def _parse_states(value: Optional[str]) -> Optional[List[float]]:
    if not value:
        return None
    path = Path(value)
    if path.exists():
        raw = []
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.split("#", 1)[0]
            raw.extend(line.replace(",", " ").split())
    else:
        raw = value.replace(",", " ").split()
    states = sorted(set(float(x) for x in raw))
    if not states or not all(math.isfinite(x) for x in states):
        raise InputError("state list must contain at least one finite numeric state")
    return states


def _signflip(values: Sequence[float], iterations: int, seed: int) -> Tuple[Optional[float], str]:
    n = len(values)
    if not n:
        return None, "none"
    observed = abs(sum(values) / n)
    if observed == 0:
        return 1.0, "exact" if n <= 15 else "monte_carlo"
    if n <= 15:
        count = 0
        total = 1 << n
        for mask in range(total):
            mean = sum(v if mask & (1 << i) else -v for i, v in enumerate(values)) / n
            if abs(mean) >= observed - 1e-15:
                count += 1
        return count / total, "exact"
    rng = random.Random(seed)
    count = 0
    for _ in range(iterations):
        mean = sum(v if rng.getrandbits(1) else -v for v in values) / n
        if abs(mean) >= observed - 1e-15:
            count += 1
    return (count + 1) / (iterations + 1), "monte_carlo"


def _holm(pvalues: List[Optional[float]]) -> List[Optional[float]]:
    indexed = [(i, p) for i, p in enumerate(pvalues) if p is not None]
    result = [None] * len(pvalues)
    prev = 0.0
    m = len(indexed)
    for rank, (idx, p) in enumerate(sorted(indexed, key=lambda x: x[1])):
        adjusted = min(1.0, (m - rank) * p)
        adjusted = max(adjusted, prev)
        result[idx] = adjusted
        prev = adjusted
    return result


def _make_plots(out: Path, group: Tuple[str, str, str, str, str], subject_rows: List[dict], window_rows: List[dict], force_svg: bool = False):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        plt = None
    tag = "__".join(_safe_name(x) for x in group) + "__" + hashlib.sha256("|".join(group).encode("utf-8")).hexdigest()[:10]
    subjects = [r for r in subject_rows if r["mae"] is not None]
    errors = [float(r["abs_error"]) for r in window_rows if r["abs_error"] not in (None, "")]
    if not subjects or not errors:
        return False
    if force_svg:
        plt = None
    if plt is None:
        # Dependency-free static fallback, suitable for audit previews.
        def esc(value):
            return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        bar_w = max(10.0, 520.0 / len(subjects)); max_y = max([r["mae"] for r in subjects] + [1.0])
        def sy(value):
            return 320 - 280 * value / max_y
        bars = []
        for i, row in enumerate(subjects):
            x = 60 + i * bar_w; bh = 280 * row["mae"] / max_y
            bars.append(f'<rect x="{x:.1f}" y="{sy(row["mae"]):.1f}" width="{bar_w*.8:.1f}" height="{bh:.1f}" fill="#4472c4"/><text x="{x+bar_w*.32:.1f}" y="{sy(row["mae"])-5:.1f}" text-anchor="middle" font-size="10">{row["mae"]:.3g}</text><text x="{x:.1f}" y="345" font-size="10" transform="rotate(35 {x:.1f},345)">{esc(row["subject_id"])}</text>')
        ticks = []
        for value in (0.0, max_y / 2, max_y):
            y = sy(value); ticks.append(f'<line x1="50" y1="{y:.1f}" x2="610" y2="{y:.1f}" stroke="#dddddd"/><text x="44" y="{y+4:.1f}" text-anchor="end" font-size="10">{value:.3g}</text>')
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="400"><text x="220" y="25" font-size="18">Subject MAE (BPM)</text>{"".join(ticks)}<line x1="50" y1="40" x2="50" y2="320" stroke="black"/><line x1="50" y1="320" x2="610" y2="320" stroke="black"/>{"".join(bars)}<text x="250" y="395" font-size="12">subject (sorted)</text><text x="12" y="190" font-size="12" transform="rotate(-90 12,190)">MAE (BPM)</text></svg>'
        (out / f"subject_mae__{tag}.svg").write_text(svg, encoding="utf-8")
        max_x = max(errors + [1.0]); x0, x1, y0, y1 = 50, 590, 320, 40
        counts = defaultdict(int)
        for value in errors:
            counts[value] += 1
        path_points = [f"M{x0},{y0}"]
        cumulative = 0
        for value in sorted(counts):
            x = x0 + (x1 - x0) * value / max_x
            path_points.append(f"L{x:.1f},{y0 - (y0-y1)*cumulative/len(errors):.1f}")
            cumulative += counts[value]
            path_points.append(f"L{x:.1f},{y0 - (y0-y1)*cumulative/len(errors):.1f}")
        path_points.append(f"L{x1},{y0 - (y0-y1):.1f}")
        ticks = []
        for value in (0.0, 0.5, 1.0):
            y = y0 - (y0-y1)*value; ticks.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#dddddd"/><text x="44" y="{y+4:.1f}" text-anchor="end" font-size="10">{value:.1f}</text>')
        x_ticks = f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y0+5}" stroke="black"/><text x="{x0}" y="340" text-anchor="middle" font-size="10">0</text><line x1="{x1}" y1="{y0}" x2="{x1}" y2="{y0+5}" stroke="black"/><text x="{x1}" y="340" text-anchor="middle" font-size="10">{max_x:.3g}</text>'
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="400"><text x="220" y="25" font-size="18">Window error ECDF</text>{"".join(ticks)}{x_ticks}<line x1="{x0}" y1="{y1}" x2="{x0}" y2="{y0}" stroke="black"/><line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y0}" stroke="black"/><path d="{" ".join(path_points)}" fill="none" stroke="#c00000"/><text x="250" y="395" font-size="12">absolute error (BPM)</text><text x="12" y="190" font-size="12" transform="rotate(-90 12,190)">ECDF</text></svg>'
        (out / f"error_ecdf__{tag}.svg").write_text(svg, encoding="utf-8")
        return [f"subject_mae__{tag}.svg", f"error_ecdf__{tag}.svg"]
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.bar(range(len(subjects)), [r["mae"] for r in subjects])
    ax.set(xlabel="subject (sorted by id)", ylabel="MAE (BPM)", title="Subject MAE")
    ax.set_xticks(range(len(subjects)), [r["subject_id"] for r in subjects], rotation=45, ha="right")
    fig.tight_layout(); fig.savefig(out / f"subject_mae__{tag}.png", dpi=150); plt.close(fig)
    fig, ax = plt.subplots(figsize=(6, 4))
    xs = sorted(errors); ys = [(i + 1) / len(xs) for i in range(len(xs))]
    ax.step(xs, ys, where="post"); ax.set(xlabel="absolute error (BPM)", ylabel="ECDF", title="Window error ECDF")
    fig.tight_layout(); fig.savefig(out / f"error_ecdf__{tag}.png", dpi=150); plt.close(fig)
    return [f"subject_mae__{tag}.png", f"error_ecdf__{tag}.png"]


def analyze(predictions_path: Path, expected_path: Path, out_dir: Path, *, baseline_method: Optional[str] = None,
            baseline_variant: Optional[str] = None, baseline_config_id: Optional[str] = None, bootstrap: int = 10000,
            permutations: int = 10000, seed: int = 20260911, states: Optional[List[float]] = None,
            make_figures: bool = True, protocol_id: Optional[str] = None,
            expected_hop_s: Optional[float] = None) -> dict:
    if bootstrap < 1 or permutations < 1:
        raise InputError("bootstrap/permutations must be positive")
    if baseline_method and not protocol_id:
        raise InputError("--protocol-id is required when paired baseline comparisons are requested; it asserts one shared protocol")
    if expected_hop_s is not None and (not math.isfinite(expected_hop_s) or expected_hop_s <= 0):
        raise InputError("expected-hop-s must be a positive finite number")
    if out_dir.exists() and any(out_dir.iterdir()):
        raise InputError(f"output directory is non-empty; refusing to mix old results: {out_dir}")
    out_dir.mkdir(parents=True, exist_ok=True)
    expected_rows = _read_csv(expected_path, EXPECTED_REQUIRED)
    expected, expected_by_ds = _validate_expected(expected_rows)
    prediction_rows = _read_csv(predictions_path, PRED_REQUIRED)
    groups = _validate_predictions(prediction_rows, expected)
    joined_rows = []
    subject_rows = []
    aggregate_rows = []
    strata_rows = []
    lower_rows = []
    failure_episode_rows = []
    valid_sets = {}
    group_subject_values = {}
    plot_files = []
    for group in sorted(groups):
        ds, split, method, variant, config_id = group
        predmap = groups[group]
        exp_rows = expected_by_ds[(ds, split)]
        if expected_hop_s is not None:
            failure_episode_rows.extend(_failure_episodes(group, exp_rows, predmap, expected_hop_s))
        rows_by_subject = defaultdict(list)
        valid_window_keys = set()
        all_errors, all_signed = [], []
        for exp in exp_rows:
            key = _window_key(exp)
            pred = predmap.get(key)
            ref = exp["reference_bpm_n"]
            status = "no_reference" if ref is None else ("missing_prediction" if pred is None else pred["status_n"])
            estimate = None if pred is None else pred["estimate_bpm_n"]
            abs_error = signed_error = None
            if status == "success" and ref is not None and estimate is not None:
                signed_error = estimate - ref; abs_error = abs(signed_error)
                valid_window_keys.add(key); all_errors.append(abs_error); all_signed.append(signed_error)
                rows_by_subject[exp["subject_id"]].append((exp, abs_error, signed_error))
            joined_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                "subject_id": exp["subject_id"], "recording_id": exp["recording_id"], "window_id": exp["window_id"],
                                "window_start_s": exp["window_start_s_n"], "window_end_s": exp["window_end_s_n"], "target_time_s": exp["target_time_s_n"],
                                "available_time_s": None if pred is None else pred["available_time_s_n"], "reference_bpm": ref, "estimate_bpm": estimate,
                                "status": status, "abs_error": abs_error, "signed_error": signed_error,
                                "activity": exp.get("activity", "")})
        valid_sets[group] = valid_window_keys
        subject_values = []
        n_missing_subjects = 0
        n_complete_subjects = 0
        for subject in sorted({r["subject_id"] for r in exp_rows}):
            expected_n = sum(r["reference_bpm_n"] is not None for r in exp_rows if r["subject_id"] == subject)
            vals = rows_by_subject.get(subject, [])
            stats = _stats([x[1] for x in vals], [x[2] for x in vals])
            if stats["mae"] is not None:
                subject_values.append(stats["mae"])
            if expected_n and stats["n_valid"] < expected_n:
                n_missing_subjects += 1
            if expected_n and stats["n_valid"] == expected_n:
                n_complete_subjects += 1
            subject_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                 "subject_id": subject, "n_reference_valid": expected_n, "n_valid": stats["n_valid"],
                                 "coverage": stats["n_valid"] / expected_n if expected_n else None, **{k: v for k, v in stats.items() if k != "n_valid"},
                                 "n_failed": expected_n - stats["n_valid"]})
        group_subject_values[group] = subject_values
        ci_lo, ci_hi = _bootstrap_mean(subject_values, bootstrap, seed)
        agg_stats = _stats(all_errors, all_signed)
        n_reference_valid = sum(r["reference_bpm_n"] is not None for r in exp_rows)
        n_subjects_expected = len({r["subject_id"] for r in exp_rows})
        conditional_macro = sum(subject_values) / len(subject_values) if subject_values else None
        complete_macro = conditional_macro if n_missing_subjects == 0 and n_complete_subjects == n_subjects_expected else None
        aggregate_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                               "n_subjects_expected": n_subjects_expected,
                               "n_subjects_with_predictions": len(subject_values),
                               "n_missing_subjects": n_missing_subjects, "n_complete_subjects": n_complete_subjects,
                               "n_reference_valid": n_reference_valid,
                               "n_valid": agg_stats["n_valid"], "coverage": agg_stats["n_valid"] / n_reference_valid if n_reference_valid else None,
                               "n_failed": n_reference_valid - agg_stats["n_valid"],
                               "subject_macro_mae": conditional_macro, "subject_macro_mae_complete": complete_macro,
                               "subject_macro_mae_sd": _sample_sd(subject_values),
                               "subject_macro_mae_ci_low": ci_lo, "subject_macro_mae_ci_high": ci_hi,
                               "subject_ci_status": "insufficient_subjects" if len(subject_values) < 2 else "ok",
                               "window_pooled_mae": agg_stats["mae"], "rmse": agg_stats["rmse"], "median_ae": agg_stats["median_ae"],
                               "p95_ae": agg_stats["p95_ae"], "bias": agg_stats["bias"], "error_gt5": agg_stats["error_gt5"],
                               "error_gt10": agg_stats["error_gt10"]})
        group_joined = [j for j in joined_rows if (j["dataset"], j["split"], j["method"], j["variant"], j["config_id"]) == group]
        for label, selector in [("<60", lambda x: x < 60), ("60-180", lambda x: 60 <= x <= 180), (">180", lambda x: x > 180)]:
            expected_n = sum(r["reference_bpm_n"] is not None and selector(r["reference_bpm_n"]) for r in exp_rows)
            picked = [(j, j["abs_error"], j["signed_error"]) for j in group_joined if j["reference_bpm"] is not None and j["abs_error"] is not None and selector(j["reference_bpm"])]
            st = _stats([x[1] for x in picked], [x[2] for x in picked])
            strata_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                "stratum_type": "heart_rate", "stratum": label, "n_reference_expected": expected_n,
                                "coverage": st["n_valid"] / expected_n if expected_n else None, **st})
        activities = sorted({r.get("activity", "") for r in exp_rows if r.get("activity", "")})
        for activity in activities:
            expected_n = sum(r["reference_bpm_n"] is not None and r.get("activity", "") == activity for r in exp_rows)
            picked = [j for j in group_joined if j["activity"] == activity and j["abs_error"] is not None]
            st = _stats([j["abs_error"] for j in picked], [j["signed_error"] for j in picked])
            strata_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                "stratum_type": "activity", "stratum": activity, "n_reference_expected": expected_n,
                                "coverage": st["n_valid"] / expected_n if expected_n else None, **st})
        if states:
            bounds = [min(abs(r["reference_bpm_n"] - state) for state in states) for r in exp_rows if r["reference_bpm_n"] is not None]
            lower_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                               "state_count": len(states), "state_min": min(states), "state_max": max(states),
                               "n_reference_valid": len(bounds), "mean_discrete_range_lower_bound": sum(bounds) / len(bounds) if bounds else None,
                               "max_discrete_range_lower_bound": max(bounds) if bounds else None})
        if make_figures:
            made = _make_plots(out_dir, group, [r for r in subject_rows if (r["dataset"], r["split"], r["method"], r["variant"], r["config_id"]) == group], [r for r in joined_rows if (r["dataset"], r["split"], r["method"], r["variant"], r["config_id"]) == group])
            if made:
                plot_files.extend(made)

    pairing_rows = []
    if baseline_method:
        for group in sorted(groups):
            ds, split, method, variant, config_id = group
            if method == baseline_method:
                continue
            base_candidates = [g for g in groups if g[0] == ds and g[1] == split and g[2] == baseline_method and
                               (baseline_variant is None or g[3] == baseline_variant) and (baseline_config_id is None or g[4] == baseline_config_id)]
            if not base_candidates:
                continue
            if len(base_candidates) > 1:
                pairing_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                     "baseline_method": baseline_method, "baseline_variant": "", "baseline_config_id": "",
                                     "status": "baseline_ambiguous", "n_subjects": 0, "mean_subject_mae_difference": None,
                                     "bootstrap_ci_low": None, "bootstrap_ci_high": None, "signflip_p": None,
                                     "signflip_mode": "not_run", "holm_p_by_dataset": None})
                continue
            base = base_candidates[0]
            same_windows = valid_sets[group] == valid_sets[base]
            expected_valid = {_window_key(r) for r in expected_by_ds[(ds, split)] if r["reference_bpm_n"] is not None}
            complete = same_windows and valid_sets[group] == expected_valid
            pair_status = "paired" if complete else ("coverage_mismatch" if not same_windows else "incomplete_coverage")
            subject_diff = []
            if complete:
                for subject in sorted({r["subject_id"] for r in expected_by_ds[(ds, split)]}):
                    cand = next((r["mae"] for r in subject_rows if (r["dataset"], r["split"], r["method"], r["variant"], r["config_id"], r["subject_id"]) == group + (subject,)), None)
                    bvar = next((r["mae"] for r in subject_rows if (r["dataset"], r["split"], r["method"], r["variant"], r["config_id"], r["subject_id"]) == base + (subject,)), None)
                    if cand is not None and bvar is not None:
                        subject_diff.append(cand - bvar)
            lo, hi = _bootstrap_mean(subject_diff, bootstrap, seed + 1)
            p, mode = _signflip(subject_diff, permutations, seed + 2)
            pairing_rows.append({"dataset": ds, "split": split, "method": method, "variant": variant, "config_id": config_id,
                                 "baseline_method": baseline_method, "baseline_variant": base[3], "baseline_config_id": base[4],
                                 "status": pair_status, "n_subjects": len(subject_diff), "mean_subject_mae_difference": sum(subject_diff) / len(subject_diff) if subject_diff else None,
                                 "bootstrap_ci_low": lo, "bootstrap_ci_high": hi, "signflip_p": p if complete else None,
                                 "signflip_mode": mode if complete else "not_run", "holm_p_by_dataset": None})
        for dataset in sorted({r["dataset"] for r in pairing_rows}):
            idx = [i for i, row in enumerate(pairing_rows) if row["dataset"] == dataset and row["signflip_p"] is not None]
            adjusted = _holm([pairing_rows[i]["signflip_p"] for i in idx])
            for i, val in zip(idx, adjusted):
                pairing_rows[i]["holm_p_by_dataset"] = val

    fields_joined = ["dataset", "split", "method", "variant", "config_id", "subject_id", "recording_id", "window_id", "window_start_s", "window_end_s", "target_time_s", "available_time_s", "reference_bpm", "estimate_bpm", "status", "abs_error", "signed_error", "activity"]
    fields_subject = ["dataset", "split", "method", "variant", "config_id", "subject_id", "n_reference_valid", "n_valid", "coverage", "mae", "rmse", "median_ae", "p95_ae", "bias", "error_gt5", "error_gt10", "n_failed"]
    fields_agg = ["dataset", "split", "method", "variant", "config_id", "n_subjects_expected", "n_subjects_with_predictions", "n_missing_subjects", "n_complete_subjects", "n_reference_valid", "n_valid", "coverage", "n_failed", "subject_macro_mae", "subject_macro_mae_complete", "subject_macro_mae_sd", "subject_macro_mae_ci_low", "subject_macro_mae_ci_high", "subject_ci_status", "window_pooled_mae", "rmse", "median_ae", "p95_ae", "bias", "error_gt5", "error_gt10"]
    fields_strata = ["dataset", "split", "method", "variant", "config_id", "stratum_type", "stratum", "n_reference_expected", "n_valid", "coverage", "mae", "rmse", "median_ae", "p95_ae", "bias", "error_gt5", "error_gt10"]
    fields_lower = ["dataset", "split", "method", "variant", "config_id", "state_count", "state_min", "state_max", "n_reference_valid", "mean_discrete_range_lower_bound", "max_discrete_range_lower_bound"]
    fields_pair = ["dataset", "split", "method", "variant", "config_id", "baseline_method", "baseline_variant", "baseline_config_id", "status", "n_subjects", "mean_subject_mae_difference", "bootstrap_ci_low", "bootstrap_ci_high", "signflip_p", "signflip_mode", "holm_p_by_dataset"]
    _write_csv(out_dir / "window_metrics.csv", joined_rows, fields_joined)
    _write_csv(out_dir / "subject_metrics.csv", subject_rows, fields_subject)
    _write_csv(out_dir / "aggregate_metrics.csv", aggregate_rows, fields_agg)
    _write_csv(out_dir / "stratified_metrics.csv", strata_rows, fields_strata)
    if states:
        _write_csv(out_dir / "range_lower_bound.csv", lower_rows, fields_lower)
    if pairing_rows:
        _write_csv(out_dir / "paired_comparisons.csv", pairing_rows, fields_pair)
    if expected_hop_s is not None:
        fields_episodes = ["dataset", "split", "method", "variant", "config_id", "subject_id", "recording_id", "episode_id", "n_failed_windows", "first_window_end_s", "last_window_end_s", "decision_grid_duration_s"]
        _write_csv(out_dir / "failure_episodes.csv", failure_episode_rows, fields_episodes)
    def sha256(path):
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    synthetic = "tests" in predictions_path.parts and "temp" in predictions_path.parts
    metadata = {"predictions": str(predictions_path), "predictions_sha256": sha256(predictions_path),
                "expected_windows": str(expected_path), "expected_windows_sha256": sha256(expected_path),
                "analyzer_sha256": sha256(Path(__file__)), "baseline_method": baseline_method,
                "baseline_variant": baseline_variant, "baseline_config_id": baseline_config_id,
                "protocol_id": protocol_id, "state_list": states,
                "seed": seed, "bootstrap_iterations": bootstrap, "permutation_iterations": permutations,
                "states_supplied": states is not None, "groups": len(groups),
                "coverage_definition": "successful estimates / reference-valid expected windows; missing predictions remain failures",
                "pairing_coverage_rule": "paired only when candidate and baseline valid-window sets equal expected reference-valid set",
                "expected_hop_s": expected_hop_s,
                "failure_episode_definition": ("reference-valid non-success windows; same subject/recording, adjacent window_end_s within isclose(expected_hop_s); success, invalid reference, recording change, and time gaps break episodes" if expected_hop_s is not None else "not requested; failure_episodes.csv not written"),
                "plot_files": sorted(plot_files),
                "result_status": "ENGINEERING_TEST_ONLY" if synthetic else "COMPUTED_FROM_SUPPLIED_INPUT; provenance review required before paper use"}
    (out_dir / "run_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return metadata


def build_parser():
    parser = argparse.ArgumentParser(description="Compute protocol-defined window/subject metrics from predictions.csv and expected_windows.csv.")
    parser.add_argument("--predictions", required=True, type=Path, help="window-level predictions CSV")
    parser.add_argument("--expected-windows", required=True, type=Path, help="reference evaluation-window manifest CSV")
    parser.add_argument("--output-dir", required=True, type=Path, help="directory for metrics and optional figures")
    parser.add_argument("--baseline-method", help="method name used for paired comparisons")
    parser.add_argument("--baseline-variant")
    parser.add_argument("--baseline-config-id")
    parser.add_argument("--protocol-id", help="explicit assertion that all compared groups share one frozen protocol")
    parser.add_argument("--state-list", help="comma/space separated states or path to a state-list file")
    parser.add_argument("--expected-hop-s", type=float, help="positive expected decision-grid hop in seconds; enables failure_episodes.csv")
    parser.add_argument("--bootstrap", type=int, default=10000, help="subject bootstrap replicates (default 10000)")
    parser.add_argument("--permutations", type=int, default=10000, help="large-n sign-flip Monte Carlo replicates (default 10000)")
    parser.add_argument("--seed", type=int, default=20260911)
    parser.add_argument("--no-figures", action="store_true", help="skip optional matplotlib figures")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        metadata = analyze(args.predictions, args.expected_windows, args.output_dir,
                           baseline_method=args.baseline_method, baseline_variant=args.baseline_variant,
                           baseline_config_id=args.baseline_config_id, bootstrap=args.bootstrap,
                           permutations=args.permutations, seed=args.seed, states=_parse_states(args.state_list),
                           make_figures=not args.no_figures, protocol_id=args.protocol_id,
                           expected_hop_s=args.expected_hop_s)
    except (InputError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(metadata, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

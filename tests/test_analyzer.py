import csv
import json
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from analyze_predictions import InputError, _make_plots, analyze  # noqa: E402


FIXTURES = Path(__file__).resolve().parent / "temp"


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as h:
        return list(csv.DictReader(h))


class AnalyzerTest(unittest.TestCase):
    def run_fixture(self, pred=None, expected=None, **kwargs):
        out = Path(tempfile.mkdtemp(prefix="analyzer-test-", dir=FIXTURES))
        try:
            return out, analyze(pred or FIXTURES / "predictions.csv", expected or FIXTURES / "expected_windows.csv", out, make_figures=False, bootstrap=kwargs.pop("bootstrap", 200), permutations=kwargs.pop("permutations", 200), **kwargs)
        except Exception:
            shutil.rmtree(out, ignore_errors=True)
            raise

    def test_macro_differs_from_window_pooled_and_sessions_merge_by_subject(self):
        out, _ = self.run_fixture(states=[60, 80, 100, 120])
        agg = read_csv(out / "aggregate_metrics.csv")
        base = next(r for r in agg if r["method"] == "baseline")
        self.assertAlmostEqual(float(base["subject_macro_mae"]), 3.5)
        self.assertAlmostEqual(float(base["subject_macro_mae_sd"]), 2 ** -0.5)
        self.assertAlmostEqual(float(base["window_pooled_mae"]), 3.2)
        subj = read_csv(out / "subject_metrics.csv")
        s1 = next(r for r in subj if r["method"] == "baseline" and r["subject_id"] == "S01")
        self.assertEqual(s1["n_valid"], "4")
        lower = read_csv(out / "range_lower_bound.csv")
        self.assertTrue(lower)

    def test_complete_pairing_exact_signflip_and_holm(self):
        out, _ = self.run_fixture(baseline_method="baseline", protocol_id="frozen-protocol-v1")
        pairs = read_csv(out / "paired_comparisons.csv")
        pair = next(r for r in pairs if r["method"] == "candidate")
        self.assertEqual(pair["status"], "paired")
        self.assertEqual(pair["signflip_mode"], "exact")
        self.assertAlmostEqual(float(pair["mean_subject_mae_difference"]), -3.5)
        self.assertAlmostEqual(float(pair["signflip_p"]), 0.5)
        self.assertEqual(pair["holm_p_by_dataset"], "0.5")

    def test_explicit_baseline_config_can_differ_from_candidate(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        rows = read_csv(FIXTURES / "predictions.csv")
        for row in rows:
            row["config_id"] = "base-cfg" if row["method"] == "baseline" else "candidate-cfg"
        pred = work / "predictions.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
        out = work / "out"
        analyze(pred, FIXTURES / "expected_windows.csv", out, baseline_method="baseline", baseline_variant="default", baseline_config_id="base-cfg", protocol_id="frozen-protocol-v1", make_figures=False, bootstrap=100, permutations=100)
        pair = next(r for r in read_csv(out / "paired_comparisons.csv") if r["method"] == "candidate")
        self.assertEqual(pair["status"], "paired")
        self.assertEqual(pair["baseline_config_id"], "base-cfg")

    def test_missing_predictions_stay_in_denominator_and_zero_valid_is_blank(self):
        pred = Path(tempfile.mkdtemp(dir=FIXTURES)) / "missing.csv"
        rows = read_csv(FIXTURES / "predictions.csv")
        rows = [r for r in rows if not (r["method"] == "candidate" and r["subject_id"] == "S01" and r["recording_id"] == "R01" and r["window_id"] == "W1")]
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=read_csv(FIXTURES / "predictions.csv")[0].keys())
            writer.writeheader(); writer.writerows(rows)
        out, _ = self.run_fixture(pred=pred, baseline_method="baseline", protocol_id="frozen-protocol-v1")
        cand = next(r for r in read_csv(out / "aggregate_metrics.csv") if r["method"] == "candidate")
        self.assertEqual(cand["n_reference_valid"], "5")
        self.assertEqual(cand["n_valid"], "4")
        self.assertEqual(cand["n_failed"], "1")
        self.assertAlmostEqual(float(cand["coverage"]), 0.8)
        pair = next(r for r in read_csv(out / "paired_comparisons.csv") if r["method"] == "candidate")
        self.assertEqual(pair["status"], "coverage_mismatch")
        self.assertEqual(pair["signflip_p"], "")

    def test_all_predictions_failed_keeps_blank_mae(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES)); rows = read_csv(FIXTURES / "predictions.csv")
        failed = []
        for row in rows:
            if row["method"] == "candidate":
                row["estimate_bpm"] = ""; row["status"] = "failed"; failed.append(row)
        pred = work / "failed.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=failed[0].keys()); writer.writeheader(); writer.writerows(failed)
        out = work / "out"; analyze(pred, FIXTURES / "expected_windows.csv", out, make_figures=False)
        agg = read_csv(out / "aggregate_metrics.csv")[0]
        self.assertEqual(agg["n_reference_valid"], "5"); self.assertEqual(agg["n_valid"], "0")
        self.assertEqual(agg["subject_macro_mae"], ""); self.assertEqual(agg["n_missing_subjects"], "2")

    def test_failure_episodes_respect_invalid_reference_recording_and_manifest_gaps(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        expected_rows = read_csv(FIXTURES / "expected_windows.csv")
        # Make S01/R01/W2 an invalid-reference separator and S02/R01 two windows with a manifest gap.
        expected_rows[1]["reference_bpm"] = ""
        expected_rows[4]["window_id"] = "W1"; expected_rows[4]["window_start_s"] = "0"; expected_rows[4]["window_end_s"] = "8"; expected_rows[4]["target_time_s"] = "4"
        gap = dict(expected_rows[4]); gap.update({"window_id": "W3", "window_start_s": "16", "window_end_s": "24", "target_time_s": "20", "reference_bpm": "120"})
        expected_rows.append(gap)
        expected = work / "expected.csv"
        with expected.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=expected_rows[0].keys()); writer.writeheader(); writer.writerows(expected_rows)
        pred_rows = []
        for row in read_csv(FIXTURES / "predictions.csv"):
            if row["method"] != "candidate":
                continue
            row = dict(row); row["estimate_bpm"] = ""; row["status"] = "failed"
            if row["subject_id"] == "S01" and row["recording_id"] == "R01" and row["window_id"] == "W2":
                row["reference_bpm"] = ""; row["status"] = "no_reference"
            pred_rows.append(row)
        extra = dict(pred_rows[-1]); extra.update({"window_id": "W3", "window_start_s": "16", "window_end_s": "24", "target_time_s": "20", "available_time_s": "28", "reference_bpm": "120"}); pred_rows.append(extra)
        pred = work / "predictions.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=pred_rows[0].keys()); writer.writeheader(); writer.writerows(pred_rows)
        out = work / "out"; analyze(pred, expected, out, expected_hop_s=8, make_figures=False)
        episodes = read_csv(out / "failure_episodes.csv")
        self.assertEqual(len(episodes), 5)
        self.assertEqual(sum(int(row["n_failed_windows"]) for row in episodes), 5)
        self.assertTrue(all(float(row["decision_grid_duration_s"]) == 8 * int(row["n_failed_windows"]) for row in episodes))
        s1r1 = [row for row in episodes if row["subject_id"] == "S01" and row["recording_id"] == "R01"]
        self.assertEqual(len(s1r1), 2)  # W2 invalid reference breaks W1/W3.
        s2 = [row for row in episodes if row["subject_id"] == "S02"]
        self.assertEqual(len(s2), 2)  # W1 -> W3 is a manifest/time gap.

    def test_failure_episode_merges_adjacent_failed_and_missing_windows(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        expected_rows = []
        for i, (start, end, target, ref) in enumerate(((0, 8, 4, 70), (8, 16, 12, 80), (16, 24, 20, 90), (24, 32, 28, 100)), 1):
            expected_rows.append({"dataset": "SYNTH", "subject_id": "S01", "recording_id": "R-MERGE", "window_id": f"W{i}",
                                  "window_start_s": str(start), "window_end_s": str(end), "target_time_s": str(target),
                                  "reference_bpm": str(ref), "split": "test", "activity": "rest"})
        expected = work / "expected.csv"
        with expected.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=expected_rows[0].keys()); writer.writeheader(); writer.writerows(expected_rows)
        pred_rows = []
        for row, status, estimate in ((expected_rows[0], "failed", ""), (expected_rows[2], "success", "90"), (expected_rows[3], "failed", "")):
            pred_rows.append({**row, "available_time_s": str(float(row["window_end_s"]) + 4), "estimate_bpm": estimate,
                              "method": "candidate", "variant": "default", "status": status, "exclusion_reason": "", "config_id": "cfg"})
        pred = work / "predictions.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=pred_rows[0].keys()); writer.writeheader(); writer.writerows(pred_rows)
        out = work / "out"; analyze(pred, expected, out, expected_hop_s=8, make_figures=False)
        episodes = read_csv(out / "failure_episodes.csv")
        self.assertEqual(len(episodes), 2)
        self.assertEqual([int(row["n_failed_windows"]) for row in episodes], [2, 1])
        self.assertEqual(float(episodes[0]["decision_grid_duration_s"]), 16.0)
        self.assertFalse((work / "out_no_hop").exists())
        analyze(pred, expected, work / "out_no_hop", make_figures=False)
        self.assertFalse((work / "out_no_hop" / "failure_episodes.csv").exists())

    def test_success_time_and_activity_metadata_mismatch_rejected(self):
        source = read_csv(FIXTURES / "predictions.csv")
        for field, value in (("available_time_s", "7"), ("activity", "activity-mismatch")):
            work = Path(tempfile.mkdtemp(dir=FIXTURES)); rows = [dict(r) for r in source]; rows[0][field] = value
            pred = work / "bad.csv"
            with pred.open("w", newline="", encoding="utf-8") as h:
                writer = csv.DictWriter(h, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
            with self.assertRaises(InputError):
                analyze(pred, FIXTURES / "expected_windows.csv", work / "out", make_figures=False)

    def test_svg_fallback_is_step_ecdf_with_axes_and_group_hash(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        group = ("SYNTH", "test", "m/a", "default", "cfg")
        subject_rows = [{"subject_id": "S01", "mae": 1.5}, {"subject_id": "S02", "mae": 3.0}]
        window_rows = [{"abs_error": 1.0}, {"abs_error": 1.0}, {"abs_error": 3.0}]
        files = _make_plots(work, group, subject_rows, window_rows, force_svg=True)
        self.assertEqual(len(files), 2); self.assertTrue(all(name.endswith(".svg") for name in files))
        for name in files:
            root = ET.parse(work / name).getroot(); self.assertEqual(root.tag.split("}")[-1], "svg")
        ecdf = (work / [name for name in files if "ecdf" in name][0]).read_text(encoding="utf-8")
        self.assertIn("<path", ecdf); self.assertGreaterEqual(ecdf.count("L"), 4)
        self.assertIn("absolute error", ecdf); self.assertIn("ECDF", ecdf)
        self.assertIn("__", files[0])

    def test_repeated_and_reference_mismatch_rejected(self):
        pred_rows = read_csv(FIXTURES / "predictions.csv")
        pred = Path(tempfile.mkdtemp(dir=FIXTURES)) / "dup.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=pred_rows[0].keys()); writer.writeheader(); writer.writerows(pred_rows + [pred_rows[0]])
        with self.assertRaises(InputError):
            self.run_fixture(pred=pred)

        bad = Path(tempfile.mkdtemp(dir=FIXTURES)) / "reference.csv"
        rows = list(pred_rows); rows[0] = dict(rows[0]); rows[0]["reference_bpm"] = "71"
        with bad.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
        with self.assertRaises(InputError):
            self.run_fixture(pred=bad)

    def test_seed_reproducible(self):
        out1, _ = self.run_fixture(baseline_method="baseline", protocol_id="frozen-protocol-v1", seed=99)
        out2, _ = self.run_fixture(baseline_method="baseline", protocol_id="frozen-protocol-v1", seed=99)
        self.assertEqual((out1 / "aggregate_metrics.csv").read_text(), (out2 / "aggregate_metrics.csv").read_text())
        self.assertEqual((out1 / "paired_comparisons.csv").read_text(), (out2 / "paired_comparisons.csv").read_text())

    def test_all_reference_invalid_has_blank_metrics_and_zero_denominator(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        expected_rows = read_csv(FIXTURES / "expected_windows.csv")[:1]
        expected_rows[0]["reference_bpm"] = ""
        expected = work / "expected.csv"
        with expected.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=expected_rows[0].keys()); writer.writeheader(); writer.writerows(expected_rows)
        pred_rows = read_csv(FIXTURES / "predictions.csv")[:1]
        pred_rows[0].update({"reference_bpm": "", "estimate_bpm": "", "status": "no_reference"})
        pred = work / "predictions.csv"
        with pred.open("w", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=pred_rows[0].keys()); writer.writeheader(); writer.writerows(pred_rows)
        out = work / "out"
        analyze(pred, expected, out, make_figures=False, bootstrap=20, permutations=20)
        agg = read_csv(out / "aggregate_metrics.csv")[0]
        self.assertEqual(agg["n_reference_valid"], "0")
        self.assertEqual(agg["coverage"], "")
        self.assertEqual(agg["subject_macro_mae"], "")

    def test_one_subject_ci_marked_insufficient_and_output_dir_is_not_reused(self):
        work = Path(tempfile.mkdtemp(dir=FIXTURES))
        expected_rows = [r for r in read_csv(FIXTURES / "expected_windows.csv") if r["subject_id"] == "S02"]
        pred_rows = [r for r in read_csv(FIXTURES / "predictions.csv") if r["method"] == "baseline" and r["subject_id"] == "S02"]
        expected = work / "expected.csv"; pred = work / "predictions.csv"
        for path, rows in ((expected, expected_rows), (pred, pred_rows)):
            with path.open("w", newline="", encoding="utf-8") as h:
                writer = csv.DictWriter(h, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
        out = work / "out"
        analyze(pred, expected, out, make_figures=False, bootstrap=20, permutations=20)
        agg = read_csv(out / "aggregate_metrics.csv")[0]
        self.assertEqual(agg["subject_ci_status"], "insufficient_subjects")
        self.assertEqual(agg["subject_macro_mae_ci_low"], "")
        with self.assertRaises(InputError):
            analyze(pred, expected, out, make_figures=False)


if __name__ == "__main__":
    unittest.main()

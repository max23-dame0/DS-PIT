import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from verify_paper_results import verify_all  # noqa: E402


class PaperReproducibilityTests(unittest.TestCase):
    def test_all_paper_and_supplement_numbers_match_saved_outputs(self):
        passed, total, checks = verify_all()
        failed = [(label, detail) for label, ok, detail in checks if not ok]
        self.assertEqual(passed, total, f"Failed reproducibility checks: {failed}")


if __name__ == "__main__":
    unittest.main()

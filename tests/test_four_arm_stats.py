"""ENGINEERING TEST ONLY: mathematical checks, no paper results."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('four_arm_stats', Path(__file__).parents[1] / 'scripts' / 'four_arm_stats.py')
stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stats)


class FourArmStatsTests(unittest.TestCase):
    def test_exact_enumeration(self):
        self.assertEqual(stats.exact_signflip([1, 1, 1]), .25)
        self.assertEqual(stats.exact_signflip([1, -1]), 1)
        self.assertEqual(stats.exact_signflip([0, 0, 0]), 1)
        self.assertEqual(stats.exact_signflip([1, 2, -1]), stats.exact_signflip([-1, -2, 1]))

    def test_holm_order_and_monotonicity(self):
        self.assertEqual(stats.holm([.04, .01, .03]), [.06, .03, .06])
        self.assertEqual(stats.holm([1, 1]), [1, 1])

    def test_percentile_interpolation(self):
        self.assertEqual(stats.percentile([0, 10], .25), 2.5)

    def test_matlab_column_order_and_complete_family(self):
        data = dict(arm_names=['Baseline', '+SSC', '+LBP', 'Full'],
                    datasets=['IEEE SPC', 'PPG-DaLiA', 'WESAD'],
                    per_unit=[[10*d+a] * (23 if d == 0 else 15)
                              for a in range(4) for d in range(3)],
                    means=[[10*d+a for a in range(4)] for d in range(3)])
        rows = stats.analyze(data, 1)
        self.assertEqual(len(rows), 12)
        self.assertEqual([r['delta_a_minus_b'] for r in rows[:6]], [-1, -2, -3, -1, -2, -1])
        self.assertEqual({r['dataset'] for r in rows}, {'PPG-DaLiA', 'WESAD'})


if __name__ == '__main__':
    unittest.main()

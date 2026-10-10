"""Post-hoc paired analysis of saved A2 four-arm subject MAEs; no model runs."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import random


def exact_signflip(differences):
    observed = abs(sum(differences))
    sums = [0.0]
    for value in differences:
        sums = [s + sign * value for s in sums for sign in (-1, 1)]
    tolerance = 1e-12 * max(1.0, sum(map(abs, differences)))
    return sum(abs(s) >= observed - tolerance for s in sums) / len(sums)


def holm(pvalues):
    order = sorted(range(len(pvalues)), key=pvalues.__getitem__)
    result, previous = [0.0] * len(order), 0.0
    for rank, index in enumerate(order):
        previous = max(previous, min(1.0, (len(order) - rank) * pvalues[index]))
        result[index] = previous
    return result


def percentile(values, probability):
    position = (len(values) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    return values[lower] + (position - lower) * (values[upper] - values[lower])


def analyze(data, seed):
    assert data['arm_names'] == ['Baseline', '+SSC', '+LBP', 'Full']
    assert data['datasets'] == ['IEEE SPC', 'PPG-DaLiA', 'WESAD']
    # MATLAB jsonencode flattens a 3-by-4 cell array in column-major order.
    assert len(data['per_unit']) == 12
    rng, rows = random.Random(seed), []
    for d in (1, 2):
        arms = [data['per_unit'][d + 3 * a] for a in range(4)]
        for a, values in enumerate(arms):
            assert len(values) == 15 and all(math.isfinite(x) for x in values)
            assert abs(sum(values) / 15 - data['means'][d][a]) < 1e-10
        for a, b in itertools.combinations(range(4), 2):
            dif = [x - y for x, y in zip(arms[a], arms[b])]
            draws = sorted(sum(dif[rng.randrange(15)] for _ in range(15)) / 15
                           for _ in range(10000))
            rows.append(dict(dataset=data['datasets'][d], a=data['arm_names'][a],
                             b=data['arm_names'][b], n=15, delta_a_minus_b=sum(dif)/15,
                             p_exact=exact_signflip(dif),
                             ci95_pointwise=[percentile(draws, .025), percentile(draws, .975)]))
    for row, p in zip(rows, holm([r['p_exact'] for r in rows])):
        row['p_holm_12'] = p
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=20260930)
    args = parser.parse_args()
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        parser.error('Output directory must be empty.')
    raw = args.input.read_bytes()
    rows = analyze(json.loads(raw.decode('utf-8-sig')), args.seed)
    output = dict(status='POST_HOC_EXPLORATORY_REQUIRES_REVIEW', seed=args.seed,
                  input_sha256=hashlib.sha256(raw).hexdigest(), bootstrap_draws=10000,
                  family='All six pairs in each of two datasets; Holm over 12 tests',
                  ci='Pointwise paired subject bootstrap, linear percentile interpolation',
                  ieee='Excluded from inference: recording/subject independence unresolved',
                  assumption='Sign-flip inference assumes independent subjects and symmetric paired differences under the null',
                  comparisons=rows)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / 'results.json').write_text(json.dumps(output, indent=2), encoding='utf-8')
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()

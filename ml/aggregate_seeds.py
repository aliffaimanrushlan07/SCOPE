"""Turn per-seed scores into mean +/- standard deviation.

    ./backend/.venv/bin/python ml/aggregate_seeds.py

Reads ml/artifacts/seeds/{val,test}_scores_seed<N>.csv, written by section 11
of ml/notebooks/finetune_vit.ipynb.

WHAT THIS ANSWERS
-----------------
"How much of your precision is the method, and how much is the seed?"

Every figure from a single run carries the variance of that run: the head
starts from random weights, the images arrive in a random order, and the
augmentation crops at random. Retraining the same recipe on the same split with
a different seed gives a different model, and on 293 test images the difference
between 3 false positives and 6 is one unlucky initialisation.

So each seed is put through the FULL procedure independently — select the
threshold on that seed's validation scores, then report that seed's test
metrics at that frozen threshold. The spread therefore covers both the model
and the threshold that was chosen for it, which is the honest quantity: it is
what would have happened had you trained once with a different seed and
followed the same method.

WHAT IT DOES NOT ANSWER
-----------------------
The other source of uncertainty is the test split itself. With 151 non-smoking
images, the confidence interval on precision is roughly +/- 0.03 whatever the
seed does. Averaging over seeds does not shrink that; only more test data does.
Both numbers belong in the report, and this script prints both.
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from select_threshold import (  # noqa: E402
    DEFAULT_TARGET_PRECISION,
    choose,
    load_scores,
    metrics_at,
    sweep,
    wilson_interval,
)

ML_DIR = Path(__file__).resolve().parent
SEED_DIR = ML_DIR / "artifacts" / "seeds"


def average_precision(rows: list[tuple[int, float]]) -> float:
    """PR-AUC as average precision — threshold-independent, so it compares
    seeds without the threshold choice getting in the way."""
    ranked = sorted(rows, key=lambda r: -r[1])
    positives = sum(y for y, _ in ranked)
    if not positives:
        return 0.0

    tp = 0
    total = 0.0
    for seen, (y, _) in enumerate(ranked, start=1):
        if y:
            tp += 1
            total += tp / seen
    return total / positives


def discover_seeds() -> list[int]:
    found = set()
    for path in SEED_DIR.glob("val_scores_seed*.csv"):
        match = re.search(r"seed(\d+)", path.name)
        if match and (SEED_DIR / f"test_scores_seed{match.group(1)}.csv").exists():
            found.add(int(match.group(1)))
    return sorted(found)


def run_seed(seed: int, target: float) -> dict[str, float] | None:
    """One seed, put through the whole select-on-val, report-on-test procedure."""
    val = load_scores(SEED_DIR / f"val_scores_seed{seed}.csv")
    test = load_scores(SEED_DIR / f"test_scores_seed{seed}.csv")

    chosen, _ = choose(sweep(val), target)
    if chosen is None:
        print(f"  seed {seed}: no threshold reaches precision >= {target:.2f} "
              f"on validation — excluded from the summary.")
        return None

    at = metrics_at(test, chosen["threshold"])
    return {
        "seed": seed,
        "threshold": chosen["threshold"],
        "precision": at["precision"],
        "recall": at["recall"],
        "f1": at["f1"],
        "pr_auc": average_precision(test),
        "invalid_report": at["invalid_report"],
        "tp": at["tp"], "fp": at["fp"], "fn": at["fn"], "tn": at["tn"],
    }


def summarise(values: list[float]) -> str:
    """mean +/- SD, with the sample SD undefined for a single run."""
    if len(values) < 2:
        return f"{values[0]:.3f}  (one seed — no spread to report)"
    return f"{statistics.mean(values):.3f} +/- {statistics.stdev(values):.3f}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--target-precision", type=float,
                        default=DEFAULT_TARGET_PRECISION)
    args = parser.parse_args()

    seeds = discover_seeds()
    if not seeds:
        sys.exit(
            f"No per-seed scores in {SEED_DIR}\n"
            "Run section 11 of ml/notebooks/finetune_vit.ipynb, then unzip\n"
            "seed_scores.zip so the CSVs land in that directory."
        )

    print(f"{len(seeds)} seed(s): {', '.join(str(s) for s in seeds)}")
    print(f"Threshold selected on each seed's OWN validation split, "
          f"target precision {args.target_precision:.2f}.\n")

    results = [r for r in (run_seed(s, args.target_precision) for s in seeds) if r]
    if not results:
        sys.exit("No seed produced a usable threshold.")

    print("Per seed — test metrics at that seed's own frozen threshold")
    print(f"{'seed':>5} {'thresh':>7} {'prec':>7} {'recall':>7} {'F1':>7} "
          f"{'PR-AUC':>7} {'FP':>4} {'FN':>4}")
    for r in results:
        print(f"{r['seed']:>5} {r['threshold']:>7.2f} {r['precision']:>7.3f} "
              f"{r['recall']:>7.3f} {r['f1']:>7.3f} {r['pr_auc']:>7.3f} "
              f"{r['fp']:>4} {r['fn']:>4}")

    print()
    print("=" * 62)
    print(f"  ACROSS {len(results)} SEEDS (mean +/- SD)")
    print("=" * 62)
    for key, label in (("precision", "Precision"), ("recall", "Recall   "),
                       ("f1", "F1       "), ("pr_auc", "PR-AUC   ")):
        print(f"  {label} {summarise([r[key] for r in results])}")
    print(f"  Threshold {summarise([r['threshold'] for r in results])}")

    if len(results) > 1:
        spread = statistics.stdev([r["precision"] for r in results])
        print()
        print(f"  Seed-to-seed SD of precision: {spread:.3f}")

        # The other uncertainty, which averaging cannot touch.
        worst = max(results, key=lambda r: r["fp"])
        lo, hi = wilson_interval(worst["tp"], worst["tp"] + worst["fp"])
        sampling = (hi - lo) / 2
        print(f"  Test-split sampling half-width: ~{sampling:.3f} "
              f"(95% CI, {worst['fp'] + worst['tn']} negatives)")
        print()
        if sampling > spread * 1.5:
            print("  The test split, not the seed, is the larger source of")
            print("  uncertainty here. More seeds will not narrow the figure;")
            print("  more labelled test images would. Report both, and say which")
            print("  dominates.")
        else:
            print("  Seed variance is comparable to or larger than sampling noise,")
            print("  so the spread above is a real property of the training recipe")
            print("  and worth reporting as such.")

    if len(results) > 1:
        precision = [r["precision"] for r in results]
        recall = [r["recall"] for r in results]
        print()
        print("For the report, quote the spread rather than one run:")
        print(f'  "Across {len(results)} training runs differing only in random seed, '
              f'the classifier')
        print(f'  reached precision {statistics.mean(precision):.3f} +/- '
              f'{statistics.stdev(precision):.3f} and recall '
              f'{statistics.mean(recall):.3f} +/- {statistics.stdev(recall):.3f}')
        print('  on the held-out test split, each run using the threshold selected on')
        print('  its own validation split."')

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

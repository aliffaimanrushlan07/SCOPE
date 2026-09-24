"""Choose the confidence threshold from evaluation results.

    # 1. select on VALIDATION
    python ml/select_threshold.py ml/artifacts/val_scores_backend.csv

    # 2. report on TEST at the threshold that came back, without re-selecting
    python ml/select_threshold.py ml/artifacts/test_scores_backend.csv \
        --at-threshold 0.70

Input CSV needs two columns:
    label   — "smoking" or "notsmoking" (the ground truth)
    score   — the model's P(smoking), 0.0 to 1.0

`ml/score_split.py` writes these files, for any split, through the backend's
own inference code.

SELECT ON VALIDATION, REPORT ON TEST
------------------------------------
The threshold is a parameter fitted to data, exactly like a weight. Fitting it
on the test split and then reporting test metrics at that point measures the
model on images the operating point was chosen to suit: the resulting precision
is an upper bound on itself, not an independent estimate.

So this script defaults to the VALIDATION scores, and the sweep is the
selection step. Once a threshold is chosen it is frozen; test metrics are then
reported with --at-threshold, which prints one row and offers no choice. The
default and the two modes exist to make the correct order the easy one.

A number that falls when this discipline is applied has not regressed — the
previous number was measured wrongly. Report the lower one, and say why.

WHY THIS IS A SCRIPT AND NOT A GUESS
------------------------------------
`SCOPE-System-Flow-Revised.md` §8 leaves exactly one item open — the
confidence threshold — and says explicitly that it is an empirical result
rather than a design choice. This script produces that result, and the table
it prints is the evidence for it in Chapter 5.

THE ASYMMETRY THAT DRIVES THE CHOICE
------------------------------------
The two errors do not cost the same, so the threshold is NOT chosen to
maximise accuracy or F1.

  FALSE POSITIVE — an invalid report is accepted and forwarded to enforcement.
  Because administrators are read-only and the AI decision is final, nothing
  downstream can catch it. An officer may patrol on bad data, and a premise
  may be implicated by a photograph that shows no violation.

  FALSE NEGATIVE — a genuine report is rejected and the reporter is asked to
  retake the photograph. Annoying, recoverable, and the reporter is standing
  there and can try again.

So the operating point is chosen to hold PRECISION at or above a target,
then take the best recall available subject to that. Precision is the
directly relevant quantity: of the reports we accept, how many are real.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

POSITIVE = "smoking"

# Of the reports the system accepts, at least this share must be genuine.
#
# 0.99, not the 0.95 that reads like a natural default, because PER-PHOTO
# precision is not what the system delivers. A report carries up to three
# photographs and passes when ANY ONE of them clears the threshold, so a false
# positive gets three independent chances while a false negative needs all
# three to fail. Per-photo precision of 0.95 — a 5% per-photo false-positive
# rate on a balanced split — becomes roughly a 14% chance that an invalid
# report reaches enforcement. README.md section 8 makes this argument and
# overrode this script by hand because of it; encoding it here stops the
# override being needed, and stops it being forgotten.
#
# The sweep below prints the report-level rate next to the per-photo one, so
# the amplification is visible while the threshold is being chosen rather than
# discovered afterwards.
DEFAULT_TARGET_PRECISION = 0.99

# A report carries at most this many photographs, and passes when at least
# PHOTOS_TO_PASS of them clear the threshold (SCOPE-System-Flow-Revised.md §8).
PHOTOS_PER_REPORT = 3
PHOTOS_TO_PASS = 1


def load_scores(path: Path) -> list[tuple[int, float]]:
    if not path.exists():
        sys.exit(
            f"No scores file at {path}\n"
            "Produce it first, through the backend's own inference code:\n"
            f"  ./backend/.venv/bin/python ml/score_split.py "
            f"{'test' if 'test' in path.name else 'val'}"
        )

    rows: list[tuple[int, float]] = []
    with path.open() as handle:
        for row in csv.DictReader(handle):
            if "label" not in row or "score" not in row:
                sys.exit("CSV must have 'label' and 'score' columns.")
            rows.append((1 if row["label"] == POSITIVE else 0, float(row["score"])))

    if not rows:
        sys.exit("Scores file is empty.")
    if not any(y for y, _ in rows) or all(y for y, _ in rows):
        sys.exit("Scores file contains only one class; both are needed.")

    # Catch malformed scores before sweeping. Without this the sweep "succeeds"
    # and reports recall 0.000 at every threshold, which reads like a hopeless
    # model when the real problem is that the file does not contain
    # probabilities at all.
    low = min(s for _, s in rows)
    high = max(s for _, s in rows)

    if low < 0.0 or high > 1.0:
        sys.exit(
            f"Scores are outside [0, 1] — they range from {low:.4f} to {high:.4f}.\n"
            "\n"
            "These look like LOGITS, not probabilities. The model was built\n"
            "without a softmax activation, so its outputs are unbounded and can\n"
            "be negative.\n"
            "\n"
            "Fix in the training notebook, cell 4:\n"
            "    ViTImageClassifier.from_preset(PRESET, num_classes=2,\n"
            "                                   activation='softmax')\n"
            "and keep SparseCategoricalCrossentropy(from_logits=False).\n"
            "\n"
            "The mismatch also breaks TRAINING, not just these scores, so the\n"
            "model must be retrained rather than merely re-evaluated."
        )

    if high - low < 0.05:
        sys.exit(
            f"All scores sit within {low:.4f}–{high:.4f}, a range too narrow to\n"
            "threshold. The model is predicting nearly the same value for every\n"
            "image, which usually means training did not converge — check that\n"
            "the loss actually fell across epochs."
        )

    return rows


def wilson_interval(successes: int, trials: int, z: float = 1.96) -> tuple[float, float]:
    """95% confidence interval for a proportion (Wilson score).

    Precision on this test split is 131 correct out of 135 accepted. Quoting
    that as "0.970" implies a precision the sample size cannot support: with
    only 151 non-smoking images, the difference between 3 false positives and
    6 is one or two photographs.

    Wilson rather than the textbook normal approximation because the counts
    here are small and the proportions near 1, exactly where the normal
    approximation produces intervals that run above 100%.
    """
    if trials == 0:
        return (0.0, 1.0)

    from math import sqrt

    p = successes / trials
    denominator = 1 + z * z / trials
    centre = (p + z * z / (2 * trials)) / denominator
    half = z * sqrt(p * (1 - p) / trials + z * z / (4 * trials * trials)) / denominator
    return (max(0.0, centre - half), min(1.0, centre + half))


def _at_least(k: int, n: int, p: float) -> float:
    """P(at least k of n independent trials succeed), each with probability p."""
    from math import comb
    return sum(comb(n, i) * p**i * (1 - p)**(n - i) for i in range(k, n + 1))


def report_rates(fpr: float, fnr: float) -> tuple[float, float]:
    """Turn per-photo error rates into per-REPORT ones.

    This is the quantity the operating point should actually be chosen on: a
    reporter submits up to three photographs of one incident, and §8 accepts
    the report when at least one clears the threshold.

    Assumes the three photographs fail independently, which flatters the
    result — they share a scene, a light level and a photographer. Treat these
    as a lower bound on the true invalid-report rate, and say so in the report.
    """
    invalid = _at_least(PHOTOS_TO_PASS, PHOTOS_PER_REPORT, fpr)
    missed = 1.0 - _at_least(PHOTOS_TO_PASS, PHOTOS_PER_REPORT, 1.0 - fnr)
    return invalid, missed


def metrics_at(rows: list[tuple[int, float]], threshold: float) -> dict[str, float]:
    tp = sum(1 for y, s in rows if y == 1 and s >= threshold)
    fp = sum(1 for y, s in rows if y == 0 and s >= threshold)
    fn = sum(1 for y, s in rows if y == 1 and s < threshold)
    tn = sum(1 for y, s in rows if y == 0 and s < threshold)

    precision = tp / (tp + fp) if (tp + fp) else 1.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

    fpr = fp / (fp + tn) if (fp + tn) else 0.0
    fnr = fn / (tp + fn) if (tp + fn) else 0.0
    invalid_report, missed_report = report_rates(fpr, fnr)

    return {
        "threshold": threshold,
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "accuracy": (tp + tn) / len(rows),
        "fpr": fpr,
        "fnr": fnr,
        "invalid_report": invalid_report,
        "missed_report": missed_report,
    }


def sweep(rows: list[tuple[int, float]], steps: int = 99) -> list[dict[str, float]]:
    return [metrics_at(rows, i / (steps + 1)) for i in range(1, steps + 1)]


def choose(
    results: list[dict[str, float]], target_precision: float
) -> tuple[dict[str, float] | None, dict[str, float]]:
    """Lowest threshold meeting the precision target, plus the best-F1 point.

    The LOWEST qualifying threshold is chosen deliberately: among the points
    that satisfy the precision requirement, it is the one that rejects the
    fewest genuine reports.
    """
    qualifying = [r for r in results if r["precision"] >= target_precision and r["tp"] > 0]
    best_recall = max(qualifying, key=lambda r: (r["recall"], -r["threshold"])) if qualifying else None
    best_f1 = max(results, key=lambda r: r["f1"])
    return best_recall, best_f1


def warn_if_test_split(path: Path) -> None:
    """Refuse to quietly select a threshold on a file that looks like test.

    This is the mistake the split discipline in the module docstring exists to
    prevent, and it is invisible in the output once made: the sweep prints a
    perfectly ordinary table either way.
    """
    if "test" not in path.name.lower():
        return

    print("!" * 62)
    print("  These look like TEST scores, and this is the SELECTION mode.")
    print()
    print("  Choosing the operating point here and then reporting test")
    print("  metrics at it fits the threshold to the images the result is")
    print("  claimed on. Select on validation instead:")
    print()
    print("    python ml/score_split.py val")
    print("    python ml/select_threshold.py ml/artifacts/val_scores_backend.csv")
    print()
    print("  To report test metrics at an already-frozen threshold, pass")
    print("  --at-threshold <value> instead of sweeping.")
    print("!" * 62)
    print()


def report_at(rows: list[tuple[int, float]], threshold: float) -> int:
    """Print the metrics at a threshold chosen elsewhere. No selection here."""
    if not 0.0 < threshold < 1.0:
        sys.exit(f"--at-threshold must be between 0 and 1, got {threshold}.")

    m = metrics_at(rows, threshold)

    precision_lo, precision_hi = wilson_interval(m["tp"], m["tp"] + m["fp"])
    recall_lo, recall_hi = wilson_interval(m["tp"], m["tp"] + m["fn"])

    print("=" * 62)
    print(f"  METRICS AT THE FROZEN THRESHOLD: {threshold:.4f}")
    print("=" * 62)
    print(f"  Precision {m['precision']:.3f}   95% CI "
          f"[{precision_lo:.3f}, {precision_hi:.3f}]")
    print(f"  Recall    {m['recall']:.3f}   95% CI "
          f"[{recall_lo:.3f}, {recall_hi:.3f}]")
    print(f"  F1        {m['f1']:.3f}")
    print(f"  Accuracy  {m['accuracy']:.3f}")
    print(f"  Confusion  TP {m['tp']}  FP {m['fp']}  "
          f"FN {m['fn']}  TN {m['tn']}")
    print()
    print(f"  At the report level ({PHOTOS_PER_REPORT} photographs, "
          f"{PHOTOS_TO_PASS} needed to pass):")
    print(f"    {m['invalid_report'] * 100:.2f}% of invalid reports reach enforcement")
    print(f"    {m['missed_report'] * 100:.3f}% of genuine reports wrongly rejected")
    stricter = _at_least(2, PHOTOS_PER_REPORT, m["fpr"])
    stricter_missed = 1.0 - _at_least(2, PHOTOS_PER_REPORT, 1.0 - m["fnr"])
    print(f"    requiring 2 of {PHOTOS_PER_REPORT} instead: "
          f"{stricter * 100:.2f}% invalid ({stricter_missed * 100:.3f}% genuine rejected)")
    print()
    print("Report it as a sentence, with the threshold and the split named:")
    print(f"  \"At a threshold of {threshold:.2f}, selected on the validation")
    print(f"  split, the classifier reached precision {m['precision']:.3f} and "
          f"recall {m['recall']:.3f}")
    print(f"  on the held-out test split ({len(rows)} images), with a 95%")
    print(f"  confidence interval on precision of "
          f"[{precision_lo:.3f}, {precision_hi:.3f}].\"")
    print()
    print("Quote the interval, not just the point estimate. With "
          f"{m['fp'] + m['tn']} non-positive images,")
    print(f"the difference between {m['fp']} false positives and "
          f"{m['fp'] + 2} is a couple of photographs —")
    print("and averaging over training seeds does not shrink that; only more test")
    print("data does.")
    print()
    print("Do not tune the threshold against these numbers. If it is changed "
          "after seeing them,")
    print("the test split has been spent and the figure is no longer "
          "independent.")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("scores", type=Path, nargs="?",
                        default=Path("ml/artifacts/val_scores_backend.csv"))
    parser.add_argument("--target-precision", type=float,
                        default=DEFAULT_TARGET_PRECISION)
    parser.add_argument("--at-threshold", type=float, default=None,
                        help="Report metrics at this frozen threshold instead "
                             "of selecting one. Use on the test split, with "
                             "the value chosen on validation.")
    args = parser.parse_args()

    rows = load_scores(args.scores)

    positives = sum(y for y, _ in rows)
    print(f"{args.scores.name}: {len(rows)} images "
          f"({positives} smoking, {len(rows) - positives} not smoking)\n")

    if args.at_threshold is not None:
        return report_at(rows, args.at_threshold)

    warn_if_test_split(args.scores)

    results = sweep(rows)
    chosen, best_f1 = choose(results, args.target_precision)

    print("Threshold sweep")
    print(f"{'thresh':>7} {'prec':>7} {'recall':>7} {'F1':>7} "
          f"{'TP':>5} {'FP':>5} {'FN':>5} {'TN':>5} {'bad rpt':>9}")
    for r in results:
        if round(r["threshold"] * 100) % 5:
            continue
        print(f"{r['threshold']:>7.2f} {r['precision']:>7.3f} {r['recall']:>7.3f} "
              f"{r['f1']:>7.3f} {r['tp']:>5} {r['fp']:>5} {r['fn']:>5} {r['tn']:>5} "
              f"{r['invalid_report'] * 100:>8.2f}%")
    print()
    print(f"'bad rpt' is the share of invalid {PHOTOS_PER_REPORT}-photo reports that would")
    print(f"reach enforcement, given that {PHOTOS_TO_PASS} clearing photo(s) accepts a report.")
    print("It is the number the operating point should be judged on — not per-photo")
    print("precision — and it assumes the photographs fail independently, which they")
    print("do not entirely, so it is a LOWER bound.")

    print()
    print(f"Best F1 (NOT the recommendation): threshold {best_f1['threshold']:.2f}, "
          f"precision {best_f1['precision']:.3f}, recall {best_f1['recall']:.3f}")

    print()
    if chosen is None:
        print(f"NO threshold reaches precision >= {args.target_precision:.2f}.")
        print()
        print("This means the model cannot yet be trusted to accept reports "
              "without a human check. Options, in order of preference:")
        print("  1. Improve the model — more training data, especially HARD "
              "negatives (phones, drinks, inhalers held near the face).")
        print("  2. Lower the target precision, and record in the report that "
              "a known share of accepted reports will be invalid.")
        print("  3. Reintroduce a human check — but that contradicts the "
              "read-only administrator design and would need Chapter 4 revised.")
        return 1

    print("=" * 62)
    print(f"  RECOMMENDED THRESHOLD: {chosen['threshold']:.4f}")
    print("=" * 62)
    print(f"  Precision {chosen['precision']:.3f}  — of accepted reports, "
          f"{chosen['precision'] * 100:.1f}% are genuine")
    print(f"  Recall    {chosen['recall']:.3f}  — of genuine violations, "
          f"{chosen['recall'] * 100:.1f}% are accepted first time")
    print(f"  F1        {chosen['f1']:.3f}")
    print(f"  Confusion  TP {chosen['tp']}  FP {chosen['fp']}  "
          f"FN {chosen['fn']}  TN {chosen['tn']}")
    print()
    print(f"  {chosen['fp']} invalid photo(s) accepted, {chosen['fn']} genuine "
          f"photo(s) rejected.")
    print()
    print(f"  At the report level, with {PHOTOS_PER_REPORT} photographs and "
          f"{PHOTOS_TO_PASS} needed to pass:")
    print(f"    {chosen['invalid_report'] * 100:.2f}% of invalid reports would "
          f"reach enforcement")
    print(f"    {chosen['missed_report'] * 100:.3f}% of genuine reports would be "
          f"wrongly rejected")

    # The alternative rule from NEXT-STEPS §6, priced at the same threshold: it
    # costs no model change and is usually the cheapest precision available.
    stricter = _at_least(2, PHOTOS_PER_REPORT, chosen["fpr"])
    stricter_missed = 1.0 - _at_least(2, PHOTOS_PER_REPORT, 1.0 - chosen["fnr"])
    if PHOTOS_TO_PASS == 1:
        print()
        print("  For comparison, requiring 2 of 3 photographs instead of 1:")
        print(f"    {stricter * 100:.2f}% invalid reports accepted "
              f"({stricter_missed * 100:.3f}% genuine rejected)")
        print("  No model change and no retraining — only the §8 rule.")
    print()
    print("Set this in backend/.env, then restart the backend:")
    print(f"  AI_CONFIDENCE_THRESHOLD={chosen['threshold']:.4f}")
    print()
    print("The threshold is read per request, so it can be retuned later "
          "without rebuilding the mobile app — which is what §S10 requires.")
    print()
    print("This threshold is now FROZEN. Report on the test split at it:")
    print("  python ml/score_split.py test")
    print(f"  python ml/select_threshold.py ml/artifacts/test_scores_backend.csv "
          f"--at-threshold {chosen['threshold']:.4f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Choose the confidence threshold from evaluation results.

    python ml/select_threshold.py ml/artifacts/test_scores.csv

Input CSV needs two columns:
    label   — "smoking" or "notsmoking" (the ground truth)
    score   — the model's P(smoking), 0.0 to 1.0

The training notebook writes this file for the held-out TEST split.

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
# Raise it if a false report reaching enforcement is judged more costly.
DEFAULT_TARGET_PRECISION = 0.95


def load_scores(path: Path) -> list[tuple[int, float]]:
    if not path.exists():
        sys.exit(
            f"No scores file at {path}\n"
            "Run the evaluation cell in ml/notebooks/finetune_vit.ipynb first."
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

    return rows


def metrics_at(rows: list[tuple[int, float]], threshold: float) -> dict[str, float]:
    tp = sum(1 for y, s in rows if y == 1 and s >= threshold)
    fp = sum(1 for y, s in rows if y == 0 and s >= threshold)
    fn = sum(1 for y, s in rows if y == 1 and s < threshold)
    tn = sum(1 for y, s in rows if y == 0 and s < threshold)

    precision = tp / (tp + fp) if (tp + fp) else 1.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

    return {
        "threshold": threshold,
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "accuracy": (tp + tn) / len(rows),
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scores", type=Path, nargs="?",
                        default=Path("ml/artifacts/test_scores.csv"))
    parser.add_argument("--target-precision", type=float,
                        default=DEFAULT_TARGET_PRECISION)
    args = parser.parse_args()

    rows = load_scores(args.scores)
    results = sweep(rows)
    chosen, best_f1 = choose(results, args.target_precision)

    positives = sum(y for y, _ in rows)
    print(f"Test set: {len(rows)} images "
          f"({positives} smoking, {len(rows) - positives} not smoking)\n")

    print("Threshold sweep")
    print(f"{'thresh':>7} {'prec':>7} {'recall':>7} {'F1':>7} "
          f"{'TP':>5} {'FP':>5} {'FN':>5} {'TN':>5}")
    for r in results:
        if round(r["threshold"] * 100) % 5:
            continue
        print(f"{r['threshold']:>7.2f} {r['precision']:>7.3f} {r['recall']:>7.3f} "
              f"{r['f1']:>7.3f} {r['tp']:>5} {r['fp']:>5} {r['fn']:>5} {r['tn']:>5}")

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
    print(f"  {chosen['fp']} invalid report(s) would reach enforcement.")
    print(f"  {chosen['fn']} genuine report(s) would be asked to retake.")
    print()
    print("Set this in backend/.env, then restart the backend:")
    print(f"  AI_CONFIDENCE_THRESHOLD={chosen['threshold']:.4f}")
    print()
    print("The threshold is read per request, so it can be retuned later "
          "without rebuilding the mobile app — which is what §S10 requires.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

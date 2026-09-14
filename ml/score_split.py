"""Score one dataset split through the BACKEND's own inference code.

    ./backend/.venv/bin/python ml/score_split.py val
    ./backend/.venv/bin/python ml/score_split.py test

Writes `ml/artifacts/<split>_scores_backend.csv` with the columns
`select_threshold.py` expects — `label` and `score` — plus `path`, so an
individual score can be traced back to the photograph that produced it.

WHY NOT JUST USE THE NOTEBOOK'S SCORES
--------------------------------------
The notebook decodes and resizes inside `tf.data`; the backend decodes and
resizes in `app.services.inference._preprocess`. Those agreed to within
rounding, but an earlier PIL-based preprocessing in the backend shifted
individual scores by up to 0.46 against the notebook. A threshold selected on
notebook scores is a threshold for a pipeline that never serves a request.

So this script imports the backend service and calls `score_images` — the same
function `classify_photos` calls at S10. If preprocessing there ever changes,
these CSVs change with it and the threshold is re-selected against reality
rather than silently going stale.

THE SPLIT DISCIPLINE THIS SCRIPT EXISTS TO SUPPORT
--------------------------------------------------
    1. score the VAL split       -> val_scores_backend.csv
    2. select_threshold.py on it -> a threshold, now frozen
    3. score the TEST split      -> test_scores_backend.csv
    4. select_threshold.py --at-threshold <frozen> on it -> the reported figure

Steps 1-2 and 3-4 must stay in that order. Choosing the operating point on the
test split and then reporting test metrics at that point fits the threshold to
the same 293 images the result is claimed on, which biases the reported
precision upward. See ml/NEXT-STEPS.md section 1.
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
ROOT = ML_DIR.parent
MANIFEST = ML_DIR / "data" / "manifest.csv"
ARTIFACTS = ML_DIR / "artifacts"
DEFAULT_MODEL = ARTIFACTS / "vit-scope-v1.keras"

BATCH_SIZE = 16


def load_manifest_rows(split: str) -> list[dict[str, str]]:
    if not MANIFEST.exists():
        sys.exit(
            f"No manifest at {MANIFEST}\n"
            "Build the dataset first:  python ml/prepare_dataset.py"
        )

    with MANIFEST.open() as handle:
        rows = [r for r in csv.DictReader(handle) if r["split"] == split]

    if not rows:
        sys.exit(f"No rows with split == {split!r} in {MANIFEST}.")

    labels = {r["label"] for r in rows}
    if len(labels) < 2:
        sys.exit(
            f"The {split} split contains only {labels}. Both classes are needed "
            "for the scores to be usable."
        )

    return rows


def import_backend(model: Path):
    """Import the backend inference service, pointed at `model`.

    The environment is set before the import because `app.config.get_settings`
    is `lru_cache`d and `inference` reads it at module scope — setting these
    afterwards would have no effect.
    """
    sys.path.insert(0, str(ROOT / "backend"))

    os.environ["AI_MODEL_PATH"] = str(model)
    # A stub score is a hash of the image bytes. Selecting a threshold on those
    # would produce a confident-looking number that means nothing at all, so
    # refuse rather than let it happen quietly.
    os.environ["AI_STUB_MODE"] = "false"

    try:
        from app.services import inference
    except ImportError as exc:
        sys.exit(
            f"Could not import the backend service ({exc}).\n"
            "Run this with the backend's interpreter, from the repository root:\n"
            "  ./backend/.venv/bin/python ml/score_split.py val"
        )

    if inference.settings.ai_stub_mode:
        sys.exit("AI_STUB_MODE is on. Stub scores must never reach a threshold.")
    if not inference.is_available():
        sys.exit(
            f"No model at {inference.model_path()}\n"
            "Train one with ml/notebooks/finetune_vit.ipynb, or pass --model."
        )

    return inference


def score_rows(inference, rows: list[dict[str, str]]) -> list[float]:
    scores: list[float] = []

    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start : start + BATCH_SIZE]
        images = [(ML_DIR / r["path"]).read_bytes() for r in batch]
        scores.extend(inference.score_images(images))
        print(f"  scored {len(scores)}/{len(rows)}", end="\r", flush=True)

    print()
    return scores


def write_scores(split: str, rows: list[dict[str, str]], scores: list[float]) -> Path:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    out = ARTIFACTS / f"{split}_scores_backend.csv"

    with out.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["path", "label", "score"])
        for row, score in zip(rows, scores, strict=True):
            writer.writerow([row["path"], row["label"], f"{score:.6f}"])

    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("split", choices=("val", "test", "train"))
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL,
                        help=f"Model to score with (default: {DEFAULT_MODEL})")
    args = parser.parse_args()

    rows = load_manifest_rows(args.split)
    inference = import_backend(args.model.resolve())

    positives = sum(1 for r in rows if r["label"] == "smoking")
    print(f"Scoring the {args.split} split: {len(rows)} images "
          f"({positives} smoking, {len(rows) - positives} not smoking)")
    print(f"Model: {inference.model_path()}")
    print(f"Version: {inference.settings.ai_model_version}\n")

    scores = score_rows(inference, rows)
    out = write_scores(args.split, rows, scores)

    smoking = [s for r, s in zip(rows, scores) if r["label"] == "smoking"]
    other = [s for r, s in zip(rows, scores) if r["label"] != "smoking"]
    gap = sum(smoking) / len(smoking) - sum(other) / len(other)

    print(f"Wrote {out}")
    print(f"Mean score  smoking {sum(smoking) / len(smoking):.3f}   "
          f"notsmoking {sum(other) / len(other):.3f}   gap {gap:.3f}")
    if gap <= 0.3:
        print("WEAK separation — the sweep will have little to work with.")

    print()
    if args.split == "val":
        print("Next: select the threshold on these scores, then freeze it.")
        print(f"  python ml/select_threshold.py {out}")
    elif args.split == "test":
        print("Next: report at the threshold frozen on validation — do not "
              "re-select it here.")
        print(f"  python ml/select_threshold.py {out} --at-threshold <frozen>")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Turn raw downloaded images into a clean, split, manifested dataset.

    python ml/prepare_dataset.py

Reads:   ml/data/raw/<class>/*.{jpg,jpeg,png,webp}
Writes:  ml/data/manifest.csv   — one row per kept image, with its split
         ml/data/report.md      — composition table for Chapter 5

WHY THIS SCRIPT EXISTS
----------------------
Two mistakes are very easy to make when assembling an image dataset by
downloading folders, and both inflate reported accuracy in ways that are hard
to spot afterwards and embarrassing to have pointed out at viva.

1. DUPLICATES. Web-scraped image sets routinely contain the same photograph
   more than once, sometimes resized or re-encoded. If a duplicate lands in
   train and its twin lands in test, the model is being tested on an image it
   memorised. This script detects duplicates by perceptual hash — which
   survives resizing and re-encoding, unlike a byte hash — and keeps only one
   copy of each.

2. LEAKAGE THROUGH NEAR-DUPLICATES. Even after de-duplication, burst shots of
   the same scene are near-identical. This script groups images by perceptual
   hash and assigns each GROUP to exactly one split, so visually identical
   frames can never straddle the train/test boundary.

The split is also STRATIFIED: each class keeps its proportion across train,
validation and test, so the test set does not drift toward one class.

Splitting happens BEFORE any augmentation. Augmenting first and splitting
afterwards would scatter variants of one source image across all three splits,
which is the same leakage in a less obvious form.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import random
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required:  pip install Pillow")

ROOT = Path(__file__).resolve().parent
RAW_DIR = ROOT / "data" / "raw"
MANIFEST = ROOT / "data" / "manifest.csv"
REPORT = ROOT / "data" / "report.md"

EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

# The two classes. Folder names under data/raw/ must match these exactly.
CLASSES = ("smoking", "notsmoking")

SPLITS = ("train", "val", "test")
DEFAULT_RATIOS = (0.70, 0.15, 0.15)

# Seeded so the split is reproducible: rerunning must produce the same
# assignment, or a reported test accuracy cannot be checked by anyone else.
SEED = 20260813


@dataclass
class ImageRecord:
    path: Path
    label: str
    phash: str
    width: int
    height: int


def perceptual_hash(path: Path, size: int = 8) -> str | None:
    """Difference hash: robust to resizing, re-encoding and small edits.

    The image is reduced to a tiny greyscale thumbnail and each pixel compared
    with its right-hand neighbour. Two images that differ only by compression
    or scale produce the same hash; genuinely different photographs do not.
    """
    try:
        with Image.open(path) as img:
            img = img.convert("L").resize((size + 1, size), Image.Resampling.LANCZOS)
            # tobytes() on mode "L" is one byte per pixel, row-major — the same
            # values getdata() returns, without its deprecation.
            pixels = list(img.tobytes())
    except Exception:
        return None

    bits = []
    for row in range(size):
        offset = row * (size + 1)
        for col in range(size):
            bits.append("1" if pixels[offset + col] > pixels[offset + col + 1] else "0")

    return f"{int(''.join(bits), 2):016x}"


def load_images() -> tuple[list[ImageRecord], dict[str, int]]:
    records: list[ImageRecord] = []
    skipped: dict[str, int] = defaultdict(int)

    for label in CLASSES:
        folder = RAW_DIR / label
        if not folder.is_dir():
            sys.exit(
                f"Missing folder: {folder}\n"
                f"Expected layout:\n"
                f"  ml/data/raw/smoking/*.jpg\n"
                f"  ml/data/raw/notsmoking/*.jpg"
            )

        for path in sorted(folder.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in EXTENSIONS:
                continue

            digest = perceptual_hash(path)
            if digest is None:
                skipped["unreadable"] += 1
                continue

            try:
                with Image.open(path) as img:
                    width, height = img.size
            except Exception:
                skipped["unreadable"] += 1
                continue

            # Thumbnails and icons are not usable evidence photographs and
            # only teach the model artefacts of upscaling.
            if width < 64 or height < 64:
                skipped["too_small"] += 1
                continue

            records.append(ImageRecord(path, label, digest, width, height))

    return records, dict(skipped)


def group_by_hash(records: list[ImageRecord]) -> dict[str, list[ImageRecord]]:
    groups: dict[str, list[ImageRecord]] = defaultdict(list)
    for record in records:
        groups[record.phash].append(record)
    return groups


def load_frozen_splits() -> dict[str, str]:
    """{phash: split} from the current manifest, for --keep-split."""
    if not MANIFEST.exists():
        sys.exit(
            f"--keep-split needs the existing manifest at {MANIFEST}.\n"
            "It keeps every image already in that manifest in its current "
            "split, so there has to be one to keep."
        )
    with MANIFEST.open() as handle:
        return {row["phash"]: row["split"] for row in csv.DictReader(handle)}


def assign_splits(
    groups: dict[str, list[ImageRecord]],
    ratios: tuple[float, float, float],
    frozen: dict[str, str] | None = None,
) -> dict[str, str]:
    """Assign each hash group to one split, stratified by class.

    Returns {phash: split}. Because the unit of assignment is the GROUP, not
    the image, near-identical frames always land together.

    Groups found in `frozen` keep the split they already had; only the rest
    are shuffled and divided. Without this, adding a single image changes the
    shuffle order and moves many existing images between splits, so a new
    model could no longer be compared with the old one on the same test set.
    """
    rng = random.Random(SEED)
    frozen = frozen or {}

    # A group's class is the class of its members. In the rare case a
    # duplicate appears under both labels the group is dropped entirely — it is
    # a labelling contradiction and training on it teaches noise.
    by_class: dict[str, list[str]] = defaultdict(list)
    conflicted: list[str] = []
    kept: dict[str, str] = {}

    for phash, members in groups.items():
        labels = {m.label for m in members}
        if len(labels) > 1:
            conflicted.append(phash)
            continue
        if phash in frozen:
            kept[phash] = frozen[phash]
            continue
        by_class[labels.pop()].append(phash)

    assignment: dict[str, str] = dict(kept)
    for phash in conflicted:
        assignment[phash] = "conflict"

    for label, hashes in by_class.items():
        hashes.sort()  # deterministic before shuffling
        rng.shuffle(hashes)

        total = len(hashes)
        n_train = int(total * ratios[0])
        n_val = int(total * ratios[1])

        for index, phash in enumerate(hashes):
            if index < n_train:
                assignment[phash] = "train"
            elif index < n_train + n_val:
                assignment[phash] = "val"
            else:
                assignment[phash] = "test"

    return assignment


def write_manifest(
    groups: dict[str, list[ImageRecord]], assignment: dict[str, str]
) -> list[dict[str, str]]:
    """Write one row per KEPT image — the first member of each group."""
    rows: list[dict[str, str]] = []

    for phash, members in sorted(groups.items()):
        split = assignment.get(phash, "conflict")
        if split == "conflict":
            continue

        keeper = sorted(members, key=lambda m: str(m.path))[0]
        rows.append(
            {
                "path": str(keeper.path.relative_to(ROOT)),
                "label": keeper.label,
                "split": split,
                "phash": phash,
                "width": str(keeper.width),
                "height": str(keeper.height),
                "duplicates_removed": str(len(members) - 1),
            }
        )

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else
                                ["path", "label", "split", "phash", "width",
                                 "height", "duplicates_removed"])
        writer.writeheader()
        writer.writerows(rows)

    return rows


def write_report(
    rows: list[dict[str, str]],
    raw_count: int,
    skipped: dict[str, int],
    conflicts: int,
    duplicates: int,
) -> str:
    counts: dict[tuple[str, str], int] = defaultdict(int)
    for row in rows:
        counts[(row["split"], row["label"])] += 1

    lines = [
        "# Dataset composition",
        "",
        "Generated by `ml/prepare_dataset.py`. Paste into Chapter 5.",
        "",
        "## Splits",
        "",
        "| Split | " + " | ".join(CLASSES) + " | Total |",
        "|---|" + "---|" * (len(CLASSES) + 1),
    ]

    for split in SPLITS:
        per_class = [counts[(split, label)] for label in CLASSES]
        lines.append(
            f"| {split} | " + " | ".join(str(n) for n in per_class) +
            f" | {sum(per_class)} |"
        )

    totals = [sum(counts[(s, label)] for s in SPLITS) for label in CLASSES]
    lines += [
        "| **Total** | " + " | ".join(f"**{n}**" for n in totals) +
        f" | **{sum(totals)}** |",
        "",
        "## Cleaning",
        "",
        f"- Images found in `data/raw/`: **{raw_count}**",
        f"- Duplicates removed (perceptual hash): **{duplicates}**",
        f"- Dropped, labelled as both classes: **{conflicts}**",
    ]
    for reason, count in sorted(skipped.items()):
        lines.append(f"- Skipped, {reason.replace('_', ' ')}: **{count}**")

    lines += [
        f"- Images kept: **{len(rows)}**",
        "",
        "## Method",
        "",
        "Images were de-duplicated by difference hash, which is robust to "
        "resizing and re-encoding. Each hash group was assigned to exactly one "
        "split, so visually identical frames cannot appear in both training and "
        "test data. The split is stratified by class and seeded, making it "
        "reproducible. Splitting was performed before augmentation.",
        "",
    ]

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=float, default=DEFAULT_RATIOS[0])
    parser.add_argument("--val", type=float, default=DEFAULT_RATIOS[1])
    parser.add_argument(
        "--keep-split", action="store_true",
        help="Keep every image already in manifest.csv in its current split "
             "and split only the newly added images. Use when adding data to "
             "an existing dataset, so models stay comparable on one test set.",
    )
    args = parser.parse_args()

    ratios = (args.train, args.val, 1.0 - args.train - args.val)
    if min(ratios) <= 0:
        sys.exit("Split ratios must each be greater than zero.")

    print(f"Reading {RAW_DIR}…")
    records, skipped = load_images()
    if not records:
        sys.exit("No usable images found.")

    groups = group_by_hash(records)
    duplicates = len(records) - len(groups)

    frozen = load_frozen_splits() if args.keep_split else None
    assignment = assign_splits(groups, ratios, frozen)
    conflicts = sum(1 for v in assignment.values() if v == "conflict")

    if frozen is not None:
        kept = sum(1 for phash in groups if phash in frozen)
        added: dict[str, int] = defaultdict(int)
        for phash, split in assignment.items():
            if phash not in frozen and split != "conflict":
                added[split] += 1
        missing = len(set(frozen) - set(groups))
        print(f"--keep-split: {kept} images kept in their existing split; "
              f"new images added to train {added['train']}, "
              f"val {added['val']}, test {added['test']}.")
        if missing:
            print(f"WARNING: {missing} images in the old manifest are no longer "
                  "in data/raw/ and have been dropped.")

    rows = write_manifest(groups, assignment)
    report = write_report(rows, len(records), skipped, conflicts, duplicates)

    print()
    print(report)
    print(f"Manifest: {MANIFEST}")
    print(f"Report:   {REPORT}")

    # A class imbalance beyond about 60/40 will bias the model and needs to be
    # addressed by collecting more of the minority class or weighting the loss.
    per_class = [sum(1 for r in rows if r["label"] == label) for label in CLASSES]
    if per_class and min(per_class) and max(per_class) / min(per_class) > 1.5:
        print()
        print(
            f"WARNING: classes are imbalanced ({dict(zip(CLASSES, per_class))}). "
            "Collect more of the smaller class, or weight the loss during training."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

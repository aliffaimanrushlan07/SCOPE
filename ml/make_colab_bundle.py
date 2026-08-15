"""Package the prepared dataset into a small zip for Colab.

    python ml/make_colab_bundle.py

Reads:   ml/data/manifest.csv  (written by prepare_dataset.py)
Writes:  ml/data/scope-data.zip

WHY RESIZE BEFORE UPLOADING
---------------------------
The model resizes every image to 224x224 as its first step, so uploading
photographs at full camera resolution sends megabytes that are thrown away on
arrival. Shrinking the long side to 256 px first — still larger than the model
needs, leaving headroom for augmentation crops — cuts the upload by roughly an
order of magnitude and changes nothing the model ever sees.

The zip mirrors the `ml/` layout, so unzipping it to /content/ml in Colab makes
the notebook's paths resolve without modification.
"""

from __future__ import annotations

import csv
import shutil
import sys
import zipfile
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("Pillow is required:  pip install Pillow")

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "data" / "manifest.csv"
STAGE = ROOT / "data" / "_bundle"
ARCHIVE = ROOT / "data" / "scope-data.zip"

# Comfortably above the model's 224 px input, so augmentation has room to crop
# without upscaling.
LONG_SIDE = 256
JPEG_QUALITY = 90


def main() -> int:
    if not MANIFEST.exists():
        sys.exit(f"No manifest at {MANIFEST}\nRun: python ml/prepare_dataset.py")

    rows = list(csv.DictReader(MANIFEST.open()))
    if not rows:
        sys.exit("Manifest is empty.")

    if STAGE.exists():
        shutil.rmtree(STAGE)
    (STAGE / "data" / "images").mkdir(parents=True)

    out_rows: list[dict[str, str]] = []
    skipped = 0
    original_bytes = 0
    resized_bytes = 0

    for index, row in enumerate(rows, start=1):
        source = ROOT / row["path"]
        if not source.exists():
            skipped += 1
            continue

        label = row["label"]
        target_dir = STAGE / "data" / "images" / label
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{source.stem}.jpg"

        try:
            with Image.open(source) as img:
                # Honour EXIF orientation, or a phone photo saved sideways
                # trains the model on a rotation the viewer never sees.
                img = ImageOps.exif_transpose(img)
                img = img.convert("RGB")
                img.thumbnail((LONG_SIDE, LONG_SIDE), Image.Resampling.LANCZOS)
                img.save(target, "JPEG", quality=JPEG_QUALITY, optimize=True)
        except Exception:
            skipped += 1
            continue

        original_bytes += source.stat().st_size
        resized_bytes += target.stat().st_size

        out_rows.append(
            {
                # Relative to the unzip root, matching the notebook's ML_DIR.
                "path": f"data/images/{label}/{target.name}",
                "label": label,
                "split": row["split"],
                "phash": row["phash"],
            }
        )

        if index % 250 == 0:
            print(f"  {index}/{len(rows)} processed…")

    manifest_out = STAGE / "data" / "manifest.csv"
    with manifest_out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["path", "label", "split", "phash"])
        writer.writeheader()
        writer.writerows(out_rows)

    print(f"Writing {ARCHIVE.name}…")
    if ARCHIVE.exists():
        ARCHIVE.unlink()
    with zipfile.ZipFile(ARCHIVE, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(STAGE.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(STAGE))

    shutil.rmtree(STAGE)

    mb = lambda n: n / (1024 * 1024)
    print()
    print(f"Images bundled : {len(out_rows)}")
    if skipped:
        print(f"Skipped        : {skipped}")
    print(f"Original size  : {mb(original_bytes):.0f} MB")
    print(f"Resized size   : {mb(resized_bytes):.0f} MB")
    print(f"Zip            : {mb(ARCHIVE.stat().st_size):.0f} MB  ->  {ARCHIVE}")

    counts: dict[tuple[str, str], int] = {}
    for row in out_rows:
        key = (row["split"], row["label"])
        counts[key] = counts.get(key, 0) + 1
    print()
    for split in ("train", "val", "test"):
        parts = [f"{label} {counts.get((split, label), 0)}"
                 for label in ("smoking", "notsmoking")]
        print(f"  {split:<6} " + "  ".join(parts))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

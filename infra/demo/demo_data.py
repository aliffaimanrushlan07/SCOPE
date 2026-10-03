"""Simulated demonstration data for the admin dashboard (D02 / D03 / D04).

DEVELOPMENT AND PRESENTATION ONLY. Everything this script writes is simulated:
it exists so the Overview trend, Top hotspot locations and patrol-timing panels
have something meaningful to show from June to October. It is not field data
and must never be reported as such.

What it writes
--------------
Reports at nine real restaurants with outdoor dining in Bukit Bintang, Bandar
Tun Razak / Bandar Sri Permaisuri and Taman Shamelin / Pudu Ulu, following a
steady adoption curve:

    Jun ~35 -> Jul ~50 -> Aug ~65 -> Sep ~85 -> Oct (in proportion, to --until)

Genuine reports already in the database count toward those totals, week by
week, so the demo rows fill in around them rather than stacking on top.

Each restaurant has its own day-and-time pattern (a hawker street peaking on
Friday and Saturday nights, a nasi kandar at weekday lunch, a bar after
midnight at the weekend), which is what the patrol-timing heatmap shows.

Every row is internally consistent with the real pipeline:

- 1-3 photographs per report, each one scored by the real vit-scope-v3 model
  through the backend's own `score_images`, and only photographs that clear
  AI_CONFIDENCE_THRESHOLD and AI_MIN_SHARPNESS are used. The stored confidence
  scores are genuine model outputs, not invented numbers.
- `ai_classification` records the configured model version and threshold, and
  sometimes a dropped photograph (photos_evaluated > photos_passed), as S10
  allows.
- Reference numbers carry the report's own Malaysian date.
- `device_id` always starts with `demo-`, which is how `remove` finds them.

Real photographs (optional)
---------------------------
Put your own photographs in infra/demo/real-photos/ (git-ignored). Each one is
scored first; those that pass become photo 1 of the most recent report at the
busiest hotspots, in order — so they are the reports you open live in D05.
Photographs that do not pass are listed with their score and skipped.

Usage (run with the backend's virtualenv; the database must be up)
-----
    backend/.venv/bin/python infra/demo/demo_data.py plan   [--until 2026-10-19]
    backend/.venv/bin/python infra/demo/demo_data.py load   [--until 2026-10-19]
    backend/.venv/bin/python infra/demo/demo_data.py remove

`--until` is the last day (Malaysian time) that gets reports; it defaults to
yesterday, so nothing is dated in the future. `load` is repeatable: it removes
the previous demo rows first and writes the same data again for the same
--until. It also removes the rows left by docs/e2e_check.py (device_id
`e2e-…`), which would otherwise appear as a hotspot called
"E2E Test Food Court" — re-running that check adds them back.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import random
import shutil
import sys
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"
POOL_SOURCE = ROOT / "ml" / "data" / "raw" / "smoking"
POOL_CACHE = ROOT / "ml" / "artifacts" / "demo_photo_pool.csv"
REAL_PHOTOS = Path(__file__).resolve().parent / "real-photos"

# The backend resolves .env, UPLOAD_DIR and AI_MODEL_PATH relative to its own
# directory, so run from there whatever the caller's working directory is.
os.chdir(BACKEND)
sys.path.insert(0, str(BACKEND))

from sqlalchemy import delete, func, select  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.models import AIClassification, Report, ReportPhoto  # noqa: E402
from app.services import inference  # noqa: E402

settings = get_settings()
KL = ZoneInfo("Asia/Kuala_Lumpur")
DEMO_PREFIX = "demo-"
E2E_PREFIX = "e2e-"
SEED = 2026

START = dt.date(2026, 6, 1)
# Reports per full month. October is scaled by the share of it covered.
MONTH_TARGETS = {6: 35, 7: 50, 8: 65, 9: 85, 10: 100}

ALL = range(7)
WEEKDAYS = range(5)
FRI_SAT = (4, 5)
SAT_SUN = (5, 6)


@dataclass(frozen=True)
class Place:
    name: str
    address: str
    latitude: float
    longitude: float
    share: float
    # (days, block start hours, weight). Days: 0 = Monday. Hours are the start
    # of a two-hour block, Malaysian time, on that calendar day.
    pattern: tuple[tuple[tuple[int, ...], tuple[int, ...], float], ...]


# Coordinates and addresses from Google Places (the same lookup S11 uses).
# Each sits in its own three-decimal grid cell, so each is its own hotspot.
PLACES = (
    Place(
        "Wong Ah Wah Restaurant",
        "1, Jalan Alor, Bukit Bintang, 50200 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1449492, 101.7079835, 22,
        ((ALL, (18, 20, 22), 3), (FRI_SAT, (20, 22), 4), (SAT_SUN, (0,), 2), (ALL, (16,), 0.6)),
    ),
    Place(
        "Kapitan Tandoori House",
        "Jalan Tasik Permaisuri 2, Taman Tasik Permaisuri, 56000 Cheras, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.0997265, 101.7174686, 18,
        ((ALL, (20, 22), 2.5), (ALL, (0, 2), 1.5), (SAT_SUN, (0, 2), 1.5), (WEEKDAYS, (12,), 1)),
    ),
    Place(
        "Havana Bar & Grill",
        "2 & 4, Changkat Bukit Bintang, Bukit Bintang, 50200 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.14776, 101.7069067, 12,
        ((FRI_SAT, (22,), 5), (SAT_SUN, (0,), 5), (FRI_SAT, (20,), 2), ((0, 1, 2, 3), (20, 22), 1)),
    ),
    Place(
        "Nasi Kandar Stadium",
        "Stadium Bolasepak Kuala Lumpur, Jalan Yaacob Latif, Bandar Tun Razak, 56000 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.09996, 101.7221288, 12,
        ((WEEKDAYS, (12,), 5), (WEEKDAYS, (14,), 1.2), ((5,), (20,), 2.5), (ALL, (18,), 0.8)),
    ),
    Place(
        "Cu Cha Restaurant",
        "71 & 75, Jalan Alor, Bukit Bintang, 50200 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1461311, 101.7094409, 8,
        ((ALL, (18, 20), 2), (FRI_SAT, (20, 22), 2)),
    ),
    Place(
        "Bistro Mamak Bukit Bintang",
        "Jalan Bukit Bintang, Bukit Bintang, 50200 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1466798, 101.7105503, 8,
        ((ALL, (22,), 2), (ALL, (0, 2), 2), (SAT_SUN, (2,), 1.5)),
    ),
    Place(
        "Restoran Buddies",
        "11G, Lorong 6A/91, Taman Shamelin Perkasa, 56100 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1241007, 101.7378046, 7,
        ((WEEKDAYS, (12,), 3), (ALL, (18,), 2), (SAT_SUN, (10,), 1.5)),
    ),
    Place(
        "Restoran Dwitasik",
        "Jalan Dwitasik, Bandar Sri Permaisuri, 56000 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1008271, 101.7128673, 7,
        ((ALL, (6, 8), 3), (WEEKDAYS, (12,), 2), (SAT_SUN, (8, 10), 1.5)),
    ),
    Place(
        "Restoran Nikhman Bistro",
        "8, Jalan Pudu Ulu, Taman Pertama, 55300 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia",
        3.1227065, 101.7302442, 6,
        ((ALL, (20, 22), 2), (FRI_SAT, (22,), 2), (SAT_SUN, (0,), 1)),
    ),
)

# A little activity in every cell, so a heatmap is a pattern, not a stencil.
BACKGROUND = 0.05
# Weekends are busier everywhere; this shapes the adoption curve's weekly rhythm.
DAY_RHYTHM = (0.85, 0.85, 0.9, 0.95, 1.25, 1.35, 1.0)


def cell_weights(place: Place) -> list[list[float]]:
    weights = [[BACKGROUND] * 12 for _ in range(7)]
    for days, hours, weight in place.pattern:
        for day in days:
            for hour in hours:
                weights[day][hour // 2] += weight
    return weights


# ---------------------------------------------------------------------------
# Calendar: how many demo reports land in each week
# ---------------------------------------------------------------------------


def daily_expectation(until: dt.date) -> dict[dt.date, float]:
    """Expected reports per day, summing to each month's target.

    Within a month the expectation rises gently (adoption) and follows the
    weekly rhythm, so weekly bars climb rather than stepping once a month.
    """
    span = (dt.date(2026, 10, 31) - START).days
    raw: dict[dt.date, float] = {}
    day = START
    while day <= until:
        growth = 0.8 + 0.6 * (day - START).days / span
        raw[day] = growth * DAY_RHYTHM[day.weekday()]
        day += dt.timedelta(days=1)

    expected: dict[dt.date, float] = {}
    for month, target in MONTH_TARGETS.items():
        days = [d for d in raw if d.month == month]
        if not days:
            continue
        month_days = (dt.date(2026, month % 12 + 1, 1) - dt.date(2026, month, 1)).days
        covered = target * len(days) / month_days
        total = sum(raw[d] for d in days)
        for d in days:
            expected[d] = raw[d] / total * covered
    return expected


def segment(day: dt.date) -> tuple[dt.date, int]:
    """A week, split where it crosses a month boundary.

    Splitting keeps a busy end of one month from using up the quota for the
    first days of the next, so the monthly view holds the curve as well.
    """
    return day - dt.timedelta(days=day.weekday()), day.month


def genuine_by_segment(db) -> Counter:
    """Non-demo, non-e2e reports per Malaysian week segment, from START."""
    rows = db.scalars(
        select(Report.submitted_at).where(
            ~Report.device_id.startswith(DEMO_PREFIX),
            ~Report.device_id.startswith(E2E_PREFIX),
        )
    ).all()
    counts: Counter = Counter()
    for submitted in rows:
        local = submitted.astimezone(KL).date()
        if local >= START:
            counts[segment(local)] += 1
    return counts


def demo_quota(expected: dict[dt.date, float], genuine: Counter) -> dict[tuple, int]:
    """Demo reports per week segment: the curve minus the genuine reports in it."""
    target: dict[tuple, float] = defaultdict(float)
    for day, value in expected.items():
        target[segment(day)] += value

    quota: dict[tuple, int] = {}
    carry = 0.0
    for week in sorted(target):
        want = target[week] - genuine.get(week, 0) + carry
        quota[week] = max(0, round(want))
        # A week the genuine reports already overfill does not borrow from the
        # next one; that would dent the curve right after a busy week.
        carry = max(0.0, want - quota[week])
    return quota


# ---------------------------------------------------------------------------
# Photographs: only ones the real model accepts
# ---------------------------------------------------------------------------


def passes(score: float, sharp: float) -> bool:
    return score >= settings.ai_confidence_threshold and (
        settings.ai_min_sharpness <= 0 or sharp >= settings.ai_min_sharpness
    )


def score_files(paths: list[Path]) -> list[tuple[Path, float, float]]:
    results = []
    for start in range(0, len(paths), 16):
        batch = paths[start : start + 16]
        data = [p.read_bytes() for p in batch]
        scores = inference.score_images(data)
        for path, blob, score in zip(batch, data, scores, strict=True):
            results.append((path, round(score, 4), round(inference.sharpness(blob), 1)))
        print(f"  scored {min(start + 16, len(paths))}/{len(paths)}", end="\r", flush=True)
    print()
    return results


def photo_pool() -> list[tuple[Path, float]]:
    """Every dataset photograph the real model accepts, scored once and cached."""
    if not inference.is_available():
        sys.exit(f"No model at {inference.model_path()} — the pool must be scored by the real model.")

    model_version = settings.ai_model_version
    if POOL_CACHE.exists():
        with POOL_CACHE.open() as f:
            rows = list(csv.DictReader(f))
        if rows and rows[0]["model_version"] == model_version:
            return [
                (ROOT / r["path"], float(r["score"]))
                for r in rows
                if passes(float(r["score"]), float(r["sharpness"]))
            ]

    files = sorted(p for p in POOL_SOURCE.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"})
    print(f"Scoring {len(files)} photographs with {model_version} (one-off, cached)…")
    scored = score_files(files)
    POOL_CACHE.parent.mkdir(parents=True, exist_ok=True)
    with POOL_CACHE.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["path", "score", "sharpness", "model_version"])
        for path, score, sharp in scored:
            writer.writerow([path.relative_to(ROOT), score, sharp, model_version])
    return [(p, s) for p, s, sh in scored if passes(s, sh)]


def real_photos() -> list[tuple[Path, float]]:
    REAL_PHOTOS.mkdir(exist_ok=True)
    files = sorted(
        p for p in REAL_PHOTOS.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}
    )
    if not files:
        return []
    print(f"Scoring {len(files)} real photograph(s) in {REAL_PHOTOS.relative_to(ROOT)}:")
    accepted = []
    for path, score, sharp in score_files(files):
        ok = passes(score, sharp)
        reason = "" if ok else (
            "  <- below threshold, retake" if score < settings.ai_confidence_threshold
            else "  <- too blurry, retake"
        )
        print(f"  {'PASS' if ok else 'FAIL'}  {path.name}  confidence {score:.4f}  sharpness {sharp}{reason}")
        if ok:
            accepted.append((path, score))
    return accepted


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------


@dataclass
class Planned:
    place: Place
    reported_at: dt.datetime  # aware, UTC
    submitted_at: dt.datetime
    device_id: str
    photo_count: int
    dropped: int
    named: bool


def generate(quota: dict[tuple, int], until: dt.date) -> list[Planned]:
    rng = random.Random(SEED)
    expected = daily_expectation(until)
    places = list(PLACES)
    shares = [p.share for p in places]
    weights = {p.name: cell_weights(p) for p in places}

    total = sum(quota.values())
    devices = [f"{DEMO_PREFIX}{rng.getrandbits(64):016x}" for _ in range(max(1, int(total / 1.6)))]
    now = dt.datetime.now(dt.timezone.utc)

    planned: list[Planned] = []
    for (week, month), count in sorted(quota.items()):
        days = [week + dt.timedelta(days=i) for i in range(7)]
        days = [d for d in days if d in expected and d.month == month]
        for _ in range(count):
            place = rng.choices(places, shares)[0]
            grid = weights[place.name]
            cells = [(d, b) for d in days for b in range(12)]
            cell_w = [expected[d] * grid[d.weekday()][b] for d, b in cells]
            day, block = rng.choices(cells, cell_w)[0]

            local = dt.datetime(day.year, day.month, day.day, block * 2, tzinfo=KL) + dt.timedelta(
                seconds=rng.randrange(7200)
            )
            reported = local.astimezone(dt.timezone.utc)
            submitted = min(reported + dt.timedelta(minutes=rng.uniform(2, 35)), now)

            photo_count = rng.choices((1, 2, 3), (0.6, 0.28, 0.12))[0]
            dropped = 1 if photo_count < 3 and rng.random() < 0.2 else 0
            planned.append(
                Planned(place, reported, submitted, rng.choice(devices), photo_count, dropped,
                        named=rng.random() < 0.82)
            )
    planned.sort(key=lambda p: p.submitted_at)
    return planned


def reference_no(rng: random.Random, submitted: dt.datetime, taken: set[str]) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    date = submitted.astimezone(KL).strftime("%Y%m%d")
    while True:
        candidate = f"SCP-{date}-{''.join(rng.choice(alphabet) for _ in range(4))}"
        if candidate not in taken:
            taken.add(candidate)
            return candidate


def jitter(rng: random.Random, value: float, metres: float) -> Decimal:
    return Decimal(f"{value + rng.uniform(-metres, metres) / 111_000:.6f}")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def remove_rows(db, prefix: str) -> int:
    ids = db.scalars(select(Report.report_id).where(Report.device_id.startswith(prefix))).all()
    if ids:
        db.execute(delete(Report).where(Report.report_id.in_(ids)))
    for report_id in ids:
        shutil.rmtree(settings.reports_path / str(report_id), ignore_errors=True)
    return len(ids)


def summarise(planned: list[Planned], genuine: Counter, db) -> None:
    genuine_month: Counter = Counter()
    rows = db.scalars(
        select(Report.submitted_at).where(
            ~Report.device_id.startswith(DEMO_PREFIX), ~Report.device_id.startswith(E2E_PREFIX)
        )
    ).all()
    for submitted in rows:
        local = submitted.astimezone(KL).date()
        if local >= START:
            genuine_month[local.month] += 1
    demo_month = Counter(p.submitted_at.astimezone(KL).month for p in planned)

    print("\nMonth      genuine   demo   total")
    for month in sorted(set(genuine_month) | set(demo_month)):
        name = dt.date(2026, month, 1).strftime("%b")
        g, d = genuine_month[month], demo_month[month]
        print(f"  {name}      {g:>5}  {d:>5}  {g + d:>6}")
    print(f"  all      {sum(genuine_month.values()):>5}  {len(planned):>5}  "
          f"{sum(genuine_month.values()) + len(planned):>6}")

    print("\nDemo reports by restaurant")
    for name, count in Counter(p.place.name for p in planned).most_common():
        print(f"  {count:>4}  {name}")
    print(f"\nPhotographs needed: {sum(p.photo_count for p in planned)}")


def cmd_plan(until: dt.date) -> None:
    with SessionLocal() as db:
        genuine = genuine_by_segment(db)
        planned = generate(demo_quota(daily_expectation(until), genuine), until)
        summarise(planned, genuine, db)
    print("\nNothing written. Run `load` with the same --until to insert.")


def cmd_load(until: dt.date) -> None:
    pool = photo_pool()
    real = real_photos()
    print(f"Photo pool: {len(pool)} dataset photographs pass at "
          f"{settings.ai_confidence_threshold} ({settings.ai_model_version}).")

    rng = random.Random(SEED + 1)
    rng.shuffle(pool)

    with SessionLocal() as db:
        removed = remove_rows(db, DEMO_PREFIX)
        removed_e2e = remove_rows(db, E2E_PREFIX)
        db.flush()

        genuine = genuine_by_segment(db)
        planned = generate(demo_quota(daily_expectation(until), genuine), until)

        needed = sum(p.photo_count for p in planned)
        if needed > len(pool):
            print(f"Note: {needed} photographs needed, {len(pool)} in the pool — "
                  "some will appear on more than one report.")

        # Real photographs go on the latest report at each of the busiest
        # hotspots, so they are the ones nearest the top of D04.
        real_slots: dict[int, tuple[Path, float]] = {}
        for (path, score), place in zip(real, PLACES):
            latest = max((i for i, p in enumerate(planned) if p.place is place), default=None)
            if latest is not None:
                real_slots[latest] = (path, score)

        taken = set(db.scalars(select(Report.reference_no)).all())
        attached: list[str] = []
        cursor = 0
        for index, item in enumerate(planned):
            report_id = uuid.uuid4()
            photos: list[tuple[Path, float]] = []
            reference = reference_no(rng, item.submitted_at, taken)
            if index in real_slots:
                photos.append(real_slots[index])
                attached.append(
                    f"  {reference}  {real_slots[index][0].name} -> {item.place.name}, "
                    f"{item.reported_at.astimezone(KL):%d %b %H:%M}"
                )
            while len(photos) < item.photo_count:
                photos.append(pool[cursor % len(pool)])
                cursor += 1

            destination = settings.reports_path / str(report_id)
            destination.mkdir(parents=True, exist_ok=True)

            db.add(Report(
                report_id=report_id,
                reference_no=reference,
                device_id=item.device_id,
                premise_name=item.place.name if item.named else None,
                address_text=item.place.address,
                latitude=Decimal(f"{item.place.latitude:.6f}"),
                longitude=Decimal(f"{item.place.longitude:.6f}"),
                capture_latitude=jitter(rng, item.place.latitude, 25),
                capture_longitude=jitter(rng, item.place.longitude, 25),
                reported_at=item.reported_at,
                submitted_at=item.submitted_at,
            ))
            for sequence_no, (source, score) in enumerate(photos, start=1):
                name = f"{sequence_no}{source.suffix.lower()}"
                shutil.copyfile(source, destination / name)
                db.add(ReportPhoto(
                    report_id=report_id,
                    sequence_no=sequence_no,
                    storage_path=f"reports/{report_id}/{name}",
                    captured_at=item.reported_at,
                    confidence_score=Decimal(f"{score:.4f}"),
                    is_validated=True,
                ))
            db.add(AIClassification(
                report_id=report_id,
                model_version=settings.ai_model_version,
                threshold_used=Decimal(f"{settings.ai_confidence_threshold:.4f}"),
                outcome="PASS",
                highest_confidence=Decimal(f"{max(s for _, s in photos):.4f}"),
                photos_evaluated=len(photos) + item.dropped,
                photos_passed=len(photos),
                evaluated_at=item.submitted_at - dt.timedelta(seconds=rng.uniform(25, 120)),
            ))

        db.commit()
        print(f"Removed {removed} previous demo and {removed_e2e} e2e report(s).")
        summarise(planned, genuine, db)
        if attached:
            print("\nReal photographs attached to (open these in D05):")
            print("\n".join(attached))
    print(f"\nLoaded {len(planned)} demo reports up to {until:%d %b %Y}.")


def cmd_remove() -> None:
    with SessionLocal() as db:
        removed = remove_rows(db, DEMO_PREFIX)
        db.commit()
    print(f"Removed {removed} demo report(s) and their photographs.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=("plan", "load", "remove"))
    parser.add_argument(
        "--until",
        type=dt.date.fromisoformat,
        default=dt.datetime.now(KL).date() - dt.timedelta(days=1),
        help="Last day (Malaysian time) to generate reports for. Default: yesterday.",
    )
    args = parser.parse_args()

    if args.command != "remove" and not START <= args.until <= dt.date(2026, 10, 31):
        sys.exit("--until must fall between 1 Jun and 31 Oct 2026.")

    {"plan": lambda: cmd_plan(args.until), "load": lambda: cmd_load(args.until),
     "remove": cmd_remove}[args.command]()


if __name__ == "__main__":
    main()

"""Photograph storage: staging at classification, promotion at submission.

WHY A STAGING AREA
------------------
The reporting flow uploads photographs at S10 (classification) and creates the
report at S12 (submission). Two naive designs were rejected:

1. *Upload twice.* The app posts the photos to /classify, then posts them again
   to /reports. Three photographs at ~2 MB each would cross a mobile connection
   twice, which is visible to the user as a slow submit.

2. *Let the client send the scores back.* The app posts the photos to
   /classify, then posts the confidence scores it received alongside the report.
   This is not merely wasteful, it is unsound: a modified client could submit any
   score it liked, and the AI validation gate — one of the two controls that
   replace account-level accountability under anonymous reporting (S14) — would
   be trivially bypassable.

Instead, /classify writes the photographs and its own verdict to a staging
directory keyed by an opaque token, and returns only the token and the
per-photo outcomes. /reports presents the token; the server reads its own
recorded scores and promotes the passing photographs into permanent storage.
The client never has an opportunity to state a confidence score.

The verdict is written to disk rather than held in memory so that a backend
restart mid-flow does not strand a reporter who has already passed validation.
"""

from __future__ import annotations

import datetime as dt
import json
import shutil
import uuid
from pathlib import Path
from typing import Any

from app.config import get_settings

settings = get_settings()

_RESULT_FILENAME = "result.json"
_RECEIPT_FILENAME = "submitted.json"


def ensure_directories() -> None:
    for path in (
        settings.upload_path,
        settings.staging_path,
        settings.reports_path,
        settings.infographics_path,
    ):
        path.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------------------------------
# Staging — written by POST /classify
# --------------------------------------------------------------------------


def create_staging_dir() -> tuple[str, Path]:
    token = uuid.uuid4().hex
    path = settings.staging_path / token
    path.mkdir(parents=True, exist_ok=False)
    return token, path


def stage_photo(staging_dir: Path, index: int, data: bytes, suffix: str) -> Path:
    filename = f"{index}{suffix or '.jpg'}"
    destination = staging_dir / filename
    destination.write_bytes(data)
    return destination


def write_verdict(staging_dir: Path, verdict: dict[str, Any]) -> None:
    (staging_dir / _RESULT_FILENAME).write_text(json.dumps(verdict, indent=2))


def read_verdict(token: str) -> dict[str, Any] | None:
    """Return the server's own recorded classification verdict, or None."""
    if not _is_safe_token(token):
        return None
    result_file = settings.staging_path / token / _RESULT_FILENAME
    if not result_file.is_file():
        return None
    try:
        return json.loads(result_file.read_text())
    except json.JSONDecodeError:
        return None


# --------------------------------------------------------------------------
# Idempotency — a duplicate submit must not create a second report
# --------------------------------------------------------------------------


def read_receipt(token: str) -> dict[str, Any] | None:
    """Return the result of an earlier successful submission of this token.

    Section 7 of the flow document requires a duplicate submit tap to be safe.
    Because a validation token is single-use, the receipt left behind by the
    first submission is a natural idempotency record: a repeat presentation of
    the same token returns the original reference number instead of filing a
    second report.
    """
    if not _is_safe_token(token):
        return None
    receipt = settings.staging_path / token / _RECEIPT_FILENAME
    if not receipt.is_file():
        return None
    try:
        return json.loads(receipt.read_text())
    except json.JSONDecodeError:
        return None


def write_receipt(token: str, reference_no: str, report_id: str) -> None:
    receipt = settings.staging_path / token / _RECEIPT_FILENAME
    receipt.write_text(
        json.dumps(
            {
                "reference_no": reference_no,
                "report_id": report_id,
                "submitted_at": _now_iso(),
            },
            indent=2,
        )
    )


# --------------------------------------------------------------------------
# Promotion — called by POST /reports inside the request, before commit
# --------------------------------------------------------------------------


def promote_photos(
    token: str, report_id: uuid.UUID, staged_filenames: list[str]
) -> list[str]:
    """Copy passing photographs into permanent storage.

    Returns storage paths relative to ``upload_dir``, for ``report_photo``.

    Copies rather than moves: if the database transaction is rolled back the
    staged originals are still in place, so the reporter can retry a failed
    submit without repeating validation. Stale staging directories are removed
    by :func:`purge_expired_staging`.
    """
    destination_dir = settings.reports_path / str(report_id)
    destination_dir.mkdir(parents=True, exist_ok=True)

    staging_dir = settings.staging_path / token
    stored: list[str] = []

    for sequence_no, filename in enumerate(staged_filenames, start=1):
        source = staging_dir / filename
        target_name = f"{sequence_no}{source.suffix or '.jpg'}"
        shutil.copy2(source, destination_dir / target_name)
        stored.append(f"reports/{report_id}/{target_name}")

    return stored


def discard_report_photos(report_id: uuid.UUID) -> None:
    """Remove promoted files after a failed transaction."""
    shutil.rmtree(settings.reports_path / str(report_id), ignore_errors=True)


# --------------------------------------------------------------------------
# Housekeeping
# --------------------------------------------------------------------------


def purge_expired_staging() -> int:
    """Delete staging directories older than the configured TTL.

    A reporter who abandons the flow between S10 and S12 leaves photographs on
    the server. Since those photographs may show identifiable individuals,
    retaining them indefinitely would be hard to defend under the PDPA
    Security Principle. Called at application startup.
    """
    if not settings.staging_path.exists():
        return 0

    cutoff = dt.datetime.now().timestamp() - settings.staging_ttl_hours * 3600
    removed = 0

    for child in settings.staging_path.iterdir():
        if child.is_dir() and child.stat().st_mtime < cutoff:
            shutil.rmtree(child, ignore_errors=True)
            removed += 1

    return removed


def _is_safe_token(token: str) -> bool:
    """Reject anything that is not a plain hex token.

    The token is interpolated into a filesystem path, so a value containing
    path separators or '..' could escape the staging directory.
    """
    return bool(token) and len(token) == 32 and all(c in "0123456789abcdef" for c in token)


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()

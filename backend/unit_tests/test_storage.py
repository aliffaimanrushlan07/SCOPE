"""Unit tests for app.services.storage.

Units under test: _is_safe_token, create_staging_dir, stage_photo,
write_verdict/read_verdict, write_receipt/read_receipt, promote_photos,
purge_expired_staging.
"""
from __future__ import annotations

import os
import time
import uuid

from app.services import storage


# ---------------------------------------------------------------------------
# _is_safe_token
# ---------------------------------------------------------------------------

def test_is_safe_token_accepts_valid_hex_token():
    """TC-STO-01 (Valid): a genuine uuid4().hex token is accepted."""
    token = uuid.uuid4().hex
    assert storage._is_safe_token(token) is True


def test_is_safe_token_rejects_wrong_length():
    """TC-STO-02 (Boundary): tokens shorter or longer than 32 chars are rejected."""
    assert storage._is_safe_token("abc123") is False
    assert storage._is_safe_token(uuid.uuid4().hex + "a") is False


def test_is_safe_token_rejects_path_traversal():
    """TC-STO-03 (Invalid/security): a token must not allow escaping the
    staging directory via path separators or '..'."""
    assert storage._is_safe_token("../../etc/passwd") is False
    assert storage._is_safe_token("") is False


# ---------------------------------------------------------------------------
# create_staging_dir / stage_photo / write_verdict / read_verdict
# ---------------------------------------------------------------------------

def test_create_staging_dir_creates_unique_folder(isolated_storage):
    """TC-STO-04 (Valid): create_staging_dir returns a token and a folder
    that actually exists on disk."""
    token, path = storage.create_staging_dir()

    assert path.is_dir()
    assert path == isolated_storage.staging_path / token
    assert storage._is_safe_token(token)


def test_stage_photo_writes_file_with_expected_name(isolated_storage):
    """TC-STO-05 (Valid): a staged photo is written under its numeric index
    with the given suffix."""
    _, staging_dir = storage.create_staging_dir()

    destination = storage.stage_photo(staging_dir, 0, b"fake-image-bytes", ".jpg")

    assert destination.name == "0.jpg"
    assert destination.read_bytes() == b"fake-image-bytes"


def test_stage_photo_defaults_to_jpg_when_no_suffix(isolated_storage):
    """TC-STO-06 (Boundary): an empty suffix falls back to '.jpg' rather
    than producing an extensionless file."""
    _, staging_dir = storage.create_staging_dir()

    destination = storage.stage_photo(staging_dir, 2, b"data", "")

    assert destination.name == "2.jpg"


def test_write_and_read_verdict_roundtrip(isolated_storage):
    """TC-STO-07 (Valid): a verdict written to staging can be read back
    identically."""
    token, staging_dir = storage.create_staging_dir()
    verdict = {"outcome": "PASS", "photos_evaluated": 2}

    storage.write_verdict(staging_dir, verdict)
    result = storage.read_verdict(token)

    assert result == verdict


def test_read_verdict_returns_none_for_unsafe_token(isolated_storage):
    """TC-STO-08 (Invalid): a malformed token must not even attempt a file
    lookup -- it should short-circuit to None."""
    assert storage.read_verdict("../../etc/passwd") is None


def test_read_verdict_returns_none_when_missing(isolated_storage):
    """TC-STO-09 (Boundary): a syntactically valid token with no verdict
    file yet (e.g. classification still in progress) returns None."""
    token, _ = storage.create_staging_dir()

    assert storage.read_verdict(token) is None


# ---------------------------------------------------------------------------
# write_receipt / read_receipt (idempotency)
# ---------------------------------------------------------------------------

def test_write_and_read_receipt_roundtrip(isolated_storage):
    """TC-STO-10 (Valid): a submission receipt can be read back with the
    same reference number and report id, supporting duplicate-submit safety."""
    token, staging_dir = storage.create_staging_dir()
    report_id = str(uuid.uuid4())

    storage.write_receipt(token, "SCP-20260909-AB12", report_id)
    receipt = storage.read_receipt(token)

    assert receipt["reference_no"] == "SCP-20260909-AB12"
    assert receipt["report_id"] == report_id
    assert "submitted_at" in receipt


def test_read_receipt_returns_none_when_never_submitted(isolated_storage):
    """TC-STO-11 (Boundary): a token that was classified but never submitted
    has no receipt yet."""
    token, _ = storage.create_staging_dir()

    assert storage.read_receipt(token) is None


# ---------------------------------------------------------------------------
# promote_photos / discard_report_photos
# ---------------------------------------------------------------------------

def test_promote_photos_copies_into_report_folder(isolated_storage):
    """TC-STO-12 (Valid): passing photos are copied from staging into the
    permanent per-report folder with sequential filenames."""
    token, staging_dir = storage.create_staging_dir()
    storage.stage_photo(staging_dir, 0, b"photo-a", ".jpg")
    storage.stage_photo(staging_dir, 1, b"photo-b", ".png")
    report_id = uuid.uuid4()

    stored_paths = storage.promote_photos(token, report_id, ["0.jpg", "1.png"])

    assert stored_paths == [
        f"reports/{report_id}/1.jpg",
        f"reports/{report_id}/2.png",
    ]
    dest_dir = isolated_storage.reports_path / str(report_id)
    assert (dest_dir / "1.jpg").read_bytes() == b"photo-a"
    assert (dest_dir / "2.png").read_bytes() == b"photo-b"


def test_discard_report_photos_removes_folder_silently(isolated_storage):
    """TC-STO-13 (Boundary): discarding a report with no promoted photos
    (folder never created) must not raise."""
    report_id = uuid.uuid4()

    storage.discard_report_photos(report_id)  # should not raise

    assert not (isolated_storage.reports_path / str(report_id)).exists()


# ---------------------------------------------------------------------------
# purge_expired_staging
# ---------------------------------------------------------------------------

def test_purge_expired_staging_removes_old_dirs_only(isolated_storage):
    """TC-STO-14 (Valid + Boundary): only staging directories older than the
    TTL are removed; a fresh directory is left alone."""
    isolated_storage.staging_ttl_hours = 0.0  # anything not brand new expires

    old_token, old_dir = storage.create_staging_dir()
    # Backdate the folder's mtime by 1 hour so it counts as expired.
    old_time = time.time() - 3600
    os.utime(old_dir, (old_time, old_time))

    removed = storage.purge_expired_staging()

    assert removed == 1
    assert not old_dir.exists()


def test_purge_expired_staging_returns_zero_when_no_staging_dir(isolated_storage, tmp_path):
    """TC-STO-15 (Invalid/edge case): if the staging path doesn't exist yet
    (fresh install), purge must return 0 rather than raising."""
    isolated_storage.staging_path = tmp_path / "never-created"

    assert storage.purge_expired_staging() == 0

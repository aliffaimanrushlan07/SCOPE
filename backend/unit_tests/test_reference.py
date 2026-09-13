"""Unit tests for app.services.reference.generate_reference_no.

Unit under test: generate_reference_no(db) -> str
"""
from __future__ import annotations

import datetime as dt
import re
from zoneinfo import ZoneInfo

import pytest

from app.services import reference


REFERENCE_PATTERN = re.compile(r"^SCP-\d{8}-[A-Z0-9]{4}$")
AMBIGUOUS_CHARS = set("IO01")


def test_generate_reference_no_returns_correct_format(mock_db_session):
    """TC-REF-01 (Valid): a fresh reference number matches SCP-YYYYMMDD-XXXX."""
    mock_db_session.scalar.return_value = None  # no collision on first try

    result = reference.generate_reference_no(mock_db_session)

    assert REFERENCE_PATTERN.match(result), f"Unexpected format: {result}"


def test_generate_reference_no_uses_todays_malaysia_date(mock_db_session):
    """TC-REF-02 (Valid): the date segment reflects Asia/Kuala_Lumpur 'today',
    not UTC 'today' -- important near local midnight."""
    mock_db_session.scalar.return_value = None
    expected_date = dt.datetime.now(ZoneInfo("Asia/Kuala_Lumpur")).strftime("%Y%m%d")

    result = reference.generate_reference_no(mock_db_session)

    assert result.split("-")[1] == expected_date


def test_generate_reference_no_excludes_ambiguous_characters(mock_db_session):
    """TC-REF-03 (Valid/business rule): the 4-character suffix must never
    contain I, O, 0 or 1, since the reference is read aloud over the phone."""
    mock_db_session.scalar.return_value = None

    # Generate several to reduce the chance of a false pass.
    for _ in range(30):
        result = reference.generate_reference_no(mock_db_session)
        suffix = result.split("-")[2]
        assert not (set(suffix) & AMBIGUOUS_CHARS), f"Ambiguous char in {suffix}"


def test_generate_reference_no_retries_on_collision(mock_db_session):
    """TC-REF-04 (Boundary): if the first candidate collides with an existing
    reference, the function must retry rather than returning a duplicate."""
    # First call: collision (truthy). Second call: no collision.
    mock_db_session.scalar.side_effect = ["existing-report-id", None]

    result = reference.generate_reference_no(mock_db_session)

    assert REFERENCE_PATTERN.match(result)
    assert mock_db_session.scalar.call_count == 2


def test_generate_reference_no_raises_after_max_attempts(mock_db_session):
    """TC-REF-05 (Invalid/exception path): if every candidate collides, the
    function must raise rather than silently returning a duplicate."""
    mock_db_session.scalar.return_value = "always-collides"

    with pytest.raises(RuntimeError, match="Could not generate a unique"):
        reference.generate_reference_no(mock_db_session)

    assert mock_db_session.scalar.call_count == reference._MAX_ATTEMPTS

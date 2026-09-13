"""Unit tests for app.services.activity.

Units under test: client_ip(request), log(db, activity_type, ...).
"""
from __future__ import annotations

import uuid
from unittest.mock import MagicMock

from app.services import activity


# ---------------------------------------------------------------------------
# client_ip
# ---------------------------------------------------------------------------

def test_client_ip_prefers_x_forwarded_for():
    """TC-ACT-01 (Valid): when a reverse proxy sets X-Forwarded-For, its
    first hop is used as the client IP."""
    request = MagicMock()
    request.headers.get.return_value = "203.0.113.7, 10.0.0.1"

    result = activity.client_ip(request)

    assert result == "203.0.113.7"


def test_client_ip_falls_back_to_socket_address():
    """TC-ACT-02 (Valid): with no X-Forwarded-For header, fall back to the
    raw socket address."""
    request = MagicMock()
    request.headers.get.return_value = None
    request.client.host = "192.168.1.50"

    result = activity.client_ip(request)

    assert result == "192.168.1.50"


def test_client_ip_returns_none_when_no_request():
    """TC-ACT-03 (Boundary/invalid input): a background job with no HTTP
    request context must not error -- it simply has no IP to log."""
    assert activity.client_ip(None) is None


def test_client_ip_returns_none_when_client_is_none():
    """TC-ACT-04 (Boundary): a request object with no underlying client
    (e.g. in some test clients) must not raise an AttributeError."""
    request = MagicMock()
    request.headers.get.return_value = None
    request.client = None

    assert activity.client_ip(request) is None


# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------

def test_log_adds_entry_without_committing(mock_db_session):
    """TC-ACT-05 (Valid): log() must call db.add() exactly once and must
    NOT commit -- the caller owns the transaction."""
    admin_id = uuid.uuid4()

    activity.log(mock_db_session, activity.LOGIN, admin_id=admin_id)

    mock_db_session.add.assert_called_once()
    mock_db_session.commit.assert_not_called()
    entry = mock_db_session.add.call_args[0][0]
    assert entry.activity_type == activity.LOGIN
    assert entry.admin_id == admin_id


def test_log_truncates_detail_to_255_characters(mock_db_session):
    """TC-ACT-06 (Boundary): the detail column is String(255) at the
    database level, so an over-length detail must be truncated, not sent
    through untouched (which would raise a DB error)."""
    long_detail = "x" * 500

    activity.log(mock_db_session, activity.EXPORT_CSV, detail=long_detail)

    entry = mock_db_session.add.call_args[0][0]
    assert len(entry.detail) == 255


def test_log_allows_none_detail():
    """TC-ACT-07 (Boundary/invalid input): most activity types (e.g. LOGIN)
    have no detail text; None must pass through unchanged, not raise."""
    db = MagicMock()

    activity.log(db, activity.LOGIN, detail=None)

    entry = db.add.call_args[0][0]
    assert entry.detail is None

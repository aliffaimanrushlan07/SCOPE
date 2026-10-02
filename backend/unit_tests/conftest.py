"""Shared pytest fixtures for the SCOPE backend unit-test suite.

These fixtures isolate each test from the real filesystem, database, and AI
model so tests are fast, deterministic, and independent of one another.
"""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.services import storage, inference


@pytest.fixture
def isolated_storage(tmp_path, monkeypatch):
    """Point storage.py at a throwaway temp directory for this test only.

    The real Settings class exposes upload_path/staging_path/reports_path/
    infographics_path as read-only computed properties (derived from a base
    directory setting), so they cannot be assigned to directly. Instead, we
    replace the whole module-level `settings` object that storage.py reads
    from with a simple, freely-mutable stand-in for the duration of the
    test. monkeypatch automatically restores the real settings afterwards.

    Each test gets its own tmp_path, so tests never interfere with each
    other or with real uploaded files.
    """
    fake_settings = SimpleNamespace(
        upload_path=tmp_path / "uploads",
        staging_path=tmp_path / "staging",
        reports_path=tmp_path / "reports",
        infographics_path=tmp_path / "infographics",
        staging_ttl_hours=24,
    )
    monkeypatch.setattr(storage, "settings", fake_settings)
    storage.ensure_directories()
    return fake_settings


@pytest.fixture
def stub_ai_settings(monkeypatch):
    """Force inference.py into deterministic stub mode with a fixed threshold."""
    monkeypatch.setattr(inference.settings, "ai_stub_mode", True)
    monkeypatch.setattr(inference.settings, "ai_confidence_threshold", 0.6)
    monkeypatch.setattr(inference.settings, "ai_model_version", "vit-v1-test")
    monkeypatch.setattr(inference.settings, "ai_min_sharpness", 0.0)
    return inference.settings


@pytest.fixture
def mock_db_session():
    """A minimal stand-in for a SQLAlchemy Session, for tests that only need
    to observe calls (db.add, db.scalar) rather than hit a real database."""
    return MagicMock()
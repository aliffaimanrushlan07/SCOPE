"""SQLAlchemy models mirroring Tables 4.4-4.9 of the data dictionary.

The schema is owned by ``infra/schema.sql``, not by these classes. They are
declared to match it exactly and are never used to create tables — the
constraints in the SQL file carry design justifications that an ORM-generated
schema would silently drop.

Note the attributes that do NOT appear here: no ``status``, ``verified_by``,
``verified_at`` or ``reviewed_by``. Evidence is validated before submission and
administrators are read-only, so nothing can change a report after it is filed.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from geoalchemy2 import Geography
from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Numeric,
    SmallInteger,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import INET, UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Report(Base):
    """Table 4.4 — one row per submitted violation report."""

    __tablename__ = "report"

    report_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    reference_no: Mapped[str] = mapped_column(String(20), unique=True)
    device_id: Mapped[str] = mapped_column(String(64))
    premise_name: Mapped[str | None] = mapped_column(String(150))
    address_text: Mapped[str | None] = mapped_column(String(255))
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    # Derived from latitude/longitude by a database trigger so the two can
    # never disagree. Never assigned from Python.
    geom: Mapped[str] = mapped_column(Geography("POINT", srid=4326))
    capture_latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    capture_longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    reported_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))
    submitted_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    photos: Mapped[list[ReportPhoto]] = relationship(
        back_populates="report",
        cascade="all, delete-orphan",
        order_by="ReportPhoto.sequence_no",
    )
    classification: Mapped[AIClassification] = relationship(
        back_populates="report", cascade="all, delete-orphan", uselist=False
    )


class ReportPhoto(Base):
    """Table 4.5 — the one to three photographs attached to a report (R1)."""

    __tablename__ = "report_photo"

    photo_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    report_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("report.report_id", ondelete="CASCADE")
    )
    sequence_no: Mapped[int] = mapped_column(SmallInteger)
    storage_path: Mapped[str] = mapped_column(String(255))
    captured_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))
    confidence_score: Mapped[Decimal] = mapped_column(Numeric(5, 4))
    is_validated: Mapped[bool] = mapped_column(Boolean, default=True)

    report: Mapped[Report] = relationship(back_populates="photos")


class AIClassification(Base):
    """Table 4.6 — report-level classification outcome, one-to-one (R2)."""

    __tablename__ = "ai_classification"

    classification_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    report_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("report.report_id", ondelete="CASCADE"),
        unique=True,
    )
    model_version: Mapped[str] = mapped_column(String(50))
    threshold_used: Mapped[Decimal] = mapped_column(Numeric(5, 4))
    # Only PASS is ever written; the database CHECK constraint enforces it.
    outcome: Mapped[str] = mapped_column(String(10), default="PASS")
    highest_confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4))
    photos_evaluated: Mapped[int] = mapped_column(SmallInteger)
    photos_passed: Mapped[int] = mapped_column(SmallInteger)
    evaluated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))

    report: Mapped[Report] = relationship(back_populates="classification")


class AdminUser(Base):
    """Table 4.7 — the only entity in the system holding personal data."""

    __tablename__ = "admin_user"

    admin_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    email: Mapped[str] = mapped_column(String(120), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    full_name: Mapped[str] = mapped_column(String(120))
    organisation: Mapped[str] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_login_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class AdminActivityLog(Base):
    """Table 4.8 — administrator activity trail (PDPA Security Principle)."""

    __tablename__ = "admin_activity_log"

    log_id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    admin_id: Mapped[uuid.UUID | None] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("admin_user.admin_id", ondelete="SET NULL")
    )
    report_id: Mapped[uuid.UUID | None] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("report.report_id", ondelete="SET NULL")
    )
    activity_type: Mapped[str] = mapped_column(String(30))
    ip_address: Mapped[str | None] = mapped_column(INET)
    detail: Mapped[str | None] = mapped_column(String(255))
    activity_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Infographic(Base):
    """Table 4.9 — two fixed awareness slots backing D06 and S04.

    title and image_path are both NULL while a slot is empty."""

    __tablename__ = "infographic"

    infographic_id: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    title: Mapped[str | None] = mapped_column(String(120))
    image_path: Mapped[str | None] = mapped_column(String(255))
    source_filename: Mapped[str | None] = mapped_column(String(150))
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("admin_user.admin_id", ondelete="SET NULL")
    )
    updated_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))

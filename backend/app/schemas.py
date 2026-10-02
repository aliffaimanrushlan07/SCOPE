"""Request and response models.

Note what the report-creation payload does NOT accept: no confidence score, no
outcome, no model version. Those come from the server's own record of the
classification it performed, looked up by validation token. See
``services/storage.py`` for why.

Note also what it does not accept from a design standpoint: no violation type,
no premise type. The reporter supplies an optional free-text ``premise_name``
only.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


# ---------------------------------------------------------------------------
# S10 — classification
# ---------------------------------------------------------------------------


class PhotoVerdict(BaseModel):
    index: int
    filename: str
    confidence: float
    passed: bool
    reason: str | None = None


class ClassifyResponse(BaseModel):
    validation_token: str = Field(
        description="Opaque handle to the server's record of this classification. "
        "Present it to POST /reports; it is single-use."
    )
    outcome: str = Field(description="PASS when at least one photo cleared the threshold.")
    model_version: str
    threshold_used: float
    highest_confidence: float
    photos_evaluated: int
    photos_passed: int
    evaluated_at: dt.datetime
    photos: list[PhotoVerdict]


# ---------------------------------------------------------------------------
# S12 / S13 — report submission
# ---------------------------------------------------------------------------


class ReportCreate(BaseModel):
    validation_token: str = Field(min_length=32, max_length=32)
    device_id: str = Field(min_length=8, max_length=64)

    latitude: Decimal = Field(ge=-90, le=90)
    longitude: Decimal = Field(ge=-180, le=180)
    premise_name: str | None = Field(default=None, max_length=150)
    address_text: str | None = Field(default=None, max_length=255)

    # Recorded at capture time (S08). A large divergence from the tagged
    # position is the integrity control described at S11.
    capture_latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    capture_longitude: Decimal | None = Field(default=None, ge=-180, le=180)

    reported_at: dt.datetime


class ReportCreateResponse(BaseModel):
    reference_no: str
    submitted_at: dt.datetime
    photos_stored: int
    duplicate_submission: bool = Field(
        default=False,
        description="True when this token had already been submitted; the "
        "original reference number is returned rather than a second report filed.",
    )


# ---------------------------------------------------------------------------
# S14 — report history (device-bound, read-only)
# ---------------------------------------------------------------------------


class ReportPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    sequence_no: int
    storage_path: str
    confidence_score: Decimal
    captured_at: dt.datetime


class ReportHistoryItem(BaseModel):
    """One row of Report History.

    Carries no status field. Because evidence is validated before submission
    and administrators are read-only, nothing can change a report's state after
    filing; a status would advertise a workflow that does not exist.
    """

    reference_no: str
    premise_name: str | None
    address_text: str | None
    reported_at: dt.datetime
    submitted_at: dt.datetime
    photo_count: int
    thumbnail_path: str | None


class ReportDetail(ReportHistoryItem):
    latitude: Decimal
    longitude: Decimal
    photos: list[ReportPhotoOut]


# ---------------------------------------------------------------------------
# S02 / S04 / S06 — public content
# ---------------------------------------------------------------------------


class InfographicOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    infographic_id: int
    title: str
    image_path: str
    updated_at: dt.datetime | None


class AdminInfographicOut(BaseModel):
    """D06 view of a slot. Unlike the public listing it includes empty slots,
    whose title and image_path are null."""

    model_config = ConfigDict(from_attributes=True)

    infographic_id: int
    title: str | None
    image_path: str | None
    updated_at: dt.datetime | None


class HotspotPoint(BaseModel):
    """One weighted point of the public density heatmap.

    Coordinates are ROUNDED before they leave the server. The public map shows
    where violations concentrate, never which premise was reported — that
    distinction protects both reporter safety and the system's defamation
    exposure. Full precision is available only to authenticated officers on D03.
    """

    latitude: float
    longitude: float
    weight: int


# ---------------------------------------------------------------------------
# S11 — mapping proxy
# ---------------------------------------------------------------------------


class PlaceSuggestion(BaseModel):
    place_id: str
    description: str
    main_text: str | None = None
    secondary_text: str | None = None


class PlaceDetail(BaseModel):
    """A search result resolved to a taggable point (S11)."""

    place_id: str
    name: str
    address: str | None
    latitude: float
    longitude: float


class ReverseGeocodeResult(BaseModel):
    address_text: str | None
    premise_name: str | None


# ---------------------------------------------------------------------------
# D01 — admin authentication
# ---------------------------------------------------------------------------


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class AdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    admin_id: uuid.UUID
    email: str
    full_name: str
    organisation: str
    role: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Seconds. D01 discloses a 30-minute timeout.")
    admin: AdminOut


# ---------------------------------------------------------------------------
# D02 — analytics
# ---------------------------------------------------------------------------


class TimeSeriesPoint(BaseModel):
    period: dt.date
    count: int


class TopLocation(BaseModel):
    label: str
    count: int
    latitude: float
    longitude: float


class OverviewResponse(BaseModel):
    """D02 panels.

    Deliberately absent: average AI confidence, pending-review count, verified
    count. All three described a verification workflow that no longer exists.
    """

    total_reports: int
    period_total: int
    previous_period_total: int
    percentage_change: float | None
    reports_over_time: list[TimeSeriesPoint]
    top_locations: list[TopLocation]


# ---------------------------------------------------------------------------
# D03 — hotspot clusters
# ---------------------------------------------------------------------------


class ClusterOut(BaseModel):
    """A D03 cluster, resolvable to a location — unlike the public heatmap.

    ``band`` indexes the four-step scale in section 10.4, which encodes count
    three ways at once (size, colour, numeral) so the map survives colour-blind
    viewing and black-and-white printing.
    """

    latitude: float
    longitude: float
    count: int
    band: int = Field(ge=1, le=4)


# ---------------------------------------------------------------------------
# D04 / D05 — report list and detail
# ---------------------------------------------------------------------------


class AdminReportRow(BaseModel):
    """A D04 table row. Five columns, no status, no premise type."""

    report_id: uuid.UUID
    reference_no: str
    submitted_at: dt.datetime
    premise_name: str | None
    address_text: str | None
    ai_confidence: Decimal


class PaginatedReports(BaseModel):
    items: list[AdminReportRow]
    total: int
    page: int
    page_size: int
    total_pages: int


class ClassificationOut(BaseModel):
    """D05 AI panel. Display only — provenance, not a control."""

    model_config = ConfigDict(from_attributes=True)

    outcome: str
    model_version: str
    threshold_used: Decimal
    highest_confidence: Decimal
    photos_evaluated: int
    photos_passed: int
    evaluated_at: dt.datetime


class AdminReportDetail(BaseModel):
    report_id: uuid.UUID
    reference_no: str
    reported_at: dt.datetime
    submitted_at: dt.datetime
    latitude: Decimal
    longitude: Decimal
    capture_latitude: Decimal | None
    capture_longitude: Decimal | None
    premise_name: str | None
    address_text: str | None
    reporter: str = "Anonymous"
    photos: list[ReportPhotoOut]
    classification: ClassificationOut | None
    location_integrity_metres: float | None = Field(
        default=None,
        description="Distance between capture position and tagged position. "
        "A large divergence is worth an officer's attention.",
    )


# ---------------------------------------------------------------------------
# D06 — infographic management
# ---------------------------------------------------------------------------


class InfographicUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=120)

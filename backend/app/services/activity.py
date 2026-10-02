"""Administrator activity logging (Table 4.8).

Every administrator authentication, report access and data export is recorded.
Reports contain photographs of identifiable individuals at identifiable
premises, and FR13 permits that data to leave the system as a CSV export, so
the Personal Data Protection Act 2010 Security Principle expectation is met by
recording which officer performed each access and when.

Note the asymmetry with the reporter side: no reporter-facing endpoint writes
here. There is no reporter identity to log.
"""

from __future__ import annotations

import uuid

from fastapi import Request
from sqlalchemy.orm import Session

from app.models import AdminActivityLog

LOGIN = "LOGIN"
LOGOUT = "LOGOUT"
FAILED_LOGIN = "FAILED_LOGIN"
VIEW_REPORT = "VIEW_REPORT"
EXPORT_CSV = "EXPORT_CSV"
UPDATE_INFOGRAPHIC = "UPDATE_INFOGRAPHIC"
DELETE_INFOGRAPHIC = "DELETE_INFOGRAPHIC"


def log(
    db: Session,
    activity_type: str,
    *,
    admin_id: uuid.UUID | None = None,
    report_id: uuid.UUID | None = None,
    request: Request | None = None,
    detail: str | None = None,
) -> None:
    """Append an activity entry. Does not commit — the caller owns the
    transaction, so a logged action and its effect succeed or fail together."""
    db.add(
        AdminActivityLog(
            admin_id=admin_id,
            report_id=report_id,
            activity_type=activity_type,
            ip_address=client_ip(request),
            detail=detail[:255] if detail else None,
        )
    )


def client_ip(request: Request | None) -> str | None:
    if request is None:
        return None
    # Behind a reverse proxy the socket address is the proxy's. Trust
    # X-Forwarded-For only if you actually run one, and only its first hop.
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else None

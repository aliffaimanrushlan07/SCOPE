"""Report reference number generation.

Because reporting is anonymous and Report History is device-bound, the
reference number is the reporter's only durable handle on a submission
(S13). It is therefore built to be read aloud and typed by hand:

    SCP-20260812-K4M2

- No ambiguous characters. I, O, 0, 1 are excluded so the number cannot be
  misread over the phone or mistyped from a screenshot.
- The date segment lets an officer place a reference in time without a
  database lookup.

The date is taken in MALAYSIAN local time, not UTC. The system serves Kuala
Lumpur and Putrajaya, and UTC+8 means a report filed at 01:00 local would
otherwise carry the previous day's date — so a reporter reading their reference
back to an officer would name a date neither of them recognises. Only the
reference number uses local time; every stored timestamp remains TIMESTAMPTZ.
"""

from __future__ import annotations

import datetime as dt
import secrets
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Report

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_SUFFIX_LENGTH = 4
_MAX_ATTEMPTS = 10
_LOCAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


def generate_reference_no(db: Session) -> str:
    """Generate a reference number not already present in the database.

    The uniqueness check is advisory — ``report.reference_no`` carries a UNIQUE
    constraint, which is what actually guarantees it. Retrying here simply
    avoids surfacing a constraint violation to the reporter.
    """
    today = dt.datetime.now(_LOCAL_TZ).strftime("%Y%m%d")

    for _ in range(_MAX_ATTEMPTS):
        suffix = "".join(secrets.choice(_ALPHABET) for _ in range(_SUFFIX_LENGTH))
        candidate = f"SCP-{today}-{suffix}"
        exists = db.scalar(
            select(Report.report_id).where(Report.reference_no == candidate)
        )
        if exists is None:
            return candidate

    raise RuntimeError(
        "Could not generate a unique report reference number after "
        f"{_MAX_ATTEMPTS} attempts."
    )

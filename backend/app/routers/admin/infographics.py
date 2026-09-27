"""D06 — infographic management.

Three fixed slots, replace-in-place only. There is no POST and no DELETE:
the Awareness Hub (S04) renders exactly three buttons, one per slot, and has
no empty state for a missing slot and no overflow state for a fourth. Adding
a slot or removing one would break that screen.

The constraint is enforced in three places — the route surface here, the
primary-key CHECK, and a delete-blocking trigger — so it holds even against
direct database access.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, File, Form, HTTPException, Path, Request, UploadFile, status
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_admin
from app.models import AdminUser, Infographic
from app.schemas import InfographicOut
from app.services import activity, storage

router = APIRouter(prefix="/api/v1/admin/infographics", tags=["Admin — Infographics"])
settings = get_settings()

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@router.get("", response_model=list[InfographicOut], summary="The three slots (D06)")
def list_slots(
    db: Session = Depends(get_db), admin: AdminUser = Depends(get_current_admin)
) -> list[Infographic]:
    from sqlalchemy import select

    return list(
        db.scalars(select(Infographic).order_by(Infographic.infographic_id)).all()
    )


@router.put(
    "/{slot}",
    response_model=InfographicOut,
    summary="Replace a slot's image and title (D06)",
)
async def update_slot(
    request: Request,
    slot: int = Path(ge=1, le=3, description="Fixed slot number; only 1, 2 or 3 exist."),
    title: str = Form(min_length=1, max_length=120),
    image: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
) -> Infographic:
    infographic = db.get(Infographic, slot)
    if infographic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Slot {slot} not found."
        )

    infographic.title = title.strip()

    if image is not None:
        if image.content_type not in _ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=f"Unsupported image type: {image.content_type}.",
            )
        data = await image.read()
        if len(data) > settings.max_photo_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Image is too large.",
            )

        storage.ensure_directories()
        suffix = {"image/png": ".png", "image/webp": ".webp"}.get(
            image.content_type or "", ".jpg"
        )
        filename = f"slot-{slot}{suffix}"
        (settings.infographics_path / filename).write_bytes(data)

        infographic.image_path = f"infographics/{filename}"
        infographic.source_filename = (image.filename or filename)[:150]

    infographic.updated_by = admin.admin_id
    infographic.updated_at = dt.datetime.now(dt.timezone.utc)

    activity.log(
        db,
        activity.UPDATE_INFOGRAPHIC,
        admin_id=admin.admin_id,
        request=request,
        detail=f"slot={slot} title={infographic.title}",
    )
    db.commit()
    db.refresh(infographic)

    return infographic

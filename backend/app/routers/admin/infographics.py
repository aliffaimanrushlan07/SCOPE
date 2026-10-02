"""D06 — infographic management.

Two fixed slots. A slot is replaced in place (PUT) or emptied (DELETE); there
is no POST. DELETE clears the slot's title and image rather than removing its
row, so the administrator can publish into the same slot again. The public
listing behind the Awareness Hub (S04) skips empty slots.

The slot range is enforced in three places — the route surface here, the
primary-key CHECK, and a trigger that blocks row deletion — so it holds even
against direct database access.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, File, Form, HTTPException, Path, Request, UploadFile, status
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_admin
from app.models import AdminUser, Infographic
from app.schemas import AdminInfographicOut
from app.services import activity, storage

router = APIRouter(prefix="/api/v1/admin/infographics", tags=["Admin — Infographics"])
settings = get_settings()

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


_SLOT = Path(ge=1, le=2, description="Fixed slot number; only 1 or 2 exist.")


def _get_slot(db: Session, slot: int) -> Infographic:
    infographic = db.get(Infographic, slot)
    if infographic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Slot {slot} not found."
        )
    return infographic


def _remove_image(image_path: str | None) -> None:
    """Delete a slot's stored image, if it is one this router wrote."""
    if not image_path:
        return
    target = (settings.upload_path / image_path).resolve()
    if target.parent == settings.infographics_path.resolve():
        target.unlink(missing_ok=True)


@router.get("", response_model=list[AdminInfographicOut], summary="The two slots (D06)")
def list_slots(
    db: Session = Depends(get_db), admin: AdminUser = Depends(get_current_admin)
) -> list[Infographic]:
    from sqlalchemy import select

    return list(
        db.scalars(select(Infographic).order_by(Infographic.infographic_id)).all()
    )


@router.put(
    "/{slot}",
    response_model=AdminInfographicOut,
    summary="Replace a slot's image and title (D06)",
)
async def update_slot(
    request: Request,
    slot: int = _SLOT,
    title: str = Form(min_length=1, max_length=120),
    image: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
) -> Infographic:
    infographic = _get_slot(db, slot)

    # An empty slot has no image to keep, so publishing into it needs one.
    if image is None and infographic.image_path is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="This slot is empty. Choose an image to publish.",
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
        if infographic.image_path != f"infographics/{filename}":
            _remove_image(infographic.image_path)

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


@router.delete(
    "/{slot}",
    response_model=AdminInfographicOut,
    summary="Empty a slot, removing its image and title (D06)",
)
def delete_slot(
    request: Request,
    slot: int = _SLOT,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
) -> Infographic:
    infographic = _get_slot(db, slot)
    if infographic.image_path is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Slot {slot} is already empty."
        )

    old_title, old_image = infographic.title, infographic.image_path
    infographic.title = None
    infographic.image_path = None
    infographic.source_filename = None
    infographic.updated_by = admin.admin_id
    infographic.updated_at = dt.datetime.now(dt.timezone.utc)

    activity.log(
        db,
        activity.DELETE_INFOGRAPHIC,
        admin_id=admin.admin_id,
        request=request,
        detail=f"slot={slot} title={old_title}",
    )
    db.commit()
    db.refresh(infographic)

    # After the commit, so a failed transaction never leaves a row pointing
    # at a missing file.
    _remove_image(old_image)

    return infographic

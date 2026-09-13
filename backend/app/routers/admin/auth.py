"""D01 — administrator authentication (FR08)."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_admin
from app.models import AdminActivityLog, AdminUser
from app.schemas import AdminOut, LoginRequest, LoginResponse
from app.security import create_access_token, verify_password
from app.services import activity

router = APIRouter(prefix="/api/v1/admin", tags=["Admin — Authentication"])
settings = get_settings()


@router.post("/login", response_model=LoginResponse, summary="Sign in (D01, FR08)")
def login(
    payload: LoginRequest, request: Request, db: Session = Depends(get_db)
) -> LoginResponse:
    email = payload.email.lower().strip()

    # Throttle brute force using the activity log the system already keeps,
    # rather than introducing separate state for it.
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=15)
    recent_failures = db.scalar(
        select(func.count())
        .select_from(AdminActivityLog)
        .where(
            AdminActivityLog.activity_type == activity.FAILED_LOGIN,
            AdminActivityLog.activity_at >= since,
            AdminActivityLog.detail == email,
        )
    )
    if recent_failures is not None and recent_failures >= settings.max_failed_logins_per_15min:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed sign-in attempts. Please try again in 15 minutes.",
        )

    admin = db.scalar(select(AdminUser).where(func.lower(AdminUser.email) == email))

    # One message for every failure mode. Distinguishing "no such account" from
    # "wrong password" would let an attacker enumerate officer email addresses.
    if admin is None or not admin.is_active or not verify_password(
        payload.password, admin.password_hash
    ):
        activity.log(
            db, activity.FAILED_LOGIN, request=request, detail=email
        )
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password.",
        )

    token, expires_in = create_access_token(admin.admin_id, admin.email, admin.role)
    admin.last_login_at = dt.datetime.now(dt.timezone.utc)
    activity.log(db, activity.LOGIN, admin_id=admin.admin_id, request=request)
    db.commit()

    return LoginResponse(
        access_token=token,
        expires_in=expires_in,
        admin=AdminOut.model_validate(admin),
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT, summary="Sign out")
def logout(
    request: Request,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
) -> None:
    activity.log(db, activity.LOGOUT, admin_id=admin.admin_id, request=request)
    db.commit()


@router.get("/me", response_model=AdminOut, summary="Signed-in officer (sidebar)")
def me(admin: AdminUser = Depends(get_current_admin)) -> AdminUser:
    return admin

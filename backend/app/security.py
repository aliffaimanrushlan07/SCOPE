"""Password hashing and JSON Web Token issue/verification (FR08)."""

from __future__ import annotations

import datetime as dt
import uuid

import bcrypt
import jwt

from app.config import get_settings

settings = get_settings()


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode()


def verify_password(plain: str, hashed: str) -> bool:
    """Verify a password against a stored hash.

    Accepts the ``$2a$`` hashes produced by pgcrypto's ``crypt()`` in
    ``infra/seed.sql`` as well as the ``$2b$`` hashes this module writes.
    """
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        # Malformed hash in the database — treat as a failed login rather than
        # letting a 500 disclose that the stored value is unusable.
        return False


def create_access_token(admin_id: uuid.UUID, email: str, role: str) -> tuple[str, int]:
    """Issue a JWT. Returns the token and its lifetime in seconds.

    Expiry implements the thirty-minute inactivity timeout disclosed on D01.
    The dashboard refreshes the token on activity; an idle session simply
    expires.
    """
    expires_in = settings.jwt_expiry_minutes * 60
    now = dt.datetime.now(dt.timezone.utc)
    payload = {
        "sub": str(admin_id),
        "email": email,
        "role": role,
        "iat": now,
        "exp": now + dt.timedelta(seconds=expires_in),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_in


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except jwt.PyJWTError:
        return None

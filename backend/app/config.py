"""Application configuration, read from environment / .env."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # --- Database ---
    database_url: str = (
        "postgresql+psycopg://scope:scope_dev_password@localhost:5432/scope"
    )

    # --- Admin session (FR08; D01 discloses a 30-minute inactivity timeout) ---
    jwt_secret: str = "change_me"
    jwt_expiry_minutes: int = 30
    jwt_algorithm: str = "HS256"

    # --- AI classification module ---
    #
    # The threshold is read from settings on every request rather than being
    # captured at import time. This is what makes it the "server-side
    # configurable value" required by SCOPE-System-Flow-Revised.md section S10:
    # it can be retuned after model evaluation without shipping a new build of
    # the mobile application.
    ai_confidence_threshold: float = 0.85
    ai_model_version: str = "vit-scope-v1"
    ai_model_path: str = "../ml/artifacts/vit-scope-v1.keras"
    ai_request_timeout_seconds: int = 30

    # Forces the deterministic stub even when a model file is present. Useful
    # for running the app without loading a gigabyte of weights; scores are
    # then meaningless and must never be presented as real results.
    ai_stub_mode: bool = False

    # --- Google Maps Platform (server key only; never shipped in the APK) ---
    server_maps_key: str = ""

    # --- Storage ---
    upload_dir: str = "./uploads"

    # --- Abuse controls ---
    # Replaces the account-level deterrence that anonymous reporting gives up.
    # See SCOPE-System-Flow-Revised.md section S14.
    rate_limit_per_device_per_hour: int = 5
    max_failed_logins_per_15min: int = 5

    # --- Evidence handling ---
    max_photos_per_report: int = 3
    max_photo_bytes: int = 10 * 1024 * 1024
    staging_ttl_hours: int = 6

    # --- CORS ---
    dashboard_origin: str = "http://localhost:5173"

    @property
    def upload_path(self) -> Path:
        return Path(self.upload_dir).resolve()

    @property
    def staging_path(self) -> Path:
        return self.upload_path / "staging"

    @property
    def reports_path(self) -> Path:
        return self.upload_path / "reports"

    @property
    def infographics_path(self) -> Path:
        return self.upload_path / "infographics"


@lru_cache
def get_settings() -> Settings:
    return Settings()

"""Diagnose the Google Maps server key.

Reports exactly which of the three common failure modes you are in, so the
Cloud console change can be targeted rather than guessed at:

  1. Billing not enabled on the project that OWNS THIS KEY
  2. The specific API not enabled on that project
  3. The key restricted in a way that blocks this caller

Usage (from the repo root):
    ./backend/.venv/bin/python docs/check_maps_key.py

Prints only masked key material, never the key itself.
"""

from __future__ import annotations

import pathlib
import sys

import httpx

ENV_FILE = pathlib.Path(__file__).resolve().parents[1] / "backend" / ".env"


def load_key() -> str:
    if not ENV_FILE.exists():
        sys.exit(f"No .env at {ENV_FILE}")
    for line in ENV_FILE.read_text().splitlines():
        if line.strip().startswith("SERVER_MAPS_KEY"):
            value = line.split("=", 1)[1].strip()
            if value.startswith(("'", '"')) and value[0] == value[-1]:
                value = value[1:-1]
            return value
    sys.exit("SERVER_MAPS_KEY not found in backend/.env")


def diagnose(message: str) -> str:
    lowered = (message or "").lower()
    if "billing" in lowered:
        return (
            "BILLING NOT ENABLED on the project that owns this key.\n"
            "     Confirm you enabled billing on the SAME project the key was\n"
            "     created in — a key belongs to exactly one project, and it is\n"
            "     easy to create the key in a default project while enabling\n"
            "     billing on a new one."
        )
    if "not authorized" in lowered or "has not been used" in lowered:
        return "API NOT ENABLED on this project. Enable it under APIs & Services."
    if "referer" in lowered or "ip" in lowered or "restriction" in lowered:
        return (
            "KEY RESTRICTION is blocking this call. For the server key, set\n"
            "     Application restrictions to None during development."
        )
    return "Unrecognised error — read the message above."


def main() -> int:
    key = load_key()
    print(f"Key: {key[:6]}...{key[-4:]}  (len {len(key)})\n")

    ok = True

    # --- Geocoding API ------------------------------------------------------
    response = httpx.get(
        "https://maps.googleapis.com/maps/api/geocode/json",
        params={"latlng": "3.1578,101.7117", "key": key},
        timeout=25,
    )
    body = response.json()
    status = body.get("status")

    if status == "OK":
        address = body["results"][0].get("formatted_address", "?")
        print(f"[OK]   Geocoding API      -> {address}")
    else:
        ok = False
        print(f"[FAIL] Geocoding API      -> {status}")
        print(f"       {body.get('error_message')}")
        print(f"    => {diagnose(body.get('error_message', ''))}")

    # --- Places API (New) ---------------------------------------------------
    print()
    places = httpx.post(
        "https://places.googleapis.com/v1/places:autocomplete",
        json={"input": "Pavilion Kuala Lumpur"},
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": key,
            "X-Goog-FieldMask": "suggestions.placePrediction",
        },
        timeout=25,
    )

    if places.status_code == 200:
        suggestions = places.json().get("suggestions", [])
        first = (
            suggestions[0]["placePrediction"]["text"]["text"] if suggestions else "(none)"
        )
        print(f"[OK]   Places API (New)   -> {len(suggestions)} results, first: {first}")
    else:
        ok = False
        error = places.json().get("error", {})
        message = error.get("message", "")
        print(f"[FAIL] Places API (New)   -> HTTP {places.status_code} {error.get('status')}")
        print(f"       {message}")
        # Places returns a terse PERMISSION_DENIED for billing problems too,
        # so fall back to whatever Geocoding reported.
        if not message or "permission" in message.lower():
            print(
                "    => Usually the SAME cause as Geocoding above. Fix that first,\n"
                "       then confirm 'Places API (New)' — not the legacy\n"
                "       'Places API' — is enabled."
            )
        else:
            print(f"    => {diagnose(message)}")

    print()
    print("RESULT:", "all good — S06/S11 can be built" if ok else "not usable yet")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

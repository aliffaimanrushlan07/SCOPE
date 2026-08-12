"""S11 — place search and reverse geocoding, proxied.

The Google Maps server key stays on the server. An app-embedded key for these
APIs could be lifted from the APK and used at the project's expense; the
Android key that must ship in the app is restricted to the Maps SDK and to the
application's package signature.

Proxying also matches the DFD, where the arrow to the Mapping and Geocoding
Service originates from the system rather than from the reporter.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

import httpx

from app.config import get_settings
from app.schemas import PlaceSuggestion, ReverseGeocodeResult

router = APIRouter(prefix="/api/v1/geo", tags=["Mapping"])
settings = get_settings()

_AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete"
_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"

# Bias results toward the system's jurisdiction (Kuala Lumpur and Putrajaya).
_KL_CENTRE = {"latitude": 3.1390, "longitude": 101.6869}
_BIAS_RADIUS_METRES = 50_000.0


@router.get(
    "/search",
    response_model=list[PlaceSuggestion],
    summary="Premise / place autocomplete (S11)",
)
async def search_places(q: str = Query(min_length=2, max_length=200)) -> list[PlaceSuggestion]:
    _require_key()

    body = {
        "input": q,
        "locationBias": {
            "circle": {"center": _KL_CENTRE, "radius": _BIAS_RADIUS_METRES}
        },
        "includedRegionCodes": ["my"],
    }
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.server_maps_key,
        "X-Goog-FieldMask": "suggestions.placePrediction",
    }

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            response = await client.post(_AUTOCOMPLETE_URL, json=body, headers=headers)
        except httpx.RequestError as exc:
            raise _upstream_unavailable() from exc

    if response.status_code != 200:
        raise _upstream_unavailable()

    suggestions = []
    for item in response.json().get("suggestions", []):
        prediction = item.get("placePrediction", {})
        text = prediction.get("structuredFormat", {})
        suggestions.append(
            PlaceSuggestion(
                place_id=prediction.get("placeId", ""),
                description=prediction.get("text", {}).get("text", ""),
                main_text=text.get("mainText", {}).get("text"),
                secondary_text=text.get("secondaryText", {}).get("text"),
            )
        )
    return suggestions


@router.get(
    "/reverse",
    response_model=ReverseGeocodeResult,
    summary="Reverse geocode the tagged pin (S11)",
)
async def reverse_geocode(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
) -> ReverseGeocodeResult:
    """Resolve coordinates to an address and a suggested premise name.

    The premise name is only a suggestion — S11 pre-fills the field with it and
    the reporter may edit or clear it. It is free text, not a category, and is
    never used for aggregation.
    """
    _require_key()

    params = {"latlng": f"{lat},{lng}", "key": settings.server_maps_key}

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            response = await client.get(_GEOCODE_URL, params=params)
        except httpx.RequestError as exc:
            raise _upstream_unavailable() from exc

    if response.status_code != 200:
        raise _upstream_unavailable()

    results = response.json().get("results", [])
    if not results:
        return ReverseGeocodeResult(address_text=None, premise_name=None)

    best = results[0]
    premise_name = None
    for component in best.get("address_components", []):
        if {"point_of_interest", "establishment", "premise"} & set(
            component.get("types", [])
        ):
            premise_name = component.get("long_name")
            break

    return ReverseGeocodeResult(
        address_text=best.get("formatted_address"), premise_name=premise_name
    )


def _require_key() -> None:
    if not settings.server_maps_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "SERVER_MAPS_KEY is not configured. Set it in backend/.env to "
                "enable place search and reverse geocoding."
            ),
        )


def _upstream_unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail="The mapping service is unavailable. Please try again.",
    )

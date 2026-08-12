"""AI classification module — Vision Transformer evidence validation (S10).

=========================  PHASE 2 STUB  =========================
This returns synthetic confidence scores. It exists so the mobile
application and the dashboard can be built end to end before the model
exists, which is what lets Phase 3 and Phase 4 run in parallel.

Phase 3 replaces the body of ``_score_image`` with real inference. Nothing
else in this file, and nothing outside it, needs to change: the public
signature of ``classify_photos`` is the contract.

Set STUB_MODE=false in .env once the model is wired in.
==================================================================

The rules implemented here are confirmed decisions, not defaults:

- A report passes when AT LEAST ONE photograph clears the threshold
  (SCOPE-System-Flow-Revised.md section 8).
- Photographs that fail are dropped from the report automatically; the
  reporter is told which ones and why, and is not required to retake them.
- Only a total failure returns the reporter to S08.
- The threshold is read from settings per request, never captured at import
  time, so it stays retunable without a new mobile build (section S10).
"""

from __future__ import annotations

import datetime as dt
import hashlib
from dataclasses import dataclass, field

from app.config import get_settings

settings = get_settings()

OUTCOME_PASS = "PASS"
OUTCOME_FAIL = "FAIL"

# Reasons shown to the reporter on a failing photograph. They must be
# actionable — "no cigarette detected" tells the reporter what to change,
# "validation failed" does not.
REASON_NO_CIGARETTE = "No lit cigarette detected"
REASON_TOO_BLURRY = "Image too blurry"
REASON_TOO_FAR = "Subject too far from camera"


@dataclass
class PhotoResult:
    index: int
    filename: str
    staged_filename: str
    confidence: float
    passed: bool
    reason: str | None = None


@dataclass
class ClassificationResult:
    outcome: str
    model_version: str
    threshold_used: float
    highest_confidence: float
    photos_evaluated: int
    photos_passed: int
    evaluated_at: dt.datetime
    photos: list[PhotoResult] = field(default_factory=list)

    @property
    def passing_photos(self) -> list[PhotoResult]:
        return [p for p in self.photos if p.passed]


def classify_photos(images: list[tuple[str, str, bytes]]) -> ClassificationResult:
    """Evaluate 1-3 photographs.

    Args:
        images: ``(original_filename, staged_filename, image_bytes)`` per photo.

    Returns:
        A :class:`ClassificationResult`. ``outcome`` is PASS when at least one
        photograph cleared the threshold, FAIL when none did.
    """
    threshold = settings.ai_confidence_threshold
    results: list[PhotoResult] = []

    for index, (original_name, staged_name, data) in enumerate(images):
        confidence = _score_image(data)
        passed = confidence >= threshold
        results.append(
            PhotoResult(
                index=index,
                filename=original_name,
                staged_filename=staged_name,
                confidence=round(confidence, 4),
                passed=passed,
                reason=None if passed else _failure_reason(confidence),
            )
        )

    passed_count = sum(1 for r in results if r.passed)
    highest = max((r.confidence for r in results), default=0.0)

    return ClassificationResult(
        outcome=OUTCOME_PASS if passed_count >= 1 else OUTCOME_FAIL,
        model_version=settings.ai_model_version,
        threshold_used=threshold,
        highest_confidence=highest,
        photos_evaluated=len(results),
        photos_passed=passed_count,
        evaluated_at=dt.datetime.now(dt.timezone.utc),
        photos=results,
    )


def _score_image(data: bytes) -> float:
    """Return P(smoking violation) for one image.

    STUB. Derives a stable pseudo-score from the image bytes, so the same
    photograph always yields the same result — a random score per call would
    make the mobile app's retry paths untestable.

    Phase 3 replaces this with:

        inputs = processor(images=Image.open(BytesIO(data)), return_tensors="tf")
        logits = _model(**inputs).logits
        return float(tf.nn.softmax(logits, axis=-1)[0][POSITIVE_CLASS_INDEX])

    with the model loaded once at startup, never per request.
    """
    digest = hashlib.sha256(data).digest()
    # Two bytes -> 0.0000-1.0000, uniform enough to exercise both branches.
    raw = int.from_bytes(digest[:2], "big") / 65535.0
    # Skew upward so most test images pass and the happy path is the default
    # during development; roughly one image in six will fail.
    return round(0.55 + raw * 0.45, 4)


def _failure_reason(confidence: float) -> str:
    """Map a low score to an actionable reason.

    STUB. The real implementation should derive blur from a Laplacian variance
    check and subject distance from the detection bounding box, rather than
    inferring both from the confidence score alone.
    """
    if confidence < 0.30:
        return REASON_NO_CIGARETTE
    if confidence < 0.50:
        return REASON_TOO_BLURRY
    return REASON_TOO_FAR

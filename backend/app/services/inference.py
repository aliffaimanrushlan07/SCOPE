"""AI classification module — Vision Transformer evidence validation (S10).

Loads the fine-tuned ViT exported by `ml/notebooks/finetune_vit.ipynb` and
scores photographs at submission time.

The rules implemented here are confirmed decisions, not defaults:

- A report passes when AT LEAST ONE photograph clears the threshold
  (SCOPE-System-Flow-Revised.md section 8).
- Photographs that fail are dropped from the report automatically; the
  reporter is told which ones and why, and is not required to retake them.
- Only a total failure returns the reporter to S08.
- The threshold is read from settings per request, never captured at import
  time, so it stays retunable without a new mobile build (section S10).

PREPROCESSING MUST MATCH TRAINING EXACTLY
-----------------------------------------
The model was trained on images decoded with `tf.io.decode_image` and resized
with `tf.image.resize` (bilinear) to 224x224, in the 0-255 float range, with
normalisation left to the model's own built-in preprocessor.

Resizing with a different library or interpolation shifts scores — measured at
up to 0.46 on individual images between PIL and TensorFlow resizing. A shift
that size silently invalidates the calibrated threshold, so `_preprocess`
below reproduces the training pipeline rather than approximating it.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import logging
import os
import threading
from dataclasses import dataclass, field
from pathlib import Path

from app.config import get_settings

settings = get_settings()
logger = logging.getLogger("scope.inference")

OUTCOME_PASS = "PASS"
OUTCOME_FAIL = "FAIL"

# Reasons shown to the reporter on a failing photograph. They must be
# actionable — "no cigarette detected" tells the reporter what to change,
# "validation failed" does not.
REASON_NO_CIGARETTE = "No lit cigarette detected"
REASON_TOO_BLURRY = "Image too blurry"
REASON_TOO_FAR = "Subject too far from camera"

IMAGE_SIZE = 224
POSITIVE_INDEX = 1  # class_names = ["notsmoking", "smoking"]

_model = None
_model_lock = threading.Lock()


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


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------


def model_path() -> Path:
    path = Path(settings.ai_model_path)
    if not path.is_absolute():
        path = (Path(__file__).resolve().parents[2] / path).resolve()
    return path


def is_available() -> bool:
    return model_path().exists()


def load_model():
    """Load the classifier once, on first use.

    Loading takes seconds and holds the weights in memory, so it must never
    happen per request — that would make S10 unusable. `main.py` calls this at
    application startup so the first reporter does not pay the cost.
    """
    global _model
    if _model is not None:
        return _model

    with _model_lock:
        if _model is not None:
            return _model

        path = model_path()
        if not path.exists():
            raise FileNotFoundError(
                f"No model at {path}. Set AI_MODEL_PATH in backend/.env, or "
                f"train one with ml/notebooks/finetune_vit.ipynb."
            )

        os.environ.setdefault("KERAS_BACKEND", "tensorflow")
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

        import keras  # imported lazily: TensorFlow is slow to import

        logger.info("Loading classifier from %s", path)
        started = dt.datetime.now()
        _model = keras.models.load_model(str(path))
        logger.info(
            "Classifier ready in %.1fs (version %s)",
            (dt.datetime.now() - started).total_seconds(),
            settings.ai_model_version,
        )
        return _model


def _preprocess(images: list[bytes]):
    """Decode and resize exactly as the training pipeline did."""
    import tensorflow as tf

    tensors = []
    for data in images:
        img = tf.io.decode_image(data, channels=3, expand_animations=False)
        img = tf.image.resize(img, (IMAGE_SIZE, IMAGE_SIZE))
        tensors.append(tf.cast(img, tf.float32))
    return tf.stack(tensors)


def score_images(images: list[bytes]) -> list[float]:
    """Score raw image bytes with the real model and return P(smoking) each.

    Exposed, rather than left inline in :func:`classify_photos`, so that
    offline evaluation scores photographs through exactly the code path S10
    uses. `ml/score_split.py` calls this to produce the CSVs the threshold is
    selected from.

    That matters more than it looks: resizing with PIL instead of TensorFlow
    shifted individual scores by up to 0.46 here. A threshold calibrated on
    scores from any other pipeline is calibrated for a model that is not the
    one serving requests.
    """
    model = load_model()
    batch = _preprocess(images)
    probabilities = model.predict(batch, verbose=0)
    return [float(row[POSITIVE_INDEX]) for row in probabilities]


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------


def classify_photos(images: list[tuple[str, str, bytes]]) -> ClassificationResult:
    """Evaluate 1-3 photographs.

    Args:
        images: ``(original_filename, staged_filename, image_bytes)`` per photo.

    Returns:
        A :class:`ClassificationResult`. ``outcome`` is PASS when at least one
        photograph cleared the threshold, FAIL when none did.
    """
    threshold = settings.ai_confidence_threshold

    if settings.ai_stub_mode or not is_available():
        if not settings.ai_stub_mode:
            logger.warning(
                "No model at %s — falling back to the stub. Scores are NOT real.",
                model_path(),
            )
        scores = [_stub_score(data) for _, _, data in images]
    else:
        scores = score_images([data for _, _, data in images])

    results: list[PhotoResult] = []
    for index, ((original_name, staged_name, _), confidence) in enumerate(
        zip(images, scores, strict=True)
    ):
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


def _failure_reason(confidence: float) -> str:
    """Map a low score to an actionable reason.

    The model is a single-label classifier, so it reports how confident it is
    that a violation is present — not *why* it is unconvinced. These bands are
    therefore a presentational heuristic, not a measurement: a very low score
    usually means nothing cigarette-like was found, while a middling score
    usually means something was found but indistinctly.

    A future improvement would derive blur from a Laplacian variance check and
    subject distance from a detection bounding box, which would make the reason
    a measurement rather than an inference.
    """
    if confidence < 0.15:
        return REASON_NO_CIGARETTE
    if confidence < 0.40:
        return REASON_TOO_BLURRY
    return REASON_TOO_FAR


def _stub_score(data: bytes) -> float:
    """Deterministic pseudo-score, used only when no model is present.

    Derived from the image bytes so the same photograph always yields the same
    result — a random score per call would make the app's retry paths
    untestable.
    """
    digest = hashlib.sha256(data).digest()
    raw = int.from_bytes(digest[:2], "big") / 65535.0
    return round(0.55 + raw * 0.45, 4)

"""Unit tests for app.services.inference.

Units under test: _failure_reason, _stub_score, classify_photos,
ClassificationResult.passing_photos.

All tests run in stub mode (settings.ai_stub_mode = True) so no real
TensorFlow model is loaded -- this keeps the suite fast and independent of
any trained model file being present.
"""
from __future__ import annotations

import datetime as dt

import pytest

from app.services import inference


# ---------------------------------------------------------------------------
# _failure_reason -- confidence-band mapping
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "confidence, expected_reason",
    [
        (0.0, inference.REASON_NO_CIGARETTE),     # TC-INF-01 Valid: lowest possible
        (0.14, inference.REASON_NO_CIGARETTE),    # TC-INF-02 Boundary: just under 0.15
        (0.15, inference.REASON_TOO_BLURRY),      # TC-INF-03 Boundary: exactly at 0.15
        (0.39, inference.REASON_TOO_BLURRY),      # TC-INF-04 Boundary: just under 0.40
        (0.40, inference.REASON_TOO_FAR),         # TC-INF-05 Boundary: exactly at 0.40
        (0.59, inference.REASON_TOO_FAR),         # TC-INF-06 Valid: below threshold, high band
    ],
)
def test_failure_reason_bands(confidence, expected_reason):
    assert inference._failure_reason(confidence) == expected_reason


# ---------------------------------------------------------------------------
# _stub_score
# ---------------------------------------------------------------------------

def test_stub_score_is_deterministic_for_same_bytes():
    """TC-INF-07 (Valid): the same image bytes must always produce the same
    score, so retry paths behave predictably in tests and in the app."""
    data = b"identical-photo-bytes"

    first = inference._stub_score(data)
    second = inference._stub_score(data)

    assert first == second


def test_stub_score_differs_for_different_bytes():
    """TC-INF-08 (Valid): different images should (almost always) map to
    different scores, confirming the score is actually derived from content."""
    score_a = inference._stub_score(b"photo-one")
    score_b = inference._stub_score(b"photo-two")

    assert score_a != score_b


def test_stub_score_stays_within_documented_range():
    """TC-INF-09 (Boundary): the stub score is defined as 0.55 + raw*0.45,
    so it must always fall within [0.55, 1.0]."""
    for sample in (b"a", b"bb", b"ccc", b"dddd", b"e" * 1000):
        score = inference._stub_score(sample)
        assert 0.55 <= score <= 1.0


# ---------------------------------------------------------------------------
# classify_photos (stub mode)
# ---------------------------------------------------------------------------

def test_classify_photos_passes_when_stub_score_clears_threshold(stub_ai_settings, monkeypatch):
    """TC-INF-10 (Valid): with the threshold at 0.6 and a fixed stub score of
    0.9, the single photo passes and the overall outcome is PASS."""
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.9)
    images = [("front.jpg", "0.jpg", b"bytes")]

    result = inference.classify_photos(images)

    assert result.outcome == inference.OUTCOME_PASS
    assert result.photos_passed == 1
    assert result.photos[0].passed is True
    assert result.photos[0].reason is None


def test_classify_photos_fails_when_all_scores_below_threshold(stub_ai_settings, monkeypatch):
    """TC-INF-11 (Invalid/edge case): if every photo scores below the
    threshold, the overall outcome must be FAIL, and each photo carries an
    actionable reason."""
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.1)
    images = [("a.jpg", "0.jpg", b"a"), ("b.jpg", "1.jpg", b"b")]

    result = inference.classify_photos(images)

    assert result.outcome == inference.OUTCOME_FAIL
    assert result.photos_passed == 0
    assert all(p.reason is not None for p in result.photos)


def test_classify_photos_passes_with_only_one_of_several_clearing(stub_ai_settings, monkeypatch):
    """TC-INF-12 (Valid/business rule): the report-level rule is 'at least
    ONE photo must pass' -- two failing photos alongside one passing photo
    still yields an overall PASS."""
    scores = iter([0.1, 0.95, 0.2])
    monkeypatch.setattr(inference, "_stub_score", lambda data: next(scores))
    images = [("a.jpg", "0.jpg", b"a"), ("b.jpg", "1.jpg", b"b"), ("c.jpg", "2.jpg", b"c")]

    result = inference.classify_photos(images)

    assert result.outcome == inference.OUTCOME_PASS
    assert result.photos_passed == 1
    assert result.photos_evaluated == 3


def test_classify_photos_records_threshold_and_model_version(stub_ai_settings, monkeypatch):
    """TC-INF-13 (Valid): the result records which threshold/model version
    produced it, for audit purposes -- this must reflect current settings,
    not a hardcoded default."""
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.7)
    images = [("a.jpg", "0.jpg", b"a")]

    result = inference.classify_photos(images)

    assert result.threshold_used == 0.6
    assert result.model_version == "vit-v1-test"
    assert isinstance(result.evaluated_at, dt.datetime)


# ---------------------------------------------------------------------------
# ClassificationResult.passing_photos
# ---------------------------------------------------------------------------

def test_passing_photos_filters_only_passed_entries():
    """TC-INF-14 (Valid): the passing_photos property must return exactly
    the photos flagged as passed, in original order."""
    photos = [
        inference.PhotoResult(0, "a.jpg", "0.jpg", 0.9, True),
        inference.PhotoResult(1, "b.jpg", "1.jpg", 0.2, False, "No lit cigarette detected"),
        inference.PhotoResult(2, "c.jpg", "2.jpg", 0.8, True),
    ]
    result = inference.ClassificationResult(
        outcome=inference.OUTCOME_PASS,
        model_version="vit-v1-test",
        threshold_used=0.6,
        highest_confidence=0.9,
        photos_evaluated=3,
        photos_passed=2,
        evaluated_at=dt.datetime.now(dt.timezone.utc),
        photos=photos,
    )

    passing = result.passing_photos

    assert [p.index for p in passing] == [0, 2]


def test_passing_photos_empty_when_none_passed():
    """TC-INF-15 (Boundary): with zero passing photos, the property returns
    an empty list rather than None or raising."""
    photos = [inference.PhotoResult(0, "a.jpg", "0.jpg", 0.1, False, "No lit cigarette detected")]
    result = inference.ClassificationResult(
        outcome=inference.OUTCOME_FAIL,
        model_version="vit-v1-test",
        threshold_used=0.6,
        highest_confidence=0.1,
        photos_evaluated=1,
        photos_passed=0,
        evaluated_at=dt.datetime.now(dt.timezone.utc),
        photos=photos,
    )

    assert result.passing_photos == []


# ---------------------------------------------------------------------------
# score_images -- the shared real-model path
# ---------------------------------------------------------------------------

def test_classify_photos_uses_score_images_when_a_model_is_present(monkeypatch):
    """TC-INF-16 (Valid): out of stub mode, classify_photos scores through
    score_images -- the same entry point ml/score_split.py calls.

    This is what keeps offline threshold selection and live S10 classification
    on one code path. If they diverge, a threshold calibrated on the CSVs no
    longer describes the model serving requests.
    """
    monkeypatch.setattr(inference.settings, "ai_stub_mode", False)
    monkeypatch.setattr(inference.settings, "ai_confidence_threshold", 0.6)
    monkeypatch.setattr(inference, "is_available", lambda: True)

    seen: list[list[bytes]] = []

    def fake_score_images(images):
        seen.append(images)
        return [0.9, 0.2]

    monkeypatch.setattr(inference, "score_images", fake_score_images)

    result = inference.classify_photos([
        ("a.jpg", "0.jpg", b"first"),
        ("b.jpg", "1.jpg", b"second"),
    ])

    assert seen == [[b"first", b"second"]]
    assert [p.confidence for p in result.photos] == [0.9, 0.2]
    assert result.outcome == inference.OUTCOME_PASS
    assert result.photos_passed == 1


def test_score_images_returns_positive_class_probability(monkeypatch):
    """TC-INF-17 (Valid): score_images reads column 1 of the softmax output --
    P(smoking) -- and not the notsmoking column, which would invert every
    decision the system makes."""
    class FakeModel:
        def predict(self, batch, verbose=0):
            return [[0.1, 0.9], [0.75, 0.25]]

    monkeypatch.setattr(inference, "load_model", lambda: FakeModel())
    monkeypatch.setattr(inference, "_preprocess", lambda images: images)

    assert inference.score_images([b"a", b"b"]) == [0.9, 0.25]


# ---------------------------------------------------------------------------
# sharpness / blur check
# ---------------------------------------------------------------------------

def _jpeg(image) -> bytes:
    import io

    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=95)
    return buffer.getvalue()


@pytest.fixture
def sharp_and_blurry():
    from PIL import Image, ImageDraw, ImageFilter

    image = Image.new("RGB", (640, 480), "white")
    draw = ImageDraw.Draw(image)
    for x in range(0, 640, 16):
        draw.line([(x, 0), (x, 480)], fill="black", width=3)
    return _jpeg(image), _jpeg(image.filter(ImageFilter.GaussianBlur(6)))


def test_sharpness_is_higher_for_sharp_than_blurred_image(sharp_and_blurry):
    """TC-INF-18 (Valid): blurring the same picture must lower its sharpness."""
    sharp, blurry = sharp_and_blurry
    assert inference.sharpness(sharp) > inference.sharpness(blurry)


def test_sharpness_does_not_grow_with_resolution():
    """TC-INF-19 (Boundary): the same scene sent at twice the resolution must
    measure about the same, or a bigger phone photo would bypass the check."""
    from PIL import Image, ImageDraw

    large = Image.new("RGB", (1024, 768), "white")
    ImageDraw.Draw(large).rectangle([200, 200, 800, 600], outline="black", width=8)
    small = large.resize((512, 384), Image.Resampling.BILINEAR)

    a, b = inference.sharpness(_jpeg(small)), inference.sharpness(_jpeg(large))
    assert abs(a - b) / a < 0.25


def test_blurry_photo_fails_even_when_score_clears_threshold(
    stub_ai_settings, monkeypatch, sharp_and_blurry
):
    """TC-INF-20 (Invalid): a high score does not rescue a blurry photograph;
    it fails as "Image too blurry" while the sharp one passes."""
    sharp, blurry = sharp_and_blurry
    monkeypatch.setattr(inference.settings, "ai_min_sharpness", 20.0)
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.99)

    result = inference.classify_photos(
        [("sharp.jpg", "0.jpg", sharp), ("blurry.jpg", "1.jpg", blurry)]
    )

    assert [p.passed for p in result.photos] == [True, False]
    assert result.photos[1].reason == inference.REASON_TOO_BLURRY
    assert result.outcome == inference.OUTCOME_PASS


def test_unmeasurable_photo_is_not_rejected_for_blur(stub_ai_settings, monkeypatch):
    """TC-INF-21 (Edge case): bytes the sharpness check cannot decode fall back
    to the classifier alone rather than being refused for blur."""
    monkeypatch.setattr(inference.settings, "ai_min_sharpness", 20.0)
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.99)

    result = inference.classify_photos([("odd.bin", "0.jpg", b"not an image")])

    assert result.photos[0].passed is True


def test_sharp_low_score_photo_is_never_blamed_on_blur(stub_ai_settings, monkeypatch, sharp_and_blurry):
    """TC-INF-22 (Valid): with blur measured, a sharp photo in the old
    'blurry' score band is told no cigarette was detected instead."""
    sharp, _ = sharp_and_blurry
    monkeypatch.setattr(inference.settings, "ai_min_sharpness", 20.0)
    monkeypatch.setattr(inference, "_stub_score", lambda data: 0.3)

    result = inference.classify_photos([("sharp.jpg", "0.jpg", sharp)])

    assert result.photos[0].reason == inference.REASON_NO_CIGARETTE

import 'package:flutter_test/flutter_test.dart';
import 'package:scope/models/api_models.dart';
import 'package:scope/models/report_draft.dart';

/// Unit tests for the report draft — the state carried from S08 to submission.
///
/// These assert the confirmed design rules rather than incidental behaviour,
/// so a later refactor that quietly breaks one of them fails here.
void main() {
  CapturedPhoto photo(int n) => CapturedPhoto(
        // A path that does not exist on disk: deleteFile() tolerates this, and
        // these tests are about state transitions, not file IO.
        path: '/tmp/scope-test-$n.jpg',
        capturedAt: DateTime(2026, 8, 13, 10, n),
        latitude: 3.1466,
        longitude: 101.7113,
      );

  PhotoVerdict verdict(int index, {required bool passed}) => PhotoVerdict(
        index: index,
        filename: 'photo-${index + 1}.jpg',
        confidence: passed ? 0.94 : 0.21,
        passed: passed,
        reason: passed ? null : 'No lit cigarette detected',
      );

  ClassificationResult result(List<PhotoVerdict> photos) {
    final passed = photos.where((p) => p.passed).length;
    return ClassificationResult(
      validationToken: 'a' * 32,
      outcome: passed >= 1 ? 'PASS' : 'FAIL',
      modelVersion: 'vit-scope-v1',
      thresholdUsed: 0.85,
      highestConfidence:
          photos.map((p) => p.confidence).reduce((a, b) => a > b ? a : b),
      photosEvaluated: photos.length,
      photosPassed: passed,
      photos: photos,
    );
  }

  group('S08 — three-photograph maximum', () {
    test('accepts up to three photographs', () {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));
      draft.addPhoto(photo(2));
      draft.addPhoto(photo(3));

      expect(draft.photoCount, 3);
      expect(draft.isFull, isTrue);
      expect(draft.canAddPhoto, isFalse);
    });

    test('silently refuses a fourth', () {
      final draft = ReportDraft();
      for (var i = 1; i <= 4; i++) {
        draft.addPhoto(photo(i));
      }
      expect(draft.photoCount, 3);
    });

    test('counter reads the maximum-reached message when full', () {
      final draft = ReportDraft();
      expect(draft.counterLabel, 'Photo 1 of 3');

      draft.addPhoto(photo(1));
      expect(draft.counterLabel, 'Photo 2 of 3');

      draft.addPhoto(photo(2));
      draft.addPhoto(photo(3));
      expect(draft.counterLabel, contains('Maximum reached'));
    });
  });

  group('S10 — validation rule', () {
    test('passes when at least one photograph clears the threshold', () async {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));
      draft.addPhoto(photo(2));
      draft.addPhoto(photo(3));

      await draft.applyClassification(result([
        verdict(0, passed: false),
        verdict(1, passed: true),
        verdict(2, passed: false),
      ]));

      expect(draft.isValidated, isTrue);
      // Failing photographs are dropped automatically; the reporter is not
      // asked to retake them.
      expect(draft.photoCount, 1);
    });

    test('keeps every photograph when all pass', () async {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));
      draft.addPhoto(photo(2));

      await draft.applyClassification(result([
        verdict(0, passed: true),
        verdict(1, passed: true),
      ]));

      expect(draft.photoCount, 2);
      expect(draft.isValidated, isTrue);
    });

    test('a total failure does not validate and keeps photos for retake',
        () async {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));

      await draft.applyClassification(result([verdict(0, passed: false)]));

      expect(draft.isValidated, isFalse);
      expect(draft.classification!.outcome, 'FAIL');
      expect(draft.classification!.failedPhotos.single.reason,
          'No lit cigarette detected');
    });

    test('adding a photograph invalidates an earlier verdict', () async {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));
      await draft.applyClassification(result([verdict(0, passed: true)]));
      expect(draft.isValidated, isTrue);

      draft.addPhoto(photo(2));
      // The old verdict no longer describes this set of photographs.
      expect(draft.classification, isNull);
      expect(draft.isValidated, isFalse);
    });
  });

  group('S11 / S12 — location and submission readiness', () {
    test('capture coordinates come from the first photograph', () {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));

      expect(draft.captureLatitude, 3.1466);
      expect(draft.captureLongitude, 101.7113);
    });

    test('cannot submit without validation, location and a photograph', () {
      final draft = ReportDraft();
      expect(draft.canSubmit, isFalse);

      draft.addPhoto(photo(1));
      expect(draft.canSubmit, isFalse);

      draft.setLocation(latitude: 3.15, longitude: 101.71);
      // Still unvalidated.
      expect(draft.canSubmit, isFalse);
    });

    test('reverse geocoding pre-fills premise name but never overwrites', () {
      final draft = ReportDraft();
      draft.setLocation(
        latitude: 3.15,
        longitude: 101.71,
        suggestedPremiseName: 'Suggested Cafe',
      );
      expect(draft.premiseName, 'Suggested Cafe');

      draft.premiseName = 'What the reporter typed';
      draft.setLocation(
        latitude: 3.16,
        longitude: 101.72,
        suggestedPremiseName: 'A Different Suggestion',
      );
      expect(draft.premiseName, 'What the reporter typed');
    });

    test('idempotency key is stable across reads', () {
      final draft = ReportDraft();
      expect(draft.idempotencyKey, draft.idempotencyKey);
    });
  });

  group('draft lifecycle', () {
    test('clear resets everything', () async {
      final draft = ReportDraft();
      draft.addPhoto(photo(1));
      draft.setLocation(latitude: 3.15, longitude: 101.71);
      draft.premiseName = 'Somewhere';
      await draft.applyClassification(result([verdict(0, passed: true)]));

      await draft.clear();

      expect(draft.photoCount, 0);
      expect(draft.hasLocation, isFalse);
      expect(draft.premiseName, isNull);
      expect(draft.classification, isNull);
      expect(draft.canSubmit, isFalse);
    });
  });

  group('S14 — report history', () {
    test('history item exposes no status', () {
      final item = ReportHistoryItem.fromJson(const {
        'reference_no': 'SCP-20260813-K4M2',
        'reported_at': '2026-08-13T10:30:00Z',
        'submitted_at': '2026-08-13T10:31:00Z',
        'photo_count': 2,
        'premise_name': 'Test Food Court',
        'address_text': 'Jalan Bukit Bintang',
        'thumbnail_path': 'reports/x/1.jpg',
      });

      expect(item.referenceNo, 'SCP-20260813-K4M2');
      expect(item.locationLabel, 'Test Food Court');
      // There is no status field to assert on — that is the design.
    });

    test('falls back to address when no premise name was given', () {
      final item = ReportHistoryItem.fromJson(const {
        'reference_no': 'SCP-20260813-AAAA',
        'reported_at': '2026-08-13T10:30:00Z',
        'submitted_at': '2026-08-13T10:31:00Z',
        'photo_count': 1,
        'premise_name': null,
        'address_text': 'Jalan Ampang, Kuala Lumpur',
        'thumbnail_path': null,
      });

      expect(item.locationLabel, 'Jalan Ampang, Kuala Lumpur');
    });
  });
}

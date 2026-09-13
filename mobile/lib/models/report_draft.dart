import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'api_models.dart';

/// One photograph held in the draft.
///
/// [latitude] and [longitude] are the device position at the moment of
/// capture, not at tagging. Recording them gives the report an evidentiary
/// link between the photograph and the place, and lets the backend flag a
/// report whose tagged location is far from where the photograph was taken.
class CapturedPhoto {
  CapturedPhoto({
    required this.path,
    required this.capturedAt,
    this.latitude,
    this.longitude,
  });

  final String path;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;

  File get file => File(path);

  Future<void> deleteFile() async {
    final f = file;
    if (await f.exists()) await f.delete();
  }
}

/// The report draft, carried from S08 until submission succeeds or the
/// reporter cancels.
///
/// Held in memory and exposed through Provider. It survives the app being
/// backgrounded for as long as the process lives; it is deliberately NOT
/// written to disk, because doing so would leave photographs of identifiable
/// individuals in app storage after an abandoned report.
class ReportDraft extends ChangeNotifier {
  final List<CapturedPhoto> _photos = [];

  ClassificationResult? _classification;
  double? _latitude;
  double? _longitude;
  String? _premiseName;
  String? _addressText;
  DateTime? _reportedAt;

  /// Stable across retries of one submission, so a duplicate tap cannot file
  /// a second report (section 7).
  String? _idempotencyKey;

  // --- Photographs (S08, S09) ----------------------------------------------

  List<CapturedPhoto> get photos => List.unmodifiable(_photos);
  int get photoCount => _photos.length;
  bool get hasPhotos => _photos.isNotEmpty;
  bool get canAddPhoto => _photos.length < AppConfig.maxPhotos;
  bool get isFull => _photos.length >= AppConfig.maxPhotos;

  /// "Photo 2 of 3", or the maximum-reached message from S08.
  String get counterLabel => isFull
      ? 'Maximum reached — review your photos'
      : 'Photo ${_photos.length + 1} of ${AppConfig.maxPhotos}';

  void addPhoto(CapturedPhoto photo) {
    if (!canAddPhoto) return;
    _photos.add(photo);
    // Any earlier verdict no longer describes this set of photographs.
    _classification = null;
    notifyListeners();
  }

  Future<void> removePhotoAt(int index) async {
    if (index < 0 || index >= _photos.length) return;
    final photo = _photos.removeAt(index);
    await photo.deleteFile();
    _classification = null;
    notifyListeners();
  }

  // --- Validation (S10) ----------------------------------------------------

  ClassificationResult? get classification => _classification;
  bool get isValidated => _classification?.passed ?? false;

  /// Records the verdict and drops the photographs that failed.
  ///
  /// Section 8: failing photographs are removed automatically and the reporter
  /// is told which ones and why — they are not required to retake them. Only a
  /// total failure sends the reporter back to S08.
  Future<void> applyClassification(ClassificationResult result) async {
    _classification = result;

    if (result.passed) {
      final failedIndexes = result.photos
          .where((p) => !p.passed)
          .map((p) => p.index)
          .toSet();

      for (final index in failedIndexes.toList()..sort((a, b) => b.compareTo(a))) {
        if (index >= 0 && index < _photos.length) {
          final photo = _photos.removeAt(index);
          await photo.deleteFile();
        }
      }
    }

    notifyListeners();
  }

  // --- Location (S11) ------------------------------------------------------

  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get addressText => _addressText;
  bool get hasLocation => _latitude != null && _longitude != null;

  /// The position recorded when the first photograph was taken. S11 uses this
  /// as the default pin so the reporter confirms rather than searches.
  double? get captureLatitude => _photos.isEmpty ? null : _photos.first.latitude;
  double? get captureLongitude =>
      _photos.isEmpty ? null : _photos.first.longitude;

  void setLocation({
    required double latitude,
    required double longitude,
    String? addressText,
    String? suggestedPremiseName,
  }) {
    _latitude = latitude;
    _longitude = longitude;
    _addressText = addressText;
    // Pre-fill only; the reporter may edit or clear it at S12.
    if (suggestedPremiseName != null && (_premiseName?.isEmpty ?? true)) {
      _premiseName = suggestedPremiseName;
    }
    notifyListeners();
  }

  // --- Review (S12) --------------------------------------------------------

  /// Optional free text. Not a category, and never used for aggregation.
  String? get premiseName => _premiseName;
  set premiseName(String? value) {
    _premiseName = value;
    notifyListeners();
  }

  DateTime get reportedAt => _reportedAt ??= DateTime.now();

  String get idempotencyKey =>
      _idempotencyKey ??= 'draft-${DateTime.now().microsecondsSinceEpoch}';

  bool get canSubmit => isValidated && hasLocation && hasPhotos;

  // --- Lifecycle -----------------------------------------------------------

  /// Clears the draft and deletes every captured file.
  ///
  /// Called when submission succeeds (S13) and when the reporter confirms
  /// discarding a report in progress. Deleting the files matters: they are
  /// photographs of identifiable individuals and should not outlive the draft.
  Future<void> clear() async {
    for (final photo in _photos) {
      await photo.deleteFile();
    }
    _photos.clear();
    _classification = null;
    _latitude = null;
    _longitude = null;
    _premiseName = null;
    _addressText = null;
    _reportedAt = null;
    _idempotencyKey = null;
    notifyListeners();
  }
}

/// Response models mirroring the backend's Pydantic schemas.
library;

/// One photograph's verdict from S10.
class PhotoVerdict {
  const PhotoVerdict({
    required this.index,
    required this.filename,
    required this.confidence,
    required this.passed,
    this.reason,
  });

  final int index;
  final String filename;
  final double confidence;
  final bool passed;

  /// Why the photograph failed, phrased so the retake is actionable:
  /// "No lit cigarette detected", "Image too blurry", "Subject too far".
  final String? reason;

  factory PhotoVerdict.fromJson(Map<String, dynamic> json) => PhotoVerdict(
        index: json['index'] as int,
        filename: json['filename'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        passed: json['passed'] as bool,
        reason: json['reason'] as String?,
      );
}

/// The result of S10 validation.
///
/// Note there is no confidence score the app can alter or resend. The
/// [validationToken] is an opaque handle to the server's own record of this
/// classification; submission presents the token and the server reads back its
/// own scores. The app is not trusted to state them.
class ClassificationResult {
  const ClassificationResult({
    required this.validationToken,
    required this.outcome,
    required this.modelVersion,
    required this.thresholdUsed,
    required this.highestConfidence,
    required this.photosEvaluated,
    required this.photosPassed,
    required this.photos,
  });

  final String validationToken;
  final String outcome;
  final String modelVersion;
  final double thresholdUsed;
  final double highestConfidence;
  final int photosEvaluated;
  final int photosPassed;
  final List<PhotoVerdict> photos;

  /// Section 8: the report proceeds when at least one photograph clears the
  /// threshold. Only a total failure returns the reporter to S08.
  bool get passed => outcome == 'PASS';

  List<PhotoVerdict> get failedPhotos =>
      photos.where((p) => !p.passed).toList(growable: false);

  factory ClassificationResult.fromJson(Map<String, dynamic> json) =>
      ClassificationResult(
        validationToken: json['validation_token'] as String,
        outcome: json['outcome'] as String,
        modelVersion: json['model_version'] as String,
        thresholdUsed: (json['threshold_used'] as num).toDouble(),
        highestConfidence: (json['highest_confidence'] as num).toDouble(),
        photosEvaluated: json['photos_evaluated'] as int,
        photosPassed: json['photos_passed'] as int,
        photos: (json['photos'] as List)
            .map((e) => PhotoVerdict.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// S13 — the outcome of submission.
class SubmissionResult {
  const SubmissionResult({
    required this.referenceNo,
    required this.submittedAt,
    required this.photosStored,
    required this.duplicateSubmission,
  });

  final String referenceNo;
  final DateTime submittedAt;
  final int photosStored;
  final bool duplicateSubmission;

  factory SubmissionResult.fromJson(Map<String, dynamic> json) =>
      SubmissionResult(
        referenceNo: json['reference_no'] as String,
        submittedAt: DateTime.parse(json['submitted_at'] as String),
        photosStored: json['photos_stored'] as int,
        duplicateSubmission: json['duplicate_submission'] as bool? ?? false,
      );
}

/// One of the three fixed awareness slots (S02 carousel, S04 hub).
class Infographic {
  const Infographic({
    required this.id,
    required this.title,
    required this.imagePath,
  });

  final int id;
  final String title;
  final String imagePath;

  factory Infographic.fromJson(Map<String, dynamic> json) => Infographic(
        id: json['infographic_id'] as int,
        title: json['title'] as String,
        imagePath: json['image_path'] as String,
      );
}

/// One row of Report History (S14).
///
/// Carries no status, deliberately. Because evidence is validated before
/// submission and administrators are read-only, nothing in the system can
/// change a report's state after filing. Report History is a receipt log, not
/// a tracker — a status badge would advertise a workflow that does not exist.
class ReportHistoryItem {
  const ReportHistoryItem({
    required this.referenceNo,
    required this.reportedAt,
    required this.submittedAt,
    required this.photoCount,
    this.premiseName,
    this.addressText,
    this.thumbnailPath,
  });

  final String referenceNo;
  final DateTime reportedAt;
  final DateTime submittedAt;
  final int photoCount;
  final String? premiseName;
  final String? addressText;
  final String? thumbnailPath;

  String get locationLabel =>
      premiseName ?? addressText ?? 'Location not recorded';

  factory ReportHistoryItem.fromJson(Map<String, dynamic> json) =>
      ReportHistoryItem(
        referenceNo: json['reference_no'] as String,
        reportedAt: DateTime.parse(json['reported_at'] as String),
        submittedAt: DateTime.parse(json['submitted_at'] as String),
        photoCount: json['photo_count'] as int,
        premiseName: json['premise_name'] as String?,
        addressText: json['address_text'] as String?,
        thumbnailPath: json['thumbnail_path'] as String?,
      );
}

/// A search result resolved to a taggable point (S11).
class PlaceDetail {
  const PlaceDetail({
    required this.placeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final String placeId;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;

  factory PlaceDetail.fromJson(Map<String, dynamic> json) => PlaceDetail(
        placeId: json['place_id'] as String,
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
      );
}

/// One stored photograph on a report detail view.
class ReportPhotoDetail {
  const ReportPhotoDetail({
    required this.sequenceNo,
    required this.storagePath,
    required this.confidenceScore,
    required this.capturedAt,
  });

  final int sequenceNo;
  final String storagePath;
  final double confidenceScore;
  final DateTime capturedAt;

  factory ReportPhotoDetail.fromJson(Map<String, dynamic> json) =>
      ReportPhotoDetail(
        sequenceNo: json['sequence_no'] as int,
        storagePath: json['storage_path'] as String,
        confidenceScore: (json['confidence_score'] as num).toDouble(),
        capturedAt: DateTime.parse(json['captured_at'] as String),
      );
}

/// Read-only detail of a filed report (S14).
class ReportDetail {
  const ReportDetail({
    required this.referenceNo,
    required this.reportedAt,
    required this.submittedAt,
    required this.latitude,
    required this.longitude,
    required this.photos,
    this.premiseName,
    this.addressText,
  });

  final String referenceNo;
  final DateTime reportedAt;
  final DateTime submittedAt;
  final double latitude;
  final double longitude;
  final List<ReportPhotoDetail> photos;
  final String? premiseName;
  final String? addressText;

  String get locationLabel =>
      premiseName ?? addressText ?? 'Location not recorded';

  factory ReportDetail.fromJson(Map<String, dynamic> json) => ReportDetail(
        referenceNo: json['reference_no'] as String,
        reportedAt: DateTime.parse(json['reported_at'] as String),
        submittedAt: DateTime.parse(json['submitted_at'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        premiseName: json['premise_name'] as String?,
        addressText: json['address_text'] as String?,
        photos: (json['photos'] as List)
            .map((e) => ReportPhotoDetail.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// A weighted point of the public density heatmap (S06).
class HotspotPoint {
  const HotspotPoint({
    required this.latitude,
    required this.longitude,
    required this.weight,
  });

  final double latitude;
  final double longitude;
  final int weight;

  factory HotspotPoint.fromJson(Map<String, dynamic> json) => HotspotPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        weight: json['weight'] as int,
      );
}

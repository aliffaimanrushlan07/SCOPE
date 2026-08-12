import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../models/api_models.dart';
import '../models/report_draft.dart';

/// Typed access to the SCOPE backend.
class ScopeApi {
  ScopeApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Resolves a stored media path to a full URL.
  static String mediaUrl(String storagePath) =>
      '${AppConfig.apiBaseUrl}/media/$storagePath';

  // -------------------------------------------------------------------------
  // S10 — evidence validation
  // -------------------------------------------------------------------------

  /// Submits 1-3 photographs for classification.
  ///
  /// Writes nothing to the database: classification precedes persistence, so a
  /// photograph that fails is never stored anywhere.
  Future<ClassificationResult> classify(List<CapturedPhoto> photos) async {
    assert(photos.isNotEmpty && photos.length <= AppConfig.maxPhotos);

    final form = FormData();
    for (var i = 0; i < photos.length; i++) {
      form.files.add(MapEntry(
        'photos',
        await MultipartFile.fromFile(
          photos[i].path,
          filename: 'photo-${i + 1}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      ));
    }

    final response = await _client.post<Map<String, dynamic>>(
      '/classify',
      data: form,
      timeout: AppConfig.classifyTimeout,
    );
    return ClassificationResult.fromJson(response.data!);
  }

  // -------------------------------------------------------------------------
  // S12 / S13 — submission
  // -------------------------------------------------------------------------

  /// Files the report.
  ///
  /// [idempotencyKey] guards the duplicate-submit case in section 7: a repeat
  /// of the same submission returns the original reference number rather than
  /// creating a second report.
  Future<SubmissionResult> submitReport({
    required String validationToken,
    required String deviceId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    String? premiseName,
    String? addressText,
    double? captureLatitude,
    double? captureLongitude,
    String? idempotencyKey,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/reports',
      data: {
        'validation_token': validationToken,
        'device_id': deviceId,
        'latitude': latitude,
        'longitude': longitude,
        'reported_at': reportedAt.toUtc().toIso8601String(),
        if (premiseName != null && premiseName.trim().isNotEmpty)
          'premise_name': premiseName.trim(),
        'address_text': ?addressText,
        'capture_latitude': ?captureLatitude,
        'capture_longitude': ?captureLongitude,
      },
      headers: idempotencyKey == null
          ? null
          : {'Idempotency-Key': idempotencyKey},
    );
    return SubmissionResult.fromJson(response.data!);
  }

  // -------------------------------------------------------------------------
  // S14 — report history
  // -------------------------------------------------------------------------

  Future<List<ReportHistoryItem>> reportHistory(String deviceId) async {
    final response = await _client.get<List<dynamic>>('/reports/device/$deviceId');
    return (response.data ?? [])
        .map((e) => ReportHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // S02 / S04 / S06 — public content
  // -------------------------------------------------------------------------

  Future<List<Infographic>> infographics() async {
    final response = await _client.get<List<dynamic>>('/infographics');
    return (response.data ?? [])
        .map((e) => Infographic.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<HotspotPoint>> hotspots({int days = 365}) async {
    final response =
        await _client.get<List<dynamic>>('/hotspots', query: {'days': days});
    return (response.data ?? [])
        .map((e) => HotspotPoint.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // S11 — mapping, proxied so the server key never ships in the app
  // -------------------------------------------------------------------------

  Future<Map<String, String?>> reverseGeocode(double lat, double lng) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/geo/reverse',
      query: {'lat': lat, 'lng': lng},
    );
    return {
      'address_text': response.data?['address_text'] as String?,
      'premise_name': response.data?['premise_name'] as String?,
    };
  }

  /// True when the backend is reachable. Used by S01 to decide whether Home
  /// should show its offline state.
  Future<bool> ping() async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
      final response = await dio.get<Map<String, dynamic>>('/health');
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  /// Frees a staged validation token's server-side photographs when the
  /// reporter abandons the flow. Best-effort; the server also purges on a TTL.
  Future<void> discard(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

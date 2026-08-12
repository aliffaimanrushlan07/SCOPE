import 'package:dio/dio.dart';

import 'config.dart';

/// Distinguishes the failure modes S10 and S12 must treat differently.
///
/// The distinction that matters most: a network failure or a service timeout
/// is an ERROR, not a validation failure. Section 7 is explicit that a timeout
/// must offer a retry rather than telling the reporter to retake a photograph
/// that was probably fine.
enum ApiFailure {
  network,
  timeout,
  server,
  rejected,
  rateLimited,
  notFound,
}

class ApiException implements Exception {
  ApiException(this.failure, this.message);

  final ApiFailure failure;
  final String message;

  /// True when retrying the same request is the right response, as opposed to
  /// asking the reporter to change something.
  bool get isRetryable =>
      failure == ApiFailure.network ||
      failure == ApiFailure.timeout ||
      failure == ApiFailure.server;

  @override
  String toString() => message;
}

/// Thin wrapper over Dio that turns transport errors into [ApiException].
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
              connectTimeout: AppConfig.requestTimeout,
              receiveTimeout: AppConfig.requestTimeout,
              sendTimeout: AppConfig.requestTimeout,
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;

  Dio get raw => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) =>
      _guard(() => _dio.get<T>(
            path,
            queryParameters: query,
            options: timeout == null ? null : Options(receiveTimeout: timeout),
          ));

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _guard(() => _dio.post<T>(
            path,
            data: data,
            options: Options(
              headers: headers,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          ));

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  ApiException _translate(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          ApiFailure.timeout,
          'The server took too long to respond. Please try again.',
        );

      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return ApiException(
          ApiFailure.network,
          'No connection to the SCOPE service. Check your internet and try again.',
        );

      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final detail = _detailOf(e.response?.data);

        if (status == 429) {
          return ApiException(
            ApiFailure.rateLimited,
            detail ??
                'You have submitted several reports recently. Please try again later.',
          );
        }
        if (status == 404) {
          return ApiException(ApiFailure.notFound, detail ?? 'Not found.');
        }
        if (status >= 500) {
          return ApiException(
            ApiFailure.server,
            'The SCOPE service is having a problem. Please try again.',
          );
        }
        return ApiException(
          ApiFailure.rejected,
          detail ?? 'The request could not be completed.',
        );

      default:
        return ApiException(
          ApiFailure.network,
          'Something went wrong. Please try again.',
        );
    }
  }

  String? _detailOf(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) return detail;
      // FastAPI validation errors arrive as a list of objects.
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
    }
    return null;
  }
}

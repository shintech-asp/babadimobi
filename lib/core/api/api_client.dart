import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/auth/auth_storage.dart';

// ── Dio provider ──────────────────────────────────────────────────────────────

/// Returns a fully configured [Dio] instance with JWT and error interceptors.
///
/// Consume via `ref.read(dioProvider)` in other providers, or inject into
/// feature-level API classes that themselves live inside Riverpod providers.
final Provider<Dio> dioProvider = Provider<Dio>((ref) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      // PHP returns JSON; accept it explicitly.
      headers: <String, String>{
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.addAll([
    _JwtInterceptor(),
    const _ErrorInterceptor(),
  ]);

  return dio;
});

// ── JWT interceptor ───────────────────────────────────────────────────────────

/// Reads the stored JWT before every request and attaches it as a
/// `Authorization: Bearer <token>` header.
///
/// Requests that already carry an `Authorization` header (e.g. the login
/// call) are left untouched.
class _JwtInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!options.headers.containsKey('Authorization')) {
      final String? token = await AuthStorage.getToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}

// ── Error interceptor ─────────────────────────────────────────────────────────

/// Handles error responses uniformly:
///
/// * **401** — re-throws with a clear message but does NOT auto-logout.
///   Session expiry is handled at app startup by SplashScreen → AuthNotifier.init().
/// * All others — extracts the PHP `message` field from the response body
///   and re-throws a [DioException] with a human-readable message.
class _ErrorInterceptor extends Interceptor {
  const _ErrorInterceptor();

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int? statusCode = err.response?.statusCode;

    if (statusCode == 401) {
      // Re-throw with a clear message but do NOT auto-logout.
      // Session expiry is handled at app startup by SplashScreen → AuthNotifier.init().
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: err.type,
          message: 'Session expired. Please log in again.',
        ),
        true,
      );
      return;
    }

    // For all other HTTP errors, surface the PHP-provided message if present.
    final String message = _extractMessage(err);
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: err.error,
        message: message,
      ),
    );
  }

  /// Pulls `response.data['message']` from the PHP error envelope, falling
  /// back to the raw Dio message when the body is absent or malformed.
  static String _extractMessage(DioException err) {
    try {
      final dynamic data = err.response?.data;
      if (data is Map<String, dynamic>) {
        final dynamic msg = data['error'] ?? data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // Ignore parse failures; use the fallback below.
    }
    return err.message ?? 'An unexpected error occurred.';
  }
}

// ── Convenience helper ────────────────────────────────────────────────────────

/// Validates that [response] carries `"ok": true` and returns its `data`
/// field. Throws a [StateError] if the response shape deviates from the
/// PHP contract.
///
/// Use this inside feature-level API methods:
/// ```dart
/// final res = await dio.get(ApiEndpoints.listings);
/// return ApiClient.unwrap(res);
/// ```
abstract class ApiClient {
  ApiClient._();

  /// Unwraps `{ "ok": true, "data": ... }` and returns the `data` value.
  ///
  /// Throws [StateError] if `ok` is false or the key is missing.
  static dynamic unwrap(Response<dynamic> response) {
    final dynamic body = response.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) return body['data'];
      final dynamic msg = body['error'] ?? body['message'];
      throw StateError(
        msg is String && msg.isNotEmpty ? msg : 'API returned ok=false.',
      );
    }
    throw StateError('Unexpected response format from server.');
  }
}

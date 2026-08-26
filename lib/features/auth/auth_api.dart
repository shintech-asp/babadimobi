import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_client.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';

/// Wraps all auth-related PHP endpoints under `api/v1/auth/`.
///
/// Every method either:
/// - returns the unwrapped `data` payload on success, or
/// - throws an [Exception] whose message comes from the PHP `message` field.
///
/// The [Dio] instance is injected so the JWT and error interceptors in
/// [api_client.dart] remain active for all requests.
class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  // ── login ──────────────────────────────────────────────────────────────────

  /// Authenticates a user of any type (seeker, provider, admin, portal staff).
  ///
  /// PHP endpoint: `POST auth/login.php`
  ///
  /// Request body:
  /// ```json
  /// { "username_or_email": "...", "password": "..." }
  /// ```
  ///
  /// Success response shape (inside `data`):
  /// ```json
  /// {
  ///   "token": "<jwt>",
  ///   "user_type": "seeker",
  ///   "user": { "id": 1, "first_name": "Juan", "email": "..." }
  /// }
  /// ```
  ///
  /// Returns the full `data` map so the caller can hand the token to
  /// [AuthNotifier.login] and read any user fields it needs.
  ///
  /// Throws [Exception] with the PHP-provided message on failure.
  Future<Map<String, dynamic>> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    final Response<dynamic> res = await _dio.post(
      ApiEndpoints.login,
      data: <String, String>{
        'email': usernameOrEmail,   // PHP field name is 'email' (also accepts username)
        'password': password,
      },
    );

    final dynamic body = res.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) {
        // PHP returns flat: { ok, token, user } — no nested 'data' key.
        return body;
      }
      final dynamic msg = body['error'] ?? body['message'];
      throw Exception(
        msg is String && msg.isNotEmpty ? msg : 'Login failed.',
      );
    }
    throw Exception('Unexpected response format from server.');
  }

  // ── register ───────────────────────────────────────────────────────────────

  /// Registers a new seeker account and triggers OTP email delivery.
  ///
  /// PHP endpoint: `POST auth/register.php`
  ///
  /// Request body:
  /// ```json
  /// {
  ///   "first_name": "Juan",
  ///   "last_name": "dela Cruz",
  ///   "email": "juan@example.com",
  ///   "password": "secret",
  ///   "phone": "09171234567"
  /// }
  /// ```
  ///
  /// Success response: `{ "ok": true }` — no `data` payload.
  ///
  /// Throws [Exception] with the PHP-provided message on failure (e.g. email
  /// already in use, validation error).
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
  }) async {
    final Response<dynamic> res = await _dio.post(
      ApiEndpoints.register,
      data: <String, String>{
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
        'phone': phone,
      },
    );

    final dynamic body = res.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) return;
      final dynamic msg = body['message'];
      throw Exception(
        msg is String && msg.isNotEmpty ? msg : 'Registration failed.',
      );
    }
    throw Exception('Unexpected response format from server.');
  }

  // ── verifyOtp ──────────────────────────────────────────────────────────────

  /// Verifies the one-time password sent to [email] during registration or
  /// a password-reset flow.
  ///
  /// PHP endpoint: `POST auth/verify-otp.php`
  ///
  /// Request body:
  /// ```json
  /// { "email": "juan@example.com", "otp": "123456" }
  /// ```
  ///
  /// Success response: `{ "ok": true }` — no `data` payload.
  ///
  /// Throws [Exception] with the PHP-provided message on failure (e.g. wrong
  /// code, expired OTP).
  Future<void> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final Response<dynamic> res = await _dio.post(
      ApiEndpoints.verifyOtp,
      data: <String, String>{
        'email': email,
        'otp': otp,
      },
    );

    final dynamic body = res.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) return;
      final dynamic msg = body['message'];
      throw Exception(
        msg is String && msg.isNotEmpty ? msg : 'OTP verification failed.',
      );
    }
    throw Exception('Unexpected response format from server.');
  }

  // ── forgotPassword ─────────────────────────────────────────────────────────

  /// Sends a password-reset OTP to [email] if a matching account exists.
  ///
  /// PHP endpoint: `POST auth/forgot-password.php`
  ///
  /// Request body:
  /// ```json
  /// { "email": "juan@example.com" }
  /// ```
  ///
  /// Success response: `{ "ok": true }` — no `data` payload.
  ///
  /// The PHP backend intentionally returns `ok: true` even when the email is
  /// not found, to prevent user-enumeration. The caller should always display
  /// a generic "check your inbox" message regardless.
  ///
  /// Throws [Exception] only on hard errors (validation failure, server error).
  Future<void> forgotPassword({
    required String email,
  }) async {
    final Response<dynamic> res = await _dio.post(
      ApiEndpoints.forgotPassword,
      data: <String, String>{
        'email': email,
      },
    );

    final dynamic body = res.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) return;
      final dynamic msg = body['message'];
      throw Exception(
        msg is String && msg.isNotEmpty ? msg : 'Password reset request failed.',
      );
    }
    throw Exception('Unexpected response format from server.');
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Riverpod provider for [AuthApi].
///
/// Resolves the shared [Dio] instance (with JWT + error interceptors) from
/// [dioProvider] and injects it into [AuthApi].
///
/// Usage:
/// ```dart
/// final authApi = ref.read(authApiProvider);
/// final data = await authApi.login(
///   usernameOrEmail: 'juan@example.com',
///   password: 'secret',
/// );
/// await ref.read(authProvider.notifier).login(data['token'] as String);
/// ```
final Provider<AuthApi> authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});

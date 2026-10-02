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

  /// Authenticates a user of **any** role — seeker, provider, admin, or
  /// portal staff — through one centralized call. Mirrors the web app's
  /// shared `auth/login.php` login page: the PHP endpoint checks
  /// `admin_users` → `provider_staff` (portal staff) → `users` (seeker/
  /// provider) in that order, so there is no separate admin/portal login
  /// screen or endpoint to call — this is the only one.
  ///
  /// PHP endpoint: `POST auth/login.php`
  ///
  /// Request body (the field is named `email` for backward compatibility,
  /// but accepts a username for the admin/portal-staff tiers too):
  /// ```json
  /// { "email": "...", "password": "..." }
  /// ```
  ///
  /// Response is **flat** (not nested under `data`) and its shape depends on
  /// which tier matched — always `token`; `user` for seeker/provider,
  /// `admin` + `must_change_password` for admin, `staff` +
  /// `must_change_password` for portal staff. The caller only needs `token`
  /// to route correctly — [AuthState.userType] is decoded straight from the
  /// JWT, not from this body.
  ///
  /// Throws [Exception] with the PHP-provided message on failure — the
  /// message is always the generic "Invalid credentials" (matching the web),
  /// never reveals which tier (if any) the identifier matched.
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
    String? suffix,
  }) async {
    final Response<dynamic> res = await _dio.post(
      ApiEndpoints.register,
      data: <String, String>{
        'first_name': firstName,
        'last_name': lastName,
        if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
        'email': email,
        'password': password,
        'phone': phone,
        // Mobile self-registration is seeker-only by design — provider
        // sign-up requires business documents + Cavite geofencing + admin
        // review and is handled only on the website. See
        // api/v1/auth/register.php, which rejects any other value.
        'user_type': 'seeker',
      },
    );

    final dynamic body = res.data;
    if (body is Map<String, dynamic>) {
      if (body['ok'] == true) return;
      final dynamic msg = body['error'] ?? body['message'];
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

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_client.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';

/// Admin panel REST API surface (Phase 3 — Dashboard + Provider approval
/// slice only; Users/Bookings/Logs/Subscriptions/HR/Finance are not built).
///
/// Every `api/v1/admin/*` endpoint is guarded by `require_admin_role()` on
/// the PHP side — an admin JWT (issued by the centralized `AuthApi.login()`,
/// which decodes `user_type: 'admin'` from an `admin_users` match) is
/// required for all of these.
class AdminApi {
  const AdminApi(this._dio);

  final Dio _dio;

  static Exception _handleDio(DioException e) {
    final dynamic body = e.response?.data;
    String msg = 'Network error. Please check your connection.';
    if (body is Map<String, dynamic>) {
      final dynamic err = body['error'] ?? body['message'];
      if (err is String && err.isNotEmpty) msg = err;
    }
    return Exception(msg);
  }

  static Exception _handleStateError(StateError e) {
    final String raw = e.message;
    return Exception(raw.isNotEmpty ? raw : 'An unexpected error occurred.');
  }

  /// Platform overview stats. `super_admin`/`admin`/`hr`/`finance` can all
  /// call this (PHP is more permissive than the route table's "super_admin,
  /// admin" would suggest); `super_admin` gets two extra fields
  /// (`active_subscriptions`, `monthly_revenue`).
  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.adminDashboard);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Lists providers with owner info and booking counts.
  /// [status] is `all` (default), `pending`, `approved`, or `rejected` —
  /// filtered against the computed `verification_status`, not the raw
  /// `providers.status` column (see `admin/providers/index.php`).
  /// `super_admin`/`admin` only.
  Future<Map<String, dynamic>> getProviders({
    String status = 'all',
    String? search,
    int page = 1,
  }) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.adminProviders,
        queryParameters: <String, dynamic>{
          'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
        },
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Full provider detail: owner user, listing/booking counts, verification
  /// history. `super_admin`/`admin` only.
  Future<Map<String, dynamic>> getProviderDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.adminProviderDetail,
        queryParameters: <String, dynamic>{'id': id},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Approves a pending provider — sets `providers.status = 'active'` and
  /// `verification_status = 'approved'`.
  Future<void> approveProvider(int id) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.adminProviderApprove,
        data: <String, dynamic>{'id': id},
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Rejects a provider. Only `verification_status` changes to `'rejected'`
  /// — `providers.status` has no such ENUM value, so it's left as-is
  /// server-side (see `admin/providers/reject.php`).
  Future<void> rejectProvider(int id, {String? reason}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.adminProviderReject,
        data: <String, dynamic>{
          'id': id,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  static String _bodyError(dynamic body) {
    return (body is Map
            ? (body['error'] ?? body['message'] ?? 'Server error')
            : 'Server error')
        .toString();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final Provider<AdminApi> adminApiProvider = Provider<AdminApi>(
  (Ref ref) => AdminApi(ref.watch(dioProvider)),
);

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_client.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';

/// Provider-portal REST API surface (Phase 3 — foundation only: identity via
/// [getMe]. HR/Finance/CRM/staff/subscriptions endpoints are added by later
/// phases onto this same class, not a second one, so every portal screen
/// shares one client.)
///
/// A `portal_staff` (promoted owner/hr/finance/crm) or `portal_employee`
/// (plain self-service) JWT — both issued by the centralized
/// `AuthApi.login()` — is required for every `api/v1/portal/*` endpoint,
/// guarded server-side by `require_portal_actor()` (or the stricter
/// `require_portal_role()` for management-only endpoints added later).
class PortalApi {
  const PortalApi(this._dio);

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

  static String _bodyError(dynamic body) {
    return (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
  }

  /// Returns `{'account_type': 'staff'|'employee', 'staff': {...}}` for the
  /// authenticated portal actor — works for both a promoted `provider_staff`
  /// login and a plain `employees` self-service login. Response isn't
  /// wrapped under a `data` key (see `api/v1/portal/auth/me.php`), so this
  /// reads the raw body directly rather than using `ApiClient.unwrap()`.
  Future<Map<String, dynamic>> getMe() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalMe);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Works for either account kind (staff or employee) — the backend reads
  /// the actor from the JWT, not a parameter. Clears must_change_password
  /// (and the stale temp_password) on success.
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalChangePassword,
        data: <String, dynamic>{'current_password': currentPassword, 'new_password': newPassword},
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Employee self-service (attendance, leave, payslips, assigned bookings) ──
  //
  // Works for both account kinds via require_portal_actor() server-side — a
  // plain employees-table login, or a promoted provider_staff account that
  // also has a linked employee record by email (see resolve_portal_login()
  // in api/v1/_bootstrap.php). All fail with a clear 403 if the actor has no
  // linked employee record at all.

  /// Returns `{'data': List, 'today': Map, 'meta': Map}` — this month's (or
  /// [month], `YYYY-MM`) attendance history plus today's clock-in/out state.
  Future<Map<String, dynamic>> getAttendance({String? month}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalMeAttendance,
        queryParameters: <String, dynamic>{
          if (month != null && month.isNotEmpty) 'month': month,
          'limit': 100,
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

  /// Records a self clock-in for right now. Returns `{'message', 'time_in',
  /// 'late_min', 'status'}`.
  Future<Map<String, dynamic>> clockIn() async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalMeClockIn);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Records a self clock-out for right now. Returns `{'message', 'time_in',
  /// 'time_out', 'hours_worked', 'overtime_min', 'undertime_min', 'status'}`.
  Future<Map<String, dynamic>> clockOut() async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalMeClockOut);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns `{'data': List, 'balances': Map<leaveType, {total, used,
  /// remaining, has_override}>, 'meta': Map}`.
  Future<Map<String, dynamic>> getLeaveRequests() async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalMeLeaveRequests,
        queryParameters: <String, dynamic>{'limit': 100},
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

  /// Submits a leave request against the employee's own balance. [leaveType]
  /// is one of annual/sick/personal/maternity/paternity; dates are `Y-m-d`.
  /// Rejected server-side (422) if the requested days exceed the remaining
  /// balance for that leave type/year.
  Future<Map<String, dynamic>> submitLeaveRequest({
    required String leaveType,
    required String startDate,
    required String endDate,
    String? reason,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalMeLeaveRequestStore,
        data: <String, dynamic>{
          'leave_type': leaveType,
          'start_date': startDate,
          'end_date': endDate,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns `{'employee': Map, 'data': List<payslip>, 'meta': Map}` — the
  /// employee's own payroll history, read-only.
  Future<Map<String, dynamic>> getPayslips() async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalMePayslips,
        queryParameters: <String, dynamic>{'limit': 100},
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

  /// Field-technician-only: bookings assigned to this employee, confirmed
  /// (`assigned_employee_id` set via Prepare Booking) or tentative (matched
  /// only via the service's default handler) — 403s for a non-field account.
  Future<Map<String, dynamic>> getMyBookings({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalMeBookings,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': 100,
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

  // ── Subscription (Free/Pro/Grace tier) ──────────────────────────────────────

  /// Returns `{'tier': 'free'|'pro'|'grace', 'tier_expires', 'tier_grace',
  /// 'subscription': Map?, 'plans': List}` — readable by any portal actor
  /// (mirrors the web sidebar showing the tier badge to every role, not just
  /// the owner).
  Future<Map<String, dynamic>> getSubscription() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalSubscriptions);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only: creates a PayMongo checkout session for [planId] billed
  /// [billingCycle] ('monthly'|'yearly') and a pending subscription row.
  /// Returns `{'checkout_url': String, 'subscription_id': int}` — load
  /// `checkout_url` in a WebView. Unlike the web flow, activation does NOT
  /// happen by letting PayMongo's success redirect load (that page requires
  /// a PHP session the WebView doesn't have) — call [confirmSubscription]
  /// instead once the WebView reaches the success/cancel URL.
  Future<Map<String, dynamic>> purchaseSubscription({
    required int planId,
    required String billingCycle,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalSubscriptionStore,
        data: <String, dynamic>{
          'plan_id': planId,
          'billing_cycle': billingCycle,
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

  /// Owner-only: verifies the provider's most recent pending subscription
  /// directly with PayMongo and activates it if paid — the JWT-authenticated
  /// equivalent of `provider-portal/subscription-success.php` (which can't
  /// work from the app; see that PHP file's own doc comment). Safe to call
  /// repeatedly/poll. Returns `{'verified': bool, 'tier': String, 'expires_at':
  /// String?, 'message': String}`.
  Future<Map<String, dynamic>> confirmSubscription() async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalSubscriptionConfirm);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only: activates a true no-payment 1-month free trial — no
  /// PayMongo checkout involved. Only succeeds once per provider ever (see
  /// `getSubscription()`'s `trial_eligible` flag, which should gate whether
  /// this button is even shown). Returns `{'expires_at': String}`.
  Future<Map<String, dynamic>> startTrial() async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalSubscriptionTrial);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Employees (owner/hr) — the HR-record CRUD, distinct from Staff above
  // (which manages provider_staff portal-login accounts, i.e. promoted
  // managers). Mirrors provider-portal/employees.php.

  /// Returns `{'tier': ..., 'data': List<employee>, 'catalog': {...}}` — the
  /// full body (not just `data`), since the catalog (positions/employment
  /// types/departments) is needed for the Add/Edit form's dropdowns.
  Future<Map<String, dynamic>> getEmployees({String? search, String? department, String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalHrEmployees,
        queryParameters: <String, dynamic>{
          if (search != null && search.isNotEmpty) 'search': search,
          if (department != null && department.isNotEmpty) 'department': department,
          if (status != null && status.isNotEmpty) 'status': status,
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

  /// Owner/HR: creates a new employee record — same employee_id/temp
  /// password/welcome-email behavior as the web's Add Employee. Returns
  /// `{'id', 'employee_id', 'temp_password', 'email_sent'}` so the caller
  /// can show the credentials once (not re-shown later, matching web).
  Future<Map<String, dynamic>> createEmployee({
    required String firstName,
    required String lastName,
    required String email,
    String? position,
    String? department,
    double? basicSalary,
    String? hireDate,
    String? employmentType,
    String? staffType,
    String? sssNo,
    String? philhealthNo,
    String? pagibigNo,
    String? tinNo,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalHrEmployeeStore,
        data: <String, dynamic>{
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          if (position != null) 'position': position,
          if (department != null) 'department': department,
          if (basicSalary != null) 'basic_salary': basicSalary.toString(),
          if (hireDate != null) 'hire_date': hireDate,
          if (employmentType != null) 'employment_type': employmentType,
          if (staffType != null) 'staff_type': staffType,
          if (sssNo != null) 'sss_no': sssNo,
          if (philhealthNo != null) 'philhealth_no': philhealthNo,
          if (pagibigNo != null) 'pagibig_no': pagibigNo,
          if (tinNo != null) 'tin_no': tinNo,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/HR: partial update of employee [id]. Pass only changed fields.
  Future<void> updateEmployee({
    required int id,
    String? status,
    String? position,
    String? department,
    String? employmentType,
    String? staffType,
    double? basicSalary,
    String? sssNo,
    String? philhealthNo,
    String? pagibigNo,
    String? tinNo,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalHrEmployeeUpdate,
        data: <String, dynamic>{
          'id': id,
          if (status != null) 'status': status,
          if (position != null) 'position': position,
          if (department != null) 'department': department,
          if (employmentType != null) 'employment_type': employmentType,
          if (staffType != null) 'staff_type': staffType,
          if (basicSalary != null) 'basic_salary': basicSalary.toString(),
          if (sssNo != null) 'sss_no': sssNo,
          if (philhealthNo != null) 'philhealth_no': philhealthNo,
          if (pagibigNo != null) 'pagibig_no': pagibigNo,
          if (tinNo != null) 'tin_no': tinNo,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── HR management (owner/hr; payroll approve/mark-paid is owner/finance) ───
  //
  // List/view endpoints are readable free-tier (mirrors the web pages, which
  // render read-only under a "Free Tier" banner rather than hard-locking);
  // every mutation (approve/reject/grant/override/generate/approve/mark-paid)
  // enforces Pro server-side and surfaces "Pro subscription required..." via
  // the normal error path if called on a free-tier provider.

  /// Owner-only: `{'data': List<staff>}`.
  Future<List<dynamic>> getStaff() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalStaffIndex);
      final dynamic data = ApiClient.unwrap(res);
      return data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only: creates a new hr/finance/crm staff member. [department] is
  /// one of hr/finance/crm/all. Returns the new row, with `temp_password`
  /// included once so the owner can share it (not emailed automatically).
  Future<Map<String, dynamic>> createStaff({
    required String username,
    required String email,
    required String role,
    required String department,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalStaffStore,
        data: <String, dynamic>{'username': username, 'email': email, 'role': role, 'department': department},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only: updates role/department/status of staff [id]. Pass only
  /// the fields being changed.
  Future<Map<String, dynamic>> updateStaff({
    required int id,
    String? role,
    String? department,
    String? status,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalStaffUpdate,
        data: <String, dynamic>{
          'id': id,
          if (role != null) 'role': role,
          if (department != null) 'department': department,
          if (status != null) 'status': status,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only: soft-deletes (deactivates) staff [id].
  Future<void> deleteStaff(int id) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalStaffDelete, data: <String, dynamic>{'id': id});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/hr: `{'data': List<request>, 'counts': {pending,approved,rejected},
  /// 'meta': {...}}`. [status] optionally filters to one status.
  Future<Map<String, dynamic>> getLeaveRequestsForReview({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalHrLeaveRequests,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': 100,
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

  /// Owner/hr, Pro required: approves a pending leave request.
  Future<void> approveLeaveRequest(int requestId) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalHrLeaveRequestApprove, data: <String, dynamic>{'request_id': requestId});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/hr, Pro required: rejects a pending leave request.
  Future<void> rejectLeaveRequest(int requestId) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalHrLeaveRequestReject, data: <String, dynamic>{'request_id': requestId});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/hr, Pro required: directly grants pre-approved paid leave.
  Future<Map<String, dynamic>> grantLeave({
    required int employeeId,
    required String leaveType,
    required String startDate,
    required String endDate,
    String? reason,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalHrLeaveRequestGrant,
        data: <String, dynamic>{
          'employee_id': employeeId,
          'leave_type': leaveType,
          'start_date': startDate,
          'end_date': endDate,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/hr: `{'data': List<{employee_id, employee_code, first_name,
  /// last_name, department, position, balances: {leaveType: {total, used,
  /// remaining, has_override}}}>, 'year': int}`.
  Future<Map<String, dynamic>> getLeaveBalances({int? year}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalHrLeaveBalances,
        queryParameters: <String, dynamic>{if (year != null) 'year': year},
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

  /// Owner/hr, Pro required: sets a per-employee leave-day override for the
  /// current year. [overrides] keys are leave types (annual/sick/personal/
  /// maternity/paternity), values the new day count for that type.
  Future<Map<String, dynamic>> overrideLeaveBalance({
    required int employeeId,
    required Map<String, num> overrides,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalHrLeaveBalanceOverride,
        data: <String, dynamic>{
          'employee_id': employeeId,
          for (final MapEntry<String, num> e in overrides.entries) '${e.key}_override_days': e.value,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/hr/finance, Pro required: `{'data': List<payroll>, 'meta': {...}}`.
  Future<Map<String, dynamic>> getPayroll({int? month, int? year}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalHrPayroll,
        queryParameters: <String, dynamic>{
          if (month != null) 'month': month,
          if (year != null) 'year': year,
          'limit': 100,
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

  /// Owner/hr, Pro required: bulk-generates payroll for [month] (`YYYY-MM`)
  /// and cutoff [half] ('1' or '2') from real attendance/leave data.
  Future<Map<String, dynamic>> generatePayroll({required String month, required String half}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalHrPayrollGenerate,
        data: <String, dynamic>{'month': month, 'half': half},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: pending -> processed.
  Future<void> approvePayroll(int payrollId) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalHrPayrollApprove, data: <String, dynamic>{'payroll_id': payrollId});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: processed -> paid.
  Future<void> markPayrollPaid(int payrollId) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalHrPayrollMarkPaid, data: <String, dynamic>{'payroll_id': payrollId});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Finance management (owner/finance) ──────────────────────────────────────
  //
  // Income's list view is free-tier viewable (mirrors the web's income.php,
  // which renders for every tier); adding an income record still enforces
  // Pro server-side. Expenses, Inventory, and Budget Requests are fully
  // Pro-gated end-to-end (mirrors their web pages, which hard-lock free
  // tier entirely).

  /// `{'data': List<income>, 'summary': {total_income}, 'meta': {...}}`.
  Future<Map<String, dynamic>> getIncome({String? dateFrom, String? dateTo}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalFinanceIncome,
        queryParameters: <String, dynamic>{
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          'limit': 100,
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

  /// Owner/finance, Pro required.
  Future<Map<String, dynamic>> addIncome({
    required num amount,
    required String source,
    required String description,
    required String date,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceIncomeStore,
        data: <String, dynamic>{'amount': amount, 'source': source, 'description': description, 'date': date},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: `{'data': List<expense>, 'summary':
  /// {total_expenses}, 'meta': {...}}`.
  Future<Map<String, dynamic>> getExpenses({String? category, String? dateFrom, String? dateTo}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalFinanceExpenses,
        queryParameters: <String, dynamic>{
          if (category != null && category.isNotEmpty) 'category': category,
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          'limit': 100,
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

  /// Owner/finance, Pro required.
  Future<Map<String, dynamic>> addExpense({
    required num amount,
    required String category,
    required String description,
    required String date,
    String? receiptUrl,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceExpensesStore,
        data: <String, dynamic>{
          'amount': amount,
          'category': category,
          'description': description,
          'date': date,
          if (receiptUrl != null && receiptUrl.isNotEmpty) 'receipt_url': receiptUrl,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: `{'data': List<item>, 'meta': {...}}`.
  /// [itemType] filters to 'equipment'|'consumable'; [lowStockOnly] shows
  /// only items at/under their reorder threshold.
  Future<Map<String, dynamic>> getInventory({String? itemType, bool lowStockOnly = false}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalFinanceInventory,
        queryParameters: <String, dynamic>{
          if (itemType != null && itemType.isNotEmpty) 'item_type': itemType,
          if (lowStockOnly) 'low_stock': '1',
          'limit': 100,
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

  /// Owner/finance, Pro required: adds an item with a starting quantity
  /// (logged as an expense if quantity/price are both positive).
  Future<Map<String, dynamic>> addInventoryItem({
    required String itemName,
    required String referenceNo,
    required String itemType,
    required num unitPrice,
    int quantityAvailable = 0,
    String? unit,
    int reorderThreshold = 5,
    String? supplierName,
    String? notes,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceInventoryStore,
        data: <String, dynamic>{
          'item_name': itemName,
          'reference_no': referenceNo,
          'item_type': itemType,
          'unit_price': unitPrice,
          'quantity_available': quantityAvailable,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
          'reorder_threshold': reorderThreshold,
          if (supplierName != null && supplierName.isNotEmpty) 'supplier_name': supplierName,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: edits item details — never touches
  /// quantity (see restockInventoryItem for the only way to increase it).
  Future<Map<String, dynamic>> updateInventoryItem({
    required int id,
    required String itemName,
    required String referenceNo,
    required String itemType,
    required num unitPrice,
    String? unit,
    int reorderThreshold = 5,
    String? supplierName,
    String? notes,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceInventoryUpdate,
        data: <String, dynamic>{
          'id': id,
          'item_name': itemName,
          'reference_no': referenceNo,
          'item_type': itemType,
          'unit_price': unitPrice,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
          'reorder_threshold': reorderThreshold,
          if (supplierName != null && supplierName.isNotEmpty) 'supplier_name': supplierName,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: increases quantity and logs the purchase
  /// as an expense at the item's current unit price.
  Future<Map<String, dynamic>> restockInventoryItem({required int id, required int addQuantity}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceInventoryRestock,
        data: <String, dynamic>{'id': id, 'add_quantity': addQuantity},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: soft-deletes an inventory item.
  Future<void> archiveInventoryItem(int id) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalFinanceInventoryArchive, data: <String, dynamic>{'id': id});
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner/finance, Pro required: `{'data': List<request>, 'meta': {...}}`.
  Future<Map<String, dynamic>> getBudgetRequests({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalFinanceRequests,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': 100,
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

  /// Owner/finance, Pro required: submits a new budget request.
  Future<Map<String, dynamic>> submitBudgetRequest({
    required String department,
    required num amount,
    required String description,
    String? neededDate,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceRequestStore,
        data: <String, dynamic>{
          'department': department,
          'request_type': 'budget',
          'amount': amount,
          'description': description,
          if (neededDate != null && neededDate.isNotEmpty) 'needed_date': neededDate,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only, Pro required: approves with [approvedAmount] (a value of 0
  /// rejects it instead, matching the web's single-action semantics).
  Future<void> approveBudgetRequest({required int requestId, required num approvedAmount, String? remarks}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceRequestApprove,
        data: <String, dynamic>{
          'request_id': requestId,
          'approved_amount': approvedAmount,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Owner-only, Pro required: rejects outright.
  Future<void> rejectBudgetRequest({required int requestId, String? remarks}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalFinanceRequestReject,
        data: <String, dynamic>{
          'request_id': requestId,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── CRM management (owner/crm) — all Pro-gated end-to-end ───────────────────

  /// `{'data': List<booking>, 'meta': {...}}`. [status] optionally filters
  /// (e.g. 'pending' for the "Requests" view vs. unfiltered "Bookings").
  Future<Map<String, dynamic>> getCrmBookings({String? status, String? dateFrom, String? dateTo}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalCrmBookings,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          'limit': 100,
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

  /// Full booking detail (seeker/listing/payment/verification info). The
  /// seeker's own control number is deliberately never included server-side
  /// — only the provider's own code comes back.
  Future<Map<String, dynamic>> getCrmBookingDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalCrmBookingShow, queryParameters: <String, dynamic>{'id': id});
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Advances a booking's status. [status] must be one of the workflow
  /// values EXCEPT 'on_going' — that transition only happens via
  /// [scanCrmBookingQr] (the QR handshake).
  Future<void> updateCrmBookingStatus({required int id, required String status, String? notes}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalCrmBookingUpdateStatus,
        data: <String, dynamic>{'id': id, 'status': status, if (notes != null && notes.isNotEmpty) 'notes': notes},
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Resolves a scanned/entered 6-char QR [token] (dashes stripped
  /// automatically) and advances the matching `starting` booking to
  /// `on_going`. Returns `{'message': String}`.
  Future<Map<String, dynamic>> scanCrmBookingQr(String token) async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.portalCrmBookingScanQr, data: <String, dynamic>{'token': token});
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// `{'data': List<service>, 'meta': {...}}`. [status] optionally filters
  /// to 'active'|'inactive'.
  Future<Map<String, dynamic>> getCrmServices({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.portalCrmServices,
        queryParameters: <String, dynamic>{if (status != null && status.isNotEmpty) 'status': status, 'limit': 100},
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

  /// Creates a service listing. Non-'fixed' [pricingType] forces
  /// `requires_inspection` on server-side regardless of [requiresInspection].
  Future<Map<String, dynamic>> createCrmService({
    required String title,
    required String description,
    required num price,
    required String pricingType,
    required int categoryId,
    bool isEmergency = false,
    bool requiresInspection = false,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalCrmServiceStore,
        data: <String, dynamic>{
          'title': title,
          'description': description,
          'price': price,
          'pricing_type': pricingType,
          'category_id': categoryId,
          'is_emergency': isEmergency,
          'requires_inspection': requiresInspection,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Edits a service listing — only non-null fields are sent/updated.
  /// Same `requires_inspection` server-side lock as [createCrmService].
  Future<void> updateCrmService({
    required int id,
    String? title,
    String? description,
    num? price,
    String? pricingType,
    String? status,
    bool? isEmergency,
    bool? requiresInspection,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalCrmServiceUpdate,
        data: <String, dynamic>{
          'id': id,
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (price != null) 'price': price,
          if (pricingType != null) 'pricing_type': pricingType,
          if (status != null) 'status': status,
          if (isEmergency != null) 'is_emergency': isEmergency,
          if (requiresInspection != null) 'requires_inspection': requiresInspection,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// `{'data': {'customers': List, 'services': List}}` — past customers
  /// (completed-booking seekers) + this provider's catalog, for composing
  /// an outreach message.
  Future<Map<String, dynamic>> getOutreachCustomers() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalCrmOutreachCustomers);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Sends an outreach email to the given past-customer [recipients]
  /// (seeker_user_ids — re-validated server-side against this provider's own
  /// completed bookings). [serviceId], if given, adds a "View & Book" link.
  Future<Map<String, dynamic>> sendOutreach({
    required String subject,
    required String message,
    required List<int> recipients,
    int? serviceId,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.portalCrmOutreachSend,
        data: <String, dynamic>{
          'subject': subject,
          'message': message,
          'recipients': recipients,
          if (serviceId != null) 'service_id': serviceId,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// `{'data': List<log>, 'meta': {...}}` — recent outreach send history.
  Future<Map<String, dynamic>> getOutreachHistory() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.portalCrmOutreachHistory, queryParameters: <String, dynamic>{'limit': 100});
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final Provider<PortalApi> portalApiProvider = Provider<PortalApi>(
  (Ref ref) => PortalApi(ref.watch(dioProvider)),
);

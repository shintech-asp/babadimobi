// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart' show kIsWeb;

/// All PHP API endpoint paths for the Pestify backend.
///
/// [base] defaults to the live production API (`https://pestify.site`) for
/// any native build/run — this is what makes a distributed release APK
/// actually work on a real phone, since `10.0.2.2` (the old default) only
/// ever resolves inside the Android emulator, never on real hardware.
///
/// For local dev against XAMPP instead, override at build/run time:
///   flutter run --dart-define=API_BASE=http://10.0.2.2/pestify/api/v1 --dart-define=SITE_ROOT=http://10.0.2.2/pestify   (Android emulator)
///   flutter run --dart-define=API_BASE=http://192.168.x.x/pestify/api/v1 --dart-define=SITE_ROOT=http://192.168.x.x/pestify   (real device on same LAN)
class ApiEndpoints {
  ApiEndpoints._();

  static const String _baseOverride = String.fromEnvironment('API_BASE');
  static const String _siteRootOverride = String.fromEnvironment('SITE_ROOT');

  static String get base {
    if (_baseOverride.isNotEmpty) return _baseOverride;
    return kIsWeb ? 'http://localhost/pestify/api/v1' : 'https://pestify.site/api/v1';
  }

  /// The web root (no `/api/v1` suffix) — used to resolve relative
  /// `uploads/...` paths returned by the PHP API into loadable image URLs.
  static String get siteRoot {
    if (_siteRootOverride.isNotEmpty) return _siteRootOverride;
    return kIsWeb ? 'http://localhost/pestify' : 'https://pestify.site';
  }

  /// Resolves a possibly-relative image path (e.g. `uploads/services/x.jpg`,
  /// as returned by `provider/listings/*`) into a full URL. Returns `null`
  /// for null/empty input and passes already-absolute URLs through as-is.
  static String? resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$siteRoot/${path.startsWith('/') ? path.substring(1) : path}';
  }

  // ── Auth ────────────────────────────────────────────────────────────────────
  static const String login          = '/auth/login.php';
  static const String register       = '/auth/register.php';
  static const String verifyOtp      = '/auth/verify-otp.php';
  static const String resendOtp      = '/auth/resend-otp.php';
  static const String forgotPassword = '/auth/forgot-password.php';

  // ── Seeker — browse ─────────────────────────────────────────────────────────
  static const String categories     = '/categories/index.php';
  static const String listings       = '/listings/index.php';
  static const String listingDetail  = '/listings/show.php';
  static const String providers      = '/providers/index.php';
  static const String providerDetail = '/providers/show.php';

  // ── Seeker — bookings ───────────────────────────────────────────────────────
  static const String bookings         = '/seeker/bookings/index.php';
  static const String bookingDetail    = '/seeker/bookings/show.php';
  static const String createBooking    = '/seeker/bookings/store.php';
  static const String cancelBooking    = '/seeker/bookings/cancel.php';
  static const String confirmPayment   = '/seeker/bookings/confirm-payment.php';
  static const String remainingPayment = '/seeker/bookings/remaining-payment.php';
  static const String verifySeeker     = '/seeker/bookings/verify.php';
  static const String submitReview     = '/seeker/bookings/feedback.php';
  static const String confirmComplete    = '/seeker/bookings/confirm-complete.php';
  static const String rescheduleRespond  = '/seeker/bookings/reschedule-respond.php';
  static const String inspectionRespond  = '/seeker/bookings/inspection-respond.php';
  static const String emergencyNow       = '/seeker/bookings/emergency-now.php';
  static const String retryPayment       = '/seeker/bookings/retry-payment.php';

  // ── Seeker — comms & profile ────────────────────────────────────────────────
  static const String notifications  = '/notifications/index.php';
  static const String notifCount     = '/notifications/count.php';
  static const String notifMarkRead  = '/notifications/mark-read.php';
  static const String profile        = '/user/profile.php';

  // Transaction-scoped chat (one thread per booking, closed once the booking
  // is completed/cancelled) — mirrors the web's seeker/messages-seeker.php.
  static const String bookingThreads = '/seeker/messages/index.php';
  static const String bookingThread  = '/seeker/messages/show.php';
  static const String sendBookingMessage = '/seeker/messages/send.php';
  static const String pollBookingMessages = '/seeker/messages/poll.php';

  // ── Decision Support System ("Find My Match") ───────────────────────────────
  // Guest-accessible (no auth guard server-side) — only booking requires login.
  static const String recommend        = '/seeker/recommend.php';
  static const String recommendOptions = '/seeker/recommend-options.php';

  // ── Admin (Phase 3) ──────────────────────────────────────────────────────────
  // Login is centralized through /auth/login.php (see AuthApi.login) — no
  // separate admin login endpoint.
  static const String adminDashboard       = '/admin/dashboard.php';
  static const String adminProviders       = '/admin/providers/index.php';
  static const String adminProviderDetail  = '/admin/providers/show.php';
  static const String adminProviderApprove = '/admin/providers/approve.php';
  static const String adminProviderReject  = '/admin/providers/reject.php';

  // ── Provider — dashboard & listings ─────────────────────────────────────────
  static const String providerDashboard     = '/provider/dashboard.php';
  static const String providerListings      = '/provider/listings/index.php';
  static const String providerListingStore  = '/provider/listings/store.php';
  static const String providerListingUpdate = '/provider/listings/update.php';
  static const String providerListingDelete = '/provider/listings/delete.php';

  // ── Provider — service requests ─────────────────────────────────────────────
  static const String providerRequests      = '/provider/requests/index.php';
  static const String providerRequestDetail = '/provider/requests/show.php';
  static const String providerUpdateStatus  = '/provider/requests/update-status.php';
  static const String providerVerify        = '/provider/requests/verify.php';
  static const String providerScanQr        = '/provider/requests/scan-qr.php';
  static const String providerPrepareBooking = '/provider/requests/prepare.php';
  static const String providerSubmitInspection = '/provider/requests/submit-inspection.php';
  static const String providerEmergencyAccept  = '/provider/requests/emergency-accept.php';
  static const String providerReschedule       = '/provider/requests/reschedule.php';

  // Transaction-scoped chat, provider side (one thread per booking, closed
  // once completed/cancelled) — mirrors the seeker's bookingThreads/etc.
  // above exactly, replacing the old provider_id-scoped `/messages/*`
  // endpoints (one lifetime thread per counterpart, no booking context).
  static const String providerBookingThreads = '/provider/messages/index.php';
  static const String providerBookingThread  = '/provider/messages/show.php';
  static const String providerSendBookingMessage = '/provider/messages/send.php';
  static const String providerPollBookingMessages = '/provider/messages/poll.php';

  // ── Provider portal (HR/Finance/CRM/staff/subscriptions) ───────────────────
  // Login is centralized through /auth/login.php (see AuthApi.login) — no
  // separate portal login call from the app; this section is for
  // POST-login portal-specific endpoints only.
  static const String portalMe = '/portal/auth/me.php';
  static const String portalChangePassword = '/portal/auth/change-password.php';

  // ── Portal — employee self-service ──────────────────────────────────────────
  static const String portalMeAttendance       = '/portal/me/attendance/index.php';
  static const String portalMeClockIn          = '/portal/me/attendance/clock-in.php';
  static const String portalMeClockOut         = '/portal/me/attendance/clock-out.php';
  static const String portalMeLeaveRequests     = '/portal/me/leave-requests/index.php';
  static const String portalMeLeaveRequestStore = '/portal/me/leave-requests/store.php';
  static const String portalMePayslips         = '/portal/me/payslips/index.php';
  static const String portalMeBookings         = '/portal/me/bookings.php';

  // ── Portal — subscriptions (tier visibility + purchase) ────────────────────
  static const String portalSubscriptions      = '/portal/subscriptions/index.php';
  static const String portalSubscriptionStore  = '/portal/subscriptions/store.php';
  static const String portalSubscriptionConfirm = '/portal/subscriptions/confirm.php';
  static const String portalSubscriptionTrial  = '/portal/subscriptions/trial.php';

  // ── Portal — HR management (owner/hr, Pro-gated except read-only views) ────
  static const String portalStaffIndex   = '/portal/staff/index.php';
  static const String portalStaffStore   = '/portal/staff/store.php';
  static const String portalStaffUpdate  = '/portal/staff/update.php';
  static const String portalStaffDelete  = '/portal/staff/delete.php';

  static const String portalHrLeaveRequests        = '/portal/hr/leave-requests/index.php';
  static const String portalHrLeaveRequestApprove  = '/portal/hr/leave-requests/approve.php';
  static const String portalHrLeaveRequestReject   = '/portal/hr/leave-requests/reject.php';
  static const String portalHrLeaveRequestGrant    = '/portal/hr/leave-requests/grant.php';

  static const String portalHrLeaveBalances        = '/portal/hr/leave-balances/index.php';
  static const String portalHrLeaveBalanceOverride = '/portal/hr/leave-balances/override.php';

  static const String portalHrPayroll         = '/portal/hr/payroll/index.php';
  static const String portalHrPayrollGenerate = '/portal/hr/payroll/generate.php';
  static const String portalHrPayrollApprove  = '/portal/hr/payroll/approve.php';
  static const String portalHrPayrollMarkPaid = '/portal/hr/payroll/mark-paid.php';

  static const String portalHrEmployees       = '/portal/hr/employees/index.php';
  static const String portalHrEmployeeStore   = '/portal/hr/employees/store.php';
  static const String portalHrEmployeeUpdate  = '/portal/hr/employees/update.php';

  // ── Portal — Finance management (owner/finance, Pro-gated except Income view) ─
  static const String portalFinanceIncome      = '/portal/finance/income/index.php';
  static const String portalFinanceIncomeStore = '/portal/finance/income/store.php';

  static const String portalFinanceExpenses      = '/portal/finance/expenses/index.php';
  static const String portalFinanceExpensesStore = '/portal/finance/expenses/store.php';

  static const String portalFinanceInventory        = '/portal/finance/inventory/index.php';
  static const String portalFinanceInventoryStore   = '/portal/finance/inventory/store.php';
  static const String portalFinanceInventoryUpdate  = '/portal/finance/inventory/update.php';
  static const String portalFinanceInventoryRestock = '/portal/finance/inventory/restock.php';
  static const String portalFinanceInventoryArchive = '/portal/finance/inventory/archive.php';

  static const String portalFinanceRequests        = '/portal/finance/requests/index.php';
  static const String portalFinanceRequestStore    = '/portal/finance/requests/store.php';
  static const String portalFinanceRequestApprove  = '/portal/finance/requests/approve.php';
  static const String portalFinanceRequestReject   = '/portal/finance/requests/reject.php';

  // ── Portal — CRM management (owner/crm, Pro-gated) ─────────────────────────
  static const String portalCrmBookings           = '/portal/crm/bookings/index.php';
  static const String portalCrmBookingShow        = '/portal/crm/bookings/show.php';
  static const String portalCrmBookingUpdateStatus = '/portal/crm/bookings/update-status.php';
  static const String portalCrmBookingScanQr      = '/portal/crm/bookings/scan-qr.php';

  static const String portalCrmServices      = '/portal/crm/services/index.php';
  static const String portalCrmServiceStore  = '/portal/crm/services/store.php';
  static const String portalCrmServiceUpdate = '/portal/crm/services/update.php';

  static const String portalCrmOutreachCustomers = '/portal/crm/outreach/customers.php';
  static const String portalCrmOutreachSend      = '/portal/crm/outreach/send.php';
  static const String portalCrmOutreachHistory   = '/portal/crm/outreach/history.php';
}

// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart' show kIsWeb;

/// All PHP API endpoint paths for the Pestify backend.
///
/// [base] switches automatically:
///   - Web browser  → http://localhost/pestify/api/v1
///   - Android emu  → http://10.0.2.2/pestify/api/v1  (maps to host localhost)
///   - Real device  → swap 10.0.2.2 to your LAN IP (192.168.x.x)
class ApiEndpoints {
  ApiEndpoints._();

  static String get base => kIsWeb
      ? 'http://localhost/pestify/api/v1'
      : 'http://10.0.2.2/pestify/api/v1';

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

  // ── Seeker — comms & profile ────────────────────────────────────────────────
  static const String notifications  = '/notifications/index.php';
  static const String notifCount     = '/notifications/count.php';
  static const String notifMarkRead  = '/notifications/mark-read.php';
  static const String messages       = '/messages/index.php';
  static const String messageThread  = '/messages/thread.php';
  static const String sendMessage    = '/messages/send.php';
  static const String profile        = '/user/profile.php';
}

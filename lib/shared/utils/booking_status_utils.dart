/// Normalizes legacy/inconsistent PHP web-app booking status spellings onto
/// the canonical mobile FSM values (see PHP `includes/booking_workflow_helper.php`).
///
/// The web app (`seeker/my-requests.php`, `provider/service-requests.php`)
/// writes several spellings for the same real states:
///  - `ongoing` instead of `on_going`
///  - `waiting_remaining_payment` instead of `waiting_for_remaining_payment`
///  - `waiting_provider_confirmation` (no "for"), `waiting_seeker_information`,
///    and `waiting_seeker_confirmation` — all of which, despite the confusing
///    "provider" spelling on the first one, mean the SEEKER must confirm
///    (see `api/v1/seeker/bookings/confirm-complete.php`'s accepted-status set).
///
/// This is distinct from the canonical `waiting_for_provider_confirmation`
/// (WITH "for"), which `confirm-payment.php` writes after a downpayment's
/// remaining balance is paid — that one genuinely means the PROVIDER must
/// confirm, and must never be normalized onto the seeker-confirm family.
///
/// The ambiguous legacy family has a THIRD meaning: the provider-portal CRM
/// writes the exact same `waiting_provider_confirmation` string to mean
/// "just accepted a pending request" — an early, pre-service state. Pass
/// [hasStarted] (derived from `dual_verified_at` being a real, non-zero
/// timestamp) to disambiguate; when false, the ambiguous family is treated
/// as `accepted` instead of the seeker-confirm step, matching
/// `api/v1/seeker/bookings/confirm-complete.php`'s own gate.
String normalizeBookingStatus(String status, {bool hasStarted = true}) {
  final String s = status.toLowerCase().trim();
  if (s == 'ongoing') return 'on_going';
  if (s == 'waiting_remaining_payment') return 'waiting_for_remaining_payment';
  // Provider-portal CRM (Phase 3) spellings for the same in-progress states.
  if (s == 'on_the_way') return 'starting';
  if (s == 'in_progress') return 'on_going';
  const Set<String> seekerConfirmFamily = <String>{
    'waiting_provider_confirmation',
    'waiting_seeker_information',
    'waiting_seeker_confirmation',
  };
  if (seekerConfirmFamily.contains(s)) {
    return hasStarted ? 'waiting_for_seeker_confirmation' : 'accepted';
  }
  return s;
}

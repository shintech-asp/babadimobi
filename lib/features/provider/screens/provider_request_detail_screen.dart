import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/utils/booking_status_utils.dart';
import 'package:pestify_flutter/shared/utils/timestamps.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/inspection_pending_banner.dart';
import 'package:url_launcher/url_launcher.dart';

/// Provider request detail — seeker info, service/payment details, the
/// PCF-… control number the provider must enter, and status-driven actions.
///
/// Action buttons mirror the allowed transitions in `booking_workflow_helper.php`
/// (`update-status.php`'s `$allowed` list) — `starting → on_going` is
/// deliberately excluded there and only reachable via `scan-qr.php`.
class ProviderRequestDetailScreen extends ConsumerStatefulWidget {
  const ProviderRequestDetailScreen({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<ProviderRequestDetailScreen> createState() =>
      _ProviderRequestDetailScreenState();
}

class _ProviderRequestDetailScreenState
    extends ConsumerState<ProviderRequestDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      return await ref.read(providerApiProvider).getRequestDetail(widget.requestId);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Awaits the new fetch (not just assigns it) so [RefreshIndicator]'s own
  /// spinner stays up until the data has actually arrived, instead of
  /// dismissing the instant this function returns.
  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _fetch();
    // Block body, not `() => _future = next` — an assignment expression
    // evaluates to the assigned value, so that arrow form actually returns
    // the Future itself. setState() then throws "callback argument returned
    // a Future" *before* calling markNeedsBuild(), so every caller of this
    // method (status updates, prepare/edit equipment, verify, etc.) silently
    // updated `_future` but never actually triggered a rebuild.
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  bool _dualVerified(Map<String, dynamic> r) {
    final String raw = r['dual_verified_at']?.toString().trim() ?? '';
    return raw.isNotEmpty && raw != '0000-00-00 00:00:00';
  }

  Future<void> _setStatus(String status, {String? notes}) async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(providerApiProvider).updateRequestStatus(
            id: widget.requestId,
            status: status,
            notes: notes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated'), backgroundColor: AppTheme.primary),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _confirmAndSetStatus({
    required String title,
    required String message,
    required String status,
    bool askReason = false,
  }) async {
    final TextEditingController reasonCtrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            if (askReason) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(hintText: 'Reason (optional)'),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(title)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _setStatus(status, notes: askReason ? reasonCtrl.text.trim() : null);
  }

  Future<void> _openVerify() async {
    await context.push('/provider/verify', extra: <String, dynamic>{'availId': widget.requestId});
    if (!mounted) return;
    _refresh();
  }

  /// Opens the equipment/staff assignment screen — the one-shot 'accepted'
  /// -> 'preparing' trigger when [isEdit] is false, or the re-edit path for
  /// an already-'preparing' booking when true. Status now changes (if at
  /// all) as a side effect of a successful save there, not via a bare
  /// `_setStatus('preparing')` call — that would have skipped equipment
  /// assignment entirely, exactly the gap this screen exists to close.
  Future<void> _openPrepareBooking({required bool isEdit}) async {
    final Object? result = await context.push(
      '/provider/prepare-booking',
      extra: <String, dynamic>{'requestId': widget.requestId, 'isEdit': isEdit},
    );
    if (!mounted || result != true) return;
    _refresh();
  }

  Future<void> _openScanQr() async {
    await context.push('/provider/scan-qr', extra: <String, dynamic>{'availId': widget.requestId});
    if (!mounted) return;
    _refresh();
  }

  /// Opens the inspection-report screen — the only mobile entry point into
  /// the Inspection -> Agreement flow (see CLAUDE.md). [isRevising] just
  /// varies the title/copy; both cases POST to the same endpoint.
  Future<void> _openSubmitInspection({required bool isRevising}) async {
    final Object? result = await context.push(
      '/provider/submit-inspection',
      extra: <String, dynamic>{'requestId': widget.requestId, 'isRevising': isRevising},
    );
    if (!mounted || result != true) return;
    _refresh();
  }

  Future<void> _acceptEmergency() async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(providerApiProvider).acceptEmergency(availId: widget.requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency request accepted'), backgroundColor: AppTheme.primary),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _openReschedule() async {
    final Object? result = await context.push(
      '/provider/reschedule',
      extra: <String, dynamic>{'requestId': widget.requestId},
    );
    if (!mounted || result != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reschedule request sent to the seeker'), backgroundColor: AppTheme.primary),
    );
    _refresh();
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Request Detail')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<Map<String, dynamic>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(snap.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> b = snap.data ?? <String, dynamic>{};
          final String rawStatus = b['status']?.toString() ?? 'pending';
          final bool hasStarted = _dualVerified(b);
          final String normalized = normalizeBookingStatus(rawStatus, hasStarted: hasStarted);
          final String seekerName = <String?>[
            b['seeker_first']?.toString(),
            b['seeker_last']?.toString(),
          ].where((String? s) => s != null && s.isNotEmpty).join(' ');
          final String? controlNumber = b['control_number']?.toString();
          final String paymentStatus = b['payment_status']?.toString() ?? 'unpaid';
          final String paymentMethod = b['payment_method']?.toString() ?? 'full_payment';
          final bool requiresInspection = b['requires_inspection'] == true ||
              b['requires_inspection'] == 1 ||
              b['requires_inspection'] == '1';
          final bool isRevising = rawStatus == 'revising';
          final bool awaitingInspection = requiresInspection &&
              rawStatus == 'accepted' &&
              !isRealTimestamp(b['inspection_agreed_at']);
          // Covers both the first submission ('accepted') and a resubmission
          // after the seeker asked for changes ('revising') — mirrors web's
          // needsInspectionReport exactly.
          final bool needsInspectionReport = requiresInspection &&
              (rawStatus == 'accepted' || isRevising) &&
              !isRealTimestamp(b['inspection_agreed_at']);
          final bool isEmergency = (b['emergency_now_requested'] == true ||
                  b['emergency_now_requested'] == 1 ||
                  b['emergency_now_requested'] == '1') &&
              !<String>['completed', 'cancelled'].contains(normalized);
          final bool isEmergencyAccepted = isEmergency && isRealTimestamp(b['emergency_now_accepted_at']);
          final bool showEmergencyAcceptBtn = isEmergency && !isEmergencyAccepted;
          final String rescheduleState = (b['reschedule_request_status']?.toString() ?? '').toLowerCase();
          final bool hasRescheduleDate = (b['reschedule_proposed_date']?.toString() ?? '').isNotEmpty &&
              (b['reschedule_proposed_time']?.toString() ?? '').isNotEmpty;
          final bool isReschedulePending = rescheduleState == 'pending' && hasRescheduleDate;
          final bool isRescheduleRejected = rescheduleState == 'rejected' && hasRescheduleDate;
          final bool canRequestReschedule =
              <String>['accepted', 'preparing'].contains(normalized) && !isReschedulePending;

          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        b['title']?.toString() ?? b['service_name']?.toString() ?? 'Service',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
                      ),
                    ),
                    BookingStatusChip(status: rawStatus, hasStarted: hasStarted),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Request #${widget.requestId}', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 20),

                if (b['rejection_reason'] != null && b['rejection_reason'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ErrorBanner(message: 'Cancelled: ${b['rejection_reason']}'),
                  ),

                if (isEmergency)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _InfoBanner(
                      icon: Icons.bolt_rounded,
                      color: const Color(0xFFB91C1C),
                      background: const Color(0xFFFEF2F2),
                      border: const Color(0xFFFCA5A5),
                      title: isEmergencyAccepted ? 'Emergency — Accepted' : 'Emergency Service Now Requested',
                      message: isEmergencyAccepted
                          ? 'You accepted this emergency request and prioritized it.'
                          : 'The client requested emergency service. Accept to prioritize this booking.',
                    ),
                  ),

                if (awaitingInspection)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InspectionPendingBanner(
                      inspectionDate: _formatDate(
                          b['inspection_date'] ?? b['preferred_date']),
                      forProvider: true,
                    ),
                  ),

                if (isRevising && requiresInspection)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _InfoBanner(
                      icon: Icons.replay_rounded,
                      color: const Color(0xFF9A3412),
                      background: const Color(0xFFFFF7ED),
                      border: const Color(0xFFFDBA74),
                      title: 'Seeker requested changes',
                      message: (b['inspection_change_notes']?.toString().isNotEmpty ?? false)
                          ? b['inspection_change_notes'].toString()
                          : 'Submit a revised inspection report.',
                    ),
                  ),

                if (isReschedulePending || isRescheduleRejected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _InfoBanner(
                      icon: Icons.event_repeat_rounded,
                      color: isReschedulePending ? const Color(0xFF854D0E) : const Color(0xFFB91C1C),
                      background: isReschedulePending ? const Color(0xFFFEFCE8) : const Color(0xFFFEF2F2),
                      border: isReschedulePending ? const Color(0xFFFDE68A) : const Color(0xFFFCA5A5),
                      title: isReschedulePending ? 'Reschedule Proposed' : 'Reschedule Declined',
                      message: isReschedulePending
                          ? 'Proposed: ${_formatDate(b['reschedule_proposed_date'])} at ${_formatTime(b['reschedule_proposed_time'])} — waiting for the client to respond.'
                          : 'The client declined your proposed reschedule. You can send a new one below.',
                    ),
                  ),

                _SectionCard(
                  title: 'Client',
                  children: <Widget>[
                    _InfoRow(label: 'Name', value: seekerName.isEmpty ? '—' : seekerName),
                    _InfoRow(
                      label: 'Phone',
                      value: b['seeker_phone']?.toString() ?? '—',
                      trailing: (b['seeker_phone'] != null && b['seeker_phone'].toString().isNotEmpty)
                          ? IconButton(
                              icon: const Icon(Icons.call_outlined, size: 18, color: AppTheme.primary),
                              onPressed: () => _call(b['seeker_phone']?.toString()),
                              tooltip: 'Call',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                    _InfoRow(label: 'Email', value: b['seeker_email']?.toString() ?? '—'),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'Service Details',
                  children: <Widget>[
                    _InfoRow(
                      label: awaitingInspection ? 'Inspection Date' : 'Date',
                      value: _formatDate(awaitingInspection
                          ? (b['inspection_date'] ?? b['preferred_date'])
                          : b['preferred_date']),
                    ),
                    _InfoRow(label: 'Time', value: _formatTime(b['preferred_time'])),
                    _InfoRow(label: 'Address', value: b['address']?.toString() ?? '—'),
                    if (b['notes'] != null && b['notes'].toString().isNotEmpty)
                      _InfoRow(label: 'Notes', value: b['notes'].toString()),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'Payment',
                  children: <Widget>[
                    _InfoRow(label: 'Method', value: paymentMethod == 'downpayment' ? 'Downpayment' : 'Full Payment'),
                    _InfoRow(label: 'Status', value: paymentStatus[0].toUpperCase() + paymentStatus.substring(1)),
                    _InfoRow(label: 'Total', value: '₱${_money(b['total_amount'])}'),
                    if (paymentMethod == 'downpayment') ...<Widget>[
                      _InfoRow(label: 'Paid', value: '₱${_money(b['paid_amount'])}'),
                      _InfoRow(label: 'Remaining', value: '₱${_money(b['remaining_amount'])}'),
                    ],
                  ],
                ),

                if (controlNumber != null &&
                    controlNumber.isNotEmpty &&
                    (paymentStatus == 'paid' || paymentStatus == 'partial')) ...<Widget>[
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Client Verification Code',
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          controlNumber,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: AppTheme.navy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasStarted
                            ? 'Verified — both sides confirmed.'
                            : 'Ask the client to read this code aloud, then tap "Enter Seeker Code" below to confirm.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                _ActionArea(
                  normalizedStatus: normalized,
                  rawStatus: rawStatus,
                  hasStarted: hasStarted,
                  paymentStatus: paymentStatus,
                  paymentMethod: paymentMethod,
                  preferredDate: b['preferred_date']?.toString(),
                  seekerVerified: isRealTimestamp(b['seeker_verified_at']),
                  needsInspectionReport: needsInspectionReport,
                  isRevising: isRevising,
                  showEmergencyAcceptBtn: showEmergencyAcceptBtn,
                  canRequestReschedule: canRequestReschedule,
                  busy: _actionInProgress,
                  onAccept: () => _confirmAndSetStatus(
                    title: 'Accept',
                    message: 'Accept this service request?',
                    status: 'accepted',
                  ),
                  onDecline: () => _confirmAndSetStatus(
                    title: 'Decline',
                    message: 'Decline this request? This cannot be undone.',
                    status: 'cancelled',
                    askReason: true,
                  ),
                  onStartPreparing: () => _openPrepareBooking(isEdit: false),
                  onEditEquipment: () => _openPrepareBooking(isEdit: true),
                  onStartService: () => _setStatus('starting'),
                  onCancel: () => _confirmAndSetStatus(
                    title: 'Cancel',
                    message: 'Cancel this booking? This cannot be undone.',
                    status: 'cancelled',
                    askReason: true,
                  ),
                  onMarkWaitingRemaining: () => _setStatus('waiting_for_remaining_payment'),
                  onMarkWaitingSeekerConfirm: () => _setStatus('waiting_for_seeker_confirmation'),
                  onConfirmRemainingReceived: () => _setStatus('waiting_for_provider_confirmation'),
                  onConfirmComplete: () => _confirmAndSetStatus(
                    title: 'Complete',
                    message: 'Mark this booking as completed?',
                    status: 'completed',
                  ),
                  onEnterCode: _openVerify,
                  onScanQr: _openScanQr,
                  onSubmitInspection: () => _openSubmitInspection(isRevising: isRevising),
                  onAcceptEmergency: _acceptEmergency,
                  onRequestReschedule: _openReschedule,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '—';
    final String s = raw.toString();
    try {
      final DateTime t = DateFormat('HH:mm:ss').parse(s);
      return DateFormat('h:mm a').format(t);
    } catch (_) {
      return s;
    }
  }

  String _money(dynamic raw) {
    final double v = double.tryParse(raw?.toString() ?? '') ?? 0;
    return v.toStringAsFixed(2);
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.navy)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 3),
                Text(message, style: TextStyle(fontSize: 12.5, color: color, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 13, color: AppTheme.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.navy))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.normalizedStatus,
    required this.rawStatus,
    required this.hasStarted,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.preferredDate,
    required this.seekerVerified,
    required this.needsInspectionReport,
    required this.isRevising,
    required this.showEmergencyAcceptBtn,
    required this.canRequestReschedule,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onStartPreparing,
    required this.onEditEquipment,
    required this.onStartService,
    required this.onCancel,
    required this.onMarkWaitingRemaining,
    required this.onMarkWaitingSeekerConfirm,
    required this.onConfirmRemainingReceived,
    required this.onConfirmComplete,
    required this.onEnterCode,
    required this.onScanQr,
    required this.onSubmitInspection,
    required this.onAcceptEmergency,
    required this.onRequestReschedule,
  });

  final String normalizedStatus;
  final String rawStatus;
  final bool hasStarted;
  final String paymentStatus;
  final String paymentMethod;
  // Raw preferred_date and the seeker's own verification timestamp — used
  // only to gate "Enter Seeker Code" to the service day (or bypass it once
  // the seeker has already submitted their side — Start Early), same as
  // the web's provider dashboard and the seeker's own mobile screen.
  final String? preferredDate;
  final bool seekerVerified;
  // Gates the Submit/Resubmit Inspection Report button — true while a
  // requires_inspection booking is 'accepted' or 'revising' and hasn't had
  // its report agreed to yet (mirrors web's needsInspectionReport).
  final bool needsInspectionReport;
  final bool isRevising;
  final bool showEmergencyAcceptBtn;
  final bool canRequestReschedule;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onStartPreparing;
  final VoidCallback onEditEquipment;
  final VoidCallback onStartService;
  final VoidCallback onCancel;
  final VoidCallback onMarkWaitingRemaining;
  final VoidCallback onMarkWaitingSeekerConfirm;
  final VoidCallback onConfirmRemainingReceived;
  final VoidCallback onConfirmComplete;
  final VoidCallback onEnterCode;
  final VoidCallback onScanQr;
  final VoidCallback onSubmitInspection;
  final VoidCallback onAcceptEmergency;
  final VoidCallback onRequestReschedule;

  // Same "paid or at least a downpayment" bar the seeker's own mobile
  // screen and the web's dual-verification widget both enforce.
  bool get _isPaidEnough =>
      paymentStatus == 'paid' || paymentStatus == 'partial';

  bool get _isServiceDay {
    if (preferredDate == null || preferredDate!.isEmpty) return false;
    try {
      final DateTime d = DateTime.parse(preferredDate!);
      final DateTime now = DateTime.now();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    } catch (_) {
      return false;
    }
  }

  bool get _verificationWindowOpen =>
      !hasStarted &&
      !<String>['pending', 'cancelled', 'completed'].contains(normalizedStatus) &&
      _isPaidEnough;

  // "Enter Seeker Code" additionally waits for the service day, unless the
  // seeker already verified their side first (Start Early).
  bool get _canEnterCode =>
      _verificationWindowOpen && (_isServiceDay || seekerVerified);

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = <Widget>[];

    if (normalizedStatus == 'pending') {
      actions.add(_btn('Accept', Icons.check_circle_outline, AppTheme.primary, Colors.white, onAccept));
      actions.add(_btn('Decline', Icons.cancel_outlined, Colors.red.withValues(alpha: 0.08), Colors.red[700]!, onDecline));
    }

    if (_canEnterCode) {
      actions.add(_btn(
        'Enter Seeker Code',
        Icons.pin_outlined,
        const Color(0xFF52B788).withValues(alpha: 0.15),
        AppTheme.primary,
        onEnterCode,
      ));
    }

    // Additive — shown alongside whatever the status chain below renders,
    // not instead of it (mirrors web's footer button logic exactly).
    if (showEmergencyAcceptBtn) {
      actions.add(_btn('Accept Emergency', Icons.bolt_rounded, const Color(0xFFB91C1C), Colors.white, onAcceptEmergency));
    }

    if (needsInspectionReport) {
      actions.add(_btn(
        isRevising ? 'Resubmit Inspection Report' : 'Submit Inspection Report',
        Icons.assignment_outlined,
        AppTheme.indigo,
        Colors.white,
        onSubmitInspection,
      ));
    } else if (normalizedStatus == 'accepted') {
      actions.add(_btn('Start Preparing', Icons.build_outlined, AppTheme.indigo, Colors.white, onStartPreparing));
    }

    if (normalizedStatus == 'accepted') {
      if (canRequestReschedule) {
        actions.add(_btn('Request Reschedule', Icons.event_repeat_rounded, AppTheme.indigo.withValues(alpha: 0.1), AppTheme.indigo, onRequestReschedule));
      }
      actions.add(_btn('Cancel', Icons.cancel_outlined, Colors.red.withValues(alpha: 0.08), Colors.red[700]!, onCancel));
    }

    if (normalizedStatus == 'preparing') {
      actions.add(_btn('Start Service', Icons.play_circle_outline, AppTheme.indigo, Colors.white, onStartService));
      actions.add(_btn('Edit Equipment & Staff', Icons.build_circle_outlined, AppTheme.indigo.withValues(alpha: 0.1), AppTheme.indigo, onEditEquipment));
      if (canRequestReschedule) {
        actions.add(_btn('Request Reschedule', Icons.event_repeat_rounded, AppTheme.indigo.withValues(alpha: 0.1), AppTheme.indigo, onRequestReschedule));
      }
      actions.add(_btn('Cancel', Icons.cancel_outlined, Colors.red.withValues(alpha: 0.08), Colors.red[700]!, onCancel));
    }

    if (normalizedStatus == 'starting') {
      actions.add(_btn('Scan QR to Start Service', Icons.qr_code_scanner_rounded, AppTheme.primary, Colors.white, onScanQr));
    }

    if (normalizedStatus == 'on_going') {
      final bool needsRemaining = paymentMethod == 'downpayment' && paymentStatus != 'paid';
      if (needsRemaining) {
        actions.add(_btn('Mark Waiting for Remaining Payment', Icons.payments_outlined, Colors.orange[700]!, Colors.white, onMarkWaitingRemaining));
      } else {
        actions.add(_btn('Mark Ready for Client Confirmation', Icons.task_alt_rounded, AppTheme.primary, Colors.white, onMarkWaitingSeekerConfirm));
      }
    }

    if (normalizedStatus == 'waiting_for_remaining_payment') {
      if (paymentStatus == 'paid') {
        actions.add(_btn('Confirm Remaining Payment Received', Icons.price_check_rounded, AppTheme.primary, Colors.white, onConfirmRemainingReceived));
      } else {
        actions.add(_infoBadge('Waiting for the client to pay the remaining balance.'));
      }
      actions.add(_btn('Cancel', Icons.cancel_outlined, Colors.red.withValues(alpha: 0.08), Colors.red[700]!, onCancel));
    }

    if (normalizedStatus == 'waiting_for_provider_confirmation') {
      actions.add(_btn('Confirm & Complete', Icons.task_alt_rounded, AppTheme.primary, Colors.white, onConfirmComplete));
    }

    if (normalizedStatus == 'waiting_for_seeker_confirmation') {
      actions.add(_infoBadge('Waiting for the client to confirm the service was completed.'));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return AbsorbPointer(
      absorbing: busy,
      child: Opacity(
        opacity: busy ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: actions.expand<Widget>((Widget w) => <Widget>[w, const SizedBox(height: 10)]).toList()..removeLast(),
        ),
      ),
    );
  }

  Widget _btn(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _infoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: <Widget>[
          Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
        ],
      ),
    );
  }
}

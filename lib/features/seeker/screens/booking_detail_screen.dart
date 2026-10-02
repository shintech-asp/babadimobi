import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/utils/booking_status_utils.dart';
import 'package:pestify_flutter/shared/utils/timestamps.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';
import 'package:pestify_flutter/shared/widgets/inspection_pending_banner.dart';

/// Booking Detail Screen
///
/// Loads a single booking by [bookingId] (path param) and renders:
///  - Service / provider / date / address / payment info
///  - Status timeline (vertical stepper)
///  - Conditional action buttons based on current status
///
/// Navigation targets for actions are pushed as named routes with extras.
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      ref.read(seekerApiProvider).getBookingDetail(widget.bookingId);

  /// Awaits the new fetch (not just assigns it) so [RefreshIndicator]'s own
  /// spinner stays up until the data has actually arrived, instead of
  /// dismissing the instant this function returns — which made a successful
  /// pull-to-refresh look like it hadn't done anything.
  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _load();
    // Block body, not `() => _future = next` — an assignment expression
    // evaluates to the assigned value, so that arrow-function form actually
    // returns the Future itself. setState() then throws "callback argument
    // returned a Future" *before* calling markNeedsBuild(), so every prior
    // caller of this method (cancel, confirm-complete, respond-reschedule,
    // emergency-now, retry-payment, and now agree/request-changes) silently
    // updated `_future` but never actually triggered a rebuild — the screen
    // just sat on stale data no matter how many times you pulled to refresh.
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  // ── Cancel booking ────────────────────────────────────────────────────────────

  Future<void> _cancelBooking() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking? '
          'This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(seekerApiProvider).cancelBooking(widget.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Confirm service complete ─────────────────────────────────────────────────

  Future<void> _confirmComplete(int bookingId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Confirm Completion'),
        content: const Text(
          'Was the service completed to your satisfaction? '
          'This will mark the booking as completed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not Yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Completed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(seekerApiProvider).confirmServiceComplete(bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Booking marked as completed.')),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Reschedule response ──────────────────────────────────────────────────────

  Future<void> _respondReschedule(int bookingId, bool accept) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(accept ? 'Accept New Schedule?' : 'Keep Current Schedule?'),
        content: Text(
          accept
              ? 'Your booking will be updated to the provider\'s proposed date and time.'
              : 'The provider\'s proposed schedule will be declined.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(seekerApiProvider)
          .respondToReschedule(availId: bookingId, accept: accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept
              ? 'New schedule accepted.'
              : 'Reschedule request declined.'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Inspection report response ───────────────────────────────────────────────

  Future<void> _agreeInspection(int bookingId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Agree & Schedule?'),
        content: const Text(
          'This locks in the proposed working date and final price. '
          'You can then proceed to payment.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(seekerApiProvider)
          .respondToInspection(bookingId: bookingId, agree: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Working date and price confirmed.')),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  Future<void> _requestInspectionChanges(int bookingId) async {
    final TextEditingController notesCtrl = TextEditingController();
    final String? notes = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Request Changes'),
        content: TextField(
          controller: notesCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'What would you like changed? (price, scope, working date...)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final String text = notesCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );

    if (notes == null || notes.isEmpty) return;

    try {
      await ref.read(seekerApiProvider).respondToInspection(
            bookingId: bookingId,
            agree: false,
            notes: notes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change request sent to the provider.')),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Emergency Now ─────────────────────────────────────────────────────────────

  Future<void> _requestEmergencyNow(int bookingId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Request Emergency Service Now?'),
        content: const Text(
          'This will notify the provider to prioritize this booking for '
          'immediate service today.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request Now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(seekerApiProvider).requestEmergencyNow(bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency service requested.')),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Retry payment ─────────────────────────────────────────────────────────────

  Future<void> _retryPayment(int bookingId) async {
    try {
      final Map<String, dynamic> result =
          await ref.read(seekerApiProvider).retryPayment(bookingId);
      if (!mounted) return;
      final String? checkoutUrl = result['checkout_url'] as String?;
      if (checkoutUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unexpected server response. Please try again.')),
        );
        return;
      }
      context.push(
        '/seeker/payment',
        extra: <String, dynamic>{
          'checkoutUrl': checkoutUrl,
          'bookingId': bookingId,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateFormat('MMMM d, yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final DateTime dt = DateFormat('HH:mm:ss').parse(raw);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '—';
    final double? d = double.tryParse(amount.toString());
    if (d == null) return amount.toString();
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(d);
  }

  String _extractError(Object e) {
    String raw = e.toString();
    if (raw.startsWith('Exception: ')) raw = raw.replaceFirst('Exception: ', '');
    if (raw.startsWith('Bad state: ')) raw = raw.replaceFirst('Bad state: ', '');
    return raw.trim().isEmpty ? 'Something went wrong. Please try again.' : raw;
  }

  bool _hasNoReview(Map<String, dynamic> booking) {
    final dynamic review = booking['review'] ?? booking['existing_review'];
    return review == null;
  }

  int? _existingRating(Map<String, dynamic> booking) {
    final dynamic review = booking['review'] ?? booking['existing_review'];
    if (review is Map) {
      return int.tryParse(review['rating']?.toString() ?? '');
    }
    return null;
  }

  bool _canCancel(String status) =>
      status == 'pending' || status == 'accepted';

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Booking Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (
          BuildContext ctx,
          AsyncSnapshot<Map<String, dynamic>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primary,
                strokeWidth: 2.5,
              ),
            );
          }

          if (snapshot.hasError) {
            return _DetailErrorState(
              message: _extractError(snapshot.error!),
              onRetry: _refresh,
            );
          }

          final Map<String, dynamic> booking =
              snapshot.data ?? <String, dynamic>{};
          final String status = booking['status']?.toString() ?? 'pending';
          final bool hasStarted = isRealTimestamp(booking['dual_verified_at']);
          final bool requiresInspection = booking['requires_inspection'] == true ||
              booking['requires_inspection'] == 1 ||
              booking['requires_inspection'] == '1';
          final bool inspectionAgreed =
              isRealTimestamp(booking['inspection_agreed_at']);
          // Still waiting for the technician to visit and set a final
          // price — status is plain 'accepted', not yet 'awaiting_agreement'
          // (that only starts once a report is actually submitted). Same
          // signal seeker/my-requests.php's "Waiting for on-site
          // inspection" strip and monitoring pill use.
          final bool awaitingInspection =
              requiresInspection && status == 'accepted' && !inspectionAgreed;
          final bool isAwaitingAgreement = status == 'awaiting_agreement';
          final bool isRevising = status == 'revising';
          final String? qrToken = booking['qr_token']?.toString();
          final String? controlNumber = booking['control_number']?.toString();
          final dynamic rawId = booking['id'] ?? booking['avail_id'];
          final int? id = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '');
          final String paymentMethod =
              booking['payment_method']?.toString() ?? 'full_payment';
          final double remainingBalance = double.tryParse(
                  booking['remaining_balance']?.toString() ??
                      booking['remaining_amount']?.toString() ??
                      '') ??
              0;
          final List<Map<String, dynamic>> receipts = (booking['receipts']
                      is List
                  ? booking['receipts'] as List
                  : const <dynamic>[])
              .whereType<Map>()
              .map((dynamic r) => Map<String, dynamic>.from(r))
              .toList();

          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      // ── Status header ───────────────────────────────────────
                      _SectionCard(
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    // API: listing_title (from sl.title) or service_name
                                    (booking['listing_title'] ?? booking['service_name'])?.toString() ??
                                        'Service',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    // API: company_name or provider_name
                                    (booking['company_name'] ?? booking['provider_name'])?.toString() ?? '',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                BookingStatusChip(status: status, hasStarted: hasStarted),
                                const SizedBox(height: 8),
                                _MessageProviderButton(
                                  bookingId: id ?? widget.bookingId,
                                  companyName: (booking['company_name'] ??
                                          booking['provider_name'])
                                      ?.toString() ??
                                      'Provider',
                                  serviceName: (booking['listing_title'] ??
                                          booking['service_name'])
                                      ?.toString() ??
                                      '',
                                  status: status,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Reschedule proposal banner ──────────────────────────
                      if (booking['reschedule_request_status']?.toString() ==
                              'pending' &&
                          (booking['reschedule_proposed_date']?.toString() ?? '')
                              .isNotEmpty &&
                          (booking['reschedule_proposed_time']?.toString() ?? '')
                              .isNotEmpty &&
                          status != 'completed' &&
                          status != 'cancelled') ...<Widget>[
                        _RescheduleProposalBanner(
                          proposedDate: _formatDate(
                              booking['reschedule_proposed_date']?.toString()),
                          proposedTime: _formatTime(
                              booking['reschedule_proposed_time']?.toString()),
                          reason: booking['reschedule_reason']?.toString(),
                          onAccept: () =>
                              _respondReschedule(id ?? widget.bookingId, true),
                          onReject: () =>
                              _respondReschedule(id ?? widget.bookingId, false),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Awaiting inspection banner ──────────────────────────
                      if (awaitingInspection) ...<Widget>[
                        InspectionPendingBanner(
                          inspectionDate: _formatDate(
                            (booking['inspection_date'] ??
                                    booking['preferred_date'])
                                ?.toString(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Inspection report / revising banners ────────────────
                      if (isAwaitingAgreement) ...<Widget>[
                        _InspectionReportBanner(
                          imageUrl: ApiEndpoints.resolveImageUrl(
                            booking['inspection_report_image']?.toString(),
                          ),
                          notes: booking['inspection_report_notes']?.toString(),
                          proposedPrice: _formatCurrency(
                              booking['inspection_proposed_price']),
                          proposedWorkingDate: _formatDate(
                            booking['inspection_proposed_working_date']
                                ?.toString(),
                          ),
                          onAgree: () =>
                              _agreeInspection(id ?? widget.bookingId),
                          onRequestChanges: () => _requestInspectionChanges(
                              id ?? widget.bookingId),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (isRevising) ...<Widget>[
                        _InspectionRevisingBanner(
                          changeNotes:
                              booking['inspection_change_notes']?.toString(),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Details grid ────────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          children: <Widget>[
                            _DetailRow(
                              icon: Icons.calendar_today_outlined,
                              // Same distinction as the web's monitoring
                              // pill: while still awaiting inspection, this
                              // date is only when the technician visits to
                              // assess the job, not the actual service date
                              // — labeling it plain "Date" would let the
                              // seeker mistake it for a confirmed schedule.
                              label: awaitingInspection ? 'Inspection Date' : 'Date',
                              value: _formatDate(
                                (awaitingInspection
                                        ? (booking['inspection_date'] ??
                                            booking['preferred_date'])
                                        : booking['preferred_date'])
                                    ?.toString(),
                              ),
                            ),
                            const Divider(height: 20),
                            _DetailRow(
                              icon: Icons.access_time_outlined,
                              label: 'Time',
                              value: _formatTime(
                                  booking['preferred_time']?.toString()),
                            ),
                            const Divider(height: 20),
                            _DetailRow(
                              icon: Icons.location_on_outlined,
                              label: 'Address',
                              value:
                                  booking['address']?.toString() ?? '—',
                            ),
                            const Divider(height: 20),
                            _DetailRow(
                              icon: Icons.payment_outlined,
                              label: 'Payment',
                              value: (booking['payment_method']?.toString() ??
                                      'full')
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Payment amounts ─────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'PAYMENT SUMMARY',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _AmountRow(
                              label: 'Total Price',
                              value: _formatCurrency(booking['total_price'] ??
                                  booking['price']),
                            ),
                            if (booking['amount_paid'] != null) ...<Widget>[
                              const SizedBox(height: 6),
                              _AmountRow(
                                label: 'Amount Paid',
                                value:
                                    _formatCurrency(booking['amount_paid']),
                                valueColor: AppTheme.primary,
                              ),
                            ],
                            if (booking['remaining_balance'] != null) ...<Widget>[
                              const SizedBox(height: 6),
                              _AmountRow(
                                label: 'Remaining Balance',
                                value: _formatCurrency(
                                    booking['remaining_balance']),
                                valueColor: Colors.orange[700],
                                isBold: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Payment receipts ─────────────────────────────────────
                      if (receipts.isNotEmpty) ...<Widget>[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'PAYMENT RECEIPTS',
                                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color:
                                          Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              for (final Map<String, dynamic> receipt in receipts) ...<Widget>[
                                _ReceiptRow(
                                  receipt: receipt,
                                  formatCurrency: _formatCurrency,
                                ),
                                if (receipt != receipts.last)
                                  const Divider(height: 20),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Status timeline ─────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'BOOKING TIMELINE',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            _StatusTimeline(
                              currentStatus: status,
                              paymentMethod: paymentMethod,
                              hasStarted: hasStarted,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Action area ─────────────────────────────────────────
                      _ActionArea(
                        status: status,
                        paymentStatus: booking['payment_status']?.toString() ?? '',
                        preferredDate: booking['preferred_date']?.toString(),
                        providerVerified:
                            isRealTimestamp(booking['provider_verified_at']),
                        // For a requires_inspection service the price at
                        // 'pending'/'accepted' is only an estimate (see
                        // api/v1/seeker/bookings/store.php, which
                        // deliberately never creates a checkout for these) —
                        // there's nothing to pay yet unless the seeker has
                        // already agreed to the technician's final proposed
                        // price (inspection_agreed_at set), at which point
                        // this is a normal, already-finalized booking again.
                        requiresPendingPayment: !(booking['requires_inspection'] == true ||
                                booking['requires_inspection'] == 1 ||
                                booking['requires_inspection'] == '1') ||
                            isRealTimestamp(booking['inspection_agreed_at']),
                        remainingBalance: remainingBalance,
                        hasStarted: hasStarted,
                        bookingId: id ?? widget.bookingId,
                        qrToken: qrToken,
                        controlNumber: controlNumber,
                        hasNoReview: _hasNoReview(booking),
                        existingRating: _existingRating(booking),
                        canCancel: _canCancel(status),
                        emergencyRequested:
                            booking['emergency_now_requested'] == true ||
                                booking['emergency_now_requested'] == 1 ||
                                booking['emergency_now_requested'] == '1',
                        onCancel: _cancelBooking,
                        onConfirmComplete: () =>
                            _confirmComplete(id ?? widget.bookingId),
                        onEmergencyNow: () =>
                            _requestEmergencyNow(id ?? widget.bookingId),
                        onRetryPayment: () =>
                            _retryPayment(id ?? widget.bookingId),
                        onAfterNavigate: _refresh,
                      ),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Message provider button ───────────────────────────────────────────────────

/// Opens this booking's transaction-scoped chat thread. Always tappable,
/// even once the booking is closed (completed/cancelled) — the thread
/// screen itself renders the closed bar and read-only history in that case,
/// same as opening a closed thread from the Messages inbox.
class _MessageProviderButton extends StatelessWidget {
  const _MessageProviderButton({
    required this.bookingId,
    required this.companyName,
    required this.serviceName,
    required this.status,
  });

  final int bookingId;
  final String companyName;
  final String serviceName;
  final String status;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push(
        '/seeker/message-thread',
        extra: <String, dynamic>{
          'bookingId': bookingId,
          'companyName': companyName,
          'serviceName': serviceName,
          'status': status,
        },
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.chat_bubble_outline_rounded,
                size: 14, color: AppTheme.primary),
            SizedBox(width: 5),
            Text(
              'Message',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Timeline ───────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    required this.currentStatus,
    required this.paymentMethod,
    required this.hasStarted,
  });

  final String currentStatus;
  final String paymentMethod;
  final bool hasStarted;

  bool get _isDownpayment => paymentMethod == 'downpayment';

  /// The web app shows a different branch of the timeline depending on
  /// payment method — downpayment bookings pass through a remaining-payment
  /// + provider-confirmation pair that full-payment bookings never reach,
  /// and vice versa for the seeker-confirmation step. Mirror that here so a
  /// booking on one path doesn't show a permanently-unreached step from the
  /// other.
  List<_TimelineStep> get _steps {
    final List<_TimelineStep> steps = <_TimelineStep>[
      const _TimelineStep(status: 'pending', label: 'Pending', icon: Icons.hourglass_empty_rounded),
      const _TimelineStep(status: 'accepted', label: 'Accepted', icon: Icons.thumb_up_outlined),
      const _TimelineStep(status: 'preparing', label: 'Preparing', icon: Icons.inventory_2_outlined),
      const _TimelineStep(status: 'starting', label: 'Starting', icon: Icons.directions_run_rounded),
      const _TimelineStep(status: 'on_going', label: 'In Progress', icon: Icons.pest_control_rounded),
    ];
    if (_isDownpayment) {
      steps.add(const _TimelineStep(
          status: 'waiting_for_remaining_payment',
          label: 'Awaiting Payment',
          icon: Icons.payment_outlined));
      steps.add(const _TimelineStep(
          status: 'waiting_for_provider_confirmation',
          label: 'Awaiting Provider Confirmation',
          icon: Icons.verified_outlined));
    } else {
      steps.add(const _TimelineStep(
          status: 'waiting_for_seeker_confirmation',
          label: 'Awaiting Your Confirmation',
          icon: Icons.verified_outlined));
    }
    steps.add(const _TimelineStep(
        status: 'completed', label: 'Completed', icon: Icons.check_circle_outline_rounded));
    return steps;
  }

  static const Set<String> _finalStageFamily = <String>{
    'waiting_for_remaining_payment',
    'waiting_for_seeker_confirmation',
    'waiting_for_provider_confirmation',
  };

  /// Finds this booking's position in [_steps]. [normalizeBookingStatus]
  /// always maps the legacy web "confirm" spellings onto
  /// `waiting_for_seeker_confirmation` regardless of payment method (that's
  /// their true meaning), but a downpayment booking's step list only
  /// contains `waiting_for_provider_confirmation` in that slot — so a direct
  /// lookup can miss even though the booking is genuinely in its final
  /// pre-completion stage. When that happens, fall back to "the last waiting
  /// step before completed" rather than silently resetting to "Pending".
  int _statusIndex(String normalizedStatus) {
    final List<_TimelineStep> steps = _steps;
    final int idx = steps.indexWhere((s) => s.status == normalizedStatus);
    if (idx >= 0) return idx;
    if (_finalStageFamily.contains(normalizedStatus)) {
      return steps.length - 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (currentStatus == 'cancelled') {
      return Row(
        children: <Widget>[
          const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Text(
            'This booking was cancelled.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      );
    }

    final List<_TimelineStep> steps = _steps;
    final String normalizedStatus =
        normalizeBookingStatus(currentStatus, hasStarted: hasStarted);
    final int currentIndex = _statusIndex(normalizedStatus);
    // The step occupying currentIndex may not be the semantically-correct
    // one when the booking crossed into the "other" branch's final-stage
    // status (see _statusIndex's fallback) — always trust the normalized
    // status itself for what to actually tell the seeker, not whichever
    // step object happened to land at that index.
    const Map<String, String> finalStageLabels = <String, String>{
      'waiting_for_remaining_payment': 'Awaiting Payment',
      'waiting_for_seeker_confirmation': 'Awaiting Your Confirmation',
      'waiting_for_provider_confirmation': 'Awaiting Provider Confirmation',
    };
    const Map<String, IconData> finalStageIcons = <String, IconData>{
      'waiting_for_remaining_payment': Icons.payment_outlined,
      'waiting_for_seeker_confirmation': Icons.verified_outlined,
      'waiting_for_provider_confirmation': Icons.verified_outlined,
    };
    final String? currentLabelOverride = finalStageLabels[normalizedStatus];
    final IconData? currentIconOverride = finalStageIcons[normalizedStatus];

    return Column(
      children: List<Widget>.generate(steps.length, (int i) {
        final _TimelineStep step = steps[i];
        final bool isCompleted = i < currentIndex;
        final bool isCurrent = i == currentIndex;
        final bool isLast = i == steps.length - 1;
        final String label =
            isCurrent && currentLabelOverride != null ? currentLabelOverride : step.label;
        final IconData icon =
            isCurrent && currentIconOverride != null ? currentIconOverride : step.icon;

        final Color dotColor = isCompleted || isCurrent
            ? AppTheme.primary
            : Theme.of(context).colorScheme.outlineVariant;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── Dot + connector ─────────────────────────────────────────────
              SizedBox(
                width: 28,
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withValues(alpha: isCurrent ? 1 : 0.15),
                        border: Border.all(
                          color: dotColor,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 13,
                        color: isCompleted || isCurrent
                            ? (isCurrent
                                ? Colors.white
                                : AppTheme.primary)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isCompleted
                              ? AppTheme.primary.withValues(alpha: 0.4)
                              : Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // ── Label ───────────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 4,
                    bottom: isLast ? 0 : 16,
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isCurrent
                              ? AppTheme.primary
                              : isCompleted
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.5),
                        ),
                  ),
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CURRENT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppTheme.primary,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.status,
    required this.label,
    required this.icon,
  });

  final String status;
  final String label;
  final IconData icon;
}

// ── Verification code bottom sheet ──────────────────────────────────────────

void _showControlNumberSheet(BuildContext context, String controlNumber) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext ctx) => _ControlNumberSheet(controlNumber: controlNumber),
  );
}

class _ControlNumberSheet extends StatefulWidget {
  const _ControlNumberSheet({required this.controlNumber});

  final String controlNumber;

  @override
  State<_ControlNumberSheet> createState() => _ControlNumberSheetState();
}

class _ControlNumberSheetState extends State<_ControlNumberSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.controlNumber));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Your Verification Code',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Read this code out to your technician (or let them type it in) '
              'so they can verify their side and unlock the service — no need '
              'to wait until service day.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Text(
                widget.controlNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppTheme.navy,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                label: Text(_copied ? 'Copied!' : 'Copy Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Area ───────────────────────────────────────────────────────────────

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.status,
    required this.paymentStatus,
    required this.preferredDate,
    required this.providerVerified,
    required this.requiresPendingPayment,
    required this.remainingBalance,
    required this.hasStarted,
    required this.bookingId,
    required this.qrToken,
    required this.controlNumber,
    required this.hasNoReview,
    required this.existingRating,
    required this.canCancel,
    required this.emergencyRequested,
    required this.onCancel,
    required this.onConfirmComplete,
    required this.onEmergencyNow,
    required this.onRetryPayment,
    required this.onAfterNavigate,
  });

  final String status;
  final String paymentStatus;
  // Raw preferred_date (YYYY-MM-DD or full timestamp) — used only to gate
  // the "Enter Provider Code" action to the service day, same as web.
  final String? preferredDate;
  // Whether the technician has already submitted their side of the code
  // handshake — when true, the seeker's own service-day gate is bypassed
  // (Start Early), matching seeker/my-requests.php's own bypass.
  final bool providerVerified;
  // False for a requires_inspection booking whose price is still only an
  // estimate (no checkout was ever created for it server-side — see
  // api/v1/seeker/bookings/store.php); true once the price is finalized,
  // either because the service never required inspection or because the
  // seeker already agreed to the technician's proposed price.
  final bool requiresPendingPayment;
  final double remainingBalance;
  final bool hasStarted;
  final int bookingId;
  final String? qrToken;
  final String? controlNumber;
  final bool hasNoReview;
  final int? existingRating;
  final bool canCancel;
  final bool emergencyRequested;
  final VoidCallback onCancel;
  final VoidCallback onConfirmComplete;
  final VoidCallback onEmergencyNow;
  final VoidCallback onRetryPayment;
  // Called after returning from a pushed screen that may have changed
  // verification state (QR scan / control-number entry), so the caller can
  // refetch — otherwise this screen keeps showing stale pre-verification
  // actions until a manual pull-to-refresh.
  final VoidCallback onAfterNavigate;

  bool get _isStarting => status == 'starting';

  // Same "paid or at least a downpayment" bar the web's dual-verification
  // widget and ControlNumberService (backend) both enforce — a downpayment
  // plan is expected to still read 'partial' throughout the service, so
  // only a fully 'unpaid' booking is blocked.
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

  // The dual control-number handshake (ControlNumberService on the backend)
  // is what unlocks the service early — it runs as soon as the booking is
  // accepted and doesn't require (or lead through) the QR-based 'starting'
  // status at all. Both sides can submit their code any time before
  // `dual_verified_at` is stamped, but only once payment is actually in —
  // codes are generated right at Accept, long before payment (and, for an
  // inspection-required service, before a final price even exists).
  bool get _verificationWindowOpen =>
      !hasStarted &&
      !<String>['pending', 'cancelled', 'completed'].contains(status) &&
      _isPaidEnough;

  // The actual "Enter Provider Code" action additionally waits for the
  // service day — unless the technician already verified their side first
  // (Start Early), same bypass seeker/my-requests.php's own handler uses.
  // "Show My Verification Code" has no such date restriction — nothing
  // wrong with seeing/copying it early once paid.
  bool get _canEnterCode =>
      _verificationWindowOpen && (_isServiceDay || providerVerified);

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = <Widget>[];

    // 0. Retry Payment (initial checkout never completed)
    if ((status == 'pending' || status == 'accepted') &&
        paymentStatus == 'unpaid' &&
        requiresPendingPayment) {
      actions.add(
        _ActionButton(
          label: 'Complete Payment',
          icon: Icons.credit_card_rounded,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onTap: onRetryPayment,
        ),
      );
    }

    // 1a. Show My Verification Code (available as soon as it's generated,
    // i.e. once accepted — this is the code the provider reads/types to
    // verify their side of the handshake; it's what lets them start the
    // service early, before 'starting'/QR is ever reached).
    if (_verificationWindowOpen &&
        controlNumber != null &&
        controlNumber!.isNotEmpty) {
      actions.add(
        _ActionButton(
          label: 'Show My Verification Code',
          icon: Icons.badge_outlined,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onTap: () => _showControlNumberSheet(context, controlNumber!),
        ),
      );
    }

    // 1b. Show QR Code (only meaningful once 'starting' — separate,
    // scan-based mechanism from the typed code above).
    if (_isStarting && qrToken != null && qrToken!.isNotEmpty) {
      actions.add(
        _ActionButton(
          label: 'Show My QR Code',
          icon: Icons.qr_code_2_rounded,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onTap: () async {
            await context.push(
              '/seeker/qr',
              extra: <String, dynamic>{'qrToken': qrToken},
            );
            onAfterNavigate();
          },
        ),
      );
    }

    // 2. Enter Provider Code — available once paid and on/after the service
    // day (or as soon as the technician has already verified their side —
    // Start Early). The seeker doesn't need to wait for the provider to go
    // first otherwise; ControlNumberService accepts either order once the
    // date gate is satisfied.
    if (_canEnterCode) {
      actions.add(
        _ActionButton(
          label: 'Enter Provider Code',
          icon: Icons.pin_outlined,
          backgroundColor: const Color(0xFF52B788).withValues(alpha: 0.15),
          foregroundColor: AppTheme.primary,
          onTap: () async {
            await context.push(
              '/seeker/verify',
              extra: <String, dynamic>{'availId': bookingId},
            );
            onAfterNavigate();
          },
        ),
      );
    }

    // 3. Pay Remaining Balance — the legacy 'waiting_remaining_payment' status
    // can linger with the balance already paid (my-requests.php's own
    // "auto-heal" comment documents this exact drift), so also require
    // paymentStatus != 'paid' to avoid offering a second checkout for money
    // already collected.
    if (normalizeBookingStatus(status) == 'waiting_for_remaining_payment' &&
        paymentStatus != 'paid' &&
        remainingBalance > 0.009) {
      actions.add(
        _ActionButton(
          label: 'Pay Remaining Balance',
          icon: Icons.payment_rounded,
          backgroundColor: Colors.orange[700]!,
          foregroundColor: Colors.white,
          onTap: () => context.push(
            '/seeker/remaining-payment',
            extra: <String, dynamic>{'bookingId': bookingId},
          ),
        ),
      );
    }

    // 3b. Confirm Service Complete — normalizeBookingStatus() folds the web
    // app's legacy 'waiting_provider_confirmation' (no "for") spelling onto
    // 'waiting_for_seeker_confirmation', since that's its usual meaning —
    // distinct from the canonical mobile-written
    // 'waiting_for_provider_confirmation' (WITH "for"), which means the
    // PROVIDER must confirm, e.g. after collecting a downpayment's
    // remaining balance, and is deliberately excluded here.
    //
    // BUT the exact same legacy string is ALSO written by the provider
    // portal CRM to mean "just accepted" — an early, pre-service state. The
    // literal 'waiting_for_seeker_confirmation' (canonical) is unambiguous;
    // for the legacy family, only trust it once hasStarted (dual_verified_at
    // set) proves the booking actually reached the service-day handshake —
    // a freshly-accepted booking could never have that set.
    final String normalizedStatus = normalizeBookingStatus(status);
    final bool isCanonicalSeekerConfirm =
        status.toLowerCase().trim() == 'waiting_for_seeker_confirmation';
    final bool awaitingSeekerConfirmation =
        (normalizedStatus == 'waiting_for_seeker_confirmation' &&
                (isCanonicalSeekerConfirm || hasStarted)) ||
            (normalizedStatus == 'waiting_for_remaining_payment' &&
                paymentStatus == 'paid');
    final bool balanceSettled =
        !(paymentStatus == 'partial' && remainingBalance > 0.009);
    if (awaitingSeekerConfirmation && balanceSettled) {
      actions.add(
        _ActionButton(
          label: 'Confirm Service Complete',
          icon: Icons.task_alt_rounded,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onTap: onConfirmComplete,
        ),
      );
    }

    // 3c. Emergency Service Now
    if (const <String>['accepted', 'preparing'].contains(status) &&
        const <String>['paid', 'partial'].contains(paymentStatus)) {
      if (emergencyRequested) {
        actions.add(const _EmergencyRequestedBadge());
      } else {
        actions.add(
          _ActionButton(
            label: 'Emergency Service Now',
            icon: Icons.bolt_rounded,
            backgroundColor: Colors.deepOrange.withValues(alpha: 0.12),
            foregroundColor: Colors.deepOrange[700]!,
            onTap: onEmergencyNow,
          ),
        );
      }
    }

    // 4. Leave a Review
    if (status == 'completed') {
      if (hasNoReview) {
        actions.add(
          _ActionButton(
            label: 'Leave a Review',
            icon: Icons.star_outline_rounded,
            backgroundColor: Colors.amber.withValues(alpha: 0.15),
            foregroundColor: Colors.amber[800]!,
            onTap: () => context.push(
              '/seeker/review',
              extra: <String, dynamic>{'availId': bookingId},
            ),
          ),
        );
      } else {
        actions.add(_AlreadyReviewedBadge(rating: existingRating));
      }
    }

    // 5. Cancel Booking
    if (canCancel) {
      actions.add(
        _ActionButton(
          label: 'Cancel Booking',
          icon: Icons.cancel_outlined,
          backgroundColor: Colors.red.withValues(alpha: 0.08),
          foregroundColor: Colors.red[700]!,
          onTap: onCancel,
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actions
          .expand<Widget>(
            (w) => <Widget>[w, const SizedBox(height: 10)],
          )
          .toList()
        ..removeLast(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Non-interactive indicator shown in place of "Leave a Review" once the
/// seeker has already rated this booking — prevents duplicate submissions.
class _AlreadyReviewedBadge extends StatelessWidget {
  const _AlreadyReviewedBadge({required this.rating});

  final int? rating;

  @override
  Widget build(BuildContext context) {
    final String label = (rating != null && rating! > 0)
        ? 'You rated this $rating/5'
        : 'You already reviewed this booking';

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.check_circle_rounded,
              size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-interactive indicator shown in place of "Emergency Service Now" once
/// it has already been requested for this booking.
class _EmergencyRequestedBadge extends StatelessWidget {
  const _EmergencyRequestedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.bolt_rounded, size: 18, color: Colors.deepOrange[700]),
          const SizedBox(width: 8),
          Text(
            'Emergency Service Requested',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.deepOrange[700],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when status is 'awaiting_agreement' — the technician submitted an
/// inspection report (photo, notes, final price, proposed working date) and
/// the seeker must Agree & Schedule (locks it in, re-enters the normal
/// accepted -> Pay Now pipeline) or Request Changes (loops back to the
/// provider for a new report). Mirrors seeker/my-requests.php's
/// "awaiting_agreement" pay-strip.
class _InspectionReportBanner extends StatelessWidget {
  const _InspectionReportBanner({
    required this.imageUrl,
    required this.notes,
    required this.proposedPrice,
    required this.proposedWorkingDate,
    required this.onAgree,
    required this.onRequestChanges,
  });

  final String? imageUrl;
  final String? notes;
  final String proposedPrice;
  final String proposedWorkingDate;
  final VoidCallback onAgree;
  final VoidCallback onRequestChanges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EEF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7BDE2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.search_rounded, color: Color(0xFF4A235A), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Inspection report ready — please review',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4A235A),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The technician inspected the site and proposed a working date and final price.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6C3483),
                ),
          ),
          if (imageUrl != null && imageUrl!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl!,
                height: 220,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (notes != null && notes!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE9D8F0)),
              ),
              child: Text(
                notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF334155),
                    ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: <Widget>[
              _InspectionFact(label: 'Proposed Working Date', value: proposedWorkingDate),
              _InspectionFact(label: 'Final Price', value: proposedPrice),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9A3412),
                    side: const BorderSide(color: Color(0xFFFDBA74)),
                  ),
                  onPressed: onRequestChanges,
                  child: const Text('Request Changes'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A9648),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onAgree,
                  child: const Text('Agree & Schedule'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InspectionFact extends StatelessWidget {
  const _InspectionFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6C3483)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A6640),
          ),
        ),
      ],
    );
  }
}

/// Shown when status is 'revising' — the seeker requested changes and the
/// provider hasn't submitted a new report yet. Read-only; nothing to action
/// until the next report arrives. Mirrors seeker/my-requests.php's
/// "revising" pay-strip.
class _InspectionRevisingBanner extends StatelessWidget {
  const _InspectionRevisingBanner({this.changeNotes});

  final String? changeNotes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF7ED), Color(0xFFFFFAF0)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.replay_rounded, color: Color(0xFF9A3412), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Provider is revising the inspection report',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9A3412),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  changeNotes != null && changeNotes!.isNotEmpty
                      ? 'You asked for changes: "$changeNotes". Waiting for a new report.'
                      : 'You asked for changes. Waiting for a new report.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF7C2D12), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner shown when the provider has proposed a new date/time, letting the
/// seeker accept or decline the reschedule.
class _RescheduleProposalBanner extends StatelessWidget {
  const _RescheduleProposalBanner({
    required this.proposedDate,
    required this.proposedTime,
    required this.reason,
    required this.onAccept,
    required this.onReject,
  });

  final String proposedDate;
  final String proposedTime;
  final String? reason;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.event_repeat_rounded,
                  color: Color(0xFF1D4ED8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Provider proposed a new schedule',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E3A8A),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$proposedDate at $proposedTime',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
          ),
          if (reason != null && reason!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              reason!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF1E40AF),
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Keep Current Schedule'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onAccept,
                  child: const Text('Accept New Schedule'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only row summarizing a single completed payment_transactions record.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt, required this.formatCurrency});

  final Map<String, dynamic> receipt;
  final String Function(dynamic) formatCurrency;

  @override
  Widget build(BuildContext context) {
    final String type = (receipt['payment_type']?.toString() ?? 'payment')
        .replaceAll('_', ' ');
    final String? receiptNumber = receipt['receipt_number']?.toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                type.isEmpty
                    ? 'Payment'
                    : '${type[0].toUpperCase()}${type.substring(1)}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (receiptNumber != null && receiptNumber.isNotEmpty)
                Text(
                  'Ref: $receiptNumber',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
        Text(
          formatCurrency(receipt['amount']),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.primary),
        ),
      ],
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: valueColor,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
        ),
      ],
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

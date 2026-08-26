import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';

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

  Future<void> _refresh() async {
    setState(() => _future = _load());
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
          final String? providerVerifiedAt =
              booking['provider_verified_at']?.toString();
          final String? qrToken = booking['qr_token']?.toString();
          final dynamic rawId = booking['id'] ?? booking['avail_id'];
          final int? id = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '');

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
                            BookingStatusChip(status: status),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Details grid ────────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          children: <Widget>[
                            _DetailRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Date',
                              value: _formatDate(
                                  booking['preferred_date']?.toString()),
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
                            _StatusTimeline(currentStatus: status),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Action area ─────────────────────────────────────────
                      _ActionArea(
                        status: status,
                        bookingId: id ?? widget.bookingId,
                        qrToken: qrToken,
                        providerVerifiedAt: providerVerifiedAt,
                        hasNoReview: _hasNoReview(booking),
                        canCancel: _canCancel(status),
                        onCancel: _cancelBooking,
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

// ── Status Timeline ───────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.currentStatus});

  final String currentStatus;

  static const List<_TimelineStep> _steps = <_TimelineStep>[
    _TimelineStep(status: 'pending', label: 'Pending', icon: Icons.hourglass_empty_rounded),
    _TimelineStep(status: 'accepted', label: 'Accepted', icon: Icons.thumb_up_outlined),
    _TimelineStep(status: 'preparing', label: 'Preparing', icon: Icons.inventory_2_outlined),
    _TimelineStep(status: 'starting', label: 'Starting', icon: Icons.directions_run_rounded),
    _TimelineStep(status: 'on_going', label: 'In Progress', icon: Icons.pest_control_rounded),
    _TimelineStep(
        status: 'waiting_for_remaining_payment',
        label: 'Awaiting Payment',
        icon: Icons.payment_outlined),
    _TimelineStep(
        status: 'waiting_for_seeker_confirmation',
        label: 'Awaiting Your Confirmation',
        icon: Icons.verified_outlined),
    _TimelineStep(status: 'completed', label: 'Completed', icon: Icons.check_circle_outline_rounded),
  ];

  int _statusIndex(String status) {
    final String normalized =
        status == 'ongoing' ? 'on_going' : status.toLowerCase();
    final int idx =
        _steps.indexWhere((s) => s.status == normalized);
    return idx < 0 ? 0 : idx;
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

    final int currentIndex = _statusIndex(currentStatus);

    return Column(
      children: List<Widget>.generate(_steps.length, (int i) {
        final _TimelineStep step = _steps[i];
        final bool isCompleted = i < currentIndex;
        final bool isCurrent = i == currentIndex;
        final bool isLast = i == _steps.length - 1;

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
                        step.icon,
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
                    step.label,
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

// ── Action Area ───────────────────────────────────────────────────────────────

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.status,
    required this.bookingId,
    required this.qrToken,
    required this.providerVerifiedAt,
    required this.hasNoReview,
    required this.canCancel,
    required this.onCancel,
  });

  final String status;
  final int bookingId;
  final String? qrToken;
  final String? providerVerifiedAt;
  final bool hasNoReview;
  final bool canCancel;
  final VoidCallback onCancel;

  bool get _isStarting => status == 'starting';
  bool get _providerVerified =>
      providerVerifiedAt != null && providerVerifiedAt!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = <Widget>[];

    // 1. Show QR Code (starting, seeker side)
    if (_isStarting && qrToken != null && qrToken!.isNotEmpty) {
      actions.add(
        _ActionButton(
          label: 'Show My QR Code',
          icon: Icons.qr_code_2_rounded,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onTap: () => context.push(
            '/seeker/qr',
            extra: <String, dynamic>{'qrToken': qrToken},
          ),
        ),
      );
    }

    // 2. Enter Provider Code (provider already verified OR it's starting)
    if (_isStarting && _providerVerified) {
      actions.add(
        _ActionButton(
          label: 'Enter Provider Code',
          icon: Icons.pin_outlined,
          backgroundColor: const Color(0xFF52B788).withValues(alpha: 0.15),
          foregroundColor: AppTheme.primary,
          onTap: () => context.push(
            '/seeker/verify',
            extra: <String, dynamic>{'availId': bookingId},
          ),
        ),
      );
    }

    // 3. Pay Remaining Balance
    if (status == 'waiting_for_remaining_payment') {
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

    // 4. Leave a Review
    if (status == 'completed' && hasNoReview) {
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

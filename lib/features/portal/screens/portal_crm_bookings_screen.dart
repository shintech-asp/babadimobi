import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, Color> _kBookingStatusColors = <String, Color>{
  'pending': Colors.orange,
  'accepted': Color(0xFF6366F1),
  'preparing': Color(0xFF6366F1),
  'starting': Color(0xFF0EA5E9),
  'on_going': AppTheme.primary,
  // Matches BK_WAITING_REMAINING in booking_workflow_helper.php exactly —
  // update-status.php's whitelist is the "_for_" spelling; the no-"_for_"
  // variant here always 422'd ("Invalid status value").
  'waiting_for_remaining_payment': Colors.orange,
  'waiting_for_seeker_confirmation': Colors.orange,
  'waiting_for_provider_confirmation': Colors.orange,
  'completed': AppTheme.primary,
  'cancelled': Colors.red,
};

const List<String> _kAdvanceableStatuses = <String>[
  'accepted',
  'preparing',
  'starting',
  'waiting_for_remaining_payment',
  'waiting_for_seeker_confirmation',
  'waiting_for_provider_confirmation',
  'completed',
  'cancelled',
];

/// CRM bookings (owner/crm) — mirrors `provider-portal/crm-bookings.php`.
/// Also used for the "Requests" nav item (same screen, [initialStatus]
/// pre-set to 'pending') since both read from the same endpoint.
class PortalCrmBookingsScreen extends ConsumerStatefulWidget {
  const PortalCrmBookingsScreen({super.key, this.initialStatus, this.title = 'Bookings'});

  final String? initialStatus;
  final String title;

  @override
  ConsumerState<PortalCrmBookingsScreen> createState() => _PortalCrmBookingsScreenState();
}

class _PortalCrmBookingsScreenState extends ConsumerState<PortalCrmBookingsScreen> {
  late Future<Map<String, dynamic>> _future;
  late String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus;
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getCrmBookings(status: _statusFilter);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  void _setFilter(String? status) {
    setState(() => _statusFilter = status);
    _refresh();
  }

  Future<void> _openDetail(int id) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _BookingDetailSheet(id: id),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            final String msg = snapshot.error.toString().replaceFirst('Exception: ', '');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(msg, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (isProError(msg))
                      ElevatedButton(
                        onPressed: () => context.push('/portal/subscription'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                        child: const Text('Upgrade to Pro'),
                      )
                    else
                      OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final List<dynamic> bookings = body['data'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: const Text('All'), selected: _statusFilter == null, onSelected: (_) => _setFilter(null)),
                    ChoiceChip(label: const Text('Pending'), selected: _statusFilter == 'pending', onSelected: (_) => _setFilter('pending')),
                    ChoiceChip(label: const Text('Accepted'), selected: _statusFilter == 'accepted', onSelected: (_) => _setFilter('accepted')),
                    ChoiceChip(label: const Text('Starting'), selected: _statusFilter == 'starting', onSelected: (_) => _setFilter('starting')),
                    ChoiceChip(label: const Text('On Going'), selected: _statusFilter == 'on_going', onSelected: (_) => _setFilter('on_going')),
                    ChoiceChip(label: const Text('Completed'), selected: _statusFilter == 'completed', onSelected: (_) => _setFilter('completed')),
                  ],
                ),
                const SizedBox(height: 16),
                if (bookings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No bookings found.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...bookings.map((dynamic b) => _BookingRow(row: b as Map<String, dynamic>, onTap: () => _openDetail((b['id'] as num).toInt()))),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = row['status']?.toString() ?? 'pending';
    final Color color = _kBookingStatusColors[status] ?? AppTheme.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: ListTile(
        onTap: onTap,
        title: Text(row['seeker_name']?.toString() ?? 'Customer', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text(
          '${row['service_name'] ?? 'Service'} · ${_fmtDate(row['preferred_date'])} ${row['preferred_time'] ?? ''}',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ),
      ),
    );
  }
}

class _BookingDetailSheet extends ConsumerStatefulWidget {
  const _BookingDetailSheet({required this.id});
  final int id;

  @override
  ConsumerState<_BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends ConsumerState<_BookingDetailSheet> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;
  String? _error;
  String? _pendingStatus;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getCrmBookingDetail(widget.id);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _advance() async {
    if (_pendingStatus == null) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(portalApiProvider).updateCrmBookingStatus(id: widget.id, status: _pendingStatus!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openScanQr() async {
    final bool? started = await context.push<bool>('/portal/crm/scan-qr');
    if (started == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (BuildContext ctx, ScrollController scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }
              if (snapshot.hasError) {
                return Center(child: Text(snapshot.error.toString().replaceFirst('Exception: ', '')));
              }

              final Map<String, dynamic> data = snapshot.data ?? <String, dynamic>{};
              final Map<String, dynamic> seeker = (data['seeker'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final Map<String, dynamic> listing = (data['listing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final Map<String, dynamic> payment = (data['payment'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final Map<String, dynamic> controlNumbers = (data['control_numbers'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final String status = data['status']?.toString() ?? 'pending';

              return ListView(
                controller: scrollController,
                children: <Widget>[
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(seeker['name']?.toString() ?? 'Customer', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                  Text(listing['title']?.toString() ?? 'Service', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  const SizedBox(height: 16),
                  if (_error != null) ...<Widget>[
                    ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                    if (isProError(_error!)) ...<Widget>[
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
                    ],
                    const SizedBox(height: 14),
                  ],
                  _DetailRow(label: 'Status', value: status.replaceAll('_', ' ')),
                  _DetailRow(label: 'Date', value: '${data['preferred_date'] ?? '—'} ${data['preferred_time'] ?? ''}'),
                  _DetailRow(label: 'Address', value: data['address']?.toString() ?? '—'),
                  const SizedBox(height: 10),
                  const Text('CONTACT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                  _DetailRow(label: 'Phone', value: seeker['phone']?.toString() ?? '—'),
                  _DetailRow(label: 'Email', value: seeker['email']?.toString() ?? '—'),
                  const SizedBox(height: 10),
                  const Text('PAYMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                  _DetailRow(label: 'Method', value: payment['method']?.toString() ?? '—'),
                  _DetailRow(label: 'Total', value: payment['total_amount'] != null ? peso.format(num.tryParse(payment['total_amount'].toString()) ?? 0) : '—'),
                  if (controlNumbers['provider'] != null) ...<Widget>[
                    const SizedBox(height: 10),
                    const Text('YOUR CODE (share with the seeker)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                    Text(controlNumbers['provider'].toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navy, letterSpacing: 2)),
                  ],
                  const SizedBox(height: 20),
                  if (status == 'starting') ...<Widget>[
                    LoadingButton(label: 'Scan Seeker QR', isLoading: _busy, onPressed: _openScanQr),
                    const SizedBox(height: 12),
                  ] else if (status != 'completed' && status != 'cancelled') ...<Widget>[
                    const Text('Advance Status', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _pendingStatus,
                      hint: const Text('Select new status'),
                      items: _kAdvanceableStatuses
                          .map((String s) => DropdownMenuItem<String>(value: s, child: Text(s.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (String? v) => setState(() => _pendingStatus = v),
                    ),
                    const SizedBox(height: 12),
                    LoadingButton(label: 'Update Status', isLoading: _busy, onPressed: _advance),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy))),
        ],
      ),
    );
  }
}

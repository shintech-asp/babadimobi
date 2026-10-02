import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Field-technician self-service: bookings assigned to this employee —
/// mirrors `provider-portal/my-services.php`'s confirmed/tentative
/// distinction (a booking is "Tentative" when only matched via the
/// service's default handler, not yet locked in via Prepare Booking).
/// Read-only — processing actions (Enter Code, Scan QR, Submit Inspection
/// Report) aren't part of this phase; a tech still uses the web portal for
/// those until a later pass adds them here too.
class PortalMyBookingsScreen extends ConsumerStatefulWidget {
  const PortalMyBookingsScreen({super.key});

  @override
  ConsumerState<PortalMyBookingsScreen> createState() => _PortalMyBookingsScreenState();
}

class _PortalMyBookingsScreenState extends ConsumerState<PortalMyBookingsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getMyBookings();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Assigned Services')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(snapshot.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final List<dynamic> bookings = body['data'] as List<dynamic>? ?? <dynamic>[];

          if (bookings.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const Center(child: Text('No assigned services yet.', style: TextStyle(color: AppTheme.textMuted))),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: bookings.map((dynamic b) => _BookingCard(row: b as Map<String, dynamic>)).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.row});
  final Map<String, dynamic> row;

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'starting':
        return 'Starting';
      case 'on_going':
      case 'ongoing':
        return 'Ongoing';
      case 'waiting_for_remaining_payment':
        return 'Awaiting Payment';
      case 'waiting_for_provider_confirmation':
      case 'waiting_for_seeker_confirmation':
        return 'Awaiting Confirmation';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'awaiting_agreement':
        return 'Awaiting Agreement';
      case 'revising':
        return 'Revising';
      default:
        return status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppTheme.primary;
      case 'cancelled':
        return Colors.red;
      case 'preparing':
      case 'starting':
        return AppTheme.indigo;
      default:
        return Colors.orange[800]!;
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _fmtTime(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm:ss').parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = row['status']?.toString() ?? '';
    final bool isTentative = row['assigned_employee_id'] == null;
    final String date = row['working_date'] ?? row['inspection_date'] ?? row['preferred_date'];
    final Color statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isTentative ? Colors.orange.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  row['service_name']?.toString() ?? 'Service',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.navy),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(_statusLabel(status), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor)),
                  ),
                  if (isTentative) ...<Widget>[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Tentative', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.person_outline_rounded, size: 15, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text(row['full_name']?.toString() ?? '—', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text('${_fmtDate(date)} ${_fmtTime(row['preferred_time'])}', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ],
          ),
          if ((row['address']?.toString() ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(row['address'].toString(), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted))),
              ],
            ),
          ],
          if ((row['operations_notes']?.toString() ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.sticky_note_2_outlined, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(row['operations_notes'].toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

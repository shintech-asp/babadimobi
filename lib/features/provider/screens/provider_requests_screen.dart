import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/utils/booking_status_utils.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';

/// Provider "Service Requests" screen — fetches all requests once (the PHP
/// endpoint only supports an exact status match, unlike the seeker side's
/// `status=active` grouping) and buckets them into tabs client-side.
class ProviderRequestsScreen extends ConsumerStatefulWidget {
  const ProviderRequestsScreen({super.key});

  @override
  ConsumerState<ProviderRequestsScreen> createState() =>
      _ProviderRequestsScreenState();
}

class _ProviderRequestsScreenState extends ConsumerState<ProviderRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<dynamic>> _future;

  static const List<String> _tabs = <String>['All', 'Pending', 'Active', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _future = _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final Map<String, dynamic> body = await ref.read(providerApiProvider).getRequests();
      final dynamic items = body['data'];
      return items is List ? items : <dynamic>[];
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Awaits the new fetch (not just assigns it) so [RefreshIndicator]'s own
  /// spinner stays up until the data has actually arrived, instead of
  /// dismissing the instant this function returns.
  Future<void> _refresh() async {
    final Future<List<dynamic>> next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  Future<void> _openRequest(int id) async {
    await context.push('/provider/requests/$id');
    if (!mounted) return;
    _refresh();
  }

  bool _dualVerified(Map<String, dynamic> r) {
    final String raw = r['dual_verified_at']?.toString().trim() ?? '';
    return raw.isNotEmpty && raw != '0000-00-00 00:00:00';
  }

  List<Map<String, dynamic>> _bucket(List<dynamic> all, String tabLabel) {
    final List<Map<String, dynamic>> rows =
        all.whereType<Map<String, dynamic>>().toList();
    if (tabLabel == 'All') return rows;

    return rows.where((Map<String, dynamic> r) {
      final String status = r['status']?.toString() ?? 'pending';
      final String normalized =
          normalizeBookingStatus(status, hasStarted: _dualVerified(r));
      switch (tabLabel) {
        case 'Pending':
          return normalized == 'pending';
        case 'Completed':
          return normalized == 'completed';
        case 'Cancelled':
          return normalized == 'cancelled';
        case 'Active':
          return normalized != 'pending' && normalized != 'completed' && normalized != 'cancelled';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Service Requests'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((String t) => Tab(text: t)).toList(),
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snap) {
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

          final List<dynamic> all = snap.data ?? <dynamic>[];

          return TabBarView(
            controller: _tabController,
            children: _tabs.map((String tab) {
              final List<Map<String, dynamic>> rows = _bucket(all, tab);
              if (rows.isEmpty) {
                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      SizedBox(
                        height: 400,
                        child: Center(
                          child: Text('No requests here.', style: TextStyle(color: AppTheme.textMuted)),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext ctx, int i) => _RequestCard(
                    request: rows[i],
                    hasStarted: _dualVerified(rows[i]),
                    onTap: _openRequest,
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.hasStarted, required this.onTap});

  final Map<String, dynamic> request;
  final bool hasStarted;
  final ValueChanged<int> onTap;

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dynamic rawId = request['id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final String status = request['status']?.toString() ?? 'pending';
    final String seekerName = <String?>[
      request['seeker_first']?.toString(),
      request['seeker_last']?.toString(),
    ].where((String? s) => s != null && s.isNotEmpty).join(' ');
    final String service = request['listing_title']?.toString() ??
        request['service_name']?.toString() ??
        'Service';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: id != null ? () => onTap(id) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          service,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (seekerName.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(seekerName, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  BookingStatusChip(status: status, hasStarted: hasStarted),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.calendar_today_outlined, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(request['preferred_date']),
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const Spacer(),
                  if (id != null)
                    TextButton.icon(
                      onPressed: () => onTap(id),
                      icon: const Icon(Icons.chevron_right, size: 16),
                      label: const Text('View'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

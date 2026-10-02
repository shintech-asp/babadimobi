import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';

/// Provider dashboard — stat cards, rating summary, and the 5 most recent
/// service requests. Shows a "pending approval" banner while
/// `providers.status != 'active'`, per CLAUDE.md's Phase 2 requirement.
class ProviderHomeScreen extends ConsumerStatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  ConsumerState<ProviderHomeScreen> createState() =>
      _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends ConsumerState<ProviderHomeScreen> {
  late Future<Map<String, dynamic>> _future;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    try {
      final int count = await ref.read(providerApiProvider).getNotificationCount();
      if (!mounted) return;
      setState(() => _unreadCount = count);
    } catch (_) {
      // A failed badge fetch shouldn't surface as an error on the dashboard.
    }
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      return await ref.read(providerApiProvider).getDashboard();
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    final String raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      return 'No internet connection. Pull down to retry.';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  /// Reassigns [_future] immediately (so [FutureBuilder] shows the spinner
  /// right away) but also awaits it, so a caller like [RefreshIndicator]
  /// keeps its own spinner up until the data has actually arrived — it stops
  /// as soon as `onRefresh` returns, so returning early left it dismissing
  /// itself before the fetch resolved, making a successful refresh look like
  /// nothing happened.
  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _fetch();
    setState(() {
      _future = next;
    });
    unawaited(_loadUnread());
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

  Future<void> _openNotifications() async {
    await context.push('/provider/notifications');
    if (!mounted) return;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: <Widget>[
          IconButton(
            icon: _unreadCount > 0
                ? Badge.count(
                    count: _unreadCount,
                    child: const Icon(Icons.notifications_none_rounded),
                  )
                : const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
            onPressed: _openNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: () => context.push('/provider/profile'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<Map<String, dynamic>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _refresh,
            );
          }

          final Map<String, dynamic> d = snap.data ?? <String, dynamic>{};
          final String providerStatus =
              (d['provider_status'] ?? 'active').toString();
          final String companyName =
              (d['company_name'] ?? 'Your business').toString();
          final List<dynamic> recent =
              d['recent_requests'] is List ? d['recent_requests'] as List : <dynamic>[];

          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                Text(
                  companyName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Here\'s how your business is doing.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
                if (providerStatus != 'active') ...<Widget>[
                  const SizedBox(height: 16),
                  _PendingApprovalBanner(status: providerStatus),
                ],
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: <Widget>[
                    _StatCard(
                      label: 'Pending Requests',
                      value: '${d['pending_requests'] ?? 0}',
                      icon: Icons.pending_actions_rounded,
                      color: Colors.orange,
                      onTap: () => context.push('/provider/requests'),
                    ),
                    _StatCard(
                      label: 'Active Bookings',
                      value: '${d['active_bookings'] ?? 0}',
                      icon: Icons.local_shipping_rounded,
                      color: AppTheme.indigo,
                      onTap: () => context.push('/provider/requests'),
                    ),
                    _StatCard(
                      label: 'Completed Jobs',
                      value: '${d['completed_jobs'] ?? 0}',
                      icon: Icons.task_alt_rounded,
                      color: AppTheme.primary,
                      onTap: () => context.push('/provider/requests'),
                    ),
                    _StatCard(
                      label: 'Active Listings',
                      value: '${d['active_listings'] ?? 0}',
                      icon: Icons.storefront_rounded,
                      color: Colors.teal,
                      onTap: () => context.push('/provider/listings'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RatingCard(
                  avgRating: d['avg_rating'] == null
                      ? null
                      : double.tryParse(d['avg_rating'].toString()),
                  reviewCount:
                      int.tryParse(d['review_count']?.toString() ?? '') ?? 0,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 12),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No requests yet.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  )
                else
                  ...recent.map((dynamic raw) {
                    if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                    return _RecentRequestTile(
                      request: raw,
                      onTap: _openRequest,
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _PendingApprovalBanner extends StatelessWidget {
  const _PendingApprovalBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final String message = status == 'suspended'
        ? 'Your provider account is suspended. Contact support for details.'
        : status == 'inactive'
            ? 'Your provider account is inactive. Contact support to reactivate it.'
            : 'Your provider account is pending admin approval. Your listings won\'t be visible to seekers until approved.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.avgRating, required this.reviewCount});

  final double? avgRating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.star_rounded, color: AppTheme.starColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  avgRating != null ? avgRating!.toStringAsFixed(1) : '—',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                Text(
                  '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRequestTile extends StatelessWidget {
  const _RecentRequestTile({required this.request, required this.onTap});

  final Map<String, dynamic> request;
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

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: id != null ? () => onTap(id) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request['service_name']?.toString() ?? 'Service',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(request['preferred_date']),
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              BookingStatusChip(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

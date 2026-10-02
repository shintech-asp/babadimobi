import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/admin/admin_api.dart';

/// Admin dashboard — platform-wide stat cards + recent bookings.
/// Accessible to all 4 admin roles (super_admin/admin/hr/finance); the
/// `active_subscriptions`/`monthly_revenue` cards only appear for
/// super_admin, matching what `admin/dashboard.php` actually returns.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      return await ref.read(adminApiProvider).getDashboard();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<Map<String, dynamic>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.navy));
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

          final Map<String, dynamic> d = snap.data ?? <String, dynamic>{};
          final bool isSuperAdmin = d.containsKey('active_subscriptions');
          final List<dynamic> recent = d['recent_bookings'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            color: AppTheme.navy,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: <Widget>[
                    _StatCard(
                      label: 'Total Users',
                      value: '${d['total_users'] ?? 0}',
                      icon: Icons.people_alt_rounded,
                      color: AppTheme.indigo,
                    ),
                    _StatCard(
                      label: 'Providers',
                      value: '${d['total_providers'] ?? 0}',
                      icon: Icons.storefront_rounded,
                      color: AppTheme.primary,
                      onTap: () => context.push('/admin/providers'),
                    ),
                    _StatCard(
                      label: 'Pending Approval',
                      value: '${d['pending_providers'] ?? 0}',
                      icon: Icons.hourglass_top_rounded,
                      color: Colors.orange,
                      onTap: () => context.push('/admin/providers', extra: <String, String>{'status': 'pending'}),
                    ),
                    _StatCard(
                      label: 'Total Bookings',
                      value: '${d['total_bookings'] ?? 0}',
                      icon: Icons.receipt_long_rounded,
                      color: Colors.teal,
                    ),
                    _StatCard(
                      label: 'Pending Bookings',
                      value: '${d['pending_bookings'] ?? 0}',
                      icon: Icons.pending_actions_rounded,
                      color: Colors.deepOrange,
                    ),
                    _StatCard(
                      label: 'Completed Bookings',
                      value: '${d['completed_bookings'] ?? 0}',
                      icon: Icons.task_alt_rounded,
                      color: Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RevenueCard(
                  label: 'Total Revenue',
                  amount: double.tryParse(d['total_revenue']?.toString() ?? '') ?? 0,
                ),
                if (isSuperAdmin) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _RevenueCard(
                          label: 'This Month',
                          amount: double.tryParse(d['monthly_revenue']?.toString() ?? '') ?? 0,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: 'Active Subscriptions',
                          value: '${d['active_subscriptions'] ?? 0}',
                          icon: Icons.workspace_premium_rounded,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Recent Bookings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navy),
                ),
                const SizedBox(height: 12),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No bookings yet.', style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                else
                  ...recent.map((dynamic raw) {
                    if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                    return _RecentBookingTile(booking: raw);
                  }),
              ],
            ),
          );
        },
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
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

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
              // Fixed gap, not Spacer() — this card is reused directly inside
              // a plain Row (the super_admin-only "Active Subscriptions" tile
              // below) which gives it no bounded height the way the GridView
              // cells above do; Spacer() there throws "RenderFlex children
              // have non-zero flex but incoming height constraints are
              // unbounded", which was the actual cause of the whole
              // dashboard rendering blank specifically for super_admin (the
              // only role that ever reaches that code path).
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.navy),
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

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.label, required this.amount, this.compact = false});
  final String label;
  final double amount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text(
            NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0).format(amount),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 18 : 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentBookingTile extends StatelessWidget {
  const _RecentBookingTile({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final String seeker = <String?>[
      booking['seeker_first_name']?.toString(),
      booking['seeker_last_name']?.toString(),
    ].where((String? s) => s != null && s.isNotEmpty).join(' ');
    final double amount = double.tryParse(booking['total_amount']?.toString() ?? '') ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    booking['service_name']?.toString() ?? 'Service',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (seeker.isNotEmpty) seeker,
                      if (booking['company_name'] != null) booking['company_name'].toString(),
                    ].join(' → '),
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              '₱${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

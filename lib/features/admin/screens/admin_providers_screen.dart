import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/admin/admin_api.dart';
import 'package:pestify_flutter/features/admin/screens/not_authorized_screen.dart';

const List<String> _kStatusTabs = <String>['all', 'pending', 'approved', 'rejected'];

/// Providers list — status filter tabs + search, matching
/// `admin/providers/index.php`'s filter/search support exactly.
///
/// Optional GoRouter extra: `{'status': 'pending'}` to arrive pre-filtered
/// (used by the dashboard's "Pending Approval" stat card).
class AdminProvidersScreen extends ConsumerStatefulWidget {
  const AdminProvidersScreen({super.key, this.initialStatus});

  final String? initialStatus;

  @override
  ConsumerState<AdminProvidersScreen> createState() => _AdminProvidersScreenState();
}

class _AdminProvidersScreenState extends ConsumerState<AdminProvidersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  late String _status;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus != null && _kStatusTabs.contains(widget.initialStatus)
        ? widget.initialStatus!
        : 'all';
    _future = _fetch();
  }

  /// Was previously a [TabBar]/[TabController] — switched to a plain
  /// [SegmentedButton] (same pattern as the Provider app's Active/Inactive
  /// listings toggle) after the TabBar version never reliably refetched on
  /// tab switch: `TabController.addListener` + `indexIsChanging` (the
  /// textbook pattern) silently failed to fire for a bare TabBar with no
  /// TabBarView behind it, and a follow-up fix using `TabBar.onTap` fired
  /// **twice** per tap for reasons never fully root-caused (visible as
  /// duplicate identical requests in the access log) — a plain
  /// `onSelectionChanged` callback has no controller, no animation timing,
  /// and no duplicate-firing surface at all to get wrong.
  void _onStatusChanged(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _future = _fetch();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final Map<String, dynamic> body = await ref.read(adminApiProvider).getProviders(
            status: _status,
            search: _search.isEmpty ? null : _search,
          );
      final dynamic items = body['data'];
      return items is List ? items : <dynamic>[];
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final String? role = ref.watch(authProvider).role;
    if (role != null && !<String>['super_admin', 'admin'].contains(role)) {
      return const NotAuthorizedScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Providers')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: _kStatusTabs
                    .map((String s) => ButtonSegment<String>(
                          value: s,
                          label: Text(s[0].toUpperCase() + s.substring(1)),
                        ))
                    .toList(),
                selected: <String>{_status},
                onSelectionChanged: (Set<String> sel) => _onStatusChanged(sel.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search company, owner name, or email',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onSubmitted: (String v) {
                setState(() {
                  _search = v.trim();
                  _future = _fetch();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snap) {
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

                final List<dynamic> providers = snap.data ?? <dynamic>[];
                if (providers.isEmpty) {
                  return RefreshIndicator(
                    color: AppTheme.navy,
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        SizedBox(
                          height: 400,
                          child: Center(
                            child: Text('No providers found.', style: TextStyle(color: AppTheme.textMuted)),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppTheme.navy,
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext ctx, int i) {
                      final dynamic raw = providers[i];
                      if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                      return _ProviderTile(
                        provider: raw,
                        onTap: () async {
                          final int? id = int.tryParse(raw['id']?.toString() ?? '');
                          if (id == null) return;
                          await context.push('/admin/providers/$id');
                          if (!mounted) return;
                          _refresh();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.onTap});
  final Map<String, dynamic> provider;
  final VoidCallback onTap;

  static const Map<String, Color> _statusColors = <String, Color>{
    'approved': AppTheme.primary,
    'pending': Colors.orange,
    'rejected': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> owner = (provider['owner'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String ownerName = <String?>[
      owner['first_name']?.toString(),
      owner['last_name']?.toString(),
    ].where((String? s) => s != null && s.isNotEmpty).join(' ');
    final String verification = provider['verification_status']?.toString() ?? 'pending';
    final Color statusColor = _statusColors[verification] ?? AppTheme.textMuted;
    String createdLabel = '';
    try {
      createdLabel = DateFormat('MMM d, yyyy').format(DateTime.parse(provider['created_at'].toString()));
    } catch (_) {}

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      provider['company_name']?.toString() ?? 'Provider',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (ownerName.isNotEmpty) ownerName,
                        if (provider['city'] != null) provider['city'].toString(),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(createdLabel, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        const SizedBox(width: 12),
                        Icon(Icons.receipt_long_outlined, size: 12, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${provider['booking_count'] ?? 0} bookings',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  verification[0].toUpperCase() + verification.substring(1),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

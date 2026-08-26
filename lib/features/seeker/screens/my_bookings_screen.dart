import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/booking_status_chip.dart';

/// My Bookings Screen
///
/// Three tabs: Active, Completed, Cancelled. Each tab fetches its own
/// list via [SeekerApi.getBookings] with a status filter group, and
/// supports pull-to-refresh. Tapping a card navigates to BookingDetailScreen.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<_TabConfig> _tabs = <_TabConfig>[
    _TabConfig(label: 'Active', statusGroup: 'active'),
    _TabConfig(label: 'Completed', statusGroup: 'completed'),
    _TabConfig(label: 'Cancelled', statusGroup: 'cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('My Bookings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs
              .map((t) => Tab(text: t.label))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map((t) => _BookingTabView(statusGroup: t.statusGroup))
            .toList(),
      ),
    );
  }
}

// ── Tab view ──────────────────────────────────────────────────────────────────

class _BookingTabView extends ConsumerStatefulWidget {
  const _BookingTabView({required this.statusGroup});

  final String statusGroup;

  @override
  ConsumerState<_BookingTabView> createState() => _BookingTabViewState();
}

class _BookingTabViewState extends ConsumerState<_BookingTabView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<dynamic>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetchBookings();
  }

  Future<List<dynamic>> _fetchBookings() async {
    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final Map<String, dynamic> result =
          await api.getBookings(status: widget.statusGroup);
      final dynamic items = result['data'];
      if (items is List<dynamic>) return items;
      return <dynamic>[];
    } catch (e) {
      // Re-throw a friendly message so _ErrorState shows something readable.
      throw Exception(_friendlyFetchError(e));
    }
  }

  String _friendlyFetchError(Object e) {
    final String raw = e.toString();
    if (raw.contains('SocketException') ||
        raw.contains('HandshakeException') ||
        raw.contains('Connection refused')) {
      return 'No internet connection. Pull down to retry.';
    }
    if (raw.contains('TimeoutException')) {
      return 'Request timed out. Pull down to retry.';
    }
    return 'Could not load bookings. Pull down to retry.';
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetchBookings());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2.5,
            ),
          );
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: _extractError(snapshot.error),
            onRetry: _refresh,
          );
        }

        final List<dynamic> bookings = snapshot.data ?? <dynamic>[];

        if (bookings.isEmpty) {
          return _EmptyState(statusGroup: widget.statusGroup, onRefresh: _refresh);
        }

        return RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext ctx, int index) {
              final dynamic raw = bookings[index];
              if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
              return _BookingCard(booking: raw);
            },
          ),
        );
      },
    );
  }

  String _extractError(Object? err) {
    if (err == null) return 'An error occurred.';
    final String raw = err.toString();
    // Strip the 'Exception: ' prefix added by our re-throw.
    if (raw.startsWith('Exception: ')) return raw.replaceFirst('Exception: ', '');
    if (raw.contains('StateError')) return raw.replaceFirst('Bad state: ', '');
    return 'Could not load bookings. Pull down to retry.';
  }
}

// ── Booking card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Map<String, dynamic> booking;

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final DateTime dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final String serviceName =
        booking['service_name']?.toString() ?? 'Service';
    final String providerName =
        booking['provider_name']?.toString() ?? 'Provider';
    final String date = _formatDate(booking['preferred_date']?.toString());
    final String status = booking['status']?.toString() ?? 'pending';
    final dynamic rawId = booking['id'] ?? booking['avail_id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: id != null
            ? () => context.push('/seeker/booking/$id')
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── Header row ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.pest_control_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          serviceName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          providerName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  BookingStatusChip(status: status),
                ],
              ),
              const SizedBox(height: 12),

              // ── Footer row ──────────────────────────────────────────────────
              Row(
                children: <Widget>[
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  if (id != null)
                    TextButton.icon(
                      onPressed: () => context.push('/seeker/booking/$id'),
                      icon: const Icon(Icons.chevron_right, size: 16),
                      label: const Text('View'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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

// ── Empty / error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.statusGroup,
    required this.onRefresh,
  });

  final String statusGroup;
  final VoidCallback onRefresh;

  String get _message => switch (statusGroup) {
        'active' => 'No active bookings.\nBook a service to get started.',
        'completed' => 'No completed bookings yet.',
        'cancelled' => 'No cancelled bookings.',
        _ => 'No bookings found.',
      };

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 420,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 52,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
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
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _TabConfig {
  const _TabConfig({required this.label, required this.statusGroup});

  final String label;
  final String statusGroup;
}

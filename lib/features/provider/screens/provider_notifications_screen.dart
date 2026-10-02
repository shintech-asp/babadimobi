import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';

/// Provider notifications — booking status changes and incoming messages,
/// merged and sorted server-side by `notifications/index.php`'s provider branch.
///
/// Opening the screen marks everything read, matching the seeker behaviour.
class ProviderNotificationsScreen extends ConsumerStatefulWidget {
  const ProviderNotificationsScreen({super.key});

  @override
  ConsumerState<ProviderNotificationsScreen> createState() =>
      _ProviderNotificationsScreenState();
}

class _ProviderNotificationsScreenState
    extends ConsumerState<ProviderNotificationsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final ProviderApi api = ref.read(providerApiProvider);
      final Map<String, dynamic> result = await api.getNotifications();
      // Fire-and-forget: a failed mark-read shouldn't blank out the list the
      // user came here to read.
      api.markNotificationsRead().catchError((Object _) {});
      return result['items'] as List<dynamic>? ?? <dynamic>[];
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Awaits the new fetch (not just assigns it) so [RefreshIndicator]'s own
  /// spinner stays up until the data has actually arrived, instead of
  /// dismissing the instant `onRefresh` returns.
  Future<void> _refresh() async {
    final Future<List<dynamic>> next = _fetch();
    // Block body, not `() => _future = next` — see provider_request_detail_
    // screen.dart's identical fix for why the arrow form silently never
    // rebuilds the widget.
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  void _open(Map<String, dynamic> n) {
    final String type = n['type']?.toString() ?? '';
    final int? linkId = int.tryParse(n['link_id']?.toString() ?? '');
    if (linkId == null || linkId <= 0) return;

    if (type == 'booking') {
      context.push('/provider/requests/$linkId');
    } else if (type == 'message') {
      // link_id is now the booking (request_id), not the sender's user id —
      // messages/index.php's link_id changed meaning to match the
      // transaction-scoped chat model (one thread per booking).
      final String title = n['title']?.toString() ?? '';
      // 'New Message from Juan Dela Cruz' → 'Juan Dela Cruz'
      final String name = title.startsWith('New Message from ')
          ? title.substring('New Message from '.length)
          : 'Client';
      context.push(
        '/provider/message-thread',
        extra: <String, dynamic>{'bookingId': linkId, 'seekerName': name},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      snap.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final List<Map<String, dynamic>> items =
              (snap.data ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList();

          if (items.isEmpty) {
            return RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  SizedBox(
                    height: 380,
                    child: Center(
                      child: Text(
                        'Nothing to catch up on.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext ctx, int i) =>
                  _NotificationCard(n: items[i], onTap: () => _open(items[i])),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.n, required this.onTap});

  final Map<String, dynamic> n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isMessage = n['type']?.toString() == 'message';
    final bool isRead = n['is_read'] == true;
    final Color accent = isMessage ? AppTheme.indigo : AppTheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isRead ? null : accent.withValues(alpha: 0.04),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isMessage
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.event_note_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            n['title']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w700,
                              color: AppTheme.navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n['body']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relative(n['created_at']),
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(dynamic raw) {
    if (raw == null) return '';
    try {
      final DateTime dt = DateTime.parse(raw.toString());
      final Duration d = DateTime.now().difference(dt);
      if (d.inMinutes < 1) return 'Just now';
      if (d.inMinutes < 60) return '${d.inMinutes}m ago';
      if (d.inHours < 24) return '${d.inHours}h ago';
      if (d.inDays < 7) return '${d.inDays}d ago';
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }
}

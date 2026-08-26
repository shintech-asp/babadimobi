import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Seeker notification centre.
///
/// Fetches all notifications on load, marks them read on pull-to-refresh,
/// and shows a dot badge for unread items.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<dynamic> _notifications = <dynamic>[];
  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool markRead = false}) async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final SeekerApi api = ref.read(seekerApiProvider);

      if (markRead) {
        // Fire-and-forget: ignore errors from mark-read — don't crash the screen.
        try {
          await api.markNotificationsRead();
        } catch (_) {}
        if (!mounted) return;
      }

      // API returns { items: [...], unread_count: N }
      final Map<String, dynamic> response = await api.getNotifications();
      if (!mounted) return;
      final List<dynamic> items =
          response['items'] as List<dynamic>? ?? <dynamic>[];
      setState(() => _notifications = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Could not load notifications.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() => _load(markRead: true);

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF2D6A4F);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMsg != null
                ? _ErrorView(
                    message: _errorMsg!,
                    onRetry: _load,
                  )
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: primary,
                    child: _notifications.isEmpty
                        ? const _EmptyView()
                        : ListView.separated(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 2),
                            itemBuilder: (context, index) {
                              final dynamic item =
                                  _notifications[index];
                              return _NotifTile(item: item);
                            },
                          ),
                  ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.item});

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    final dynamic rawRead = item['is_read'];
    final bool isRead = rawRead == true || rawRead == 1 || rawRead == '1';
    final String message =
        (item['body'] as String?) ??
        (item['message'] as String?) ??
        'Notification';
    final String? createdAt = item['created_at'] as String?;
    final String timeAgo = _timeAgo(createdAt);
    final String? type = item['type'] as String?;

    const Color primary = Color(0xFF2D6A4F);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isRead ? Colors.white : const Color(0xFF2D6A4F).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRead
              ? cs.outlineVariant.withValues(alpha: 0.3)
              : primary.withValues(alpha: 0.15),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconForType(type),
                color: primary,
                size: 22,
              ),
            ),
            if (!isRead)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF52B788),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            timeAgo,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String? type) {
    return switch (type) {
      'booking' => Icons.calendar_today_rounded,
      'message' => Icons.chat_bubble_outline_rounded,
      'payment' => Icons.payment_rounded,
      'status' => Icons.update_rounded,
      _ => Icons.notifications_outlined,
    };
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final DateTime dt = DateTime.parse(dateStr).toLocal();
      final Duration diff = DateTime.now().difference(dt);

      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 64,
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.25),
              ),
              const SizedBox(height: 16),
              const Text(
                'No notifications yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to refresh.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}


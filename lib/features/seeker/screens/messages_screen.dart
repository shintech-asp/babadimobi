import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Inbox — list of conversation threads between the seeker and providers.
///
/// Layout inspired by Telegram 2024: custom header with large title + inline
/// search bar, gradient-colored initials avatars (56px), no list separators.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<dynamic> _threads = <dynamic>[];
  List<dynamic> _filtered = <dynamic>[];
  bool _loading = true;
  String? _errorMsg;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final String q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _threads
          : _threads.where((dynamic t) {
              final String firstName = (t['first_name'] as String?) ?? '';
              final String lastName = (t['last_name'] as String?) ?? '';
              final String name =
                  (t['provider_name'] as String?) ??
                      (t['business_name'] as String?) ??
                      '$firstName $lastName'.trim();
              final String lastMsg =
                  (t['last_msg'] as String?) ??
                      (t['last_message'] as String?) ??
                      '';
              return name.toLowerCase().contains(q) ||
                  lastMsg.toLowerCase().contains(q);
            }).toList();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final List<dynamic> threads =
          await ref.read(seekerApiProvider).getMessages();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _filtered = threads;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Could not load messages.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: <Widget>[
          // ── Custom header ───────────────────────────────────────────────
          _Header(
            topPad: topPad,
            searchCtrl: _searchCtrl,
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg != null
                    ? _ErrorView(message: _errorMsg!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: _filtered.isEmpty
                            ? _EmptyView(
                                isSearch: _searchCtrl.text.isNotEmpty)
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                itemCount: _filtered.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final dynamic thread = _filtered[index];
                                  return _ThreadTile(
                                    thread: thread,
                                    avatarIndex: index,
                                    onTap: () => _openThread(thread),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  void _openThread(dynamic thread) {
    final int providerId =
        (thread['provider_id'] as int?) ??
            (thread['user_id'] as int?) ??
            (thread['id'] as int? ?? 0);
    final String firstName = (thread['first_name'] as String?) ?? '';
    final String lastName = (thread['last_name'] as String?) ?? '';
    final String providerName =
        (thread['provider_name'] as String?) ??
            (thread['business_name'] as String?) ??
            (firstName.isNotEmpty || lastName.isNotEmpty
                ? '$firstName $lastName'.trim()
                : 'Provider');
    context.push(
      '/seeker/message-thread',
      extra: <String, dynamic>{
        'providerId': providerId,
        'providerName': providerName,
      },
    );
  }
}

// ── Custom Header ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.topPad,
    required this.searchCtrl,
  });

  final double topPad;
  final TextEditingController searchCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, topPad + 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Inline search bar ──────────────────────────────────────────
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: searchCtrl,
              style: const TextStyle(fontSize: 14, color: AppTheme.navy),
              decoration: InputDecoration(
                hintText: 'Search conversations…',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textMuted.withValues(alpha: 0.7),
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: Icon(Icons.search_rounded,
                      size: 18, color: AppTheme.textMuted),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Thread Tile ───────────────────────────────────────────────────────────────

/// Avatar gradient palette — each conversation thread gets a consistent color
/// based on its position index mod the palette length.
const List<List<Color>> _kAvatarGradients = <List<Color>>[
  <Color>[Color(0xFF2E8B57), Color(0xFF48BB78)],   // green (brand)
  <Color>[Color(0xFF4C51BF), Color(0xFF7C3AED)],   // indigo→violet
  <Color>[Color(0xFF0EA5E9), Color(0xFF38BDF8)],   // sky blue
  <Color>[Color(0xFFEF4444), Color(0xFFF97316)],   // red→orange
  <Color>[Color(0xFFF59E0B), Color(0xFFFBBF24)],   // amber
  <Color>[Color(0xFF10B981), Color(0xFF34D399)],   // emerald
  <Color>[Color(0xFFEC4899), Color(0xFFF472B6)],   // pink
  <Color>[Color(0xFF1A1F3A), Color(0xFF374151)],   // navy
];

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.avatarIndex,
    required this.onTap,
  });

  final dynamic thread;
  final int avatarIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String firstName = (thread['first_name'] as String?) ?? '';
    final String lastName = (thread['last_name'] as String?) ?? '';
    final String name =
        (thread['provider_name'] as String?) ??
            (thread['business_name'] as String?) ??
            (firstName.isNotEmpty || lastName.isNotEmpty
                ? '$firstName $lastName'.trim()
                : 'Provider');
    final String lastMsg =
        (thread['last_msg'] as String?) ??
            (thread['last_message'] as String?) ??
            '';
    final String? avatarUrl =
        (thread['profile_image'] as String?) ?? (thread['avatar'] as String?);
    final String? createdAt =
        (thread['last_time'] as String?) ?? (thread['created_at'] as String?);
    final dynamic rawUnread = thread['unread'] ?? thread['unread_count'];
    final int unreadCount = rawUnread is int
        ? rawUnread
        : int.tryParse(rawUnread?.toString() ?? '') ?? 0;
    final bool hasUnread = unreadCount > 0;

    final List<Color> gradient =
        _kAvatarGradients[avatarIndex % _kAvatarGradients.length];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // ── Avatar ──────────────────────────────────────────────────
            _Avatar(
              name: name,
              avatarUrl: avatarUrl,
              gradient: gradient,
              size: 56,
            ),

            const SizedBox(width: 14),

            // ── Content ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: AppTheme.navy,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: hasUnread
                              ? AppTheme.primary
                              : AppTheme.textMuted,
                          fontWeight: hasUnread
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          lastMsg.isEmpty ? 'Start a conversation' : lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread
                                ? AppTheme.navy
                                : AppTheme.textMuted,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unreadCount > 0) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadCount > 99
                                ? '99+'
                                : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final DateTime dt = DateTime.parse(dateStr).toLocal();
      final Duration diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return DateFormat('h:mm a').format(dt);
      if (diff.inDays < 7) return DateFormat('EEE').format(dt);
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return '';
    }
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.gradient,
    required this.size,
  });

  final String name;
  final String? avatarUrl;
  final List<Color> gradient;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (BuildContext context, ImageProvider imageProvider) =>
            CircleAvatar(
          radius: size / 2,
          backgroundImage: imageProvider,
        ),
        placeholder: (BuildContext context, String url) =>
            _GradientInitials(name: name, gradient: gradient, size: size),
        errorWidget: (BuildContext context, String url, Object error) =>
            _GradientInitials(name: name, gradient: gradient, size: size),
      );
    }
    return _GradientInitials(name: name, gradient: gradient, size: size);
  }
}

class _GradientInitials extends StatelessWidget {
  const _GradientInitials({
    required this.name,
    required this.gradient,
    required this.size,
  });

  final String name;
  final List<Color> gradient;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String initials = name.isNotEmpty
        ? name
              .trim()
              .split(RegExp(r'\s+'))
              .where((String s) => s.isNotEmpty)
              .map((String s) => s[0])
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.33,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Empty / Error views ───────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.isSearch});
  final bool isSearch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 36,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isSearch ? 'No conversations found' : 'No messages yet',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSearch
                    ? 'Try a different search term.'
                    : 'Start a conversation with a provider.',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
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
          children: <Widget>[
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Chat bubble thread between the seeker and a specific provider.
///
/// Expected GoRouter extra:
/// ```dart
/// context.push(
///   '/seeker/message-thread',
///   extra: {'providerId': 5, 'providerName': 'Green Shield Pest Control'},
/// );
/// ```
class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  final int providerId;
  final String providerName;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState
    extends ConsumerState<MessageThreadScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _messages = <dynamic>[];
  bool _initialLoading = true;
  bool _sending = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadThread().then((_) {
      if (!mounted) return;
      // Start polling after the first load completes.
      _pollTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => _loadThread(),
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    try {
      final List<dynamic> msgs = await ref
          .read(seekerApiProvider)
          .getMessageThread(widget.providerId);

      if (!mounted) return;

      final bool wasAtBottom = _isAtBottom();
      setState(() {
        _messages = msgs;
        _initialLoading = false;
      });

      // Scroll to bottom if user was at the bottom or it is the first load.
      if (wasAtBottom || _initialLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
    }
  }

  bool _isAtBottom() {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.offset >=
        _scrollCtrl.position.maxScrollExtent - 80;
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final String text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    _inputCtrl.clear();

    try {
      await ref.read(seekerApiProvider).sendMessage(
            receiverId: widget.providerId,
            message: text,
          );

      if (!mounted) return;
      await _loadThread();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (!mounted) return;
      // Restore the text on failure so the user can retry.
      _inputCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authProvider);
    final int? myUserId = auth.userId;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.providerName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              'Provider',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Message list ───────────────────────────────────────────────
            Expanded(
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const _EmptyThread()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final dynamic msg = _messages[index];
                            final dynamic rawSender = msg['sender_id'];
                            final int senderId = rawSender is int
                                ? rawSender
                                : int.tryParse(
                                        rawSender?.toString() ?? '') ??
                                    -1;
                            final bool isMe = senderId == myUserId;
                            return _ChatBubble(
                              message: msg,
                              isMe: isMe,
                              showDate: _shouldShowDate(index),
                            );
                          },
                        ),
            ),

            // ── Input bar ──────────────────────────────────────────────────
            _InputBar(
              controller: _inputCtrl,
              focusNode: _focusNode,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  /// Returns true if this message's date differs from the previous one,
  /// or if it is the first message — so a date separator is rendered.
  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final String? currDate =
        _messages[index]['created_at'] as String?;
    final String? prevDate =
        _messages[index - 1]['created_at'] as String?;
    if (currDate == null || prevDate == null) return false;
    try {
      final DateTime curr = DateTime.parse(currDate).toLocal();
      final DateTime prev = DateTime.parse(prevDate).toLocal();
      return curr.day != prev.day ||
          curr.month != prev.month ||
          curr.year != prev.year;
    } catch (_) {
      return false;
    }
  }
}

// ── Chat bubble ───────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.showDate,
  });

  final dynamic message;
  final bool isMe;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    const Color theirBubble = Colors.white;

    final String text = (message['message'] as String?) ?? '';
    final String? createdAt = message['created_at'] as String?;
    final String timeLabel = _timeLabel(createdAt);

    return Column(
      children: [
        if (showDate) _DateSeparator(dateStr: createdAt),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primary : theirBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: isMe ? Colors.white : AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.65)
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _timeLabel(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final DateTime dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({this.dateStr});

  final String? dateStr;

  @override
  Widget build(BuildContext context) {
    String label = '';
    if (dateStr != null) {
      try {
        final DateTime dt = DateTime.parse(dateStr!).toLocal();
        final DateTime now = DateTime.now();
        final Duration diff = now.difference(dt);
        if (diff.inDays == 0) {
          label = 'Today';
        } else if (diff.inDays == 1) {
          label = 'Yesterday';
        } else {
          label = DateFormat('MMMM d, y').format(dt);
        }
      } catch (_) {}
    }

    if (label.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: MaterialButton(
              onPressed: sending ? null : onSend,
              minWidth: 44,
              height: 44,
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
              color: AppTheme.primary,
              disabledColor: AppTheme.primary.withValues(alpha: 0.4),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_rounded,
              size: 56,
              color: AppTheme.primary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            const Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B4332),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send the first message below.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}


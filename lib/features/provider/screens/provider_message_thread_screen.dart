import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';

/// Transaction-scoped chat thread for one booking, provider side — direct
/// structural mirror of the seeker's `MessageThreadScreen`: the header
/// always shows the client + service + status, and the input is replaced
/// with a closed notice once the booking is completed/cancelled. No
/// payment banner here (that's a seeker-only concern).
///
/// Expected GoRouter extra:
/// ```dart
/// context.push(
///   '/provider/message-thread',
///   extra: {
///     'bookingId': 76,
///     'seekerName': 'Juan Dela Cruz',
///     'serviceName': 'Rat Exterminator',
///     'status': 'accepted',
///   },
/// );
/// ```
class ProviderMessageThreadScreen extends ConsumerStatefulWidget {
  const ProviderMessageThreadScreen({
    super.key,
    required this.bookingId,
    this.initialSeekerName = 'Client',
    this.initialServiceName = '',
    this.initialStatus = '',
  });

  final int bookingId;
  final String initialSeekerName;
  final String initialServiceName;
  final String initialStatus;

  @override
  ConsumerState<ProviderMessageThreadScreen> createState() =>
      _ProviderMessageThreadScreenState();
}

class _ProviderMessageThreadScreenState
    extends ConsumerState<ProviderMessageThreadScreen> with WidgetsBindingObserver {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _messages = <dynamic>[];
  Map<String, dynamic> _booking = <String, dynamic>{};
  bool _initialLoading = true;
  bool _sending = false;
  Timer? _pollTimer;
  bool _pollPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThread();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pollPaused) _poll();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pollPaused = state != AppLifecycleState.resumed;
  }

  // The MAX id across all loaded messages, not just the last one — ordering
  // is by created_at (1-second resolution), so two messages written in the
  // same second can come back id-descending, which would otherwise regress
  // the poll cursor and cause the higher-id message to be re-appended.
  int get _lastMessageId {
    int max = 0;
    for (final dynamic m in _messages) {
      final dynamic raw = m['id'];
      final int id = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
      if (id > max) max = id;
    }
    return max;
  }

  Future<void> _loadThread() async {
    try {
      final Map<String, dynamic> result =
          await ref.read(providerApiProvider).getBookingThread(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages = result['messages'] as List<dynamic>? ?? <dynamic>[];
        _booking = (result['booking'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        _initialLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _poll() async {
    if (_initialLoading) return;
    try {
      final Map<String, dynamic> result = await ref
          .read(providerApiProvider)
          .pollBookingMessages(bookingId: widget.bookingId, sinceId: _lastMessageId);
      if (!mounted) return;
      final List<dynamic> newMsgs = result['messages'] as List<dynamic>? ?? <dynamic>[];
      final String? newStatus = result['status'] as String?;
      final bool statusChanged = newStatus != null && newStatus != (_booking['status'] as String?);

      if (newMsgs.isEmpty && !statusChanged) return;

      if (statusChanged) {
        await _loadThread();
        return;
      }

      final bool wasAtBottom = _isAtBottom();
      final Set<dynamic> existingIds = _messages.map((dynamic m) => m['id']).toSet();
      final List<dynamic> deduped = newMsgs.where((dynamic m) => !existingIds.contains(m['id'])).toList();
      setState(() {
        _messages = <dynamic>[..._messages, ...deduped];
      });
      if (wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (_) {
      // Silent — a failed poll tick just retries on the next one.
    }
  }

  bool _isAtBottom() {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 80;
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
      await ref.read(providerApiProvider).sendBookingMessage(
            bookingId: widget.bookingId,
            message: text,
          );
      if (!mounted) return;
      await _loadThread();
    } catch (e) {
      if (!mounted) return;
      _inputCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _extractError(Object e) {
    // ProviderApi's error helpers always throw a plain Exception (never a
    // raw StateError), so e.toString() is "Exception: <message>" — the old
    // 'StateError: ' prefix check never matched, leaving that literal
    // "Exception: " prefix in the snackbar text.
    return e.toString().replaceFirst('Exception: ', '');
  }

  bool get _chatOpen => _booking['chat_open'] == true;

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authProvider);
    final int? myUserId = auth.userId;

    final String seekerName = (_booking['seeker_first_name'] != null)
        ? '${_booking['seeker_first_name']} ${_booking['seeker_last_name'] ?? ''}'.trim()
        : widget.initialSeekerName;
    final String serviceName = (_booking['service_name'] as String?) ?? widget.initialServiceName;
    final String status = (_booking['status'] as String?) ?? widget.initialStatus;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              seekerName.isEmpty ? widget.initialSeekerName : seekerName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              serviceName.isEmpty ? 'Client' : '$serviceName · ${_statusLabel(status)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const _EmptyThread()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (BuildContext context, int index) {
                            final dynamic msg = _messages[index];
                            final dynamic rawSender = msg['sender_id'];
                            final int senderId =
                                rawSender is int ? rawSender : int.tryParse(rawSender?.toString() ?? '') ?? -1;
                            final bool isMe = senderId == myUserId;
                            return _ChatBubble(
                              message: msg,
                              isMe: isMe,
                              showDate: _shouldShowDate(index),
                            );
                          },
                        ),
            ),
            if (_initialLoading)
              const SizedBox.shrink()
            else if (!_chatOpen)
              _ClosedBar(status: status)
            else
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

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final String? currDate = _messages[index]['created_at'] as String?;
    final String? prevDate = _messages[index - 1]['created_at'] as String?;
    if (currDate == null || prevDate == null) return false;
    try {
      final DateTime curr = DateTime.parse(currDate).toLocal();
      final DateTime prev = DateTime.parse(prevDate).toLocal();
      return curr.day != prev.day || curr.month != prev.month || curr.year != prev.year;
    } catch (_) {
      return false;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'awaiting_agreement':
        return 'Awaiting agreement';
      case 'revising':
        return 'Revising quote';
      case 'preparing':
        return 'Preparing';
      case 'starting':
        return 'Starting';
      case 'on_going':
      case 'ongoing':
      case 'in_progress':
        return 'Ongoing';
      case 'waiting_for_remaining_payment':
      case 'waiting_remaining_payment':
        return 'Awaiting payment';
      case 'waiting_for_provider_confirmation':
      case 'waiting_for_seeker_confirmation':
      // Raw DB spellings (no "for") this API's `status` field actually uses —
      // see includes/booking_workflow_helper.php's normalizeWorkflowStatus()
      // and lib/shared/utils/booking_status_utils.dart's own comment on the
      // "ambiguous legacy family". Without these, every one of these raw
      // values fell through to the generic default label below.
      case 'waiting_provider_confirmation':
      case 'waiting_seeker_confirmation':
      case 'waiting_seeker_information':
        return 'Awaiting confirmation';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
    }
  }
}

// ── Closed-conversation bar ──────────────────────────────────────────────────

class _ClosedBar extends StatelessWidget {
  const _ClosedBar({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F5),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'This conversation is closed because the service is $status.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
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
      children: <Widget>[
        if (showDate) _DateSeparator(dateStr: createdAt),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primary : theirBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: TextStyle(fontSize: 14, height: 1.45, color: isMe ? Colors.white : AppTheme.navy),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white.withValues(alpha: 0.65) : Colors.grey.shade500,
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
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade500, letterSpacing: 0.3),
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
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF4F6F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          MaterialButton(
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
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
          children: <Widget>[
            Icon(Icons.chat_rounded, size: 56, color: AppTheme.primary.withValues(alpha: 0.2)),
            const SizedBox(height: 14),
            const Text(
              'No messages yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
            ),
            const SizedBox(height: 6),
            Text('Send the first message below.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

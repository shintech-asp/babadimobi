import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/admin/admin_api.dart';
import 'package:url_launcher/url_launcher.dart';

/// Provider detail — owner info, verification history, stats, and
/// Approve/Reject actions gated on `verification_status`.
class AdminProviderDetailScreen extends ConsumerStatefulWidget {
  const AdminProviderDetailScreen({super.key, required this.providerId});

  final int providerId;

  @override
  ConsumerState<AdminProviderDetailScreen> createState() => _AdminProviderDetailScreenState();
}

class _AdminProviderDetailScreenState extends ConsumerState<AdminProviderDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      return await ref.read(adminApiProvider).getProviderDetail(widget.providerId);
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

  Future<void> _approve() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Approve provider?'),
        content: const Text('This provider will be able to list services and receive bookings.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      await ref.read(adminApiProvider).approveProvider(widget.providerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provider approved'), backgroundColor: AppTheme.primary),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _reject() async {
    final TextEditingController reasonCtrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reject provider?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('This provider will not be able to list services.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      await ref.read(adminApiProvider).rejectProvider(widget.providerId, reason: reasonCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provider rejected'), backgroundColor: AppTheme.navy),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _email(String? email) async {
    if (email == null || email.isEmpty) return;
    final Uri uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Provider Detail')),
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

          final Map<String, dynamic> p = snap.data ?? <String, dynamic>{};
          final Map<String, dynamic> owner = (p['owner'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final Map<String, dynamic> stats = (p['stats'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final String verification = p['verification_status']?.toString() ?? 'pending';
          final String ownerName = <String?>[
            owner['first_name']?.toString(),
            owner['last_name']?.toString(),
          ].where((String? s) => s != null && s.isNotEmpty).join(' ');

          return RefreshIndicator(
            color: AppTheme.navy,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        p['company_name']?.toString() ?? 'Provider',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
                      ),
                    ),
                    _VerificationBadge(status: verification),
                  ],
                ),
                if (p['city'] != null && p['city'].toString().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(p['city'].toString(), style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                ],
                const SizedBox(height: 20),

                Row(
                  children: <Widget>[
                    Expanded(child: _StatBox(label: 'Listings', value: '${stats['listings_count'] ?? 0}')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatBox(label: 'Bookings', value: '${stats['total_bookings'] ?? 0}')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatBox(label: 'Completed', value: '${stats['completed_bookings'] ?? 0}')),
                  ],
                ),
                const SizedBox(height: 16),

                _SectionCard(
                  title: 'Owner',
                  children: <Widget>[
                    _InfoRow(label: 'Name', value: ownerName.isEmpty ? '—' : ownerName),
                    _InfoRow(
                      label: 'Phone',
                      value: owner['phone']?.toString() ?? '—',
                      trailing: (owner['phone'] != null && owner['phone'].toString().isNotEmpty)
                          ? IconButton(
                              icon: const Icon(Icons.call_outlined, size: 18, color: AppTheme.navy),
                              onPressed: () => _call(owner['phone']?.toString()),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                    _InfoRow(
                      label: 'Email',
                      value: owner['email']?.toString() ?? '—',
                      trailing: (owner['email'] != null && owner['email'].toString().isNotEmpty)
                          ? IconButton(
                              icon: const Icon(Icons.email_outlined, size: 18, color: AppTheme.navy),
                              onPressed: () => _email(owner['email']?.toString()),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                    _InfoRow(label: 'Account Status', value: owner['status']?.toString() ?? '—'),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'Business',
                  children: <Widget>[
                    _InfoRow(label: 'Address', value: p['address']?.toString() ?? '—'),
                    if (p['description'] != null && p['description'].toString().isNotEmpty)
                      _InfoRow(label: 'About', value: p['description'].toString()),
                  ],
                ),

                if (verification != 'pending' && (p['verified_by'] != null || p['verification_notes'] != null)) ...<Widget>[
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Verification History',
                    children: <Widget>[
                      if (p['verified_by'] != null) _InfoRow(label: 'Reviewed by', value: p['verified_by'].toString()),
                      if (p['verification_date'] != null)
                        _InfoRow(label: 'Date', value: _formatDate(p['verification_date'])),
                      if (p['verification_notes'] != null && p['verification_notes'].toString().isNotEmpty)
                        _InfoRow(label: 'Notes', value: p['verification_notes'].toString()),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                AbsorbPointer(
                  absorbing: _actionInProgress,
                  child: Opacity(
                    opacity: _actionInProgress ? 0.6 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (verification != 'approved')
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _approve,
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ),
                        if (verification != 'rejected')
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _reject,
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Reject'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[700],
                                side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatDate(dynamic raw) {
    try {
      return DateFormat('MMM d, yyyy \'at\' h:mm a').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status});
  final String status;

  static const Map<String, Color> _colors = <String, Color>{
    'approved': AppTheme.primary,
    'pending': Colors.orange,
    'rejected': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final Color c = _colors[status] ?? AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.navy)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: AppTheme.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.navy))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

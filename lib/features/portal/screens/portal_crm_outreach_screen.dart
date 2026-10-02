import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// CRM outreach (owner/crm) — mirrors `provider-portal/crm-outreach.php`.
/// Compose tab lists past customers (completed-booking seekers) with
/// multi-select + an optional featured service link; History tab shows
/// recent sends. Fully Pro-gated.
class PortalCrmOutreachScreen extends ConsumerStatefulWidget {
  const PortalCrmOutreachScreen({super.key});

  @override
  ConsumerState<PortalCrmOutreachScreen> createState() => _PortalCrmOutreachScreenState();
}

class _PortalCrmOutreachScreenState extends ConsumerState<PortalCrmOutreachScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<Map<String, dynamic>> _customersFuture;
  late Future<Map<String, dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _customersFuture = _loadCustomers();
    _historyFuture = _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadCustomers() async {
    try {
      return await ref.read(portalApiProvider).getOutreachCustomers();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<Map<String, dynamic>> _loadHistory() async {
    try {
      return await ref.read(portalApiProvider).getOutreachHistory();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refreshHistory() async {
    final Future<Map<String, dynamic>> next = _loadHistory();
    setState(() {
      _historyFuture = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Customer Outreach'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          tabs: const <Widget>[Tab(text: 'Compose'), Tab(text: 'History')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildComposeTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildComposeTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _customersFuture,
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (snapshot.hasError) {
          final String msg = snapshot.error.toString().replaceFirst('Exception: ', '');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(msg, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (isProError(msg))
                    ElevatedButton(
                      onPressed: () => context.push('/portal/subscription'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      child: const Text('Upgrade to Pro'),
                    ),
                ],
              ),
            ),
          );
        }

        final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
        final List<dynamic> customers = body['customers'] as List<dynamic>? ?? <dynamic>[];
        final List<dynamic> services = body['services'] as List<dynamic>? ?? <dynamic>[];

        if (customers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No past customers yet — outreach needs at least one completed booking.', style: TextStyle(color: AppTheme.textMuted), textAlign: TextAlign.center),
            ),
          );
        }

        return _ComposeForm(customers: customers, services: services, onSent: _refreshHistory);
      },
    );
  }

  Widget _buildHistoryTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _historyFuture,
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(snapshot.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
            ),
          );
        }

        final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
        final List<dynamic> rows = body['data'] as List<dynamic>? ?? <dynamic>[];

        return RefreshIndicator(
          onRefresh: _refreshHistory,
          color: AppTheme.primary,
          child: rows.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
                  children: const <Widget>[Center(child: Text('No outreach sent yet.', style: TextStyle(color: AppTheme.textMuted)))],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int i) => _HistoryRow(row: rows[i] as Map<String, dynamic>),
                ),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});
  final Map<String, dynamic> row;

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sent = row['status']?.toString() == 'sent';
    final String name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(row['subject']?.toString() ?? '', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                const SizedBox(height: 2),
                Text('to ${name.isEmpty ? (row['email'] ?? 'customer') : name}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text(_fmtDate(row['created_at']), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: (sent ? AppTheme.primary : Colors.red).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(sent ? 'Sent' : 'Failed', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: sent ? AppTheme.primary : Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ComposeForm extends ConsumerStatefulWidget {
  const _ComposeForm({required this.customers, required this.services, required this.onSent});
  final List<dynamic> customers;
  final List<dynamic> services;
  final VoidCallback onSent;

  @override
  ConsumerState<_ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends ConsumerState<_ComposeForm> {
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  final Set<int> _selectedIds = <int>{};
  int? _serviceId;
  bool _sending = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _toggleAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedIds
          ..clear()
          ..addAll(widget.customers.map((dynamic c) => ((c as Map<String, dynamic>)['seeker_user_id'] as num).toInt()));
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _send() async {
    setState(() {
      _error = null;
      _result = null;
    });
    final String subject = _subjectCtrl.text.trim();
    final String message = _messageCtrl.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      setState(() => _error = 'Please fill in a subject and message.');
      return;
    }
    if (_selectedIds.isEmpty) {
      setState(() => _error = 'Select at least one customer.');
      return;
    }
    setState(() => _sending = true);
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).sendOutreach(
            subject: subject,
            message: message,
            recipients: _selectedIds.toList(),
            serviceId: _serviceId,
          );
      if (!mounted) return;
      setState(() {
        _result = result['message']?.toString() ?? 'Sent.';
        _selectedIds.clear();
        _subjectCtrl.clear();
        _messageCtrl.clear();
        _serviceId = null;
      });
      widget.onSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        if (_error != null) ...<Widget>[
          ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
          if (isProError(_error!)) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
          ],
          const SizedBox(height: 14),
        ],
        if (_result != null) ...<Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(_result!, style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
        ],
        const Text('Subject', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
        const SizedBox(height: 6),
        TextField(controller: _subjectCtrl),
        const SizedBox(height: 14),
        const Text('Message', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
        const SizedBox(height: 6),
        TextField(controller: _messageCtrl, maxLines: 4),
        const SizedBox(height: 14),
        if (widget.services.isNotEmpty) ...<Widget>[
          const Text('Featured Service (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: _serviceId,
            hint: const Text('None'),
            isExpanded: true,
            items: widget.services.map((dynamic s) {
              final Map<String, dynamic> svc = s as Map<String, dynamic>;
              return DropdownMenuItem<int>(value: (svc['id'] as num).toInt(), child: Text(svc['service_name']?.toString() ?? '', overflow: TextOverflow.ellipsis));
            }).toList(),
            onChanged: (int? v) => setState(() => _serviceId = v),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('CUSTOMERS (${_selectedIds.length}/${widget.customers.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
            TextButton(
              onPressed: () => _toggleAll(_selectedIds.length != widget.customers.length),
              child: Text(_selectedIds.length == widget.customers.length ? 'Deselect All' : 'Select All'),
            ),
          ],
        ),
        ...widget.customers.map((dynamic c) {
          final Map<String, dynamic> cust = c as Map<String, dynamic>;
          final int id = (cust['seeker_user_id'] as num).toInt();
          final bool selected = _selectedIds.contains(id);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: selected,
            activeColor: AppTheme.primary,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(cust['full_name']?.toString() ?? cust['email']?.toString() ?? 'Customer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            subtitle: Text('${cust['completed_count']} completed · ${cust['services_had'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            onChanged: (bool? v) => setState(() {
              if (v == true) {
                _selectedIds.add(id);
              } else {
                _selectedIds.remove(id);
              }
            }),
          );
        }),
        const SizedBox(height: 14),
        LoadingButton(label: 'Send Outreach', isLoading: _sending, onPressed: _send),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, String> _kLeaveTypeLabels = <String, String>{
  'annual': 'Annual',
  'sick': 'Sick',
  'personal': 'Personal',
  'maternity': 'Maternity',
  'paternity': 'Paternity',
};

/// Own leave requests + current-year balances, and a form to submit a new
/// one — mirrors `provider-portal/my-leave-requests.php`.
class PortalLeaveRequestsScreen extends ConsumerStatefulWidget {
  const PortalLeaveRequestsScreen({super.key});

  @override
  ConsumerState<PortalLeaveRequestsScreen> createState() => _PortalLeaveRequestsScreenState();
}

class _PortalLeaveRequestsScreenState extends ConsumerState<PortalLeaveRequestsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getLeaveRequests();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _openSubmitForm(Map<String, dynamic> balances) async {
    final bool? submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _SubmitLeaveSheet(balances: balances),
    );
    if (submitted == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Leave Requests')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(snapshot.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final List<dynamic> requests = body['data'] as List<dynamic>? ?? <dynamic>[];
          final Map<String, dynamic> balances = (body['balances'] as Map<String, dynamic>?) ?? <String, dynamic>{};

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Text('BALANCES ${DateTime.now().year}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kLeaveTypeLabels.entries.map((MapEntry<String, String> e) {
                    final Map<String, dynamic> b = (balances[e.key] as Map<String, dynamic>?) ?? <String, dynamic>{};
                    final num remaining = (b['remaining'] as num?) ?? 0;
                    final num total = (b['total'] as num?) ?? 0;
                    return _BalanceChip(label: e.value, remaining: remaining, total: total);
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text('MY REQUESTS', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No leave requests yet.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...requests.map((dynamic r) => _RequestRow(row: r as Map<String, dynamic>)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          final Map<String, dynamic> balances =
              (snapshot.data?['balances'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          return FloatingActionButton.extended(
            onPressed: snapshot.hasData ? () => _openSubmitForm(balances) : null,
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add),
            label: const Text('Request Leave'),
          );
        },
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.label, required this.remaining, required this.total});

  final String label;
  final num remaining;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          Text('${remaining.toStringAsFixed(0)}/${total.toStringAsFixed(0)}d', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.row});
  final Map<String, dynamic> row;

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.primary;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String type = row['leave_type']?.toString() ?? '';
    final String status = row['status']?.toString() ?? 'pending';
    final Color color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_kLeaveTypeLabels[type] ?? type, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                const SizedBox(height: 3),
                Text('${_fmtDate(row['start_date'])} – ${_fmtDate(row['end_date'])}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                if ((row['reason']?.toString() ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(row['reason'].toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }
}

class _SubmitLeaveSheet extends ConsumerStatefulWidget {
  const _SubmitLeaveSheet({required this.balances});
  final Map<String, dynamic> balances;

  @override
  ConsumerState<_SubmitLeaveSheet> createState() => _SubmitLeaveSheetState();
}

class _SubmitLeaveSheetState extends ConsumerState<_SubmitLeaveSheet> {
  String _leaveType = 'annual';
  DateTime? _start;
  DateTime? _end;
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (picked != null) {
      setState(() {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      });
    }
  }

  Future<void> _pickEnd() async {
    final DateTime base = _start ?? DateTime.now();
    final DateTime? picked = await showDatePicker(context: context, initialDate: base, firstDate: base, lastDate: base.add(const Duration(days: 365)));
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_start == null || _end == null) {
      setState(() => _error = 'Please pick a start and end date.');
      return;
    }
    setState(() => _saving = true);
    try {
      final DateFormat fmt = DateFormat('yyyy-MM-dd');
      final Map<String, dynamic> result = await ref.read(portalApiProvider).submitLeaveRequest(
            leaveType: _leaveType,
            startDate: fmt.format(_start!),
            endDate: fmt.format(_end!),
            reason: _reasonCtrl.text.trim(),
          );
      if (!mounted) return;
      final int days = int.tryParse(result['days']?.toString() ?? '0') ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave request submitted ($days day${days == 1 ? '' : 's'}).'), backgroundColor: AppTheme.primary),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat fmt = DateFormat('MMM d, yyyy');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Request Leave', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            const Text('Leave Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _leaveType,
              items: _kLeaveTypeLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) => setState(() => _leaveType = v ?? 'annual'),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Start Date', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                      const SizedBox(height: 6),
                      OutlinedButton(onPressed: _pickStart, child: Text(_start == null ? 'Select' : fmt.format(_start!))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('End Date', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                      const SizedBox(height: 6),
                      OutlinedButton(onPressed: _pickEnd, child: Text(_end == null ? 'Select' : fmt.format(_end!))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Reason (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _reasonCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Why do you need this leave?')),
            const SizedBox(height: 20),
            LoadingButton(label: 'Submit Request', isLoading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

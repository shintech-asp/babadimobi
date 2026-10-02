import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

bool _isProError(String message) => message.toLowerCase().contains('pro subscription');

/// Shows an upgrade prompt when a mutation 403s with the "Pro subscription
/// required" error, otherwise a plain error snackbar — every action on this
/// screen (approve/reject/grant/override) is Pro-gated server-side even
/// though the lists themselves are free-viewable (matches the web's
/// "Free Tier — View Only" banner behavior).
void _handleActionError(BuildContext context, String message) {
  if (_isProError(message)) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Pro feature'),
        content: const Text('Approving, rejecting, granting leave, and balance overrides need a Pro subscription. Viewing stays free.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not now')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ctx.push('/portal/subscription');
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// HR leave management (owner/hr) — review/approve/reject requests, grant
/// paid leave directly, and view/override per-employee balances. Mirrors
/// `provider-portal/leave-requests.php` + its balance map / override card.
class PortalHrLeaveScreen extends ConsumerStatefulWidget {
  const PortalHrLeaveScreen({super.key});

  @override
  ConsumerState<PortalHrLeaveScreen> createState() => _PortalHrLeaveScreenState();
}

class _PortalHrLeaveScreenState extends ConsumerState<PortalHrLeaveScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<Map<String, dynamic>> _requestsFuture;
  late Future<Map<String, dynamic>> _balancesFuture;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestsFuture = _loadRequests();
    _balancesFuture = _loadBalances();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadRequests() async {
    try {
      return await ref.read(portalApiProvider).getLeaveRequestsForReview(status: _statusFilter);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<Map<String, dynamic>> _loadBalances() async {
    try {
      return await ref.read(portalApiProvider).getLeaveBalances();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refreshRequests() async {
    final Future<Map<String, dynamic>> next = _loadRequests();
    setState(() {
      _requestsFuture = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _refreshBalances() async {
    final Future<Map<String, dynamic>> next = _loadBalances();
    setState(() {
      _balancesFuture = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await Future.wait(<Future<void>>[_refreshRequests(), _refreshBalances()]);
  }

  void _setFilter(String? status) {
    setState(() => _statusFilter = status);
    _refreshRequests();
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    try {
      await ref.read(portalApiProvider).approveLeaveRequest((row['id'] as num).toInt());
      if (!mounted) return;
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      _handleActionError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _reject(Map<String, dynamic> row) async {
    try {
      await ref.read(portalApiProvider).rejectLeaveRequest((row['id'] as num).toInt());
      if (!mounted) return;
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      _handleActionError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openGrantForm() async {
    final Map<String, dynamic> balancesBody = await _balancesFuture.catchError((Object _) => <String, dynamic>{});
    final List<dynamic> employees = balancesBody['data'] as List<dynamic>? ?? <dynamic>[];
    if (!mounted) return;
    final bool? granted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _GrantLeaveSheet(employees: employees),
    );
    if (granted == true) _refreshAll();
  }

  Future<void> _openOverrideSheet(Map<String, dynamic> employeeRow) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _OverrideSheet(employeeRow: employeeRow),
    );
    if (changed == true) _refreshBalances();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Leave Requests'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          tabs: const <Widget>[Tab(text: 'Requests'), Tab(text: 'Balances')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[_buildRequestsTab(), _buildBalancesTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGrantForm,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Grant Leave'),
      ),
    );
  }

  Widget _buildRequestsTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _requestsFuture,
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
                  OutlinedButton(onPressed: _refreshRequests, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
        final List<dynamic> requests = body['data'] as List<dynamic>? ?? <dynamic>[];
        final Map<String, dynamic> counts = (body['counts'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        return RefreshIndicator(
          onRefresh: _refreshRequests,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  _FilterChip(label: 'All', selected: _statusFilter == null, onTap: () => _setFilter(null)),
                  _FilterChip(label: 'Pending (${counts['pending'] ?? 0})', selected: _statusFilter == 'pending', onTap: () => _setFilter('pending')),
                  _FilterChip(label: 'Approved (${counts['approved'] ?? 0})', selected: _statusFilter == 'approved', onTap: () => _setFilter('approved')),
                  _FilterChip(label: 'Rejected (${counts['rejected'] ?? 0})', selected: _statusFilter == 'rejected', onTap: () => _setFilter('rejected')),
                ],
              ),
              const SizedBox(height: 16),
              if (requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No leave requests found.', style: TextStyle(color: AppTheme.textMuted))),
                )
              else
                ...requests.map((dynamic r) => _RequestCard(
                      row: r as Map<String, dynamic>,
                      onApprove: () => _approve(r),
                      onReject: () => _reject(r),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalancesTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _balancesFuture,
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
                  OutlinedButton(onPressed: _refreshBalances, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
        final List<dynamic> employees = body['data'] as List<dynamic>? ?? <dynamic>[];
        final int year = (body['year'] as num?)?.toInt() ?? DateTime.now().year;

        return RefreshIndicator(
          onRefresh: _refreshBalances,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: <Widget>[
              Text('BALANCES $year', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
              const SizedBox(height: 10),
              if (employees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No active employees found.', style: TextStyle(color: AppTheme.textMuted))),
                )
              else
                ...employees.map((dynamic e) => _EmployeeBalanceCard(
                      row: e as Map<String, dynamic>,
                      onOverride: () => _openOverrideSheet(e),
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: selected ? AppTheme.primary : AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
      side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.row, required this.onApprove, required this.onReject});
  final Map<String, dynamic> row;
  final VoidCallback onApprove;
  final VoidCallback onReject;

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
    final bool isPending = status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(row['employee_name']?.toString() ?? 'Employee', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                    const SizedBox(height: 2),
                    Text('${_kLeaveTypeLabels[type] ?? type} · ${_fmtDate(row['start_date'])} – ${_fmtDate(row['end_date'])}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
          if ((row['reason']?.toString() ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(row['reason'].toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
          if (isPending) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeeBalanceCard extends StatelessWidget {
  const _EmployeeBalanceCard({required this.row, required this.onOverride});
  final Map<String, dynamic> row;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> balances = (row['balances'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                    Text(row['position']?.toString() ?? '', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              TextButton.icon(onPressed: onOverride, icon: const Icon(Icons.tune_rounded, size: 16), label: const Text('Override')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _kLeaveTypeLabels.entries.map((MapEntry<String, String> e) {
              final Map<String, dynamic> b = (balances[e.key] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final num remaining = (b['remaining'] as num?) ?? 0;
              final num total = (b['total'] as num?) ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
                child: Text('${e.value} ${remaining.toStringAsFixed(0)}/${total.toStringAsFixed(0)}d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _GrantLeaveSheet extends ConsumerStatefulWidget {
  const _GrantLeaveSheet({required this.employees});
  final List<dynamic> employees;

  @override
  ConsumerState<_GrantLeaveSheet> createState() => _GrantLeaveSheetState();
}

class _GrantLeaveSheetState extends ConsumerState<_GrantLeaveSheet> {
  int? _employeeId;
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
    final DateTime? picked = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 365)));
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
    if (_employeeId == null || _start == null || _end == null) {
      setState(() => _error = 'Please select an employee and date range.');
      return;
    }
    setState(() => _saving = true);
    try {
      final DateFormat fmt = DateFormat('yyyy-MM-dd');
      await ref.read(portalApiProvider).grantLeave(
            employeeId: _employeeId!,
            leaveType: _leaveType,
            startDate: fmt.format(_start!),
            endDate: fmt.format(_end!),
            reason: _reasonCtrl.text.trim(),
          );
      if (!mounted) return;
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
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Grant Paid Leave', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              if (_isProError(_error!)) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
              ],
              const SizedBox(height: 14),
            ],
            const Text('Employee', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              hint: const Text('Select employee'),
              isExpanded: true,
              items: widget.employees.map((dynamic e) {
                final Map<String, dynamic> emp = e as Map<String, dynamic>;
                final int id = (emp['employee_id'] as num).toInt();
                final String name = '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim();
                return DropdownMenuItem<int>(value: id, child: Text(name, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (int? v) => setState(() => _employeeId = v),
            ),
            const SizedBox(height: 14),
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
            TextField(controller: _reasonCtrl, maxLines: 2),
            const SizedBox(height: 20),
            LoadingButton(label: 'Grant Leave', isLoading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _OverrideSheet extends ConsumerStatefulWidget {
  const _OverrideSheet({required this.employeeRow});
  final Map<String, dynamic> employeeRow;

  @override
  ConsumerState<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends ConsumerState<_OverrideSheet> {
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> balances = (widget.employeeRow['balances'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final String type in _kLeaveTypeLabels.keys) {
      final Map<String, dynamic> b = (balances[type] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final num total = (b['total'] as num?) ?? 0;
      _controllers[type] = TextEditingController(text: total.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final Map<String, num> overrides = <String, num>{};
    for (final MapEntry<String, TextEditingController> e in _controllers.entries) {
      final num? v = num.tryParse(e.value.text.trim());
      if (v != null) overrides[e.key] = v;
    }
    if (overrides.isEmpty) {
      setState(() => _error = 'Enter at least one value.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).overrideLeaveBalance(
            employeeId: (widget.employeeRow['employee_id'] as num).toInt(),
            overrides: overrides,
          );
      if (!mounted) return;
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
    final String name = '${widget.employeeRow['first_name'] ?? ''} ${widget.employeeRow['last_name'] ?? ''}'.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Leave Override', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              Text('for $name (this year only)', style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                if (_isProError(_error!)) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
                ],
                const SizedBox(height: 14),
              ],
              ..._kLeaveTypeLabels.entries.map((MapEntry<String, String> e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text('${e.value} days', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy))),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _controllers[e.key],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
              LoadingButton(label: 'Save Override', isLoading: _saving, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

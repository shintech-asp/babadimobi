import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, Color> _kStatusColors = <String, Color>{
  'pending': Colors.orange,
  'approved': AppTheme.primary,
  'rejected': Colors.red,
  'partially_approved': Color(0xFF6366F1),
};

/// Budget requests — mirrors `provider-portal/budget-requests.php`. Fully
/// Pro-gated. Any finance/owner staff can submit a request; only the owner
/// can approve/reject (matches the web page's Action-column visibility).
class PortalBudgetRequestsScreen extends ConsumerStatefulWidget {
  const PortalBudgetRequestsScreen({super.key});

  @override
  ConsumerState<PortalBudgetRequestsScreen> createState() => _PortalBudgetRequestsScreenState();
}

class _PortalBudgetRequestsScreenState extends ConsumerState<PortalBudgetRequestsScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final PortalApi api = ref.read(portalApiProvider);
      final List<dynamic> results = await Future.wait(<Future<dynamic>>[
        api.getMe(),
        api.getBudgetRequests(status: _statusFilter),
      ]);
      return <String, dynamic>{'me': results[0], 'requests': results[1]};
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

  void _setFilter(String? status) {
    setState(() => _statusFilter = status);
    _refresh();
  }

  Future<void> _openAddForm() async {
    final bool? submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _AddBudgetRequestSheet(),
    );
    if (submitted == true) _refresh();
  }

  Future<void> _openDecisionSheet(Map<String, dynamic> row) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _DecisionSheet(row: row),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Budget Requests')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
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
                      )
                    else
                      OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final Map<String, dynamic> me = (body['me'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final Map<String, dynamic> staff = (me['staff'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final bool isOwner = staff['role']?.toString() == 'owner';

          final Map<String, dynamic> reqBody = (body['requests'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final List<dynamic> requests = reqBody['data'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: const Text('All'), selected: _statusFilter == null, onSelected: (_) => _setFilter(null)),
                    ChoiceChip(label: const Text('Pending'), selected: _statusFilter == 'pending', onSelected: (_) => _setFilter('pending')),
                    ChoiceChip(label: const Text('Approved'), selected: _statusFilter == 'approved', onSelected: (_) => _setFilter('approved')),
                    ChoiceChip(label: const Text('Rejected'), selected: _statusFilter == 'rejected', onSelected: (_) => _setFilter('rejected')),
                  ],
                ),
                const SizedBox(height: 16),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No budget requests found.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...requests.map((dynamic r) => _RequestCard(
                        row: r as Map<String, dynamic>,
                        canDecide: isOwner,
                        onDecide: () => _openDecisionSheet(r),
                      )),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.row, required this.canDecide, required this.onDecide});
  final Map<String, dynamic> row;
  final bool canDecide;
  final VoidCallback onDecide;

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
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final String status = row['status']?.toString() ?? 'pending';
    final Color color = _kStatusColors[status] ?? AppTheme.textMuted;
    final num amount = (row['amount'] as num?) ?? 0;
    final num? approvedAmount = row['approved_amount'] as num?;
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
                    Text(row['department']?.toString() ?? 'Department', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                    Text('by ${row['requester_name'] ?? 'Staff'} · ${_fmtDate(row['request_date'])}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          if ((row['purpose']?.toString() ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(row['purpose'].toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text('Requested: ${peso.format(amount)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.navy)),
              if (approvedAmount != null) ...<Widget>[
                const SizedBox(width: 10),
                Text('Approved: ${peso.format(approvedAmount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ],
            ],
          ),
          if (row['remarks'] != null && row['remarks'].toString().isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('Remarks: ${row['remarks']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (canDecide && isPending) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onDecide, child: const Text('Review')),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddBudgetRequestSheet extends ConsumerStatefulWidget {
  const _AddBudgetRequestSheet();

  @override
  ConsumerState<_AddBudgetRequestSheet> createState() => _AddBudgetRequestSheetState();
}

class _AddBudgetRequestSheetState extends ConsumerState<_AddBudgetRequestSheet> {
  final TextEditingController _departmentCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _purposeCtrl = TextEditingController();
  DateTime? _neededDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _departmentCtrl.dispose();
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickNeededDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 730)));
    if (picked != null) setState(() => _neededDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String department = _departmentCtrl.text.trim();
    final num? amount = num.tryParse(_amountCtrl.text.trim());
    final String purpose = _purposeCtrl.text.trim();
    if (department.isEmpty || amount == null || amount <= 0 || purpose.isEmpty) {
      setState(() => _error = 'Please fill in department, a valid amount, and purpose.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).submitBudgetRequest(
            department: department,
            amount: amount,
            description: purpose,
            neededDate: _neededDate != null ? DateFormat('yyyy-MM-dd').format(_neededDate!) : null,
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
            const Text('New Budget Request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              if (isProError(_error!)) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
              ],
              const SizedBox(height: 14),
            ],
            const Text('Department', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _departmentCtrl, decoration: const InputDecoration(hintText: 'e.g. HR, Operations, Marketing')),
            const SizedBox(height: 14),
            const Text('Amount Requested (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 14),
            const Text('Purpose', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _purposeCtrl, maxLines: 3),
            const SizedBox(height: 14),
            const Text('Date Needed (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: _pickNeededDate, child: Text(_neededDate == null ? 'Select' : DateFormat('MMM d, yyyy').format(_neededDate!))),
            const SizedBox(height: 20),
            LoadingButton(label: 'Submit Request', isLoading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _DecisionSheet extends ConsumerStatefulWidget {
  const _DecisionSheet({required this.row});
  final Map<String, dynamic> row;

  @override
  ConsumerState<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<_DecisionSheet> {
  late final TextEditingController _approvedAmountCtrl;
  final TextEditingController _remarksCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _approvedAmountCtrl = TextEditingController(text: (widget.row['amount'] as num?)?.toString() ?? '');
  }

  @override
  void dispose() {
    _approvedAmountCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() => _error = null);
    final num? amount = num.tryParse(_approvedAmountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an approved amount greater than 0 (or use Reject instead).');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).approveBudgetRequest(
            requestId: (widget.row['id'] as num).toInt(),
            approvedAmount: amount,
            remarks: _remarksCtrl.text.trim(),
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

  Future<void> _reject() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(portalApiProvider).rejectBudgetRequest(
            requestId: (widget.row['id'] as num).toInt(),
            remarks: _remarksCtrl.text.trim(),
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
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
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
            Text('Review Request', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            Text('${widget.row['department']} — requested ${peso.format(widget.row['amount'] ?? 0)}', style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            const Text('Approved Amount (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _approvedAmountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 14),
            const Text('Remarks (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _remarksCtrl, maxLines: 2),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _reject,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: LoadingButton(label: 'Approve', isLoading: _saving, onPressed: _approve)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

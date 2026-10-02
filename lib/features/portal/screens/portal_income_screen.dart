import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Income / Sales — mirrors `provider-portal/income.php`. The list is
/// free-tier viewable; adding a manual record still needs Pro server-side.
class PortalIncomeScreen extends ConsumerStatefulWidget {
  const PortalIncomeScreen({super.key});

  @override
  ConsumerState<PortalIncomeScreen> createState() => _PortalIncomeScreenState();
}

class _PortalIncomeScreenState extends ConsumerState<PortalIncomeScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getIncome();
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

  Future<void> _openAddForm() async {
    final bool? added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _AddIncomeSheet(),
    );
    if (added == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Income / Sales')),
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
          final List<dynamic> records = body['data'] as List<dynamic>? ?? <dynamic>[];
          final Map<String, dynamic> summary = (body['summary'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final num totalIncome = (summary['total_income'] as num?) ?? 0;

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('TOTAL INCOME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(peso.format(totalIncome), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No income records yet.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...records.map((dynamic r) => _IncomeRow(row: r as Map<String, dynamic>)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add Income'),
      ),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  const _IncomeRow({required this.row});
  final Map<String, dynamic> row;

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
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final num amount = (row['amount'] as num?) ?? 0;

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
                Text(row['income_type']?.toString() ?? 'Income', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                const SizedBox(height: 2),
                Text(_fmtDate(row['income_date']), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                if ((row['description']?.toString() ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(row['description'].toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Text(peso.format(amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
        ],
      ),
    );
  }
}

class _AddIncomeSheet extends ConsumerStatefulWidget {
  const _AddIncomeSheet();

  @override
  ConsumerState<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends ConsumerState<_AddIncomeSheet> {
  final TextEditingController _sourceCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final num? amount = num.tryParse(_amountCtrl.text.trim());
    final String source = _sourceCtrl.text.trim();
    final String description = _descriptionCtrl.text.trim();
    if (amount == null || amount <= 0 || source.isEmpty || description.isEmpty) {
      setState(() => _error = 'Please fill in a valid amount, source, and description.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).addIncome(
            amount: amount,
            source: source,
            description: description,
            date: DateFormat('yyyy-MM-dd').format(_date),
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
            const Text('Add Income', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              if (isProError(_error!)) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
              ],
              const SizedBox(height: 14),
            ],
            const Text('Source', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _sourceCtrl, decoration: const InputDecoration(hintText: 'e.g. Booking, Consultation, Rental')),
            const SizedBox(height: 14),
            const Text('Amount (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 14),
            const Text('Description', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _descriptionCtrl, maxLines: 2),
            const SizedBox(height: 14),
            const Text('Date', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: _pickDate, child: Text(DateFormat('MMM d, yyyy').format(_date))),
            const SizedBox(height: 20),
            LoadingButton(label: 'Save Income', isLoading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

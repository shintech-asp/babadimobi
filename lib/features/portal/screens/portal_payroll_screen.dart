import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

const Map<String, Color> _kStatusColors = <String, Color>{
  'pending': Colors.orange,
  'processed': Color(0xFF6366F1),
  'paid': AppTheme.primary,
};

/// Payroll (owner/hr generate, owner/finance approve + mark paid) — mirrors
/// `provider-portal/payroll.php`. Pro-gated entirely server-side.
class PortalPayrollScreen extends ConsumerStatefulWidget {
  const PortalPayrollScreen({super.key});

  @override
  ConsumerState<PortalPayrollScreen> createState() => _PortalPayrollScreenState();
}

class _PortalPayrollScreenState extends ConsumerState<PortalPayrollScreen> {
  late Future<Map<String, dynamic>> _future;
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  bool _busyId = false;

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
        api.getPayroll(month: _month, year: _year),
      ]);
      return <String, dynamic>{'me': results[0], 'payroll': results[1]};
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

  Future<void> _pickPeriod() async {
    int month = _month;
    int year = _year;
    final bool? changed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) => AlertDialog(
          title: const Text('Filter Period'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: month,
                  items: List<int>.generate(12, (int i) => i + 1)
                      .map((int m) => DropdownMenuItem<int>(value: m, child: Text(DateFormat('MMMM').format(DateTime(2000, m)))))
                      .toList(),
                  onChanged: (int? v) => setDialogState(() => month = v ?? month),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: year,
                  items: List<int>.generate(4, (int i) => DateTime.now().year - 2 + i)
                      .map((int y) => DropdownMenuItem<int>(value: y, child: Text(y.toString())))
                      .toList(),
                  onChanged: (int? v) => setDialogState(() => year = v ?? year),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (changed == true) {
      setState(() {
        _month = month;
        _year = year;
      });
      _refresh();
    }
  }

  Future<void> _openGenerateDialog() async {
    String half = '1';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) => AlertDialog(
          title: const Text('Generate Payroll'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Period: ${DateFormat('MMMM yyyy').format(DateTime(_year, _month))}'),
              const SizedBox(height: 12),
              const Text('Cutoff', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('1st half'),
                value: '1',
                groupValue: half,
                onChanged: (String? v) => setDialogState(() => half = v ?? '1'),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('2nd half'),
                value: '2',
                groupValue: half,
                onChanged: (String? v) => setDialogState(() => half = v ?? '1'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Generate')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).generatePayroll(
            month: DateFormat('yyyy-MM').format(DateTime(_year, _month)),
            half: half,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'Payroll generated.'), backgroundColor: AppTheme.primary));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _approve(int id) async {
    setState(() => _busyId = true);
    try {
      await ref.read(portalApiProvider).approvePayroll(id);
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busyId = false);
    }
  }

  Future<void> _markPaid(int id) async {
    setState(() => _busyId = true);
    try {
      await ref.read(portalApiProvider).markPayrollPaid(id);
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busyId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickPeriod),
        ],
      ),
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
                    if (msg.toLowerCase().contains('pro subscription'))
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
          final String role = staff['role']?.toString() ?? '';
          final bool canProcess = role == 'owner' || role == 'finance';

          final Map<String, dynamic> payrollBody = (body['payroll'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final List<dynamic> records = payrollBody['data'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Text(DateFormat('MMMM yyyy').format(DateTime(_year, _month)).toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No payroll records for this period.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...records.map((dynamic r) => _PayrollCard(
                        row: r as Map<String, dynamic>,
                        busy: _busyId,
                        canProcess: canProcess,
                        onApprove: () => _approve((r['id'] as num).toInt()),
                        onMarkPaid: () => _markPaid((r['id'] as num).toInt()),
                      )),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final Map<String, dynamic> me = (snapshot.data!['me'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final Map<String, dynamic> staff = (me['staff'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final String role = staff['role']?.toString() ?? '';
          if (role != 'owner' && role != 'hr') return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: _openGenerateDialog,
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Generate'),
          );
        },
      ),
    );
  }
}

class _PayrollCard extends StatelessWidget {
  const _PayrollCard({
    required this.row,
    required this.busy,
    required this.canProcess,
    required this.onApprove,
    required this.onMarkPaid,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final bool canProcess;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final String status = row['status']?.toString() ?? 'pending';
    final Color color = _kStatusColors[status] ?? AppTheme.textMuted;
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final num netSalary = (row['net_salary'] as num?) ?? 0;
    final String name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();

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
                    Text(name.isEmpty ? 'Employee' : name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                    Text(row['pay_period_name']?.toString() ?? '', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
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
          const SizedBox(height: 8),
          Text('Net: ${peso.format(netSalary)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
          if (canProcess && (status == 'pending' || status == 'processed')) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy ? null : (status == 'pending' ? onApprove : onMarkPaid),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                child: Text(status == 'pending' ? 'Approve' : 'Mark Paid'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

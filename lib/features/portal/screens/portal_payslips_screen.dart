import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Own payroll history, read-only — mirrors `provider-portal/my-payslips.php`.
class PortalPayslipsScreen extends ConsumerStatefulWidget {
  const PortalPayslipsScreen({super.key});

  @override
  ConsumerState<PortalPayslipsScreen> createState() => _PortalPayslipsScreenState();
}

class _PortalPayslipsScreenState extends ConsumerState<PortalPayslipsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getPayslips();
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

  void _openDetail(Map<String, dynamic> payslip, String employeeName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _PayslipDetailSheet(payslip: payslip, employeeName: employeeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('My Salary')),
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
          final List<dynamic> payslips = body['data'] as List<dynamic>? ?? <dynamic>[];
          final Map<String, dynamic> employee = (body['employee'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final String employeeName = '${employee['first_name'] ?? ''} ${employee['last_name'] ?? ''}'.trim();

          if (payslips.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const Center(child: Text('No payslips yet.', style: TextStyle(color: AppTheme.textMuted))),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: payslips.map((dynamic p) {
                final Map<String, dynamic> row = p as Map<String, dynamic>;
                return _PayslipRow(row: row, onTap: () => _openDetail(row, employeeName));
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _PayslipRow extends StatelessWidget {
  const _PayslipRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return AppTheme.primary;
      case 'processed':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = row['status']?.toString() ?? 'pending';
    final Color color = _statusColor(status);
    final double net = double.tryParse(row['net_salary']?.toString() ?? '0') ?? 0;
    final String periodName = row['pay_period_name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        title: Text(
          periodName.isNotEmpty ? periodName : '${_fmtDate(row['pay_period_start'])} – ${_fmtDate(row['pay_period_end'])}',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy),
        ),
        subtitle: Text('${_fmtDate(row['pay_period_start'])} – ${_fmtDate(row['pay_period_end'])}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text('₱${net.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _PayslipDetailSheet extends StatelessWidget {
  const _PayslipDetailSheet({required this.payslip, required this.employeeName});
  final Map<String, dynamic> payslip;
  final String employeeName;

  double _n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    final double gross = _n(payslip['gross_salary']);
    final double net = _n(payslip['net_salary']);
    final double sss = _n(payslip['sss_employee']);
    final double philhealth = _n(payslip['philhealth_employee']);
    final double pagibig = _n(payslip['pagibig_employee']);
    final double tax = _n(payslip['withholding_tax']);
    final double lateDed = _n(payslip['late_deduction']);
    final double absentDed = _n(payslip['absent_deduction']);
    final double overtime = _n(payslip['overtime_pay']);
    final double otherDed = _n(payslip['deductions']);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: <Widget>[
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(employeeName.isEmpty ? 'Payslip' : employeeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              Text(payslip['pay_period_name']?.toString() ?? '', style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
              const SizedBox(height: 20),
              _Line('Gross Salary', gross, bold: true),
              const Divider(height: 20),
              if (overtime > 0) _Line('Overtime Pay', overtime, positive: true),
              if (lateDed > 0) _Line('Late Deduction', -lateDed),
              if (absentDed > 0) _Line('Absent Deduction', -absentDed),
              const Divider(height: 20),
              const Text('STATUTORY DEDUCTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _Line('SSS', -sss),
              _Line('PhilHealth', -philhealth),
              _Line('Pag-IBIG', -pagibig),
              _Line('Withholding Tax', -tax),
              if (otherDed > 0) _Line('Other Deductions', -otherDed),
              const Divider(height: 20),
              _Line('Net Pay', net, bold: true, big: true),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.bold = false, this.big = false, this.positive = false});
  final String label;
  final double amount;
  final bool bold;
  final bool big;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final Color color = amount < 0 ? Colors.red[700]! : (positive ? AppTheme.primary : AppTheme.navy);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: big ? 15 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: AppTheme.navy)),
          Text(
            '${amount < 0 ? '-' : ''}₱${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(fontSize: big ? 17 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

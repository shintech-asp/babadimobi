import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, String> _kEmploymentTypeLabels = <String, String>{
  'regular': 'Regular',
  'probationary': 'Probationary',
  'contractual': 'Contractual',
  'part_time': 'Part-time',
};

const Map<String, String> _kStatusLabels = <String, String>{
  'active': 'Active',
  'inactive': 'Inactive',
  'on_leave': 'On Leave',
};

/// Owner/HR employee record management — distinct from Staff Accounts
/// (`/portal/staff`, which manages provider_staff portal-login accounts).
/// Mirrors `provider-portal/employees.php`'s Add Employee flow.
class PortalEmployeesScreen extends ConsumerStatefulWidget {
  const PortalEmployeesScreen({super.key});

  @override
  ConsumerState<PortalEmployeesScreen> createState() => _PortalEmployeesScreenState();
}

class _PortalEmployeesScreenState extends ConsumerState<PortalEmployeesScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getEmployees();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _openAddForm(Map<String, dynamic> catalog) async {
    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _EmployeeFormSheet(catalog: catalog),
    );
    if (created == true) _refresh();
  }

  Future<void> _openEditSheet(Map<String, dynamic> row, Map<String, dynamic> catalog) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _EmployeeFormSheet(catalog: catalog, existing: row),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Employees')),
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
          final List<dynamic> rows = body['data'] as List<dynamic>? ?? <dynamic>[];
          final Map<String, dynamic> catalog = body['catalog'] as Map<String, dynamic>? ?? <String, dynamic>{};

          return Stack(
            children: <Widget>[
              RefreshIndicator(
                onRefresh: _refresh,
                color: AppTheme.primary,
                child: rows.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
                        children: const <Widget>[
                          Center(child: Text('No employees yet. Tap + to add one.', style: TextStyle(color: AppTheme.textMuted))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemCount: rows.length,
                        itemBuilder: (BuildContext context, int i) {
                          final Map<String, dynamic> row = rows[i] as Map<String, dynamic>;
                          return _EmployeeRow(row: row, onTap: () => _openEditSheet(row, catalog));
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          final Map<String, dynamic> catalog =
              (snapshot.data?['catalog'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          return FloatingActionButton.extended(
            onPressed: () => _openAddForm(catalog),
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add Employee'),
          );
        },
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String status = row['status']?.toString() ?? 'active';
    final bool active = status == 'active';
    final String name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    final String position = row['position']?.toString() ?? '';
    final String department = row['department']?.toString() ?? '';
    final Color statusColor = active
        ? AppTheme.primary
        : (status == 'on_leave' ? Colors.orange : Colors.red);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: statusColor,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text(
          '${row['employee_id'] ?? ''}\n${position.isEmpty ? '—' : position}${department.isEmpty ? '' : ' · $department'}',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.4),
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Text(_kStatusLabels[status] ?? status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor)),
        ),
      ),
    );
  }
}

/// Shared Add/Edit form. In "edit" mode (existing != null), only the fields
/// the web's own Edit modal exposes are mutable there too — but since this
/// is a from-scratch mobile CRUD screen (not just mirroring a status-only
/// web modal), it allows editing the full record, matching
/// api/v1/portal/hr/employees/update.php's capability.
class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({required this.catalog, this.existing});

  final Map<String, dynamic> catalog;
  final Map<String, dynamic>? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _salaryCtrl = TextEditingController();
  final TextEditingController _sssCtrl = TextEditingController();
  final TextEditingController _philhealthCtrl = TextEditingController();
  final TextEditingController _pagibigCtrl = TextEditingController();
  final TextEditingController _tinCtrl = TextEditingController();

  String? _position;
  String? _department;
  String _employmentType = 'regular';
  String _staffType = 'office';
  String _status = 'active';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? e = widget.existing;
    if (e != null) {
      _firstNameCtrl.text = e['first_name']?.toString() ?? '';
      _lastNameCtrl.text = e['last_name']?.toString() ?? '';
      _emailCtrl.text = e['email']?.toString() ?? '';
      _salaryCtrl.text = e['basic_salary'] != null ? e['basic_salary'].toString() : '';
      _sssCtrl.text = e['sss_no']?.toString() ?? '';
      _philhealthCtrl.text = e['philhealth_no']?.toString() ?? '';
      _pagibigCtrl.text = e['pagibig_no']?.toString() ?? '';
      _tinCtrl.text = e['tin_no']?.toString() ?? '';
      _position = (e['position']?.toString().isNotEmpty ?? false) ? e['position'].toString() : null;
      _department = (e['department']?.toString().isNotEmpty ?? false) ? e['department'].toString() : null;
      _employmentType = e['employment_type']?.toString() ?? 'regular';
      _staffType = e['staff_type']?.toString() ?? 'office';
      _status = e['status']?.toString() ?? 'active';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _salaryCtrl.dispose();
    _sssCtrl.dispose();
    _philhealthCtrl.dispose();
    _pagibigCtrl.dispose();
    _tinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (!widget.isEdit) {
      if (_firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
        setState(() => _error = 'First name, last name, and email are required.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final double? salary = double.tryParse(_salaryCtrl.text.trim());

      if (widget.isEdit) {
        await ref.read(portalApiProvider).updateEmployee(
              id: (widget.existing!['id'] as num).toInt(),
              status: _status,
              position: _position,
              department: _department,
              employmentType: _employmentType,
              staffType: _staffType,
              basicSalary: salary,
              sssNo: _sssCtrl.text.trim(),
              philhealthNo: _philhealthCtrl.text.trim(),
              pagibigNo: _pagibigCtrl.text.trim(),
              tinNo: _tinCtrl.text.trim(),
            );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final Map<String, dynamic> result = await ref.read(portalApiProvider).createEmployee(
              firstName: _firstNameCtrl.text.trim(),
              lastName: _lastNameCtrl.text.trim(),
              email: _emailCtrl.text.trim(),
              position: _position,
              department: _department,
              basicSalary: salary,
              employmentType: _employmentType,
              staffType: _staffType,
              sssNo: _sssCtrl.text.trim(),
              philhealthNo: _philhealthCtrl.text.trim(),
              pagibigNo: _pagibigCtrl.text.trim(),
              tinNo: _tinCtrl.text.trim(),
            );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        _showCredentials(
          context,
          result['employee_id']?.toString() ?? '',
          result['temp_password']?.toString() ?? '',
          result['email_sent'] == true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static void _showCredentials(BuildContext context, String employeeId, String tempPassword, bool emailSent) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Employee added'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              emailSent
                  ? 'A welcome email with these credentials was sent to the employee.'
                  : 'Could not send the welcome email — share these credentials manually.',
            ),
            const SizedBox(height: 16),
            _CredentialRow(label: 'Employee ID', value: employeeId),
            const SizedBox(height: 8),
            _CredentialRow(label: 'Temp Password', value: tempPassword),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> positions = (widget.catalog['positions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
    final Map<String, dynamic> employmentTypes = (widget.catalog['employment_types'] as Map<String, dynamic>?) ?? _kEmploymentTypeLabels;
    final List<String> departments = ((widget.catalog['departments'] as Map<String, dynamic>?) ?? <String, dynamic>{}).keys.toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(widget.isEdit ? 'Edit Employee' : 'Add Employee', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 16),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: 14),
              ],

              if (widget.isEdit) ...<Widget>[
                Text(
                  '${widget.existing!['first_name'] ?? ''} ${widget.existing!['last_name'] ?? ''}'.trim(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.navy),
                ),
                Text(widget.existing!['email']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 14),
                const Text('Status', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: _kStatusLabels.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (String? v) => setState(() => _status = v ?? _status),
                ),
                const SizedBox(height: 14),
              ] else ...<Widget>[
                const Text('First Name *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                const SizedBox(height: 6),
                TextField(controller: _firstNameCtrl, textCapitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                const Text('Last Name *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                const SizedBox(height: 6),
                TextField(controller: _lastNameCtrl, textCapitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                const Text('Email *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                const SizedBox(height: 6),
                TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 14),
              ],

              const Text('Position', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: positions.contains(_position) ? _position : null,
                hint: const Text('Select a position'),
                isExpanded: true,
                items: positions.map((String p) => DropdownMenuItem<String>(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (String? v) => setState(() => _position = v),
              ),
              const SizedBox(height: 14),
              const Text('Department', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: departments.contains(_department) ? _department : null,
                hint: const Text('Select a department'),
                isExpanded: true,
                items: departments.map((String d) => DropdownMenuItem<String>(value: d, child: Text(d))).toList(),
                onChanged: (String? v) => setState(() => _department = v),
              ),
              const SizedBox(height: 14),
              const Text('Basic Salary (₱ per month)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(
                controller: _salaryCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: 'e.g. 15000',
                  helperText: 'Always a full monthly amount — payroll derives daily/hourly rates from this.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 14),
              const Text('Employment Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: employmentTypes.containsKey(_employmentType) ? _employmentType : 'regular',
                items: employmentTypes.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value.toString()))).toList(),
                onChanged: (String? v) => setState(() => _employmentType = v ?? 'regular'),
              ),
              const SizedBox(height: 14),
              const Text('Staff Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _staffType,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'office', child: Text('Office Staff')),
                  DropdownMenuItem<String>(value: 'field', child: Text('Field Technician')),
                ],
                onChanged: (String? v) => setState(() => _staffType = v ?? 'office'),
              ),
              const Text(
                'Field Technicians can be assigned to services and handle bookings on-site. Office Staff cannot.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),

              const Text('Government IDs (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
              const SizedBox(height: 10),
              TextField(
                controller: _sssCtrl,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'SSS No.', hintText: '10 digits', counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _philhealthCtrl,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(labelText: 'PhilHealth No.', hintText: '12 digits', counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pagibigCtrl,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(labelText: 'Pag-IBIG No.', hintText: '12 digits', counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 13,
                decoration: const InputDecoration(labelText: 'TIN', hintText: '9 digits (+3 branch code)', counterText: ''),
              ),

              const SizedBox(height: 20),
              LoadingButton(
                label: widget.isEdit ? 'Save Changes' : 'Create Employee',
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.navy)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied.')));
          },
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, String> _kRoleLabels = <String, String>{
  'hr': 'HR',
  'finance': 'Finance',
  'crm': 'CRM',
};

const Map<String, String> _kDeptLabels = <String, String>{
  'hr': 'HR only',
  'finance': 'Finance only',
  'crm': 'CRM only',
  'all': 'All departments',
};

/// Owner-only staff management — list, add (hr/finance/crm), edit role/
/// department/status, deactivate. Mirrors `provider-portal/staff.php`.
class PortalStaffScreen extends ConsumerStatefulWidget {
  const PortalStaffScreen({super.key});

  @override
  ConsumerState<PortalStaffScreen> createState() => _PortalStaffScreenState();
}

class _PortalStaffScreenState extends ConsumerState<PortalStaffScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getStaff();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<List<dynamic>> next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _openAddForm() async {
    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _AddStaffSheet(),
    );
    if (created == true) _refresh();
  }

  Future<void> _openEditSheet(Map<String, dynamic> row) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _EditStaffSheet(staff: row),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Staff / Employees')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
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

          final List<dynamic> rows = snapshot.data ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
                    children: const <Widget>[
                      Center(child: Text('No staff members yet. Tap + to add one.', style: TextStyle(color: AppTheme.textMuted))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Map<String, dynamic> row = rows[i] as Map<String, dynamic>;
                      return _StaffRow(row: row, onTap: () => _openEditSheet(row));
                    },
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Staff'),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String role = row['role']?.toString() ?? '';
    final String department = row['department']?.toString() ?? '';
    final bool active = row['status']?.toString() == 'active';
    final bool mustChange = row['must_change_password'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: active ? AppTheme.primary : AppTheme.textMuted,
          child: Text(
            (row['username']?.toString() ?? '?').isNotEmpty ? row['username'].toString()[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(row['username']?.toString() ?? '', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text('${row['email'] ?? ''}\n${_kRoleLabels[role] ?? role} · ${_kDeptLabels[department] ?? department}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.4)),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: (active ? AppTheme.primary : Colors.red).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? AppTheme.primary : Colors.red)),
            ),
            if (mustChange) ...<Widget>[
              const SizedBox(height: 4),
              const Text('Pending setup', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddStaffSheet extends ConsumerStatefulWidget {
  const _AddStaffSheet();

  @override
  ConsumerState<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends ConsumerState<_AddStaffSheet> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  String _role = 'hr';
  String _department = 'hr';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String username = _usernameCtrl.text.trim();
    final String email = _emailCtrl.text.trim();
    if (username.isEmpty || email.isEmpty) {
      setState(() => _error = 'Please fill in username and email.');
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).createStaff(
            username: username,
            email: email,
            role: _role,
            department: _department,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _showCredentials(context, username, result['temp_password']?.toString() ?? '');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static void _showCredentials(BuildContext context, String username, String tempPassword) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Staff account created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Share these login details with the new staff member — they will be asked to change the password on first login.'),
            const SizedBox(height: 16),
            _CredentialRow(label: 'Username', value: username),
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
            const Text('Add Staff Member', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            const Text('Username', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _usernameCtrl),
            const SizedBox(height: 14),
            const Text('Email', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            const Text('Role', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _role,
              items: _kRoleLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) => setState(() => _role = v ?? 'hr'),
            ),
            const SizedBox(height: 14),
            const Text('Department Access', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _department,
              items: _kDeptLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) => setState(() => _department = v ?? 'hr'),
            ),
            const SizedBox(height: 20),
            LoadingButton(label: 'Create Staff Account', isLoading: _saving, onPressed: _submit),
          ],
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

class _EditStaffSheet extends ConsumerStatefulWidget {
  const _EditStaffSheet({required this.staff});
  final Map<String, dynamic> staff;

  @override
  ConsumerState<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends ConsumerState<_EditStaffSheet> {
  late String _role;
  late String _department;
  late bool _active;
  bool _saving = false;
  bool _deactivating = false;
  String? _error;

  // 'owner' deliberately excluded — a provider has exactly one owner, and
  // update.php now rejects it server-side too (matches the web, which never
  // offers it as a selectable role).
  static const Map<String, String> _kEditableRoleLabels = <String, String>{
    'hr': 'HR',
    'finance': 'Finance',
    'crm': 'CRM',
  };

  @override
  void initState() {
    super.initState();
    _role = widget.staff['role']?.toString() ?? 'hr';
    _department = widget.staff['department']?.toString() ?? 'hr';
    _active = widget.staff['status']?.toString() == 'active';
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(portalApiProvider).updateStaff(
            id: (widget.staff['id'] as num).toInt(),
            role: _role,
            department: _department,
            status: _active ? 'active' : 'inactive',
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

  Future<void> _deactivate() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Deactivate staff member?'),
        content: Text('${widget.staff['username']} will no longer be able to log in.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _error = null;
      _deactivating = true;
    });
    try {
      await ref.read(portalApiProvider).deleteStaff((widget.staff['id'] as num).toInt());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool alreadyInactive = widget.staff['status']?.toString() == 'inactive';
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
            Text(widget.staff['username']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            Text(widget.staff['email']?.toString() ?? '', style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            const Text('Role', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _role,
              items: _kEditableRoleLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 14),
            const Text('Department Access', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _department,
              items: _kDeptLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) => setState(() => _department = v ?? _department),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              value: _active,
              activeThumbColor: AppTheme.primary,
              onChanged: (bool v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            LoadingButton(label: 'Save Changes', isLoading: _saving, onPressed: _save),
            if (!alreadyInactive) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deactivating ? null : _deactivate,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  icon: _deactivating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                      : const Icon(Icons.person_off_outlined, size: 18),
                  label: const Text('Deactivate Account'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

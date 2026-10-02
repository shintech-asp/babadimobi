import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Change password — the only action available to a portal account still
/// flagged `must_change_password` (first login with a temp password). Wraps
/// `api/v1/portal/auth/change-password.php`, which works for either account
/// kind (staff or employee) via the JWT.
class PortalChangePasswordScreen extends ConsumerStatefulWidget {
  const PortalChangePasswordScreen({super.key});

  @override
  ConsumerState<PortalChangePasswordScreen> createState() => _PortalChangePasswordScreenState();
}

class _PortalChangePasswordScreenState extends ConsumerState<PortalChangePasswordScreen> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String current = _currentCtrl.text;
    final String next = _newCtrl.text;
    final String confirm = _confirmCtrl.text;

    if (current.isEmpty || next.isEmpty) {
      setState(() => _error = 'Please fill in both password fields.');
      return;
    }
    if (next.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }
    if (next == current) {
      setState(() => _error = 'New password must differ from the current password.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.'), backgroundColor: AppTheme.primary),
      );
      context.go('/portal/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Change Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Set a new password to continue. If this is your first login, use the temporary password you were given as the current password.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: 14),
              ],
              const Text('Current / Temporary Password', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _currentCtrl, obscureText: true),
              const SizedBox(height: 14),
              const Text('New Password', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _newCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'At least 8 characters')),
              const SizedBox(height: 14),
              const Text('Confirm New Password', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _confirmCtrl, obscureText: true),
              const SizedBox(height: 24),
              LoadingButton(label: 'Update Password', isLoading: _saving, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

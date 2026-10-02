import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';

/// Shown when an admin's `role` claim doesn't cover the screen they landed
/// on — e.g. an `hr`/`finance` admin reaching `/admin/providers`, which is
/// `super_admin`/`admin` only per `admin/providers/index.php`'s own guard.
class NotAuthorizedScreen extends StatelessWidget {
  const NotAuthorizedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Not Authorized')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.lock_outline_rounded, size: 52, color: AppTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text(
                'Not Authorized',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navy),
              ),
              const SizedBox(height: 8),
              Text(
                'Your admin role doesn\'t have access to this section.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => context.go('/admin/dashboard'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

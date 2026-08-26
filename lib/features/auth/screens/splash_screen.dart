import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/auth/auth_storage.dart';

/// Splash screen that verifies stored JWT and routes to the correct home.
///
/// Shown at app startup. Reads the persisted token, validates expiry, decodes
/// [user_type], then navigates silently — the user never needs to interact here.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Defer navigation until after the first frame so GoRouter is settled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    try {
      // 1. Init the AuthNotifier — restores persisted state and validates expiry.
      await ref.read(authProvider.notifier).init();

      if (!mounted) return;

      final AuthState auth = ref.read(authProvider);

      if (!auth.isLoggedIn) {
        context.go('/login');
        return;
      }

      // 2. Double-check the raw token for expiry (belt-and-suspenders).
      final String? raw = await AuthStorage.getToken();
      if (!mounted) return;

      if (raw == null || raw.isEmpty || JwtDecoder.isExpired(raw)) {
        await ref.read(authProvider.notifier).logout();
        if (!mounted) return;
        context.go('/login');
        return;
      }

      // 3. Route by user_type decoded from JWT.
      _routeByUserType(auth.userType);
    } catch (_) {
      // Any unexpected error (storage failure, malformed token, etc.) —
      // clear state and send the user to login so they can start fresh.
      if (!mounted) return;
      try {
        await ref.read(authProvider.notifier).logout();
      } catch (_) {
        // Ignore secondary failure — just navigate.
      }
      if (!mounted) return;
      context.go('/login');
    }
  }

  void _routeByUserType(String? userType) {
    switch (userType) {
      case 'seeker':
        context.go('/seeker/home');
      case 'provider':
        // Phase 2 placeholder — route exists in router.
        context.go('/provider/home');
      case 'admin':
        context.go('/admin/dashboard');
      case 'portal_staff':
        context.go('/portal/dashboard');
      default:
        context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo mark
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.pest_control_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              // Wordmark
              const Text(
                'Pestify',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pest control, made easy',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

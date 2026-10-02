import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Polls [PortalApi.confirmSubscription] every 3 seconds (max 10 attempts)
/// after the checkout WebView reaches PayMongo's success redirect — mirrors
/// `lib/features/seeker/screens/payment_confirm_screen.dart`'s pattern.
/// Pops `true` once verified/activated, `false` on timeout.
class PortalSubscriptionConfirmScreen extends ConsumerStatefulWidget {
  const PortalSubscriptionConfirmScreen({super.key});

  @override
  ConsumerState<PortalSubscriptionConfirmScreen> createState() => _PortalSubscriptionConfirmScreenState();
}

class _PortalSubscriptionConfirmScreenState extends ConsumerState<PortalSubscriptionConfirmScreen> with SingleTickerProviderStateMixin {
  static const int _maxAttempts = 10;
  static const Duration _pollInterval = Duration(seconds: 3);

  Timer? _pollTimer;
  int _attempts = 0;
  _ScreenState _screenState = _ScreenState.polling;
  String? _pollErrorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_attempts >= _maxAttempts) {
      _pollTimer?.cancel();
      if (mounted) setState(() => _screenState = _ScreenState.timeout);
      return;
    }
    _attempts++;

    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).confirmSubscription();
      if (!mounted) return;

      if (result['verified'] == true) {
        _pollTimer?.cancel();
        setState(() => _screenState = _ScreenState.success);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        context.pop(true);
      }
      // Not yet verified — keep polling.
    } catch (_) {
      if (!mounted) return;
      setState(() => _pollErrorMessage = 'Payment check failed, retrying...');
    }
  }

  void _retryPolling() {
    setState(() {
      _attempts = 0;
      _screenState = _ScreenState.polling;
      _pollErrorMessage = null;
    });
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Subscription Confirmation')),
        body: SafeArea(
          child: switch (_screenState) {
            _ScreenState.polling => _PollingView(pulseAnimation: _pulseAnimation, attempts: _attempts, maxAttempts: _maxAttempts, errorMessage: _pollErrorMessage),
            _ScreenState.success => const _SuccessView(),
            _ScreenState.timeout => _TimeoutView(onRetry: _retryPolling),
          },
        ),
      ),
    );
  }
}

enum _ScreenState { polling, success, timeout }

class _PollingView extends StatelessWidget {
  const _PollingView({required this.pulseAnimation, required this.attempts, required this.maxAttempts, this.errorMessage});

  final Animation<double> pulseAnimation;
  final int attempts;
  final int maxAttempts;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScaleTransition(
              scale: pulseAnimation,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary.withValues(alpha: 0.12)),
                child: const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3)),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Confirming your payment...', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('This usually takes a few seconds. Please keep this screen open.', style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: attempts / maxAttempts,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text('Attempt $attempts of $maxAttempts', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 0.4)),
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(errorMessage!, style: TextStyle(fontSize: 11, color: Colors.orange[700], fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 28),
            const Text("You're Pro!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const SizedBox(height: 10),
            const Text('All portal features are now unlocked for your team.', style: TextStyle(fontSize: 13.5, color: AppTheme.textMuted, height: 1.5), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TimeoutView extends StatelessWidget {
  const _TimeoutView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.amber.withValues(alpha: 0.15)),
              child: const Icon(Icons.hourglass_empty_rounded, color: Colors.amber, size: 40),
            ),
            const SizedBox(height: 28),
            const Text('Payment Not Confirmed Yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.navy)),
            const SizedBox(height: 10),
            const Text(
              'We could not confirm your payment automatically. If you completed it, check back on this page shortly.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                onPressed: () => context.pop(false),
                child: const Text('Back to Subscription'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(onPressed: onRetry, child: const Text('Check Again')),
            ),
          ],
        ),
      ),
    );
  }
}

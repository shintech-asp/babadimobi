import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Payment Confirm Screen
///
/// Polls [SeekerApi.confirmPayment] every 3 seconds (max 10 attempts).
/// On verified response navigates to /seeker/bookings after a brief
/// success moment. Shows timeout guidance if polling exhausts.
///
/// GoRouter extra: bookingId (int)
class PaymentConfirmScreen extends ConsumerStatefulWidget {
  const PaymentConfirmScreen({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<PaymentConfirmScreen> createState() =>
      _PaymentConfirmScreenState();
}

class _PaymentConfirmScreenState extends ConsumerState<PaymentConfirmScreen>
    with SingleTickerProviderStateMixin {
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start polling immediately then on interval.
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
      if (mounted) {
        setState(() => _screenState = _ScreenState.timeout);
      }
      return;
    }
    _attempts++;

    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final Map<String, dynamic> result =
          await api.confirmPayment(widget.bookingId);

      if (!mounted) return;

      final bool verified =
          result['verified'] == true || result['status'] == 'accepted';

      if (verified) {
        _pollTimer?.cancel();
        setState(() => _screenState = _ScreenState.success);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        context.go('/seeker/bookings');
      }
      // Not yet verified — keep polling.
    } catch (_) {
      // Network hiccup — surface a transient message but keep polling.
      if (!mounted) return;
      setState(() => _pollErrorMessage = 'Payment check failed, retrying...');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Payment Confirmation'),
      ),
      body: SafeArea(
        child: switch (_screenState) {
          _ScreenState.polling => _PollingView(
              pulseAnimation: _pulseAnimation,
              attempts: _attempts,
              maxAttempts: _maxAttempts,
              errorMessage: _pollErrorMessage,
            ),
          _ScreenState.success => const _SuccessView(),
          _ScreenState.timeout => _TimeoutView(
              bookingId: widget.bookingId,
              onRetry: _retryPolling,
            ),
        },
      ),
    );
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
}

// ── State enum ────────────────────────────────────────────────────────────────

enum _ScreenState { polling, success, timeout }

// ── Child views ───────────────────────────────────────────────────────────────

class _PollingView extends StatelessWidget {
  const _PollingView({
    required this.pulseAnimation,
    required this.attempts,
    required this.maxAttempts,
    this.errorMessage,
  });

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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2D6A4F),
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Confirming your payment...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2D6A4F),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'This usually takes a few seconds. Please keep this screen open.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: attempts / maxAttempts,
              backgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF52B788)),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              'Attempt $attempts of $maxAttempts',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
            ),
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 14,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    errorMessage!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.orange[700],
                          fontStyle: FontStyle.italic,
                        ),
                  ),
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
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2D6A4F),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Payment Confirmed!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2D6A4F),
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your booking is confirmed. Redirecting to your bookings...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeoutView extends StatelessWidget {
  const _TimeoutView({
    required this.bookingId,
    required this.onRetry,
  });

  final int bookingId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.hourglass_empty_rounded,
                color: Colors.amber,
                size: 40,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Payment Pending',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'We could not confirm your payment automatically. '
              'Your booking may still be processing — check My Bookings in a moment.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => context.go('/seeker/bookings'),
                child: const Text('Go to My Bookings'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Check Again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

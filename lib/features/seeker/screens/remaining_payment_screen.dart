import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Fetches the remaining balance for a partially-paid booking and lets the
/// seeker pay via PayMongo (WebView).
///
/// Expected GoRouter extra:
/// ```dart
/// context.push('/seeker/remaining-payment', extra: {'bookingId': 42});
/// ```
class RemainingPaymentScreen extends ConsumerStatefulWidget {
  const RemainingPaymentScreen({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<RemainingPaymentScreen> createState() =>
      _RemainingPaymentScreenState();
}

class _RemainingPaymentScreenState
    extends ConsumerState<RemainingPaymentScreen> {
  Map<String, dynamic>? _paymentData;
  String? _errorMsg;
  bool _loadingData = true;
  bool _loadingPay = false;

  @override
  void initState() {
    super.initState();
    _fetchRemainingPayment();
  }

  Future<void> _fetchRemainingPayment() async {
    setState(() {
      _loadingData = true;
      _errorMsg = null;
    });

    try {
      final Map<String, dynamic> data = await ref
          .read(seekerApiProvider)
          .getRemainingPayment(widget.bookingId);
      if (!mounted) return;
      setState(() => _paymentData = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Could not load payment details. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _openPayment() async {
    final String? checkoutUrl =
        _paymentData?['checkout_url'] as String?;

    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment link unavailable. Please try again.')),
      );
      return;
    }

    setState(() => _loadingPay = true);

    // Navigate to the shared PaymentWebViewScreen.
    // It handles /payment-success.php detection and confirmPayment polling.
    if (!mounted) return;
    await context.push(
      '/seeker/payment',
      extra: <String, dynamic>{
        'checkoutUrl': checkoutUrl,
        'bookingId': widget.bookingId,
      },
    );

    if (!mounted) return;
    setState(() => _loadingPay = false);
    // Refresh after returning from the WebView in case payment completed.
    await _fetchRemainingPayment();
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF2D6A4F);
    const Color primaryLight = Color(0xFF52B788);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        title: const Text('Remaining Payment'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loadingData
            ? const Center(child: CircularProgressIndicator())
            : _errorMsg != null
                ? _ErrorView(message: _errorMsg!, onRetry: _fetchRemainingPayment)
                : _buildBody(context, cs, primary, primaryLight),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    Color primary,
    Color primaryLight,
  ) {
    final dynamic rawAmount = _paymentData?['amount'];
    final double amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '') ?? 0.0;

    final String? note = _paymentData?['note'] as String?;
    final bool isPaid = (_paymentData?['paid'] as bool?) ?? false;

    if (isPaid) {
      return _PaidView(primary: primary);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Text(
            'Balance due',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B4332),
              letterSpacing: -1,
              fontVariations: <FontVariation>[FontVariation('wght', 800)],
            ),
          ),

          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.45,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Divider ─────────────────────────────────────────────────────
          Divider(color: cs.outlineVariant.withValues(alpha: 0.4)),

          const SizedBox(height: 16),

          // ── Info row ─────────────────────────────────────────────────────
          _InfoRow(
            icon: Icons.receipt_long_rounded,
            label: 'Booking #',
            value: '#${widget.bookingId}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.payment_rounded,
            label: 'Method',
            value: (_paymentData?['payment_method'] as String?) ?? 'PayMongo',
          ),

          const Spacer(),

          // ── Pay Now ──────────────────────────────────────────────────────
          LoadingButton(
            label: 'Pay Now',
            isLoading: _loadingPay,
            onPressed: _openPayment,
          ),

          const SizedBox(height: 12),

          Center(
            child: Text(
              'Secured by PayMongo',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PaidView extends StatelessWidget {
  const _PaidView({required this.primary});

  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Payment complete',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your remaining balance has been settled.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}


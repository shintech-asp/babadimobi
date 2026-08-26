import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Payment screen — uses an embedded WebView on mobile, and opens a browser
/// tab on web (WebView is not available on Flutter web).
///
/// GoRouter extra must be Map<String, dynamic> with:
///   'checkout_url' — String
///   'booking_id'   — int
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({
    super.key,
    required this.checkoutUrl,
    required this.bookingId,
  });

  final String checkoutUrl;
  final int bookingId;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  // ── Mobile WebView state ────────────────────────────────────────────────────
  WebViewController? _controller;
  bool _isLoading = true;

  // ── Web browser state ───────────────────────────────────────────────────────
  bool _urlOpened = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
            onWebResourceError: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.contains('/payment-success.php')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    context.go('/seeker/payment-confirm', extra: widget.bookingId);
                  }
                });
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.checkoutUrl));
    }
  }

  Future<bool> _confirmLeave() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: const Text(
          'Going back will cancel this payment session. '
          'Your booking will remain pending.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? _buildWebFallback(context) : _buildMobileWebView(context);
  }

  // ── Mobile: embedded WebView ───────────────────────────────────────────────

  Widget _buildMobileWebView(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        final ctx = context;
        // ignore: use_build_context_synchronously
        if (await _confirmLeave() && mounted) ctx.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment'),
          leading: IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Cancel payment',
            onPressed: () async {
              final ctx = context;
              // ignore: use_build_context_synchronously
              if (await _confirmLeave() && mounted) ctx.pop();
            },
          ),
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.lock_outline, size: 18, color: Colors.white70),
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            WebViewWidget(controller: _controller!),
            if (_isLoading)
              Container(
                color: const Color(0xFFF8FAF8),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(
                        color: Color(0xFF2D6A4F),
                        strokeWidth: 2.5,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading secure payment page...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF2D6A4F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Web: open browser tab + manual confirmation ────────────────────────────

  Widget _buildWebFallback(BuildContext context) {
    const Color primary = Color(0xFF2D6A4F);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () async {
            final ctx = context;
            // ignore: use_build_context_synchronously
            if (await _confirmLeave() && mounted) ctx.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_new_rounded,
                  color: primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Secure payment',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your payment will open in a new browser tab via PayMongo. '
                'Complete the payment there, then come back here and tap '
                '"I\'ve paid" to confirm your booking.',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 32),

              // Open payment tab button
              if (!_urlOpened)
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open Payment Page'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ctx = context;
                    final Uri uri = Uri.parse(widget.checkoutUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (mounted) setState(() => _urlOpened = true);
                    } else {
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Could not open payment page.')),
                      );
                    }
                  },
                )
              else ...<Widget>[
                // Re-open link
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Re-open payment page'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ctx = context;
                    final Uri uri = Uri.parse(widget.checkoutUrl);
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open payment page.'),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Confirm payment button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    context.go('/seeker/payment-confirm', extra: widget.bookingId);
                  },
                  child: const Text(
                    "I've paid — confirm my booking",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              const Spacer(),

              Center(
                child: Text(
                  'Secured by PayMongo',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    letterSpacing: 0.3,
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

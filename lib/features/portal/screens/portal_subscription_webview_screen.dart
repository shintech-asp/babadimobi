import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Subscription checkout — embedded WebView on mobile, browser tab on web.
///
/// Both `success_url` (`provider-portal/subscription-success.php`) and
/// `cancel_url` (`provider-portal/subscriptions.php`) are gated by a
/// PHP-SESSION check (`includes/portal-auth.php`), which this WebView never
/// has (it only carries a JWT header) — letting either of them actually load
/// just bounces to the web login page. So, like the seeker payment WebView,
/// this screen intercepts navigation to both BEFORE they load
/// (`onNavigationRequest` + `NavigationDecision.prevent`) rather than
/// waiting for a page to finish loading: reaching success_url pops back to
/// the caller with `true` (which pushes a native confirm/poll screen backed
/// by `api/v1/portal/subscriptions/confirm.php`); reaching cancel_url pops
/// with `false` directly.
class PortalSubscriptionWebViewScreen extends StatefulWidget {
  const PortalSubscriptionWebViewScreen({super.key, required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<PortalSubscriptionWebViewScreen> createState() => _PortalSubscriptionWebViewScreenState();
}

class _PortalSubscriptionWebViewScreenState extends State<PortalSubscriptionWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
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
              if (request.url.contains('/subscription-success.php')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).pop(true);
                });
                return NavigationDecision.prevent;
              }
              if (request.url.contains('/subscriptions.php')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).pop(false);
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
        content: const Text('Going back will cancel this checkout session.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
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

  Widget _buildMobileWebView(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        final BuildContext ctx = context;
        if (await _confirmLeave() && mounted) Navigator.of(ctx).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Subscription Checkout'),
          leading: IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () async {
              final BuildContext ctx = context;
              if (await _confirmLeave() && mounted) Navigator.of(ctx).pop(false);
            },
          ),
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
                      CircularProgressIndicator(color: Color(0xFF2D6A4F), strokeWidth: 2.5),
                      SizedBox(height: 16),
                      Text('Loading secure payment page...', style: TextStyle(fontSize: 14, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebFallback(BuildContext context) {
    const Color primary = Color(0xFF2D6A4F);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        title: const Text('Subscription Checkout'),
        leading: IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop(false)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.open_in_new_rounded, color: primary, size: 36),
              ),
              const SizedBox(height: 24),
              const Text('Secure payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1B4332))),
              const SizedBox(height: 10),
              const Text(
                'Your payment will open in a new browser tab via PayMongo. Complete it there, then come back and tap "I\'ve paid" to confirm your subscription.',
                style: TextStyle(fontSize: 14, height: 1.55),
              ),
              const SizedBox(height: 32),
              if (!_urlOpened)
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open Payment Page'),
                  style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final Uri uri = Uri.parse(widget.checkoutUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (mounted) setState(() => _urlOpened = true);
                    }
                  },
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("I've paid", style: TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

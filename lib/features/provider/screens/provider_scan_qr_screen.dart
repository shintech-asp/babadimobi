import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Camera QR scanner (with a manual 6-char fallback) that advances a
/// `starting` booking to `on_going` via `scan-qr.php`.
///
/// Expected GoRouter extra:
/// ```dart
/// context.push('/provider/scan-qr', extra: {'availId': 42});
/// ```
class ProviderScanQrScreen extends ConsumerStatefulWidget {
  const ProviderScanQrScreen({super.key, this.availId});

  final int? availId;

  @override
  ConsumerState<ProviderScanQrScreen> createState() => _ProviderScanQrScreenState();
}

class _ProviderScanQrScreenState extends ConsumerState<ProviderScanQrScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );
  final TextEditingController _manualCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  /// Strips dashes/non-alphanumerics and uppercases — mirrors scan-qr.php's
  /// own `preg_replace('/[^A-Z0-9]/i', '', ...)`.
  String _clean(String raw) => raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  Future<void> _submitToken(String rawToken) async {
    if (_submitting) return;
    final String token = _clean(rawToken);
    if (token.length != 6) {
      setState(() => _error = 'The code must be exactly 6 characters.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> result = await ref.read(providerApiProvider).scanQr(token);
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Service started!'),
          backgroundColor: AppTheme.primary,
        ),
      );
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_submitting) return;
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _submitToken(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Scan Client QR Code')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MobileScanner(controller: _controller, onDetect: _onDetect),
                  IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (_submitting)
                    Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(color: Colors.white),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Point the camera at the client\'s QR code, or enter the code manually below.',
                      style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _manualCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 8,
                      inputFormatters: <TextInputFormatter>[_UpperCaseTextFormatter()],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Manual entry',
                        hintText: 'ABC-XYZ',
                        prefixIcon: const Icon(Icons.keyboard_outlined),
                        counterText: '',
                        errorText: _error,
                      ),
                      onChanged: (String _) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: _submitToken,
                    ),
                    const SizedBox(height: 16),
                    LoadingButton(
                      label: 'Start Service',
                      isLoading: _submitting,
                      onPressed: () => _submitToken(_manualCtrl.text),
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
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

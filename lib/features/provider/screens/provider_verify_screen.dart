import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Provider enters the SEEKER's control number (PCF-…), which the provider
/// received via notification / sees on the Request Detail screen, to
/// complete their side of the dual-verification handshake.
///
/// Expected GoRouter extra:
/// ```dart
/// context.push('/provider/verify', extra: {'availId': 42});
/// ```
class ProviderVerifyScreen extends ConsumerStatefulWidget {
  const ProviderVerifyScreen({super.key, required this.availId});

  final int availId;

  @override
  ConsumerState<ProviderVerifyScreen> createState() => _ProviderVerifyScreenState();
}

class _ProviderVerifyScreenState extends ConsumerState<ProviderVerifyScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _inlineError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _inlineError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final Map<String, dynamic> result = await ref.read(providerApiProvider).verifyCode(
            availId: widget.availId,
            controlNumber: _ctrl.text.trim(),
          );

      if (!context.mounted) return;
      final bool dual = result['dual_verified'] == true;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dual
                ? 'Both sides verified — service is ready to start.'
                : 'Code verified. Waiting for the client to verify their side.',
          ),
          backgroundColor: AppTheme.primary,
        ),
      );
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _inlineError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Enter Seeker Code')),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Dual verification',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.navy),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask the client to read their verification code aloud, then enter it below.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 24,
                    inputFormatters: <TextInputFormatter>[_UpperCaseTextFormatter()],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Client\'s code',
                      hintText: 'e.g. PCF-2026-4A9F2C',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      counterText: '',
                      errorText: _inlineError,
                    ),
                    onChanged: (String _) {
                      if (_inlineError != null) setState(() => _inlineError = null);
                    },
                    validator: (String? v) => (v == null || v.trim().length < 4) ? 'Please enter the code.' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 28),
                  LoadingButton(label: 'Confirm', isLoading: _loading, onPressed: _submit),
                ],
              ),
            ),
          ),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Seeker enters the control number the technician provides in person.
///
/// Expected GoRouter extra:
/// ```dart
/// context.push('/seeker/enter-cn', extra: {'availId': 42});
/// ```
class EnterCnScreen extends ConsumerStatefulWidget {
  const EnterCnScreen({super.key, required this.availId});

  final int availId;

  @override
  ConsumerState<EnterCnScreen> createState() => _EnterCnScreenState();
}

class _EnterCnScreenState extends ConsumerState<EnterCnScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _inlineError;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Clear any previous inline error before validating.
    setState(() => _inlineError = null);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      await ref.read(seekerApiProvider).verifyCn(
            availId: widget.availId,
            controlNumber: _ctrl.text.trim(),
          );

      if (!context.mounted) return;

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code verified! Service is starting.'),
          backgroundColor: Color(0xFF2D6A4F),
        ),
      );
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true); // pop with success signal
    } catch (e) {
      if (!context.mounted) return;
      setState(
        () => _inlineError =
            e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF2D6A4F);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        title: const Text('Enter Technician Code'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Text(
                    'Dual verification',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The technician will tell you their code in person. '
                    'Enter it below to confirm they are on-site.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: cs.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Illustration chip ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF52B788).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF52B788).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_pin_circle_rounded,
                          color: primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ask the technician for their 10-character code.',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Input ────────────────────────────────────────────────
                  TextFormField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 20,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                    ],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Enter technician code',
                      hintText: 'e.g. ABCD1234EF',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      counterText: '',
                      errorText: _inlineError,
                    ),
                    onChanged: (_) {
                      if (_inlineError != null) {
                        setState(() => _inlineError = null);
                      }
                    },
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the code.';
                      }
                      if (value.trim().length < 4) {
                        return 'Code seems too short.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),

                  const SizedBox(height: 32),

                  // ── Submit ───────────────────────────────────────────────
                  LoadingButton(
                    label: 'Confirm',
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forces all input to uppercase as the user types.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}


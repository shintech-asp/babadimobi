import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/features/auth/auth_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// OTP verification screen.
///
/// Receives [email] as a GoRouter query parameter (URI-decoded here).
/// The user enters the 6-digit code sent by the server after registration.
/// On success, routes to /login with a confirmation snackbar.
class OtpScreen extends ConsumerStatefulWidget {
  /// The email address to verify. Passed via GoRouter query param.
  const OtpScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _otpCtrl = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  /// Countdown seconds remaining before Resend is re-enabled.
  int _resendCooldown = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Cooldown timer ──────────────────────────────────────────────────────────

  void _startCooldown() {
    _resendCooldown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ── Verify ──────────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    final String otp = _otpCtrl.text.trim();
    setState(() => _errorMessage = null);

    if (otp.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your email');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      await ref.read(authApiProvider).verifyOtp(
            email: widget.email,
            otp: otp,
          );

      if (!mounted) return;

      // Show confirmation then go to login.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account verified — you can now sign in'),
        ),
      );
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isVerifying = false;
      });
    }
  }

  // ── Resend ──────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _errorMessage = null;
      _isResending = true;
    });

    try {
      // The backend's forgot-password endpoint also triggers an OTP email;
      // there is no separate resend endpoint in the current API contract.
      await ref.read(authApiProvider).forgotPassword(email: widget.email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent')),
      );
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    final bool canResend = _resendCooldown == 0 && !_isResending;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: cs.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ── Icon + heading ──────────────────────────────────────────────
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.mark_email_read_outlined,
                  color: cs.primary,
                  size: 28,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Check your email',
                style: tt.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(
                      text: widget.email,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Error banner ────────────────────────────────────────────────
              if (_errorMessage != null) ...[
                ErrorBanner(
                  message: _errorMessage!,
                  onDismiss: () => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 20),
              ],

              // ── OTP input ───────────────────────────────────────────────────
              TextFormField(
                controller: _otpCtrl,
                focusNode: _otpFocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                onFieldSubmitted: (_) => _verify(),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: tt.headlineSmall?.copyWith(
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Verification code',
                  hintText: '000000',
                  hintStyle: tt.headlineSmall?.copyWith(
                    letterSpacing: 8,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w400,
                  ),
                  counterText: '',
                ),
              ),

              const SizedBox(height: 28),

              // ── Verify button ───────────────────────────────────────────────
              LoadingButton(
                label: 'Verify',
                isLoading: _isVerifying,
                onPressed: _verify,
              ),

              const SizedBox(height: 24),

              // ── Resend row ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive the code?",
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_isResending)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  else if (canResend)
                    GestureDetector(
                      onTap: _resend,
                      child: Text(
                        'Resend',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Resend in ${_resendCooldown}s',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

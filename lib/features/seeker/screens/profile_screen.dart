import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Seeker profile screen — Spotify/Airbnb-style:
/// gradient navy hero with straddling avatar → white rounded content card.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loadingProfile = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _errorMsg;

  io.File? _pendingAvatar;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _errorMsg = null;
    });
    try {
      final Map<String, dynamic> data =
          await ref.read(seekerApiProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _profile = data;
        _firstNameCtrl.text = (data['first_name'] as String?) ?? '';
        _lastNameCtrl.text = (data['last_name'] as String?) ?? '';
        _phoneCtrl.text = (data['phone'] as String?) ?? '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Could not load profile. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final BuildContext ctx = context;
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (!mounted) return;
    if (picked == null) return;

    final io.File file = io.File(picked.path);
    setState(() {
      _pendingAvatar = file;
      _uploadingAvatar = true;
    });

    try {
      final Map<String, dynamic> updated =
          await ref.read(seekerApiProvider).updateProfile(avatar: file);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _pendingAvatar = null;
      });
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated.'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingAvatar = null);
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Photo upload failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final BuildContext ctx = context;
    FocusScope.of(ctx).unfocus();
    setState(() => _saving = true);

    try {
      final Map<String, dynamic> updated =
          await ref.read(seekerApiProvider).updateProfile(
                firstName: _firstNameCtrl.text.trim(),
                lastName: _lastNameCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
              );
      if (!ctx.mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Profile saved.'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(msg.isEmpty ? 'Save failed. Please try again.' : msg),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final BuildContext ctx = context;
    final bool? confirmed = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out',
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.navy),
        ),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: AppTheme.textMuted)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Log out',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (!ctx.mounted) return;
    ctx.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final double topPad = MediaQuery.of(context).padding.top;

    if (_loadingProfile) {
      return Scaffold(
        backgroundColor: AppTheme.navy,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        body: _ErrorView(message: _errorMsg!, onRetry: _loadProfile),
      );
    }

    const double heroHeight = 240;
    const double avatarRadius = 48.0;
    final double cardTop = topPad + heroHeight - 32;
    final double avatarTop = topPad + heroHeight - avatarRadius;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.navy,
        body: Stack(
          children: <Widget>[
            // ── Gradient hero ─────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad + heroHeight,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      AppTheme.navy,
                      Color(0xFF2C3E7A),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 16),
                      const Text(
                        'My Profile',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Name + email (avatar is positioned separately)
                      Text(
                        '${(_profile?['first_name'] as String?) ?? ''} ${(_profile?['last_name'] as String?) ?? ''}'
                            .trim(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (_profile?['email'] as String?) ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── White content card ────────────────────────────────────────
            Positioned(
              top: cardTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      24, avatarRadius + 20, 24, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // ── Section label ───────────────────────────────
                        const _SectionLabel('Personal Information'),
                        const SizedBox(height: 4),

                        // ── Settings-style field group ───────────────────
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppTheme.border, width: 1),
                          ),
                          child: Column(
                            children: <Widget>[
                              _SettingsField(
                                controller: _firstNameCtrl,
                                label: 'First Name',
                                icon: Icons.badge_outlined,
                                textCapitalization: TextCapitalization.words,
                                isFirst: true,
                                validator: (String? v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
                              ),
                              _SettingsField(
                                controller: _lastNameCtrl,
                                label: 'Last Name',
                                icon: Icons.badge_outlined,
                                textCapitalization: TextCapitalization.words,
                                validator: (String? v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
                              ),
                              _SettingsField(
                                controller: _phoneCtrl,
                                label: 'Phone Number',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                isLast: true,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Save button ──────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppTheme.primary.withValues(alpha: 0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Danger zone — Logout ─────────────────────────
                        const _SectionLabel('Account'),
                        const SizedBox(height: 4),

                        InkWell(
                          onTap: _logout,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5F5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFFFFD7D7), width: 1),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                            child: const Row(
                              children: <Widget>[
                                Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 20,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Log out',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Avatar (straddling the gradient/card seam) ────────────────
            Positioned(
              top: avatarTop,
              left: 0,
              right: 0,
              child: Center(
                child: _AvatarPicker(
                  profile: _profile,
                  pendingAvatar: _pendingAvatar,
                  uploading: _uploadingAvatar,
                  radius: avatarRadius,
                  onTap: _pickAndUploadAvatar,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar picker ─────────────────────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.profile,
    required this.pendingAvatar,
    required this.uploading,
    required this.radius,
    required this.onTap,
  });

  final Map<String, dynamic>? profile;
  final io.File? pendingAvatar;
  final bool uploading;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? avatarUrl = profile?['avatar'] as String?;
    final String firstName = (profile?['first_name'] as String?) ?? '';
    final String initials =
        firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: <Widget>[
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: _content(avatarUrl: avatarUrl, initials: initials),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content({required String? avatarUrl, required String initials}) {
    if (uploading) {
      return Container(
        color: AppTheme.primary.withValues(alpha: 0.12),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (pendingAvatar != null) {
      return Image.file(pendingAvatar!, fit: BoxFit.cover);
    }
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppTheme.primary.withValues(alpha: 0.12),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => _InitialsCircle(initials: initials),
      );
    }
    return _InitialsCircle(initials: initials);
  }
}

class _InitialsCircle extends StatelessWidget {
  const _InitialsCircle({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.primary, Color(0xFF48BB78)],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Settings-style field ──────────────────────────────────────────────────────

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.isFirst = false,
    this.isLast = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  textCapitalization: textCapitalization,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navy,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: 'Not set',
                    hintStyle: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                    filled: false,
                    errorStyle: const TextStyle(fontSize: 10),
                  ),
                  validator: validator,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.border.withValues(alpha: 0.7),
            indent: 46,
          ),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

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
          children: <Widget>[
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

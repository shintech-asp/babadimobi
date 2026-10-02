import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Provider profile & settings — company details (stored on `providers`) and
/// personal contact details (stored on `users`), which `user/profile.php`
/// splits apart server-side. Also holds the logout action.
class ProviderProfileScreen extends ConsumerStatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  ConsumerState<ProviderProfileScreen> createState() =>
      _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends ConsumerState<ProviderProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();

  Map<String, dynamic>? _profile;
  io.File? _newAvatar;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final List<io.File> _newPortfolioImages = <io.File>[];
  io.File? _newPortfolioVideo;
  bool _savingPortfolio = false;
  String? _portfolioError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _descCtrl.dispose();
    _radiusCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> p =
          await ref.read(providerApiProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _companyCtrl.text = p['company_name']?.toString() ?? '';
        _descCtrl.text = p['description']?.toString() ?? '';
        _radiusCtrl.text = p['service_radius']?.toString() ?? '';
        _firstNameCtrl.text = p['first_name']?.toString() ?? '';
        _lastNameCtrl.text = p['last_name']?.toString() ?? '';
        _phoneCtrl.text = p['phone']?.toString() ?? '';
        _addressCtrl.text = p['address']?.toString() ?? '';
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Company logo takes precedence over the personal avatar, falling back to
  /// initials when neither is set.
  String? get _avatarUrl {
    final Map<String, dynamic>? p = _profile;
    if (p == null) return null;
    final String logo = p['logo_url']?.toString() ?? '';
    final String personal = p['profile_image']?.toString() ?? '';
    return ApiEndpoints.resolveImageUrl(logo.isNotEmpty ? logo : personal);
  }

  Future<void> _pickAvatar() async {
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (!mounted || picked == null) return;
    setState(() => _newAvatar = io.File(picked.path));
  }

  Future<void> _pickPortfolioImages() async {
    final List<XFile> picked = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _newPortfolioImages.addAll(picked.map((XFile x) => io.File(x.path)));
    });
  }

  void _removeNewPortfolioImage(int index) {
    setState(() => _newPortfolioImages.removeAt(index));
  }

  Future<void> _pickPortfolioVideo() async {
    final XFile? picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (!mounted || picked == null) return;
    setState(() => _newPortfolioVideo = io.File(picked.path));
  }

  Future<void> _savePortfolio() async {
    if (_newPortfolioImages.isEmpty && _newPortfolioVideo == null) return;
    setState(() {
      _savingPortfolio = true;
      _portfolioError = null;
    });
    try {
      await ref.read(providerApiProvider).updateProfile(
            portfolioImages: _newPortfolioImages,
            portfolioVideo: _newPortfolioVideo,
          );
      if (!mounted) return;
      setState(() {
        _newPortfolioImages.clear();
        _newPortfolioVideo = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Portfolio updated'), backgroundColor: AppTheme.primary),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _portfolioError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingPortfolio = false);
    }
  }

  Future<void> _removePortfolioImage(int index) async {
    try {
      await ref.read(providerApiProvider).removePortfolioImage(index);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _portfolioError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(providerApiProvider).updateProfile(
            companyName: _companyCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            serviceRadius: int.tryParse(_radiusCtrl.text.trim()),
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            avatar: _newAvatar,
          );
      if (!mounted) return;
      setState(() => _newAvatar = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: AppTheme.primary,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_error != null) ...<Widget>[
                        ErrorBanner(
                          message: _error!,
                          onDismiss: () => setState(() => _error = null),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Center(
                        child: Column(
                          children: <Widget>[
                            _Avatar(
                              file: _newAvatar,
                              url: _avatarUrl,
                              fallback: _companyCtrl.text,
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: _pickAvatar,
                              icon: const Icon(Icons.photo_camera_outlined, size: 18),
                              label: const Text('Change photo'),
                            ),
                            Text(
                              _profile?['email']?.toString() ?? '',
                              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Business'),
                      _label('Company name'),
                      TextFormField(
                        controller: _companyCtrl,
                        decoration: const InputDecoration(hintText: 'Your business name'),
                        validator: (String? v) => (v == null || v.trim().isEmpty)
                            ? 'Company name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _label('About your business'),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'What your team specialises in',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _label('Service radius (km)'),
                      TextFormField(
                        controller: _radiusCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'e.g. 50'),
                        validator: (String? v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final int? n = int.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Enter a valid distance';
                          return null;
                        },
                      ),

                      const SizedBox(height: 28),
                      _sectionTitle('Portfolio Gallery'),
                      Text(
                        'Showcase photos and a video of your team\'s work — shown on your public profile.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 12),
                      if (_portfolioError != null) ...<Widget>[
                        ErrorBanner(
                          message: _portfolioError!,
                          onDismiss: () => setState(() => _portfolioError = null),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Builder(builder: (BuildContext context) {
                        final List<dynamic> existing =
                            (_profile?['portfolio_images'] as List<dynamic>?) ?? <dynamic>[];
                        final List<dynamic> existingVideos =
                            (_profile?['portfolio_videos'] as List<dynamic>?) ?? <dynamic>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (existing.isNotEmpty)
                              SizedBox(
                                height: 84,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: existing.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (BuildContext ctx, int i) {
                                    final String? url =
                                        ApiEndpoints.resolveImageUrl(existing[i].toString());
                                    return Stack(
                                      children: <Widget>[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: SizedBox(
                                            width: 76,
                                            height: 76,
                                            child: url != null
                                                ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                                                : Container(color: AppTheme.border),
                                          ),
                                        ),
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: GestureDetector(
                                            onTap: () => _removePortfolioImage(i),
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                  color: Colors.black54, shape: BoxShape.circle),
                                              padding: const EdgeInsets.all(2),
                                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            if (existing.isNotEmpty) const SizedBox(height: 10),
                            if (existingVideos.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(Icons.videocam, size: 16, color: AppTheme.primary),
                                    const SizedBox(width: 6),
                                    Text('Video attached', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                            SizedBox(
                              height: 76,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: <Widget>[
                                  ..._newPortfolioImages.asMap().entries.map((MapEntry<int, io.File> e) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Stack(
                                        children: <Widget>[
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.file(e.value, width: 76, height: 76, fit: BoxFit.cover),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: GestureDetector(
                                              onTap: () => _removeNewPortfolioImage(e.key),
                                              child: Container(
                                                decoration: const BoxDecoration(
                                                    color: Colors.black54, shape: BoxShape.circle),
                                                padding: const EdgeInsets.all(2),
                                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  GestureDetector(
                                    onTap: _pickPortfolioImages,
                                    child: Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppTheme.border),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.add_photo_alternate_outlined,
                                          color: AppTheme.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_newPortfolioVideo == null)
                              OutlinedButton.icon(
                                onPressed: _pickPortfolioVideo,
                                icon: const Icon(Icons.videocam_outlined),
                                label: Text(existingVideos.isNotEmpty ? 'Replace Video' : 'Add Video'),
                              )
                            else
                              Row(
                                children: <Widget>[
                                  const Icon(Icons.videocam, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _newPortfolioVideo!.path.split(io.Platform.pathSeparator).last,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _newPortfolioVideo = null),
                                  ),
                                ],
                              ),
                            if (_newPortfolioImages.isNotEmpty || _newPortfolioVideo != null) ...<Widget>[
                              const SizedBox(height: 12),
                              LoadingButton(
                                label: 'Save Portfolio',
                                isLoading: _savingPortfolio,
                                onPressed: _savePortfolio,
                              ),
                            ],
                          ],
                        );
                      }),

                      const SizedBox(height: 28),
                      _sectionTitle('Contact person'),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _label('First name'),
                                TextFormField(controller: _firstNameCtrl),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _label('Last name'),
                                TextFormField(controller: _lastNameCtrl),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _label('Phone'),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: '09XX XXX XXXX'),
                      ),
                      const SizedBox(height: 16),
                      _label('Address'),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(hintText: 'Office address'),
                      ),

                      const SizedBox(height: 28),
                      LoadingButton(
                        label: 'Save Changes',
                        isLoading: _saving,
                        onPressed: _save,
                      ),

                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Account',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.red[700],
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout_rounded, size: 18),
                                label: const Text('Log out'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red[700],
                                  side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.navy,
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.file, required this.url, required this.fallback});

  final io.File? file;
  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    const double size = 96;
    Widget child;

    if (file != null) {
      child = Image.file(file!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initials(),
      );
    } else {
      child = _initials();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _initials() {
    final String text = fallback.trim().isEmpty
        ? '?'
        : fallback
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((String w) => w[0].toUpperCase())
            .join();
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

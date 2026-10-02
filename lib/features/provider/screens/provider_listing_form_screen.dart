import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Create/Edit Listing — a single form. Pass [listingId] + [initialListing]
/// to edit; omit both to create.
///
/// There is no `provider/listings/show.php` on the backend, so editing
/// relies on the caller (My Listings screen) passing the already-fetched
/// listing row as [initialListing].
///
/// Pops `true` on success so the caller knows to refresh its list.
class ProviderListingFormScreen extends ConsumerStatefulWidget {
  const ProviderListingFormScreen({
    super.key,
    this.listingId,
    this.initialListing,
  });

  final int? listingId;
  final Map<String, dynamic>? initialListing;

  bool get isEdit => listingId != null;

  @override
  ConsumerState<ProviderListingFormScreen> createState() =>
      _ProviderListingFormScreenState();
}

// Must match service_listings.pricing_type's ENUM exactly.
const Map<String, String> _kPricingTypes = <String, String>{
  'fixed': 'Fixed Price',
  'per_sqft': 'Per Sq Ft',
  'hourly': 'Hourly',
  'custom': 'Custom',
};

class _ProviderListingFormScreenState
    extends ConsumerState<ProviderListingFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController();
  final TextEditingController _equipmentNotesCtrl = TextEditingController();

  String _durationUnit = 'hour';
  io.File? _newVideo;
  String? _existingVideoUrl;

  String _pricingType = 'fixed';
  int? _categoryId;
  bool _isEmergencyAvailable = false;
  // Locked on whenever _pricingType != 'fixed' — the final price for
  // Hourly/Custom/Per Sq Ft can't be known upfront, so those pricing models
  // always require an on-site inspection first (see the "Pricing Model"
  // entry in CLAUDE.md's Recent Work Log). Mirrors provider/services.php's
  // onPricingTypeChange() exactly; server also re-enforces this regardless
  // of what's posted (store.php/update.php), so this is UX only, not the
  // authoritative check.
  bool _requiresInspection = false;
  bool _replaceImages = false;

  final List<io.File> _newImages = <io.File>[];
  List<String> _existingImages = <String>[];

  List<dynamic> _categories = <dynamic>[];
  bool _loadingCategories = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? initial = widget.initialListing;
    if (initial != null) {
      _titleCtrl.text = initial['title']?.toString() ?? '';
      _descCtrl.text = initial['description']?.toString() ?? '';
      _priceCtrl.text = initial['price']?.toString() ?? '';
      final String pt = initial['pricing_type']?.toString() ?? 'fixed';
      _pricingType = _kPricingTypes.containsKey(pt) ? pt : 'fixed';
      _categoryId = int.tryParse(initial['category_id']?.toString() ?? '');
      _isEmergencyAvailable = initial['is_emergency_available'] == true ||
          initial['is_emergency_available'] == 1 ||
          initial['is_emergency_available'] == '1';
      _requiresInspection = _pricingType != 'fixed' ||
          initial['requires_inspection'] == true ||
          initial['requires_inspection'] == 1 ||
          initial['requires_inspection'] == '1';
      final dynamic imgs = initial['images'];
      _existingImages =
          imgs is List ? imgs.map((dynamic e) => e.toString()).toList() : <String>[];
      _durationCtrl.text = initial['duration']?.toString() ?? '';
      final String du = initial['duration_unit']?.toString() ?? 'hour';
      _durationUnit = <String>['minute', 'hour', 'day'].contains(du) ? du : 'hour';
      _equipmentNotesCtrl.text = initial['equipment_notes']?.toString() ?? '';
      final dynamic vids = initial['videos'];
      if (vids is List && vids.isNotEmpty) {
        _existingVideoUrl = ApiEndpoints.resolveImageUrl(vids.first.toString());
      }
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final List<dynamic> cats = await ref.read(providerApiProvider).getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _error = 'Could not load categories: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    _equipmentNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.map((XFile x) => io.File(x.path)));
    });
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  Future<void> _pickVideo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (!mounted || picked == null) return;
    setState(() => _newVideo = io.File(picked.path));
  }

  void _removeNewVideo() {
    setState(() => _newVideo = null);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }
    final int? duration = int.tryParse(_durationCtrl.text.trim());
    if (duration == null || duration <= 0) {
      setState(() => _error = 'Please enter a valid duration.');
      return;
    }

    setState(() => _saving = true);
    try {
      final ProviderApi api = ref.read(providerApiProvider);
      final double price = double.parse(_priceCtrl.text.trim());
      final String equipmentNotes = _equipmentNotesCtrl.text.trim();

      if (widget.isEdit) {
        await api.updateListing(
          id: widget.listingId!,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          price: price,
          pricingType: _pricingType,
          categoryId: _categoryId,
          isEmergencyAvailable: _isEmergencyAvailable,
          requiresInspection: _requiresInspection,
          duration: duration,
          durationUnit: _durationUnit,
          equipmentNotes: equipmentNotes,
          newImages: _newImages,
          replaceImages: _replaceImages,
          video: _newVideo,
        );
      } else {
        await api.createListing(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          price: price,
          pricingType: _pricingType,
          categoryId: _categoryId!,
          isEmergencyAvailable: _isEmergencyAvailable,
          requiresInspection: _requiresInspection,
          duration: duration,
          durationUnit: _durationUnit,
          equipmentNotes: equipmentNotes.isEmpty ? null : equipmentNotes,
          images: _newImages,
          video: _newVideo,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit ? 'Listing updated' : 'Listing created'),
          backgroundColor: AppTheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Listing' : 'Create Listing')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_error != null) ...<Widget>[
                  ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                  const SizedBox(height: 16),
                ],

                _label('Title'),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. General Pest Control'),
                  validator: (String? v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 16),

                _label('Description'),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Describe the service you offer'),
                  validator: (String? v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _label('Price (₱)'),
                          TextFormField(
                            controller: _priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '0.00'),
                            validator: (String? v) {
                              final double? p = double.tryParse((v ?? '').trim());
                              if (p == null || p <= 0) return 'Enter a valid price';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _label('Pricing Type'),
                          DropdownButtonFormField<String>(
                            initialValue: _pricingType,
                            items: _kPricingTypes.entries
                                .map((MapEntry<String, String> e) => DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.value),
                                    ))
                                .toList(),
                            onChanged: (String? v) => setState(() {
                              _pricingType = v ?? 'fixed';
                              // Auto-check and lock when non-fixed; re-enable
                              // as an independent, optional choice when
                              // switching back to Fixed (matches web exactly).
                              if (_pricingType != 'fixed') _requiresInspection = true;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _label('Category'),
                _loadingCategories
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(color: AppTheme.primary),
                      )
                    : DropdownButtonFormField<int>(
                        initialValue: _categoryId,
                        hint: const Text('Select a category'),
                        items: _categories.map((dynamic c) {
                          final Map<String, dynamic> cat = c as Map<String, dynamic>;
                          final int id = int.tryParse(cat['id']?.toString() ?? '') ?? 0;
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(cat['name']?.toString() ?? ''),
                          );
                        }).toList(),
                        onChanged: (int? v) => setState(() => _categoryId = v),
                      ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _label('How Long Does It Take?'),
                          TextFormField(
                            controller: _durationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'e.g. 2'),
                            validator: (String? v) {
                              final int? d = int.tryParse((v ?? '').trim());
                              if (d == null || d <= 0) return 'Enter a valid duration';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _label('Unit'),
                          DropdownButtonFormField<String>(
                            initialValue: _durationUnit,
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(value: 'minute', child: Text('Minutes')),
                              DropdownMenuItem<String>(value: 'hour', child: Text('Hours')),
                              DropdownMenuItem<String>(value: 'day', child: Text('Days')),
                            ],
                            onChanged: (String? v) => setState(() => _durationUnit = v ?? 'hour'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _label('Equipment & Tools Used'),
                TextFormField(
                  controller: _equipmentNotesCtrl,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Sprayer, fogger, bait stations',
                  ),
                ),
                const SizedBox(height: 4),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isEmergencyAvailable,
                  onChanged: (bool v) => setState(() => _isEmergencyAvailable = v),
                  activeThumbColor: AppTheme.primary,
                  title: const Text('Available for emergency booking', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Seekers can request this service as an urgent "now" booking', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 4),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _requiresInspection,
                  onChanged: _pricingType != 'fixed'
                      ? null
                      : (bool v) => setState(() => _requiresInspection = v),
                  activeThumbColor: AppTheme.primary,
                  title: const Text('Requires on-site inspection first', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    _pricingType != 'fixed'
                        ? 'Locked on — ${_kPricingTypes[_pricingType]} pricing always requires an inspection before the final price is set.'
                        : 'A technician inspects on-site and sets the final price before payment is collected.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),

                _label('Photos'),
                const SizedBox(height: 4),
                if (_existingImages.isNotEmpty) ...<Widget>[
                  Text(
                    _replaceImages
                        ? 'These will be replaced by the new photos you add below.'
                        : 'Current photos (new ones are added alongside these).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _existingImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (BuildContext ctx, int i) {
                        final String? url = ApiEndpoints.resolveImageUrl(_existingImages[i]);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: url != null
                                ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                                : Container(color: AppTheme.border),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _replaceImages,
                    onChanged: (bool? v) => setState(() => _replaceImages = v ?? false),
                    dense: true,
                    title: const Text('Replace all photos with the new ones', style: TextStyle(fontSize: 13)),
                  ),
                ],

                SizedBox(
                  height: 76,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      ..._newImages.asMap().entries.map((MapEntry<int, io.File> e) {
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
                                  onTap: () => _removeNewImage(e.key),
                                  child: Container(
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
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
                        onTap: _pickImages,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _label('Video (optional)'),
                const SizedBox(height: 4),
                if (_newVideo == null) ...<Widget>[
                  if (_existingVideoUrl != null) ...<Widget>[
                    Text(
                      'A video is already attached. Pick a new one to replace it.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                  ],
                  OutlinedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(_existingVideoUrl != null ? 'Replace Video' : 'Add Video'),
                  ),
                ] else ...<Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.videocam, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _newVideo!.path.split(io.Platform.pathSeparator).last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _removeNewVideo,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 28),
                LoadingButton(
                  label: widget.isEdit ? 'Save Changes' : 'Create Listing',
                  isLoading: _saving,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy),
        ),
      );
}

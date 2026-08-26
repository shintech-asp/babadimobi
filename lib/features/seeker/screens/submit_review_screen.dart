import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Submit a 1–5 star review with an optional photo for a completed booking.
///
/// Expected GoRouter extra:
/// ```dart
/// context.push('/seeker/submit-review', extra: {'availId': 42});
/// ```
class SubmitReviewScreen extends ConsumerStatefulWidget {
  const SubmitReviewScreen({super.key, required this.availId});

  final int availId;

  @override
  ConsumerState<SubmitReviewScreen> createState() => _SubmitReviewScreenState();
}

class _SubmitReviewScreenState extends ConsumerState<SubmitReviewScreen> {
  final TextEditingController _commentCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  int _rating = 0; // 0 = not yet selected
  io.File? _selectedImage;
  bool _loading = false;
  String? _ratingError;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1280,
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedImage = io.File(picked.path));
    }
  }

  void _removeImage() => setState(() => _selectedImage = null);

  Future<void> _submit() async {
    setState(() => _ratingError = null);

    // Rating is required — not covered by Form validation.
    if (_rating < 1) {
      setState(() => _ratingError = 'Please select a rating.');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    final ctx = context;

    try {
      await ref.read(seekerApiProvider).submitReview(
            availId: widget.availId,
            rating: _rating,
            comment: _commentCtrl.text.trim(),
            image: _selectedImage,
          );

      if (!ctx.mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Review submitted. Thank you!'),
          backgroundColor: Color(0xFF2D6A4F),
        ),
      );
      Navigator.of(ctx).pop(true);
    } catch (e) {
      if (!ctx.mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? 'Submission failed. Please try again.' : msg)),
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
        title: const Text('Leave a Review'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Star rating ──────────────────────────────────────────
                  Text(
                    'How was the service?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: RatingBar.builder(
                      initialRating: _rating.toDouble(),
                      minRating: 1,
                      direction: Axis.horizontal,
                      allowHalfRating: false,
                      itemCount: 5,
                      itemPadding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      itemBuilder: (context, _) => const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF4A261),
                      ),
                      onRatingUpdate: (double val) {
                        setState(() {
                          _rating = val.toInt();
                          _ratingError = null;
                        });
                      },
                    ),
                  ),
                  if (_ratingError != null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _ratingError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                  if (_rating > 0) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _ratingLabel(_rating),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFF4A261),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── Comment ──────────────────────────────────────────────
                  Text(
                    'Tell us more',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _commentCtrl,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Describe your experience — what went well, what could improve…',
                      alignLabelWithHint: true,
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please write a comment.';
                      }
                      if (value.trim().length < 10) {
                        return 'Please write at least 10 characters.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  // ── Photo ────────────────────────────────────────────────
                  Text(
                    'Add a photo (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_selectedImage != null) ...[
                    _ImagePreview(
                      file: _selectedImage!,
                      onRemove: _removeImage,
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (_selectedImage == null)
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose from gallery'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(
                          color: primary.withValues(alpha: 0.4),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // ── Submit ───────────────────────────────────────────────
                  LoadingButton(
                    label: 'Submit Review',
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

  String _ratingLabel(int rating) {
    return switch (rating) {
      1 => 'Poor',
      2 => 'Fair',
      3 => 'Good',
      4 => 'Very good',
      5 => 'Excellent',
      _ => '',
    };
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file, required this.onRemove});

  final io.File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


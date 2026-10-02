import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Submit (or resubmit) an inspection report for a `requires_inspection`
/// booking sitting at 'accepted' or 'revising' — mirrors
/// `provider/service-requests.php`'s "Submit/Resubmit Inspection Report"
/// modal. The only mobile entry point into the Inspection -> Agreement flow
/// — without this, a field tech assigned a requires_inspection booking was
/// a dead end (see CLAUDE.md's Inspection -> Agreement -> Working Date
/// design; the seeker's side of that flow is already built on mobile).
class ProviderSubmitInspectionScreen extends ConsumerStatefulWidget {
  const ProviderSubmitInspectionScreen({
    super.key,
    required this.requestId,
    required this.isRevising,
  });

  final int requestId;
  final bool isRevising;

  @override
  ConsumerState<ProviderSubmitInspectionScreen> createState() =>
      _ProviderSubmitInspectionScreenState();
}

class _ProviderSubmitInspectionScreenState
    extends ConsumerState<ProviderSubmitInspectionScreen> {
  late Future<Map<String, dynamic>> _future;
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();

  List<Map<String, dynamic>> _fieldStaff = <Map<String, dynamic>>[];
  int? _staffId;
  DateTime? _workingDate;
  io.File? _image;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final Map<String, dynamic> detail =
        await ref.read(providerApiProvider).getRequestDetail(widget.requestId);
    _fieldStaff = (detail['field_staff'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return detail;
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) {
      final XFile? fromGallery = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (fromGallery == null) return;
      if (!mounted) return;
      setState(() => _image = io.File(fromGallery.path));
      return;
    }
    if (!mounted) return;
    setState(() => _image = io.File(picked.path));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _workingDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _workingDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_image == null) {
      setState(() => _error = 'Please attach a photo from the inspection.');
      return;
    }
    if (_notesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what the inspection found.');
      return;
    }
    final double? price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid final price.');
      return;
    }
    if (_workingDate == null) {
      setState(() => _error = 'Please pick a proposed working date.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(providerApiProvider).submitInspectionReport(
            availId: widget.requestId,
            staffId: _staffId,
            notes: _notesCtrl.text.trim(),
            proposedPrice: price,
            proposedWorkingDate: DateFormat('yyyy-MM-dd').format(_workingDate!),
            image: _image!,
          );
      if (!mounted) return;
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
      appBar: AppBar(
        title: Text(widget.isRevising ? 'Resubmit Inspection Report' : 'Submit Inspection Report'),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ErrorBanner(
                    message: snapshot.error.toString().replaceFirst('Exception: ', ''),
                  ),
                ),
              );
            }

            final Map<String, dynamic> booking = snapshot.data ?? <String, dynamic>{};
            final String? changeNotes = booking['inspection_change_notes']?.toString();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_error != null) ...<Widget>[
                    ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                    const SizedBox(height: 16),
                  ],

                  if (widget.isRevising && changeNotes != null && changeNotes.isNotEmpty) ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        border: Border.all(color: const Color(0xFFFDBA74)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Seeker requested changes',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
                          ),
                          const SizedBox(height: 6),
                          Text(changeNotes, style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_fieldStaff.isNotEmpty) ...<Widget>[
                    _label('Field Technician'),
                    DropdownButtonFormField<int?>(
                      initialValue: _staffId,
                      hint: const Text('— Select (optional) —'),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem<int?>(value: null, child: Text('— None —')),
                        ..._fieldStaff.map((Map<String, dynamic> s) {
                          final int id = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                          return DropdownMenuItem<int?>(value: id, child: Text(s['full_name']?.toString() ?? ''));
                        }),
                      ],
                      onChanged: (int? v) => setState(() => _staffId = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _label('Inspection Photo *'),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _image == null
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.camera_alt_outlined, size: 28, color: AppTheme.textMuted),
                                  SizedBox(height: 6),
                                  Text('Tap to take/choose a photo', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                ],
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_image!, fit: BoxFit.cover, width: double.infinity, height: 160),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _label('Findings & Notes *'),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Describe the site condition, scope of work, and what the seeker should expect...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  _label('Final Price (₱) *'),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '0.00'),
                  ),
                  const SizedBox(height: 16),

                  _label('Proposed Working Date *'),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.textMuted),
                          const SizedBox(width: 10),
                          Text(
                            _workingDate == null
                                ? 'Select date'
                                : DateFormat('MMM d, yyyy').format(_workingDate!),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  LoadingButton(
                    label: widget.isRevising ? 'Resend to Seeker' : 'Send to Seeker',
                    isLoading: _saving,
                    onPressed: _submit,
                  ),
                ],
              ),
            );
          },
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

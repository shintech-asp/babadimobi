import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Provider proposes a new date/time for an accepted/preparing booking —
/// mirrors `provider/service-requests.php`'s inline "Request Reschedule"
/// form. The seeker then accepts or rejects it on their own booking screen
/// (already built on mobile — this screen is the other, previously-missing
/// half of the flow).
class ProviderRescheduleScreen extends ConsumerStatefulWidget {
  const ProviderRescheduleScreen({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<ProviderRescheduleScreen> createState() => _ProviderRescheduleScreenState();
}

class _ProviderRescheduleScreenState extends ConsumerState<ProviderRescheduleScreen> {
  final TextEditingController _reasonCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_date == null || _time == null) {
      setState(() => _error = 'Please choose a proposed date and time.');
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please add a short reason for the reschedule.');
      return;
    }

    setState(() => _saving = true);
    try {
      final String date = DateFormat('yyyy-MM-dd').format(_date!);
      final String time =
          '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
      await ref.read(providerApiProvider).requestReschedule(
            availId: widget.requestId,
            rescheduleDate: date,
            rescheduleTime: time,
            rescheduleReason: _reasonCtrl.text.trim(),
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
      appBar: AppBar(title: const Text('Request Reschedule')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: 16),
              ],

              _label('Proposed Date *'),
              GestureDetector(
                onTap: _pickDate,
                child: _pickerBox(
                  Icons.calendar_today_outlined,
                  _date == null ? 'Select date' : DateFormat('MMM d, yyyy').format(_date!),
                ),
              ),
              const SizedBox(height: 16),

              _label('Proposed Time *'),
              GestureDetector(
                onTap: _pickTime,
                child: _pickerBox(
                  Icons.access_time_outlined,
                  _time == null ? 'Select time' : _time!.format(context),
                ),
              ),
              const SizedBox(height: 16),

              _label('Reason *'),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Explain why the current booking date no longer works.',
                ),
              ),
              const SizedBox(height: 12),

              LoadingButton(
                label: 'Send Reschedule Request',
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerBox(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, String> _kUrgencyLabels = <String, String>{
  'flexible': 'No rush',
  'soon': 'Soon',
  'emergency': 'Emergency — ASAP',
};

const Map<String, String> _kPriorityLabels = <String, String>{
  'balanced': 'Balanced',
  'best_rated': 'Best rated',
  'best_value': 'Best value',
};

/// "Find My Match" — the DSS structured-filter form, mirroring the web's
/// `seeker/recommend.php` form fields exactly: free-text problem
/// description, category, budget, urgency, priority, city, eco preference.
/// Guest-accessible — the ranking endpoint requires no login.
///
/// Optional GoRouter extra: `{'categoryId': int}` to arrive pre-filtered
/// (used when tapping a category chip on the landing page).
class FindMyMatchScreen extends ConsumerStatefulWidget {
  const FindMyMatchScreen({super.key, this.initialCategoryId});

  final int? initialCategoryId;

  @override
  ConsumerState<FindMyMatchScreen> createState() => _FindMyMatchScreenState();
}

class _FindMyMatchScreenState extends ConsumerState<FindMyMatchScreen> {
  final TextEditingController _needTextCtrl = TextEditingController();
  final TextEditingController _budgetCtrl = TextEditingController();

  int? _categoryId;
  String _urgency = 'flexible';
  String _priority = 'balanced';
  String? _city;
  bool _ecoOnly = false;

  List<dynamic> _categories = <dynamic>[];
  List<String> _cities = <String>[];
  double? _minPrice;
  double? _maxPrice;
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
    _loadOptions();
  }

  @override
  void dispose() {
    _needTextCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final List<dynamic> cats = await api.getCategories();
      final Map<String, dynamic> opts = await api.getRecommendOptions();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _cities = (opts['cities'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList();
        _minPrice = opts['min_price'] == null ? null : double.tryParse(opts['min_price'].toString());
        _maxPrice = opts['max_price'] == null ? null : double.tryParse(opts['max_price'].toString());
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _error = 'Could not load form options: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final double? budget = _budgetCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_budgetCtrl.text.trim());

      final Map<String, dynamic> body = await ref.read(seekerApiProvider).getRecommendations(
            needText: _needTextCtrl.text.trim().isEmpty ? null : _needTextCtrl.text.trim(),
            categoryId: _categoryId,
            budgetMax: budget,
            urgency: _urgency,
            priority: _priority,
            ecoOnly: _ecoOnly,
            city: _city,
          );

      if (!mounted) return;
      context.push(
        '/recommend/results',
        extra: <String, dynamic>{
          'result': body,
          'budgetMax': budget,
          'urgency': _urgency,
          'city': _city,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Row(
          children: const <Widget>[
            Icon(Icons.auto_awesome_rounded, size: 18),
            SizedBox(width: 8),
            Text('Find My Match'),
          ],
        ),
      ),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Tell us what you need — we\'ll rank providers for you based on reviews, price, and reliability.',
                      style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 20),

                    if (_error != null) ...<Widget>[
                      ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                      const SizedBox(height: 16),
                    ],

                    _label('What\'s the problem?', hint: '(optional — English or Tagalog)'),
                    TextField(
                      controller: _needTextCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. I have termites in my kitchen / May anay sa kusina',
                      ),
                    ),
                    const SizedBox(height: 20),

                    _label('Category', hint: '(pick one, or let your description decide)'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ..._categories.map((dynamic c) {
                          final Map<String, dynamic> cat = c as Map<String, dynamic>;
                          final int id = int.tryParse(cat['id']?.toString() ?? '') ?? 0;
                          return _Chip(
                            label: cat['name']?.toString() ?? '',
                            selected: _categoryId == id,
                            onTap: () => setState(() => _categoryId = _categoryId == id ? null : id),
                          );
                        }),
                        _Chip(
                          label: 'Not sure',
                          selected: _categoryId == null,
                          onTap: () => setState(() => _categoryId = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _label('Budget — most I\'d like to pay', hint: '(optional)'),
                    TextField(
                      controller: _budgetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'e.g. 3000'),
                    ),
                    if (_minPrice != null && _maxPrice != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        'Typical range on Pestify: ₱${_minPrice!.toStringAsFixed(0)} – ₱${_maxPrice!.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                    ],
                    const SizedBox(height: 20),

                    _label('How urgent is this?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kUrgencyLabels.entries
                          .map((MapEntry<String, String> e) => _Chip(
                                label: e.value,
                                selected: _urgency == e.key,
                                onTap: () => setState(() => _urgency = e.key),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),

                    _label('What matters most to you?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kPriorityLabels.entries
                          .map((MapEntry<String, String> e) => _Chip(
                                label: e.value,
                                selected: _priority == e.key,
                                onTap: () => setState(() => _priority = e.key),
                              ))
                          .toList(),
                    ),
                    if (_urgency == 'emergency') ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        'Since this is an emergency, we\'ll prioritize providers who can respond fastest regardless of this choice.',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                    ],
                    const SizedBox(height: 20),

                    _label('City', hint: '(optional)'),
                    DropdownButtonFormField<String?>(
                      initialValue: _city,
                      hint: const Text('Any city'),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(value: null, child: Text('Any city')),
                        ..._cities.map((String c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                      ],
                      onChanged: (String? v) => setState(() => _city = v),
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _ecoOnly,
                      onChanged: (bool v) => setState(() => _ecoOnly = v),
                      activeThumbColor: AppTheme.primary,
                      title: const Text('Prefer eco-friendly providers', style: TextStyle(fontSize: 14)),
                    ),

                    const SizedBox(height: 24),
                    LoadingButton(
                      label: 'Find My Match',
                      isLoading: _submitting,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String text, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy),
            children: <InlineSpan>[
              TextSpan(text: text),
              if (hint != null)
                TextSpan(
                  text: ' $hint',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: AppTheme.textMuted),
                ),
            ],
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.navy,
          ),
        ),
      ),
    );
  }
}

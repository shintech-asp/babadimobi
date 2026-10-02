import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

const Map<String, String> _kPricingTypeLabels = <String, String>{
  'fixed': 'Fixed Price',
  'per_sqft': 'Per Sq Ft',
  'hourly': 'Hourly',
  'custom': 'Custom',
};

/// CRM service catalog management — mirrors `provider-portal/crm-services.php`.
/// Services created/edited here are the same unified `services` table used
/// by the web booking flow and the direct provider app (see CLAUDE.md's
/// "services and service_listings centralized" log entry) — fully Pro-gated.
class PortalCrmServicesScreen extends ConsumerStatefulWidget {
  const PortalCrmServicesScreen({super.key});

  @override
  ConsumerState<PortalCrmServicesScreen> createState() => _PortalCrmServicesScreenState();
}

class _PortalCrmServicesScreenState extends ConsumerState<PortalCrmServicesScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getCrmServices(status: _statusFilter);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refresh() async {
    final Future<Map<String, dynamic>> next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  void _setFilter(String? status) {
    setState(() => _statusFilter = status);
    _refresh();
  }

  Future<void> _openAddForm() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _ServiceFormSheet(),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openEditForm(Map<String, dynamic> row) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _ServiceFormSheet(service: row),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Services')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            final String msg = snapshot.error.toString().replaceFirst('Exception: ', '');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(msg, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (isProError(msg))
                      ElevatedButton(
                        onPressed: () => context.push('/portal/subscription'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                        child: const Text('Upgrade to Pro'),
                      )
                    else
                      OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final List<dynamic> services = body['data'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: const Text('All'), selected: _statusFilter == null, onSelected: (_) => _setFilter(null)),
                    ChoiceChip(label: const Text('Active'), selected: _statusFilter == 'active', onSelected: (_) => _setFilter('active')),
                    ChoiceChip(label: const Text('Inactive'), selected: _statusFilter == 'inactive', onSelected: (_) => _setFilter('inactive')),
                  ],
                ),
                const SizedBox(height: 16),
                if (services.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No services found.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...services.map((dynamic s) => _ServiceRow(
                        row: s as Map<String, dynamic>,
                        peso: peso,
                        onTap: () => _openEditForm(s),
                      )),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.row, required this.peso, required this.onTap});
  final Map<String, dynamic> row;
  final NumberFormat peso;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = row['status']?.toString() == 'active';
    final String pricingType = row['pricing_type']?.toString() ?? 'fixed';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: ListTile(
        onTap: onTap,
        title: Text(row['title']?.toString() ?? '', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text(
          '${row['category_name'] ?? 'Uncategorized'} · ${_kPricingTypeLabels[pricingType] ?? pricingType}${row['avg_rating'] != null ? ' · ★ ${row['avg_rating']} (${row['review_count']})' : ''}',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(peso.format(row['price'] ?? 0), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: (active ? AppTheme.primary : AppTheme.textMuted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: active ? AppTheme.primary : AppTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceFormSheet extends ConsumerStatefulWidget {
  const _ServiceFormSheet({this.service});
  final Map<String, dynamic>? service;

  @override
  ConsumerState<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends ConsumerState<_ServiceFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _priceCtrl;
  String _pricingType = 'fixed';
  int? _categoryId;
  bool _isEmergency = false;
  bool _requiresInspection = false;
  bool _active = true;
  List<dynamic> _categories = <dynamic>[];
  bool _loadingCategories = true;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.service != null;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? s = widget.service;
    _titleCtrl = TextEditingController(text: s?['title']?.toString() ?? '');
    _descriptionCtrl = TextEditingController(text: s?['description']?.toString() ?? '');
    _priceCtrl = TextEditingController(text: (s?['price'] as num?)?.toString() ?? '');
    _pricingType = _kPricingTypeLabels.containsKey(s?['pricing_type']?.toString()) ? s!['pricing_type'].toString() : 'fixed';
    _categoryId = int.tryParse(s?['category_id']?.toString() ?? '');
    _isEmergency = s?['is_emergency_available'] == true;
    _active = (s?['status']?.toString() ?? 'active') == 'active';
    // Read the real stored value (now that services/index.php actually
    // selects it) rather than guessing from pricing_type — a Fixed-price
    // service can legitimately have opted into inspection for unrelated
    // reasons, and guessing silently turned it back off on every edit.
    _requiresInspection = _pricingType != 'fixed' || (s?['requires_inspection'] == true);
    _loadCategories();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
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
        _error = 'Could not load categories: ${e.toString().replaceFirst('Exception: ', '')}';
        _loadingCategories = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String title = _titleCtrl.text.trim();
    final String description = _descriptionCtrl.text.trim();
    final num? price = num.tryParse(_priceCtrl.text.trim());
    if (title.isEmpty || description.isEmpty || price == null || price <= 0 || _categoryId == null) {
      setState(() => _error = 'Please fill in title, description, a valid price, and category.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await ref.read(portalApiProvider).updateCrmService(
              id: (widget.service!['id'] as num).toInt(),
              title: title,
              description: description,
              price: price,
              pricingType: _pricingType,
              status: _active ? 'active' : 'inactive',
              isEmergency: _isEmergency,
              requiresInspection: _requiresInspection,
            );
      } else {
        await ref.read(portalApiProvider).createCrmService(
              title: title,
              description: description,
              price: price,
              pricingType: _pricingType,
              categoryId: _categoryId!,
              isEmergency: _isEmergency,
              requiresInspection: _requiresInspection,
            );
      }
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(_isEditing ? 'Edit Service' : 'Add Service', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 16),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                if (isProError(_error!)) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
                ],
                const SizedBox(height: 14),
              ],
              const Text('Title', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _titleCtrl),
              const SizedBox(height: 14),
              const Text('Description', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _descriptionCtrl, maxLines: 3),
              const SizedBox(height: 14),
              if (!_isEditing) ...<Widget>[
                const Text('Category', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                const SizedBox(height: 6),
                _loadingCategories
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator())
                    : DropdownButtonFormField<int>(
                        initialValue: _categoryId,
                        hint: const Text('Select category'),
                        isExpanded: true,
                        items: _categories.map((dynamic c) {
                          final Map<String, dynamic> cat = c as Map<String, dynamic>;
                          // categories/index.php returns every column as a
                          // raw PDO string (no int cast), so `as num` throws
                          // here every time — matches the defensive parse
                          // already used by provider_listing_form_screen.dart
                          // for this same endpoint.
                          final int catId = int.tryParse(cat['id']?.toString() ?? '') ?? 0;
                          return DropdownMenuItem<int>(value: catId, child: Text(cat['name']?.toString() ?? ''));
                        }).toList(),
                        onChanged: (int? v) => setState(() => _categoryId = v),
                      ),
                const SizedBox(height: 14),
              ],
              const Text('Price (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 14),
              const Text('Pricing Model', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _pricingType,
                items: _kPricingTypeLabels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (String? v) {
                  setState(() {
                    _pricingType = v ?? 'fixed';
                    if (_pricingType != 'fixed') _requiresInspection = true;
                  });
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Requires On-Site Inspection First', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                subtitle: Text(
                  _pricingType != 'fixed'
                      ? 'Locked on — ${_kPricingTypeLabels[_pricingType]} pricing always requires an inspection before the final price is set.'
                      : 'Optional for Fixed pricing.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                value: _requiresInspection,
                activeThumbColor: AppTheme.primary,
                onChanged: _pricingType != 'fixed' ? null : (bool v) => setState(() => _requiresInspection = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency Service Available', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                value: _isEmergency,
                activeThumbColor: AppTheme.primary,
                onChanged: (bool v) => setState(() => _isEmergency = v),
              ),
              if (_isEditing)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                  value: _active,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (bool v) => setState(() => _active = v),
                ),
              const SizedBox(height: 14),
              LoadingButton(label: _isEditing ? 'Save Changes' : 'Create Service', isLoading: _saving, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

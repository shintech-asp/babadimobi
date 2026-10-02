import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// "Prepare Booking" / "Edit Equipment & Staff" — assigns a field
/// technician, an optional companion (co-staff), and equipment/consumables
/// to a booking, mirroring the web's identical modal in
/// `provider/service-requests.php` / `provider-portal/my-services.php`.
///
/// [isEdit] = false: the one-shot `accepted` -> `preparing` trigger.
/// [isEdit] = true: re-opens an already-`preparing` booking to change its
/// assignment — the server (`prepareAvailedBooking()`) excludes this
/// booking's own current holdings from the availability check either way,
/// so quantities can be freely adjusted up or down.
///
/// Pops `true` on success so the caller (ProviderRequestDetailScreen) knows
/// to refresh.
class ProviderPrepareBookingScreen extends ConsumerStatefulWidget {
  const ProviderPrepareBookingScreen({
    super.key,
    required this.requestId,
    required this.isEdit,
  });

  final int requestId;
  final bool isEdit;

  @override
  ConsumerState<ProviderPrepareBookingScreen> createState() =>
      _ProviderPrepareBookingScreenState();
}

class _ProviderPrepareBookingScreenState
    extends ConsumerState<ProviderPrepareBookingScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _fieldStaff = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _inventory = <Map<String, dynamic>>[];
  int? _staffId;
  int? _companionId;
  final TextEditingController _notesCtrl = TextEditingController();
  final Map<int, TextEditingController> _qtyControllers =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final TextEditingController c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final Map<String, dynamic> detail =
        await ref.read(providerApiProvider).getRequestDetail(widget.requestId);

    _fieldStaff = (detail['field_staff'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _inventory = (detail['inventory'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final Map<int, int> heldById = <int, int>{};
    if (widget.isEdit) {
      _staffId = int.tryParse(detail['assigned_employee_id']?.toString() ?? '');
      if (_staffId == 0) _staffId = null;
      _companionId = int.tryParse(detail['companion_employee_id']?.toString() ?? '');
      if (_companionId == 0) _companionId = null;
      _notesCtrl.text = detail['operations_notes']?.toString() ?? '';

      for (final List<dynamic>? list in <List<dynamic>?>[
        detail['assigned_equipment'] as List<dynamic>?,
        detail['assigned_consumables'] as List<dynamic>?,
      ]) {
        for (final dynamic raw in list ?? <dynamic>[]) {
          final Map<String, dynamic> item = Map<String, dynamic>.from(raw as Map);
          final int id = int.tryParse(item['inventory_item_id']?.toString() ?? '') ?? 0;
          final int qty = int.tryParse(item['quantity_needed']?.toString() ?? '') ?? 0;
          if (id > 0) heldById[id] = qty;
        }
      }
    }

    for (final Map<String, dynamic> item in _inventory) {
      final int id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
      final int held = heldById[id] ?? 0;
      _qtyControllers[id] = TextEditingController(text: held > 0 ? held.toString() : '0');
    }

    return detail;
  }

  int _availableNow(Map<String, dynamic> item) {
    // available_now already excludes this booking's own usage (server-side,
    // via getCheckedOutQuantity()'s $excludeAvailedId) — no further
    // client-side adjustment needed here, unlike the web version which
    // computes this without a per-booking exclusion and adjusts in JS.
    return int.tryParse(item['available_now']?.toString() ?? '') ?? 0;
  }

  void _bumpQty(int itemId, int delta, int max) {
    final TextEditingController c = _qtyControllers[itemId]!;
    final int current = int.tryParse(c.text) ?? 0;
    final int next = (current + delta).clamp(0, max);
    setState(() => c.text = next.toString());
  }

  Future<void> _submit() async {
    if (_staffId == null) {
      setState(() => _error = 'Please assign a field technician.');
      return;
    }
    if (_companionId != null && _companionId == _staffId) {
      setState(() => _error = 'Companion must be a different technician than the primary assignee.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });

    final List<Map<String, int>> equipment = <Map<String, int>>[];
    final List<Map<String, int>> consumables = <Map<String, int>>[];
    for (final Map<String, dynamic> item in _inventory) {
      final int id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
      final int qty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
      if (qty <= 0) continue;
      final Map<String, int> entry = <String, int>{
        'inventory_item_id': id,
        'quantity_needed': qty,
      };
      if (item['item_type'] == 'equipment') {
        equipment.add(entry);
      } else {
        consumables.add(entry);
      }
    }

    try {
      await ref.read(providerApiProvider).prepareBooking(
            id: widget.requestId,
            staffId: _staffId!,
            companionId: _companionId,
            equipment: equipment,
            consumables: consumables,
            notes: _notesCtrl.text.trim(),
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
        title: Text(widget.isEdit ? 'Edit Equipment & Staff' : 'Prepare Booking'),
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

            final List<Map<String, dynamic>> equipmentItems =
                _inventory.where((Map<String, dynamic> i) => i['item_type'] == 'equipment').toList();
            final List<Map<String, dynamic>> consumableItems =
                _inventory.where((Map<String, dynamic> i) => i['item_type'] == 'consumable').toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_error != null) ...<Widget>[
                    ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                    const SizedBox(height: 16),
                  ],

                  _label('Field Technician *'),
                  _fieldStaff.isEmpty
                      ? _warningBox(
                          'No field technicians yet. Add an employee with Staff Type "Field Technician" in the provider portal\'s HR module.',
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _staffId,
                          hint: const Text('Select field technician'),
                          items: _fieldStaff.map((Map<String, dynamic> s) {
                            final int id = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text(s['full_name']?.toString() ?? ''),
                            );
                          }).toList(),
                          onChanged: (int? v) => setState(() => _staffId = v),
                        ),
                  const SizedBox(height: 16),

                  if (_fieldStaff.length > 1) ...<Widget>[
                    _label('Companion (optional co-staff)'),
                    DropdownButtonFormField<int?>(
                      initialValue: _companionId,
                      hint: const Text('— None —'),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem<int?>(value: null, child: Text('— None —')),
                        ..._fieldStaff.map((Map<String, dynamic> s) {
                          final int id = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                          return DropdownMenuItem<int?>(
                            value: id,
                            child: Text(s['full_name']?.toString() ?? ''),
                          );
                        }),
                      ],
                      onChanged: (int? v) => setState(() => _companionId = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _label('Equipment'),
                  if (equipmentItems.isEmpty)
                    const Text('No equipment in inventory.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
                  else
                    ...equipmentItems.map((Map<String, dynamic> item) => _qtyRow(item)),
                  const SizedBox(height: 16),

                  _label('Consumables'),
                  if (consumableItems.isEmpty)
                    const Text('No consumables in inventory.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
                  else
                    ...consumableItems.map((Map<String, dynamic> item) => _qtyRow(item)),
                  const SizedBox(height: 16),

                  _label('Operations Notes'),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Anything the other tech/owner should know...',
                    ),
                  ),
                  const SizedBox(height: 28),

                  LoadingButton(
                    label: widget.isEdit ? 'Save Changes' : 'Save & Set to Preparing',
                    isLoading: _saving,
                    onPressed: _fieldStaff.isEmpty ? null : _submit,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _qtyRow(Map<String, dynamic> item) {
    final int id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final int max = _availableNow(item);
    final int owned = int.tryParse(item['quantity_available']?.toString() ?? '') ?? 0;
    final String unit = item['unit']?.toString() ?? '';
    final TextEditingController ctrl = _qtyControllers[id]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item['item_name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  item['item_type'] == 'equipment'
                      ? 'Available now: $max of $owned owned $unit'
                      : 'Available: $owned $unit',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: () => _bumpQty(id, -1, max),
          ),
          SizedBox(
            width: 36,
            child: Text(
              ctrl.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => _bumpQty(id, 1, max),
          ),
        ],
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

  Widget _warningBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFDBA74)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF9A3412), fontSize: 13)),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';
import 'package:pestify_flutter/shared/utils/pro_gate.dart';
import 'package:pestify_flutter/shared/widgets/error_banner.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';

/// Inventory (equipment + consumables) register — mirrors
/// `provider-portal/inventory.php`. Fully Pro-gated end-to-end. Adding
/// quantity is a separate Restock action (never a plain edit) so every
/// quantity increase is traceable and logged as an expense — see
/// `includes/inventory_expense_helper.php`.
class PortalInventoryScreen extends ConsumerStatefulWidget {
  const PortalInventoryScreen({super.key});

  @override
  ConsumerState<PortalInventoryScreen> createState() => _PortalInventoryScreenState();
}

class _PortalInventoryScreenState extends ConsumerState<PortalInventoryScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _typeFilter;
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getInventory(itemType: _typeFilter, lowStockOnly: _lowStockOnly);
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

  void _setTypeFilter(String? type) {
    setState(() => _typeFilter = type);
    _refresh();
  }

  void _toggleLowStock() {
    setState(() => _lowStockOnly = !_lowStockOnly);
    _refresh();
  }

  Future<void> _openAddForm() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _InventoryItemSheet(),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openManageSheet(Map<String, dynamic> row) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _ManageInventoryItemSheet(item: row),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Inventory')),
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
          final List<dynamic> items = body['data'] as List<dynamic>? ?? <dynamic>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: const Text('All'), selected: _typeFilter == null, onSelected: (_) => _setTypeFilter(null)),
                    ChoiceChip(label: const Text('Equipment'), selected: _typeFilter == 'equipment', onSelected: (_) => _setTypeFilter('equipment')),
                    ChoiceChip(label: const Text('Consumable'), selected: _typeFilter == 'consumable', onSelected: (_) => _setTypeFilter('consumable')),
                    FilterChip(
                      label: const Text('Low Stock'),
                      selected: _lowStockOnly,
                      onSelected: (_) => _toggleLowStock(),
                      selectedColor: Colors.red.withValues(alpha: 0.12),
                      checkmarkColor: Colors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No inventory items found.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...items.map((dynamic it) => _InventoryRow(
                        item: it as Map<String, dynamic>,
                        onTap: () => _openManageSheet(it),
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
        label: const Text('Add Item'),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isLowStock = item['is_low_stock'] == true;
    final bool isEquipment = item['item_type']?.toString() == 'equipment';
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final num availableNow = (item['available_now'] as num?) ?? 0;
    final num checkedOut = (item['checked_out'] as num?) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLowStock ? Colors.red.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(item['item_name']?.toString() ?? '', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        subtitle: Text(
          'Ref: ${item['reference_no'] ?? '—'} · ${peso.format(item['unit_price'] ?? 0)}/${item['unit'] ?? 'unit'}${isEquipment ? ' · $checkedOut checked out' : ''}',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text('$availableNow', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isLowStock ? Colors.red : AppTheme.navy)),
            if (isLowStock) const Text('Low stock', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

const List<MapEntry<String, String>> _kItemTypeOptions = <MapEntry<String, String>>[
  MapEntry<String, String>('equipment', 'Equipment'),
  MapEntry<String, String>('consumable', 'Consumable'),
];

class _InventoryItemSheet extends ConsumerStatefulWidget {
  const _InventoryItemSheet();

  @override
  ConsumerState<_InventoryItemSheet> createState() => _InventoryItemSheetState();
}

class _InventoryItemSheetState extends ConsumerState<_InventoryItemSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _refCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '0');
  final TextEditingController _unitCtrl = TextEditingController();
  final TextEditingController _reorderCtrl = TextEditingController(text: '5');
  final TextEditingController _supplierCtrl = TextEditingController();
  String _itemType = 'equipment';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _refCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _reorderCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String name = _nameCtrl.text.trim();
    final String referenceNo = _refCtrl.text.trim();
    final num? price = num.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty || referenceNo.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Please fill in item name, reference no., and a positive unit price.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).addInventoryItem(
            itemName: name,
            referenceNo: referenceNo,
            itemType: _itemType,
            unitPrice: price,
            quantityAvailable: int.tryParse(_qtyCtrl.text.trim()) ?? 0,
            unit: _unitCtrl.text.trim(),
            reorderThreshold: int.tryParse(_reorderCtrl.text.trim()) ?? 5,
            supplierName: _supplierCtrl.text.trim(),
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
              const Text('Add Inventory Item', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 16),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                if (isProError(_error!)) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.push('/portal/subscription'), child: const Text('Upgrade to Pro →')),
                ],
                const SizedBox(height: 14),
              ],
              const Text('Item Name', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _nameCtrl),
              const SizedBox(height: 14),
              const Text('Reference No.', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _refCtrl, decoration: const InputDecoration(hintText: 'SKU, PO number, or supplier reference')),
              const SizedBox(height: 14),
              const Text('Item Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _itemType,
                items: _kItemTypeOptions.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (String? v) => setState(() => _itemType = v ?? 'equipment'),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Unit Price (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Starting Qty', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _qtyCtrl, keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Unit (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _unitCtrl, decoration: const InputDecoration(hintText: 'pcs, liters')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Reorder At', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _reorderCtrl, keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Supplier (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _supplierCtrl),
              const SizedBox(height: 20),
              LoadingButton(label: 'Save Item', isLoading: _saving, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageInventoryItemSheet extends ConsumerStatefulWidget {
  const _ManageInventoryItemSheet({required this.item});
  final Map<String, dynamic> item;

  @override
  ConsumerState<_ManageInventoryItemSheet> createState() => _ManageInventoryItemSheetState();
}

class _ManageInventoryItemSheetState extends ConsumerState<_ManageInventoryItemSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _openEdit() async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _EditInventorySheet(item: widget.item),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openRestock() async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _RestockSheet(item: widget.item),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _archive() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Archive item?'),
        content: Text('"${widget.item['item_name']}" will be removed from the active inventory list.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(portalApiProvider).archiveInventoryItem((widget.item['id'] as num).toInt());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.item['item_name']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined, color: AppTheme.navy),
              title: const Text('Edit Details', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Name, reference, type, price', style: TextStyle(fontSize: 11.5)),
              onTap: _busy ? null : _openEdit,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping_outlined, color: AppTheme.primary),
              title: const Text('Restock', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Add quantity — logged as an expense', style: TextStyle(fontSize: 11.5)),
              onTap: _busy ? null : _openRestock,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.archive_outlined, color: Colors.red),
              title: const Text('Archive Item', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.red)),
              onTap: _busy ? null : _archive,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditInventorySheet extends ConsumerStatefulWidget {
  const _EditInventorySheet({required this.item});
  final Map<String, dynamic> item;

  @override
  ConsumerState<_EditInventorySheet> createState() => _EditInventorySheetState();
}

class _EditInventorySheetState extends ConsumerState<_EditInventorySheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _refCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _reorderCtrl;
  late final TextEditingController _supplierCtrl;
  late String _itemType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item['item_name']?.toString() ?? '');
    _refCtrl = TextEditingController(text: widget.item['reference_no']?.toString() ?? '');
    _priceCtrl = TextEditingController(text: (widget.item['unit_price'] as num?)?.toString() ?? '');
    _unitCtrl = TextEditingController(text: widget.item['unit']?.toString() ?? '');
    _reorderCtrl = TextEditingController(text: (widget.item['reorder_threshold'] as num?)?.toString() ?? '5');
    _supplierCtrl = TextEditingController(text: widget.item['supplier_name']?.toString() ?? '');
    _itemType = widget.item['item_type']?.toString() ?? 'equipment';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _refCtrl.dispose();
    _priceCtrl.dispose();
    _unitCtrl.dispose();
    _reorderCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final String name = _nameCtrl.text.trim();
    final String referenceNo = _refCtrl.text.trim();
    final num? price = num.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty || referenceNo.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Please fill in item name, reference no., and a positive unit price.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(portalApiProvider).updateInventoryItem(
            id: (widget.item['id'] as num).toInt(),
            itemName: name,
            referenceNo: referenceNo,
            itemType: _itemType,
            unitPrice: price,
            unit: _unitCtrl.text.trim(),
            reorderThreshold: int.tryParse(_reorderCtrl.text.trim()) ?? 5,
            supplierName: _supplierCtrl.text.trim(),
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
              const Text('Edit Item', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 16),
              if (_error != null) ...<Widget>[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: 14),
              ],
              const Text('Item Name', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _nameCtrl),
              const SizedBox(height: 14),
              const Text('Reference No.', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _refCtrl),
              const SizedBox(height: 14),
              const Text('Item Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _itemType,
                items: _kItemTypeOptions.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (String? v) => setState(() => _itemType = v ?? 'equipment'),
              ),
              const SizedBox(height: 14),
              const Text('Unit Price (₱)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Unit', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _unitCtrl),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Reorder At', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
                        const SizedBox(height: 6),
                        TextField(controller: _reorderCtrl, keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Supplier', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
              const SizedBox(height: 6),
              TextField(controller: _supplierCtrl),
              const SizedBox(height: 20),
              LoadingButton(label: 'Save Changes', isLoading: _saving, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestockSheet extends ConsumerStatefulWidget {
  const _RestockSheet({required this.item});
  final Map<String, dynamic> item;

  @override
  ConsumerState<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends ConsumerState<_RestockSheet> {
  final TextEditingController _qtyCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final int? qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a quantity greater than 0.');
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).restockInventoryItem(id: (widget.item['id'] as num).toInt(), addQuantity: qty);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'Restocked.'), backgroundColor: AppTheme.primary));
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Restock "${widget.item['item_name']}"', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 4),
            const Text('This will be logged as an expense at the current unit price.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 14),
            ],
            const Text('Quantity to Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.navy)),
            const SizedBox(height: 6),
            TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, autofocus: true),
            const SizedBox(height: 20),
            LoadingButton(label: 'Restock', isLoading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

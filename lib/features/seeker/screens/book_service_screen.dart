// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';
import 'package:pestify_flutter/shared/widgets/loading_button.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Book Service Screen
///
/// Collects contact name, contact number, address (with optional map picker),
/// preferred date/time, and payment method, then calls [SeekerApi.createBooking].
/// On success pushes to the payment WebView screen via GoRouter extra.
///
/// Usage: push with GoRouter extra = {'listing_id': <int>}
class BookServiceScreen extends ConsumerStatefulWidget {
  const BookServiceScreen({super.key, required this.listingId});

  final int listingId;

  @override
  ConsumerState<BookServiceScreen> createState() => _BookServiceScreenState();
}

class _BookServiceScreenState extends ConsumerState<BookServiceScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _paymentMethod = 'full';
  bool _isLoading = false;
  bool _profileLoaded = false;

  // Map picker state
  double? _pickedLat;
  double? _pickedLng;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // ── Profile pre-fill ──────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final Map<String, dynamic> profile = await api.getProfile();
      if (!mounted) return;
      final String firstName = (profile['first_name'] ?? '').toString().trim();
      final String lastName = (profile['last_name'] ?? '').toString().trim();
      final String fullName = <String>[firstName, lastName]
          .where((String s) => s.isNotEmpty)
          .join(' ');
      final String phone =
          (profile['phone'] ?? profile['contact_number'] ?? '').toString().trim();
      setState(() {
        if (fullName.isNotEmpty) _nameCtrl.text = fullName;
        if (phone.isNotEmpty) _contactCtrl.text = phone;
        _profileLoaded = true;
      });
    } catch (_) {
      // Non-fatal — user can fill in manually.
      if (mounted) setState(() => _profileLoaded = true);
    }
  }

  // ── Pickers ───────────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (BuildContext ctx, Widget? child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppTheme.primary,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (BuildContext ctx, Widget? child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppTheme.primary,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  // ── Map picker ────────────────────────────────────────────────────────────────

  Future<void> _openMapPicker() async {
    final Map<String, dynamic>? result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => const _MapPickerSheet(),
    );

    if (result == null || !mounted) return;

    final double? lat = result['lat'] as double?;
    final double? lng = result['lng'] as double?;
    final String? addr = result['address'] as String?;

    if (lat == null || lng == null) return;

    setState(() {
      _pickedLat = lat;
      _pickedLng = lng;
      if (addr != null && addr.isNotEmpty) {
        _addressCtrl.text = addr;
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDate == null) {
      _showError('Please select a preferred date.');
      return;
    }
    if (_selectedTime == null) {
      _showError('Please select a preferred time.');
      return;
    }

    setState(() => _isLoading = true);

    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final String timeStr =
        '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';

    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final Map<String, dynamic> result = await api.createBooking(
        listingId: widget.listingId,
        address: _addressCtrl.text.trim(),
        preferredDate: dateStr,
        preferredTime: timeStr,
        paymentMethod: _paymentMethod,
        fullName: _nameCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
      );

      if (!mounted) return;

      final String? checkoutUrl = result['checkout_url'] as String?;
      final dynamic rawId = result['booking_id'] ?? result['id'];
      final int? bookingId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (checkoutUrl == null || bookingId == null) {
        _showError('Unexpected server response. Please try again.');
        return;
      }

      context.push(
        '/seeker/payment',
        extra: <String, dynamic>{
          'checkoutUrl': checkoutUrl,
          'bookingId': bookingId,
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _friendlyError(Object e) {
    String raw = e.toString();
    if (raw.startsWith('Exception: ')) raw = raw.replaceFirst('Exception: ', '');
    if (raw.startsWith('Bad state: ')) raw = raw.replaceFirst('Bad state: ', '');
    return raw.trim().isEmpty
        ? 'Something went wrong. Please check your connection.'
        : raw;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Book Service'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: <Widget>[
              // ── Section header ───────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.person_outline_rounded,
                title: 'Your Information',
                subtitle: 'Pre-filled from your profile — update if needed.',
              ),
              const SizedBox(height: 16),

              // ── Full Name ────────────────────────────────────────────────────
              const _FieldLabel(label: 'FULL NAME'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: _profileLoaded ? 'Your full name' : 'Loading…',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Contact Number ───────────────────────────────────────────────
              const _FieldLabel(label: 'CONTACT NUMBER'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
                ],
                decoration: InputDecoration(
                  hintText: _profileLoaded ? 'e.g. 09XXXXXXXXX' : 'Loading…',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Contact number is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // ── Address section ──────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.location_on_outlined,
                title: 'Service Address',
                subtitle: 'Where should the technician go?',
              ),
              const SizedBox(height: 16),

              // "Use map" row
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openMapPicker,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text(
                        'Pick on Map',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Picked coordinates badge (shown after map selection)
              if (_pickedLat != null && _pickedLng != null) ...<Widget>[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pin dropped at '
                          '${_pickedLat!.toStringAsFixed(5)}, '
                          '${_pickedLng!.toStringAsFixed(5)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _pickedLat = null;
                          _pickedLng = null;
                        }),
                        child: const Icon(Icons.close,
                            size: 16, color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Address text field
              const _FieldLabel(label: 'COMPLETE ADDRESS'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _addressCtrl,
                keyboardType: TextInputType.streetAddress,
                textCapitalization: TextCapitalization.words,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Enter the complete service address in Cavite',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 32),
                    child: Icon(Icons.location_on_outlined, size: 20),
                  ),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Address is required.';
                  }
                  if (!value.toLowerCase().contains('cavite')) {
                    return 'Service is only available within Cavite.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // ── Schedule section ─────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.calendar_today_outlined,
                title: 'Preferred Schedule',
                subtitle: 'Select when you need the service.',
              ),
              const SizedBox(height: 16),

              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _FieldLabel(label: 'DATE'),
                        const SizedBox(height: 6),
                        _PickerTile(
                          icon: Icons.calendar_today_outlined,
                          text: _selectedDate != null
                              ? DateFormat('MMM d, yyyy').format(_selectedDate!)
                              : 'Select date',
                          hasValue: _selectedDate != null,
                          onTap: _pickDate,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _FieldLabel(label: 'TIME'),
                        const SizedBox(height: 6),
                        _PickerTile(
                          icon: Icons.access_time_outlined,
                          text: _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Select time',
                          hasValue: _selectedTime != null,
                          onTap: _pickTime,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Payment section ──────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.payment_outlined,
                title: 'Payment Method',
                subtitle: 'Choose how you want to pay.',
              ),
              const SizedBox(height: 16),

              // Full Payment card
              _PaymentOptionCard(
                value: 'full',
                groupValue: _paymentMethod,
                icon: Icons.payments_outlined,
                iconBg: const Color(0xFF1A1F3A),
                label: 'Full Payment',
                description: 'Pay the entire amount before the service begins.',
                badge: null,
                onTap: () => setState(() => _paymentMethod = 'full'),
              ),
              const SizedBox(height: 12),

              // Down Payment card
              _PaymentOptionCard(
                value: 'downpayment',
                groupValue: _paymentMethod,
                icon: Icons.account_balance_wallet_outlined,
                iconBg: const Color(0xFF4C51BF),
                label: 'Down Payment',
                description: '50% charged now, remaining balance after service completion.',
                badge: '50% now',
                onTap: () => setState(() => _paymentMethod = 'downpayment'),
              ),

              // Downpayment highlight note
              if (_paymentMethod == 'downpayment') ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C51BF).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF4C51BF).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF4C51BF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '50% charged now',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF4C51BF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'The remaining 50% will be collected after the service is completed to your satisfaction.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF4C51BF),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // ── Submit ───────────────────────────────────────────────────────
              LoadingButton(
                label: 'Proceed to Payment',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'You will be redirected to a secure payment page.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Map Picker Bottom Sheet ───────────────────────────────────────────────────

class _MapPickerSheet extends StatefulWidget {
  const _MapPickerSheet();

  @override
  State<_MapPickerSheet> createState() => _MapPickerSheetState();
}

class _MapPickerSheetState extends State<_MapPickerSheet> {
  late final WebViewController _webCtrl;
  bool _webReady = false;
  bool _locating = false;
  double? _lat;
  double? _lng;
  String _displayAddr = 'Tap the map to drop a pin';

  // Cavite, Philippines center coordinates
  static const double _defaultLat = 14.4791;
  static const double _defaultLng = 120.8970;
  static const double _defaultZoom = 12;

  @override
  void initState() {
    super.initState();
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterMapChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleMapMessage(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _webReady = true);
          },
        ),
      )
      ..loadHtmlString(_buildMapHtml());
  }

  void _handleMapMessage(String message) {
    // Expected format: "lat,lng" or "addr:reverse geocoded address"
    if (message.startsWith('addr:')) {
      final String addr = message.substring(5);
      if (mounted) setState(() => _displayAddr = addr);
    } else {
      final List<String> parts = message.split(',');
      if (parts.length >= 2) {
        final double? lat = double.tryParse(parts[0]);
        final double? lng = double.tryParse(parts[1]);
        if (lat != null && lng != null && mounted) {
          setState(() {
            _lat = lat;
            _lng = lng;
            _displayAddr = 'Fetching address…';
          });
        }
      }
    }
  }

  String _buildMapHtml() {
    return '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body, #map { width: 100%; height: 100%; }
  #map { position: relative; }
  #crosshair {
    position: absolute; top: 50%; left: 50%;
    transform: translate(-50%, -50%);
    width: 32px; height: 32px;
    pointer-events: none; z-index: 1000;
    display: none;
  }
</style>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
</head>
<body>
<div id="map"></div>
<div id="crosshair">
  <svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="16" cy="16" r="14" stroke="#2E8B57" stroke-width="3" fill="white" fill-opacity="0.8"/>
    <line x1="16" y1="4" x2="16" y2="28" stroke="#2E8B57" stroke-width="2"/>
    <line x1="4" y1="16" x2="28" y2="16" stroke="#2E8B57" stroke-width="2"/>
  </svg>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
var map = L.map('map').setView([$_defaultLat, $_defaultLng], $_defaultZoom);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  attribution: '&copy; OpenStreetMap contributors',
  maxZoom: 19
}).addTo(map);

var marker = null;
var greenIcon = L.divIcon({
  className: '',
  html: '<div style="width:30px;height:30px;background:#2E8B57;border:3px solid white;border-radius:50% 50% 50% 0;transform:rotate(-45deg);box-shadow:0 2px 8px rgba(0,0,0,0.3);"></div>',
  iconSize: [30, 30],
  iconAnchor: [15, 30],
});

function placeMarker(lat, lng) {
  if (marker) { map.removeLayer(marker); }
  marker = L.marker([lat, lng], {icon: greenIcon, draggable: true}).addTo(map);
  marker.on('dragend', function(e) {
    var pos = e.target.getLatLng();
    sendCoords(pos.lat, pos.lng);
  });
  sendCoords(lat, lng);
}

function sendCoords(lat, lng) {
  FlutterMapChannel.postMessage(lat.toFixed(6) + ',' + lng.toFixed(6));
  fetch('https://nominatim.openstreetmap.org/reverse?lat=' + lat + '&lon=' + lng + '&format=json')
    .then(function(r) { return r.json(); })
    .then(function(d) {
      var addr = d.display_name || '';
      FlutterMapChannel.postMessage('addr:' + addr);
    })
    .catch(function() {});
}

map.on('click', function(e) {
  placeMarker(e.latlng.lat, e.latlng.lng);
});
</script>
</body>
</html>''';
  }

  void _useLocation() {
    if (_lat == null || _lng == null) return;
    Navigator.of(context).pop(<String, dynamic>{
      'lat': _lat,
      'lng': _lng,
      'address': _displayAddr.startsWith('Fetching') ? null : _displayAddr,
    });
  }

  @override
  Widget build(BuildContext context) {
    final double sheetH = MediaQuery.of(context).size.height * 0.78;
    return Container(
      height: sheetH,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: <Widget>[
          // Handle + title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pick Location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1F3A),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Tap anywhere on the map to drop a pin.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 8),

          // Map WebView
          Expanded(
            child: ClipRRect(
              child: Stack(
                children: <Widget>[
                  WebViewWidget(controller: _webCtrl),
                  if (!_webReady)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),

          // Address display + confirm button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_lat != null) ...<Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.location_on,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _displayAddr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1A1F3A),
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _lat != null ? _useLocation : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      _lat != null ? 'Use This Location' : 'Tap the map first',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (_locating)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment Option Card ───────────────────────────────────────────────────────

class _PaymentOptionCard extends StatelessWidget {
  const _PaymentOptionCard({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.description,
    required this.badge,
    required this.onTap,
  });

  final String value;
  final String groupValue;
  final IconData icon;
  final Color iconBg;
  final String label;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            // Icon bubble
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? AppTheme.primary
                              : const Color(0xFF1A1F3A),
                        ),
                      ),
                      if (badge != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4C51BF)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4C51BF),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Radio circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.primary : const Color(0xFFCBD5E0),
                  width: 2,
                ),
                color: selected ? AppTheme.primary : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1F3A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.text,
    required this.hasValue,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: hasValue ? AppTheme.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: hasValue
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

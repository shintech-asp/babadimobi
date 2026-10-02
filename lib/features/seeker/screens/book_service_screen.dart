// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/state/bookings_refresh.dart';
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

  // Whether the listing being booked requires an on-site inspection before a
  // final price is set (see api/v1/seeker/bookings/store.php and CLAUDE.md's
  // "Two-date Inspection → Agreement → Working Date flow"). For these
  // listings the price shown is only an estimate, so there's no payment
  // method to choose yet — that happens later once the seeker agrees to the
  // technician's proposed price and the booking re-enters 'accepted'.
  bool _requiresInspection = false;

  // Map picker state
  double? _pickedLat;
  double? _pickedLng;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadListing();
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
      // Pre-fill convenience only — the seeker can still pin a different
      // address for this specific booking via the map picker below, and
      // nothing here blocks submission if it's left blank (see the web's
      // seeker/setup-address.php lockout bug, fixed earlier, for why this
      // deliberately isn't a hard requirement).
      final String savedAddress = (profile['address'] ?? '').toString().trim();
      setState(() {
        if (fullName.isNotEmpty) _nameCtrl.text = fullName;
        if (phone.isNotEmpty) _contactCtrl.text = phone;
        if (savedAddress.isNotEmpty && _addressCtrl.text.trim().isEmpty) {
          _addressCtrl.text = savedAddress;
        }
        _profileLoaded = true;
      });
    } catch (_) {
      // Non-fatal — user can fill in manually.
      if (mounted) setState(() => _profileLoaded = true);
    }
  }

  Future<void> _loadListing() async {
    try {
      final SeekerApi api = ref.read(seekerApiProvider);
      final Map<String, dynamic> listing =
          await api.getListingDetail(widget.listingId);
      if (!mounted) return;
      setState(() {
        _requiresInspection = listing['requires_inspection'] == true ||
            listing['requires_inspection'] == 1 ||
            listing['requires_inspection'] == '1';
      });
    } catch (_) {
      // Non-fatal — fall back to showing the payment step; the backend
      // still enforces the inspection rule regardless of what this screen
      // shows.
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
      final bool requiresInspection = result['requires_inspection'] == true;

      if (bookingId == null) {
        _showError('Unexpected server response. Please try again.');
        return;
      }

      // The booking row now exists server-side regardless of which branch
      // runs next (inspection-pending, checkout-failed, or a normal payment
      // redirect) — bump the shared refresh signal so My Bookings' Active
      // tab picks it up next time it's checked, instead of only reflecting
      // it after a manual pull-to-refresh (see bookings_refresh.dart).
      ref.read(bookingsRefreshTick.notifier).state++;

      if (requiresInspection) {
        // No payment to collect yet — the request was submitted as
        // 'pending' with only an estimated price. Payment happens later,
        // once the technician inspects and the seeker agrees to a final
        // price (see api/v1/seeker/bookings/store.php).
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Request sent! The provider will review it and schedule an '
              'inspection before a final price is set.',
            ),
          ),
        );
        context.go('/seeker/bookings');
        return;
      }

      if (checkoutUrl == null) {
        // Booking was saved but PayMongo checkout creation failed
        // (`paymongo_error` in the response) — not an inspection case.
        // The seeker can retry payment later from the booking detail
        // screen, same as _retryPayment() there.
        _showError(
          'Booking saved, but starting payment failed. You can retry '
          'payment from My Bookings.',
        );
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
              // For inspection-required listings, the date/time picked here
              // is stored as `inspection_date` (see
              // api/v1/seeker/bookings/store.php) — a technician visits on
              // this date to assess the job, not perform it. The actual
              // Working Date is set later once the seeker agrees to the
              // inspection report's proposed price. Label it accordingly so
              // it doesn't read as if the service itself is scheduled now.
              _SectionHeader(
                icon: Icons.calendar_today_outlined,
                title: _requiresInspection
                    ? 'Preferred Inspection Schedule'
                    : 'Preferred Schedule',
                subtitle: _requiresInspection
                    ? 'Select when a technician can inspect on-site. The service date is set after you agree to the final price.'
                    : 'Select when you need the service.',
              ),
              const SizedBox(height: 16),

              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _FieldLabel(
                            label: _requiresInspection
                                ? 'INSPECTION DATE'
                                : 'DATE'),
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

              // ── Payment section — hidden entirely for inspection-required
              // listings. The price isn't final until a technician inspects
              // on-site, so there's nothing to choose a payment plan against
              // yet (see api/v1/seeker/bookings/store.php).
              if (_requiresInspection) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.fact_check_outlined,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'No payment needed yet',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'A technician will inspect on-site and propose a final price. '
                              "You'll choose a payment method after you agree to it.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.primary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ] else ...<Widget>[
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
              ],

              // ── Submit ───────────────────────────────────────────────────────
              LoadingButton(
                label: _requiresInspection ? 'Submit Request' : 'Proceed to Payment',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _requiresInspection
                      ? "You'll be notified once the provider schedules an inspection."
                      : 'You will be redirected to a secure payment page.',
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
  late WebViewController _webCtrl;
  bool _webReady = false;
  bool _loadTimedOut = false;
  bool _locating = false;
  double? _lat;
  double? _lng;
  String _displayAddr = 'Tap the map to drop a pin';

  @override
  void initState() {
    super.initState();
    _startLoad(isInitial: true);
  }

  void _startLoad({bool isInitial = false}) {
    if (isInitial) {
      _webReady = false;
      _loadTimedOut = false;
    } else {
      setState(() {
        _webReady = false;
        _loadTimedOut = false;
      });
    }
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
          onPageStarted: (String url) {
            debugPrint('[MapPicker] onPageStarted: $url');
          },
          onPageFinished: (String url) {
            debugPrint('[MapPicker] onPageFinished: $url');
            if (mounted) setState(() => _webReady = true);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint(
              '[MapPicker] onWebResourceError: type=${error.errorType} '
              'code=${error.errorCode} desc=${error.description} '
              'url=${error.url} isForMainFrame=${error.isForMainFrame}',
            );
          },
        ),
      )
      // Loaded from bundled assets (assets/leaflet/map.html + leaflet.js/css)
      // rather than fetched from unpkg.com at runtime — a render-blocking
      // <script src="https://unpkg.com/..."> tag in the old inline HTML
      // meant onPageFinished (and therefore _webReady) never fired if the
      // device couldn't reach that CDN, leaving this sheet stuck on its
      // loading spinner forever with no way to tell why. The map's tile
      // imagery and reverse-geocoding still need real internet access —
      // this only removes the *page itself* as a point of network failure.
      ..loadFlutterAsset('assets/leaflet/map.html');

    // Belt-and-suspenders: if the page still hasn't fired onPageFinished
    // after a generous window (e.g. a slow/blocked connection to the map
    // tile servers holding up rendering), stop spinning forever and show a
    // retry option instead.
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (mounted && !_webReady) setState(() => _loadTimedOut = true);
    });
  }

  void _handleMapMessage(String message) {
    // Expected format: "ready", "lat,lng", or "addr:reverse geocoded address"
    if (message == 'ready') {
      // Leaflet has finished laying out the map — the real "usable" signal.
      // Don't wait for onPageFinished too; see the comment in map.html.
      if (mounted && !_webReady) setState(() => _webReady = true);
      return;
    }
    if (message == 'outside_cavite') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please pick a location within Cavite.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
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
                  if (!_webReady && !_loadTimedOut)
                    const Center(child: CircularProgressIndicator()),
                  if (_loadTimedOut && !_webReady)
                    Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.wifi_off_rounded,
                              size: 36, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          const Text(
                            "Map is taking too long to load. Check your internet connection.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _startLoad,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
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

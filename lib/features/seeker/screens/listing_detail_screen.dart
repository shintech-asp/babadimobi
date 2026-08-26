// ignore_for_file: avoid_dynamic_calls

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

class ListingDetailScreen extends ConsumerStatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final int listingId;

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  Map<String, dynamic>? _listing;
  bool _isLoading = true;
  String? _error;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> data =
          await ref.read(seekerApiProvider).getListingDetail(widget.listingId);
      if (mounted) setState(() { _listing = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _isLoading = false; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _images() {
    final dynamic raw = _listing?['images'];
    if (raw is List) return raw.map((dynamic e) => e.toString()).toList();
    return <String>[];
  }

  double _avgRating() {
    final dynamic r = _listing?['avg_rating'];
    if (r == null) return 0;
    return double.tryParse(r.toString()) ?? 0;
  }

  int _reviewCount() {
    final dynamic r = _listing?['review_count'];
    if (r == null) return 0;
    return int.tryParse(r.toString()) ?? 0;
  }

  double _price() {
    final dynamic p = _listing?['price'];
    if (p == null) return 0;
    return double.tryParse(p.toString()) ?? 0;
  }

  bool _flagBool(String key) {
    final dynamic v = _listing?[key];
    if (v == null) return false;
    if (v is bool) return v;
    final int? i = int.tryParse(v.toString());
    return i == 1;
  }

  List<Map<String, dynamic>> _reviews() {
    final dynamic raw = _listing?['reviews'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .cast<Map<String, dynamic>>()
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  int _providerId() {
    final dynamic pid = _listing?['provider_id'];
    if (pid == null) return 0;
    return int.tryParse(pid.toString()) ?? 0;
  }

  String _providerName() {
    final String first = (_listing?['provider_first'] ?? '').toString().trim();
    final String last = (_listing?['provider_last'] ?? '').toString().trim();
    final String company = (_listing?['company_name'] ?? '').toString().trim();
    if (company.isNotEmpty) return company;
    return <String>[first, last].where((String s) => s.isNotEmpty).join(' ');
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_error != null || _listing == null) {
      return Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(title: const Text('Service Detail')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                Text(_error ?? 'Failed to load listing.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textMuted)),
                const SizedBox(height: 20),
                OutlinedButton(onPressed: () { setState(() { _isLoading = true; _error = null; }); _load(); },
                    style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                    child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final Map<String, dynamic> listing = _listing!;
    final List<String> images = _images();
    final double avgRating = _avgRating();
    final int reviewCount = _reviewCount();
    final double price = _price();
    final bool isEco = _flagBool('is_eco_friendly');
    final bool isEmergency = _flagBool('is_emergency_available');
    final List<Map<String, dynamic>> reviews = _reviews();
    final String title = (listing['title'] ?? 'Service').toString();
    final String description = (listing['description'] ?? '').toString().trim();
    final String categoryName = (listing['category_name'] ?? '').toString();
    final String logoUrl = (listing['logo_url'] ?? '').toString();
    final String providerCity = (listing['provider_city'] ?? '').toString().trim();
    final String providerAddress = (listing['provider_address'] ?? '').toString().trim();
    final String providerDescription = (listing['provider_description'] ?? '').toString().trim();
    final String priceFmt = NumberFormat.currency(locale: 'fil_PH', symbol: '₱').format(price);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Stack(
          children: <Widget>[
            // ── Scrollable content ───────────────────────────────────────────────
            CustomScrollView(
              slivers: <Widget>[
                // ── Hero image gallery ─────────────────────────────────────────
                _HeroSliver(
                  images: images,
                  currentIndex: _imageIndex,
                  onPageChanged: (int i) => setState(() => _imageIndex = i),
                  onBack: () => context.pop(),
                ),

                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // ── Title row ────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              // Badges row
                              if (categoryName.isNotEmpty || isEco || isEmergency)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Wrap(
                                    spacing: 6,
                                    children: <Widget>[
                                      if (categoryName.isNotEmpty)
                                        _Chip(label: categoryName, color: AppTheme.indigo),
                                      if (isEco)
                                        _Chip(label: 'ECO', color: AppTheme.primary, icon: Icons.eco_rounded),
                                      if (isEmergency)
                                        _Chip(label: 'URGENT', color: const Color(0xFFE53E3E), icon: Icons.flash_on_rounded),
                                    ],
                                  ),
                                ),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.navy,
                                  letterSpacing: -0.5,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Price + rating row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    priceFmt,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (avgRating > 0) ...<Widget>[
                                    RatingBarIndicator(
                                      rating: avgRating,
                                      itemSize: 16,
                                      itemBuilder: (_, __) => const Icon(
                                        Icons.star_rounded,
                                        color: AppTheme.starColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      avgRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.navy,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '($reviewCount)',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ] else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'New',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 28),

                        // ── Provider row ─────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Row(
                            children: <Widget>[
                              _ProviderAvatar(logoUrl: logoUrl, name: _providerName()),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      _providerName(),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.navy,
                                      ),
                                    ),
                                    if (providerCity.isNotEmpty)
                                      Text(
                                        providerCity,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push(
                                  '/seeker/provider/${_providerId()}',
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text(
                                  'View Profile',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(),

                        // ── About service ─────────────────────────────────────────
                        if (description.isNotEmpty) ...<Widget>[
                          _Section(
                            title: 'About this Service',
                            child: Text(
                              description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.navy,
                                height: 1.6,
                              ),
                            ),
                          ),
                          const Divider(),
                        ],

                        // ── About provider ────────────────────────────────────────
                        if (providerDescription.isNotEmpty || providerAddress.isNotEmpty || providerCity.isNotEmpty) ...<Widget>[
                          _Section(
                            title: 'About the Provider',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (providerDescription.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      providerDescription,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.navy,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    if (providerCity.isNotEmpty)
                                      _InfoChip(icon: Icons.location_city_rounded, label: providerCity),
                                    if (providerAddress.isNotEmpty)
                                      _InfoChip(icon: Icons.pin_drop_rounded, label: providerAddress),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                        ],

                        // ── Reviews ───────────────────────────────────────────────
                        _Section(
                          title: 'Customer Reviews',
                          trailing: reviewCount > 0
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      avgRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.navy,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        RatingBarIndicator(
                                          rating: avgRating,
                                          itemSize: 16,
                                          itemBuilder: (_, __) => const Icon(
                                            Icons.star_rounded,
                                            color: AppTheme.starColor,
                                          ),
                                        ),
                                        Text(
                                          '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : null,
                          child: reviews.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No reviews yet. Be the first!',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                                  ),
                                )
                              : Column(
                                  children: reviews
                                      .take(5)
                                      .map((Map<String, dynamic> r) => _ReviewCard(review: r))
                                      .toList(),
                                ),
                        ),

                        // Bottom padding so sticky bar doesn't cover last content
                        const SizedBox(height: 96),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Sticky Book Now bar ──────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.navy.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('Starting at',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(priceFmt,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.navy,
                              height: 1.2,
                            )),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.push(
                          '/seeker/book',
                          extra: <String, dynamic>{'listingId': widget.listingId},
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Book Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero image sliver ─────────────────────────────────────────────────────────

class _HeroSliver extends StatelessWidget {
  const _HeroSliver({
    required this.images,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onBack,
  });

  final List<String> images;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      leading: GestureDetector(
        onTap: onBack,
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (images.isEmpty)
              Container(
                color: AppTheme.primary.withValues(alpha: 0.1),
                child: const Icon(Icons.pest_control_rounded, size: 64, color: AppTheme.primary),
              )
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: onPageChanged,
                itemBuilder: (BuildContext ctx, int i) {
                  return CachedNetworkImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      child: const Icon(Icons.pest_control_rounded, size: 64, color: AppTheme.primary),
                    ),
                  );
                },
              ),
            // Gradient fade at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
            ),
            // Page indicator dots
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(images.length, (int i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == currentIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == currentIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    );
  }
}

// ── Provider avatar ───────────────────────────────────────────────────────────

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({required this.logoUrl, required this.name});

  final String logoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final String initial =
        name.isNotEmpty ? name[0].toUpperCase() : 'P';
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
      foregroundImage: logoUrl.isNotEmpty
          ? CachedNetworkImageProvider(logoUrl)
          : null,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                  letterSpacing: -0.3,
                ),
              ),
              if (trailing != null) ...<Widget>[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badge chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Map<String, dynamic> review;

  String _initial() {
    final String first = (review['first_name'] ?? '').toString().trim();
    return first.isNotEmpty ? first[0].toUpperCase() : 'U';
  }

  String _name() {
    final String first = (review['first_name'] ?? '').toString().trim();
    final String last = (review['last_name'] ?? '').toString().trim();
    if (first.isEmpty && last.isEmpty) return 'Anonymous';
    return <String>[first, last].where((String s) => s.isNotEmpty).join(' ');
  }

  double _rating() =>
      double.tryParse((review['rating'] ?? '0').toString()) ?? 0;

  String _date() {
    final String raw = (review['created_at'] ?? '').toString();
    try {
      final DateTime dt = DateTime.parse(raw);
      return DateFormat('MMM d, y').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String feedback = (review['feedback'] ?? '').toString().trim();
    final double rating = _rating();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Text(
              _initial(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _name(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _date(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                if (rating > 0)
                  RatingBarIndicator(
                    rating: rating,
                    itemSize: 13,
                    itemBuilder: (_, __) => const Icon(
                      Icons.star_rounded,
                      color: AppTheme.starColor,
                    ),
                  ),
                if (feedback.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    feedback,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.navy,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

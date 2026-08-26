// ignore_for_file: avoid_dynamic_calls

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

// ── Category model ────────────────────────────────────────────────────────────

class _Category {
  const _Category({required this.label, required this.id, required this.icon});
  final String label;
  final int? id; // null = All
  final IconData icon;
}

const List<_Category> _kCategories = <_Category>[
  _Category(label: 'All', id: null, icon: Icons.apps_rounded),
  _Category(label: 'General', id: 1, icon: Icons.home_repair_service_rounded),
  _Category(label: 'Termite', id: 2, icon: Icons.pest_control_rounded),
  _Category(label: 'Rodent', id: 3, icon: Icons.pest_control_rodent_rounded),
  _Category(label: 'Cockroach', id: 4, icon: Icons.bug_report_rounded),
  _Category(label: 'Mosquito', id: 5, icon: Icons.coronavirus_rounded),
  _Category(label: 'Bed Bug', id: 6, icon: Icons.bedroom_parent_rounded),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Category filter
  int _selectedCategoryIndex = 0; // index into _kCategories

  // Pagination
  final List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoad = true;
  String? _errorMessage;

  // Scroll controller for infinite scroll
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchListings(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _fetchListings({bool reset = false}) async {
    if (reset) {
      setState(() {
        _listings.clear();
        _currentPage = 1;
        _hasMore = true;
        _isInitialLoad = true;
        _errorMessage = null;
      });
    }

    if (!_hasMore || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final _Category cat = _kCategories[_selectedCategoryIndex];
      final Map<String, dynamic> result =
          await ref.read(seekerApiProvider).getListings(
                search: _searchQuery.isNotEmpty ? _searchQuery : null,
                categoryId: cat.id,
                page: _currentPage,
              );

      final List<dynamic> items =
          (result['data'] as List<dynamic>?) ?? <dynamic>[];
      final Map<String, dynamic>? meta =
          result['meta'] as Map<String, dynamic>?;
      // total_pages preferred; fall back to computing from total+limit.
      int? totalPages = meta?['total_pages'] as int?;
      if (totalPages == null && meta != null) {
        final int total = (meta['total'] as int?) ?? 0;
        final int limit = (meta['limit'] as int?) ?? 20;
        totalPages = limit > 0 ? ((total + limit - 1) ~/ limit) : 1;
      }

      if (!mounted) return;
      setState(() {
        for (final dynamic item in items) {
          if (item is Map<String, dynamic>) _listings.add(item);
        }
        _hasMore = totalPages != null && _currentPage < totalPages;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoad = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _currentPage++;
    await _fetchListings();
    // If _fetchListings set _errorMessage, roll back the page counter so
    // a subsequent retry starts from the correct page.
    if (_errorMessage != null) _currentPage--;
  }

  void _onSearchSubmit(String value) {
    setState(() => _searchQuery = value.trim());
    _fetchListings(reset: true);
  }

  void _onCategoryTap(int index) {
    if (_selectedCategoryIndex == index) return;
    setState(() => _selectedCategoryIndex = index);
    _fetchListings(reset: true);
  }

  Future<void> _onRefresh() => _fetchListings(reset: true);

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.seedColor,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              // ── App bar ─────────────────────────────────────────────────────
              SliverAppBar(
                floating: true,
                snap: true,
                elevation: 0,
                scrolledUnderElevation: 0.5,
                title: Row(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.pest_control_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Pestify'),
                  ],
                ),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => context.push('/seeker/notifications'),
                  ),
                ],
              ),

              // ── Hero search section ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[AppTheme.navy, Color(0xFF2C3E7A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Find Pest Control Services',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Book trusted technicians near you',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _onSearchSubmit,
                          style: const TextStyle(fontSize: 14, color: AppTheme.navy),
                          decoration: InputDecoration(
                            hintText: 'Search pest control services…',
                            hintStyle: TextStyle(
                              color: AppTheme.textMuted.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: AppTheme.textMuted),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _onSearchSubmit('');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Category chips ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    itemCount: _kCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final bool selected = _selectedCategoryIndex == index;
                      final _Category cat = _kCategories[index];
                      return FilterChip(
                        selected: selected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              cat.icon,
                              size: 14,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.seedColor,
                            ),
                            const SizedBox(width: 4),
                            Text(cat.label),
                          ],
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppTheme.seedColor,
                        ),
                        selectedColor: AppTheme.seedColor,
                        backgroundColor:
                            AppTheme.primaryLight.withValues(alpha: 0.12),
                        checkmarkColor: Colors.white,
                        showCheckmark: false,
                        side: BorderSide.none,
                        onSelected: (_) => _onCategoryTap(index),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Section label ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'Results for "$_searchQuery"'
                        : _selectedCategoryIndex == 0
                            ? 'All Services'
                            : _kCategories[_selectedCategoryIndex].label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── Body ────────────────────────────────────────────────────────
              if (_isInitialLoad)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  child: _ErrorState(
                    message: _errorMessage!,
                    onRetry: () => _fetchListings(reset: true),
                  ),
                )
              else if (_listings.isEmpty)
                SliverFillRemaining(
                  child: _EmptyState(
                    message: _searchQuery.isNotEmpty
                        ? 'No results for "$_searchQuery"'
                        : 'No services available right now.',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      if (index == _listings.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: _ListingCard(
                          data: _listings[index],
                          onTap: () {
                            final int? id = _listings[index]['id'] as int?;
                            if (id != null) {
                              context.push('/seeker/listing/$id');
                            }
                          },
                        ),
                      );
                    },
                    childCount: _listings.length + (_hasMore ? 1 : 0),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Listing card (horizontal row) ─────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.data,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ── Data extraction ──────────────────────────────────────────────────────
    final dynamic imagesRaw = data['images'];
    final List<dynamic> imagesArr =
        imagesRaw is List ? imagesRaw : <dynamic>[];
    final String? imageUrl = imagesArr.isNotEmpty
        ? imagesArr.first?.toString()
        : data['image_url']?.toString();

    final String title = (data['title'] as String?) ?? 'Untitled';
    final String companyName =
        (data['company_name'] as String?) ??
        (data['provider_name'] as String?) ??
        'Unknown Provider';

    final dynamic rawPrice = data['price'];
    final num price = rawPrice is num
        ? rawPrice
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0;

    final dynamic rawRating = data['avg_rating'] ?? data['rating'];
    final num rating = rawRating is num
        ? rawRating
        : double.tryParse(rawRating?.toString() ?? '') ?? 0;
    final double ratingVal = rating.toDouble();

    final dynamic rawReviewCount = data['review_count'];
    final int reviewCount = rawReviewCount is int
        ? rawReviewCount
        : int.tryParse(rawReviewCount?.toString() ?? '') ?? 0;

    final dynamic rawEco = data['is_eco_friendly'];
    final bool isEco = rawEco == true || rawEco == 1;
    final dynamic rawEmergency =
        data['is_emergency_available'] ?? data['is_emergency'];
    final bool isEmergency = rawEmergency == true || rawEmergency == 1;

    final String priceStr =
        NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(price);

    // ── Layout ───────────────────────────────────────────────────────────────
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── Left: thumbnail ────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: AppTheme.primaryLight.withValues(alpha: 0.1),
                          ),
                          errorWidget: (_, __, ___) =>
                              const _PlaceholderImage(),
                        )
                      : const _PlaceholderImage(),
                ),
              ),

              const SizedBox(width: 12),

              // ── Right: content ─────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Line 1: title
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 3),

                    // Line 2: company name
                    Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Line 3: star rating row
                    if (ratingVal > 0)
                      Row(
                        children: <Widget>[
                          RatingBarIndicator(
                            rating: ratingVal,
                            itemBuilder: (_, __) => const Icon(
                              Icons.star_rounded,
                              color: AppTheme.starColor,
                            ),
                            itemCount: 5,
                            itemSize: 13,
                            unratedColor:
                                AppTheme.starColor.withValues(alpha: 0.25),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ratingVal.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '($reviewCount)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppTheme.primary,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'New',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),

                    const SizedBox(height: 6),

                    // Line 4: price + ECO/URGENT badges
                    Row(
                      children: <Widget>[
                        Text(
                          priceStr,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        if (isEco) ...<Widget>[
                          const SizedBox(width: 6),
                          const _Badge(
                            label: 'ECO',
                            color: AppTheme.primary,
                          ),
                        ],
                        if (isEmergency) ...<Widget>[
                          const SizedBox(width: 4),
                          const _Badge(
                            label: 'URGENT',
                            color: Color(0xFFB91C1C),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Line 5: "View Details →" right-aligned
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'View Details →',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryLight.withValues(alpha: 0.10),
      child: const Center(
        child: Icon(
          Icons.pest_control_rounded,
          size: 32,
          color: AppTheme.primaryLight,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

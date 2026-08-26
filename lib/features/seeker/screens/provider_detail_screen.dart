// ignore_for_file: avoid_dynamic_calls

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

class ProviderDetailScreen extends ConsumerStatefulWidget {
  const ProviderDetailScreen({super.key, required this.providerId});

  final int providerId;

  @override
  ConsumerState<ProviderDetailScreen> createState() =>
      _ProviderDetailScreenState();
}

class _ProviderDetailScreenState
    extends ConsumerState<ProviderDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await ref
          .read(seekerApiProvider)
          .getProviderDetail(widget.providerId);
      if (!mounted) return;
      setState(() {
        _data = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map<String, dynamic> d = _data!;
    final String company =
        (d['company_name'] as String?) ?? 'Provider';
    final String? coverUrl = d['cover_url'] as String?;
    final String? logoUrl = d['logo_url'] as String?;
    final String description = (d['description'] as String?) ?? '';
    final String city = (d['city'] as String?) ?? '';
    final String address = (d['address'] as String?) ?? '';
    final num rating = (d['rating'] as num?) ?? 0;
    final int reviewCount = (d['review_count'] as int?) ?? 0;
    final List<dynamic> services =
        (d['services'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> reviews =
        (d['reviews'] as List<dynamic>?) ?? <dynamic>[];

    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxScrolled) {
          return <Widget>[
            // ── Collapsing cover / header ──────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: AppTheme.seedColor,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: _CoverPhoto(
                  coverUrl: coverUrl,
                  logoUrl: logoUrl,
                  company: company,
                ),
              ),
            ),

            // ── Provider info strip ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      company,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                    ),
                    const SizedBox(height: 6),
                    // Location
                    if (city.isNotEmpty || address.isNotEmpty)
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              <String>[city, address]
                                  .where((s) => s.isNotEmpty)
                                  .join(', '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    // Rating pill
                    _RatingPill(
                      rating: rating.toDouble(),
                      reviewCount: reviewCount,
                    ),
                  ],
                ),
              ),
            ),

            // ── Tab bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: AppTheme.seedColor,
                  unselectedLabelColor:
                      cs.onSurfaceVariant,
                  indicatorColor: AppTheme.seedColor,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  tabs: const <Widget>[
                    Tab(text: 'About'),
                    Tab(text: 'Services'),
                    Tab(text: 'Reviews'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabCtrl,
          children: <Widget>[
            // ── About ──────────────────────────────────────────────────────
            _AboutTab(description: description),

            // ── Services ───────────────────────────────────────────────────
            _ServicesTab(services: services),

            // ── Reviews ────────────────────────────────────────────────────
            _ReviewsTab(reviews: reviews),
          ],
        ),
      ),
    );
  }
}

// ── Cover photo ───────────────────────────────────────────────────────────────

class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({
    required this.coverUrl,
    required this.logoUrl,
    required this.company,
  });

  final String? coverUrl;
  final String? logoUrl;
  final String company;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Cover image
        if (coverUrl != null && coverUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: coverUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(color: AppTheme.seedColor.withValues(alpha: 0.3)),
            errorWidget: (_, __, ___) =>
                Container(color: AppTheme.seedColor.withValues(alpha: 0.3)),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  AppTheme.seedColor,
                  AppTheme.primaryLight,
                ],
              ),
            ),
          ),

        // Gradient overlay for readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
          ),
        ),

        // Logo in bottom-left
        Positioned(
          left: 20,
          bottom: 16,
          child: _LogoBadge(logoUrl: logoUrl, company: company),
        ),
      ],
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.logoUrl, required this.company});

  final String? logoUrl;
  final String company;

  @override
  Widget build(BuildContext context) {
    final String initial =
        company.isNotEmpty ? company[0].toUpperCase() : 'P';

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9.5),
        child: logoUrl != null && logoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    _InitialBox(initial: initial),
              )
            : _InitialBox(initial: initial),
      ),
    );
  }
}

class _InitialBox extends StatelessWidget {
  const _InitialBox({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryLight.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── Rating pill ────────────────────────────────────────────────────────────────

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.star_rounded,
            size: 16,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : 'No ratings yet',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF92400E),
            ),
          ),
          if (reviewCount > 0) ...<Widget>[
            const SizedBox(width: 4),
            Text(
              '($reviewCount)',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF92400E).withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── About tab ─────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: description.isNotEmpty
          ? Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            )
          : const _EmptyTabMessage(message: 'No description provided.'),
    );
  }
}

// ── Services tab ──────────────────────────────────────────────────────────────

class _ServicesTab extends StatelessWidget {
  const _ServicesTab({required this.services});

  final List<dynamic> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const _EmptyTabMessage(message: 'No services listed yet.');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final dynamic item = services[index];
        if (item is! Map<String, dynamic>) return const SizedBox.shrink();
        return _ServiceListingCard(
          data: item,
          onTap: () {
            final int? id = item['id'] as int?;
            if (id != null) context.push('/seeker/listing/$id');
          },
        );
      },
    );
  }
}

class _ServiceListingCard extends StatelessWidget {
  const _ServiceListingCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? imageUrl = data['image_url'] as String?;
    final String title = (data['title'] as String?) ?? 'Untitled';
    final num price = (data['price'] as num?) ?? 0;
    final bool isEco = (data['is_eco_friendly'] as bool?) ?? false;
    final bool isEmergency = (data['is_emergency'] as bool?) ?? false;

    final String priceStr =
        NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(price);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(13),
                  bottomLeft: Radius.circular(13),
                ),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color:
                                AppTheme.primaryLight.withValues(alpha: 0.1),
                          ),
                          errorWidget: (_, __, ___) =>
                              _ServicePlaceholder(),
                        )
                      : _ServicePlaceholder(),
                ),
              ),

              // Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Badges
                      if (isEco || isEmergency)
                        Row(
                          children: <Widget>[
                            if (isEco)
                              const _SmallBadge(
                                label: 'Eco',
                                color: AppTheme.seedColor,
                              ),
                            if (isEco && isEmergency)
                              const SizedBox(width: 4),
                            if (isEmergency)
                              const _SmallBadge(
                                label: 'Emergency',
                                color: Color(0xFFB91C1C),
                              ),
                          ],
                        ),
                      if (isEco || isEmergency) const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceStr,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: AppTheme.seedColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryLight.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Icon(
        Icons.pest_control_rounded,
        size: 28,
        color: AppTheme.primaryLight.withValues(alpha: 0.6),
      ),
    );
  }
}

// ── Reviews tab ───────────────────────────────────────────────────────────────

class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab({required this.reviews});

  final List<dynamic> reviews;

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const _EmptyTabMessage(message: 'No reviews yet.');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final dynamic item = reviews[index];
        if (item is! Map<String, dynamic>) return const SizedBox.shrink();
        return _ReviewCard(data: item);
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int rating = (data['rating'] as int?) ?? 0;
    final String comment = (data['comment'] as String?) ?? '';
    final String reviewer =
        (data['reviewer_name'] as String?) ?? 'Anonymous';
    final String? imageUrl = data['image_url'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Reviewer initial avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  reviewer.isNotEmpty
                      ? reviewer[0].toUpperCase()
                      : 'A',
                  style: const TextStyle(
                    color: AppTheme.seedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      reviewer,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    _StarRow(rating: rating),
                  ],
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              comment,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface,
                    height: 1.5,
                  ),
            ),
          ],
          if (imageUrl != null && imageUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(5, (int i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 14,
          color: const Color(0xFFF59E0B),
        );
      }),
    );
  }
}

// ── Shared small helpers ──────────────────────────────────────────────────────

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _EmptyTabMessage extends StatelessWidget {
  const _EmptyTabMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

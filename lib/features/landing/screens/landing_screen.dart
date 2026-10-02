import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

/// Public landing page — shown to guests instead of dropping them straight
/// onto the login screen, mirroring the PHP web app's `index.php`: a hero,
/// a "Find My Match" DSS entry point, browsable categories and featured
/// services (both guest-safe — the underlying `/categories`, `/listings`,
/// `/seeker/listing/:id` and `/seeker/provider/:id` endpoints/routes require
/// no login), a "how it works" explainer, and Login/Sign Up CTAs.
class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  late Future<_LandingData> _future;

  static const Map<String, IconData> _categoryIcons = <String, IconData>{
    'General Pest Control': Icons.home_repair_service_rounded,
    'Termite Control': Icons.pest_control_rounded,
    'Rodent Control': Icons.pest_control_rodent_rounded,
    'Cockroach Control': Icons.bug_report_rounded,
    'Mosquito Control': Icons.coronavirus_rounded,
    'Bed Bug Control': Icons.bedroom_parent_rounded,
  };

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_LandingData> _fetch() async {
    final SeekerApi api = ref.read(seekerApiProvider);
    final List<dynamic> categories = await api.getCategories();
    List<dynamic> featured = <dynamic>[];
    try {
      final Map<String, dynamic> body = await api.getListings(page: 1);
      final dynamic items = body['data'];
      if (items is List) featured = items.take(6).toList();
    } catch (_) {
      // Featured services are a nice-to-have on this page — a failure here
      // shouldn't block the rest of the landing page from rendering.
    }
    return _LandingData(categories: categories, featured: featured);
  }

  Future<void> _refresh() async {
    final Future<_LandingData> next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  void _openCategory(int categoryId) {
    context.push('/recommend', extra: <String, dynamic>{'categoryId': categoryId});
  }

  void _openListing(Map<String, dynamic> listing) {
    final dynamic rawId = listing['id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;
    context.push('/seeker/listing/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _TopBar(onLogin: () => context.push('/login'))),
              SliverToBoxAdapter(child: _Hero(
                onFindMatch: () => context.push('/recommend'),
                onBrowse: () => context.push('/register'),
              )),
              SliverToBoxAdapter(child: _StatsRow()),
              SliverToBoxAdapter(child: _FindMatchPromo(onTap: () => context.push('/recommend'))),
              FutureBuilder<_LandingData>(
                future: _future,
                builder: (BuildContext ctx, AsyncSnapshot<_LandingData> snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: CircularProgressIndicator(color: AppTheme.primary),
                        ),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: <Widget>[
                            Text(
                              snap.error.toString().replaceFirst('Exception: ', ''),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    );
                  }

                  final _LandingData data = snap.data ?? const _LandingData(categories: <dynamic>[], featured: <dynamic>[]);

                  return SliverToBoxAdapter(
                    child: Column(
                      children: <Widget>[
                        _CategoriesSection(
                          categories: data.categories,
                          iconFor: (String name) => _categoryIcons[name] ?? Icons.bug_report_outlined,
                          onTap: _openCategory,
                        ),
                        if (data.featured.isNotEmpty)
                          _FeaturedSection(listings: data.featured, onTap: _openListing),
                      ],
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(child: const _HowItWorks()),
              SliverToBoxAdapter(
                child: _BottomCta(
                  onSignUp: () => context.push('/register'),
                  onLogin: () => context.push('/login'),
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

class _LandingData {
  const _LandingData({required this.categories, required this.featured});
  final List<dynamic> categories;
  final List<dynamic> featured;
}

// ── Sections ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.pest_control_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'Pestify',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
          ),
          const Spacer(),
          TextButton(
            onPressed: onLogin,
            child: const Text('Log In'),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onFindMatch, required this.onBrowse});
  final VoidCallback onFindMatch;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Professional pest\ncontrol at your\nfingertips',
            style: TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Connect with certified pest control experts near you. Quick, reliable, and affordable — for your home or business.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onFindMatch,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Find My Match', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.navy,
                side: const BorderSide(color: AppTheme.border, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Create a Free Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const List<List<String>> stats = <List<String>>[
      <String>['500+', 'Trusted Providers'],
      <String>['10,000+', 'Happy Customers'],
      <String>['24/7', 'Emergency Service'],
      <String>['4.8★', 'Average Rating'],
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: stats
            .map(
              (List<String> s) => Expanded(
                child: Column(
                  children: <Widget>[
                    Text(s[0], style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      s[1],
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _FindMatchPromo extends StatelessWidget {
  const _FindMatchPromo({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Material(
        color: AppTheme.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.indigo, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Not sure who to pick?',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.navy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tell us your problem — we\'ll rank providers for you.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.indigo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({
    required this.categories,
    required this.iconFor,
    required this.onTap,
  });

  final List<dynamic> categories;
  final IconData Function(String name) iconFor;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Popular Services',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
          ),
          const SizedBox(height: 4),
          Text('Tap a category to see ranked providers', style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: categories.map((dynamic c) {
              final Map<String, dynamic> cat = c as Map<String, dynamic>;
              final String name = cat['name']?.toString() ?? '';
              final int id = int.tryParse(cat['id']?.toString() ?? '') ?? 0;
              return Material(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onTap(id),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(iconFor(name), color: AppTheme.primary, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.navy),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _FeaturedSection extends StatelessWidget {
  const _FeaturedSection({required this.listings, required this.onTap});
  final List<dynamic> listings;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: Text(
              'Featured Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: listings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext ctx, int i) {
                final Map<String, dynamic> l = listings[i] as Map<String, dynamic>;
                return _FeaturedCard(listing: l, onTap: () => onTap(l));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.listing, required this.onTap});
  final Map<String, dynamic> listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dynamic imagesRaw = listing['images'];
    final List<dynamic> images = imagesRaw is List ? imagesRaw : <dynamic>[];
    final String? imageUrl = images.isNotEmpty
        ? ApiEndpoints.resolveImageUrl(images.first?.toString())
        : null;
    final double price = double.tryParse(listing['price']?.toString() ?? '') ?? 0;
    final double? rating = listing['avg_rating'] == null
        ? null
        : double.tryParse(listing['avg_rating'].toString());

    return Material(
      color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 96,
                width: double.infinity,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      listing['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.navy),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          '₱${price.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        ),
                        if (rating != null) ...<Widget>[
                          const Spacer(),
                          const Icon(Icons.star_rounded, size: 13, color: AppTheme.starColor),
                          Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ],
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

  Widget _placeholder() => Container(
        color: AppTheme.primary.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: const Icon(Icons.pest_control_rounded, color: AppTheme.primary, size: 28),
      );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const List<List<String>> steps = <List<String>>[
      <String>['1', 'Search & Compare', 'Browse verified providers. Compare prices, ratings, and reviews.'],
      <String>['2', 'Book a Service', 'Pick your provider and schedule at your convenience.'],
      <String>['3', 'Get Serviced', 'A professional technician arrives fully equipped.'],
      <String>['4', 'Review & Repeat', 'Share your experience and book follow-ups as needed.'],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'How Pestify Works',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
          ),
          const SizedBox(height: 16),
          ...steps.map((List<String> s) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(s[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(s[1], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                          const SizedBox(height: 2),
                          Text(s[2], style: TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _BottomCta extends StatelessWidget {
  const _BottomCta({required this.onSignUp, required this.onLogin});
  final VoidCallback onSignUp;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.primary, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'Ready to solve your pest problem?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onSignUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sign Up Free', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onLogin,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Already have an account? Log In'),
          ),
        ],
      ),
    );
  }
}

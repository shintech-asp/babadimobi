import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/provider/provider_api.dart';

/// Provider "My Listings" screen — Active/Inactive toggle, Add FAB.
class ProviderListingsScreen extends ConsumerStatefulWidget {
  const ProviderListingsScreen({super.key});

  @override
  ConsumerState<ProviderListingsScreen> createState() =>
      _ProviderListingsScreenState();
}

class _ProviderListingsScreenState
    extends ConsumerState<ProviderListingsScreen> {
  String _status = 'active';
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final Map<String, dynamic> body =
          await ref.read(providerApiProvider).getListings(status: _status);
      final dynamic items = body['data'];
      return items is List ? items : <dynamic>[];
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Awaits the new fetch (not just assigns it) so [RefreshIndicator]'s own
  /// spinner stays up until the data has actually arrived, instead of
  /// dismissing the instant `onRefresh` returns — which made a successful
  /// pull-to-refresh look like it hadn't done anything.
  Future<void> _refresh() async {
    final Future<List<dynamic>> next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  void _switchTab(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _future = _fetch();
    });
  }

  Future<void> _addListing() async {
    final bool? created = await context.push<bool>('/provider/listings/create');
    if (created == true) _refresh();
  }

  Future<void> _editListing(Map<String, dynamic> listing) async {
    final dynamic rawId = listing['id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;
    final bool? updated = await context.push<bool>(
      '/provider/listings/edit',
      extra: <String, dynamic>{'listingId': id, 'listing': listing},
    );
    if (updated == true) _refresh();
  }

  Future<void> _toggleActive(Map<String, dynamic> listing) async {
    final dynamic rawId = listing['id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;

    final bool isActive = _status == 'active';
    final String title = isActive ? 'Deactivate listing?' : 'Reactivate listing?';
    final String body = isActive
        ? 'Seekers will no longer see this listing until you reactivate it.'
        : 'This listing will become visible to seekers again.';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(isActive ? 'Deactivate' : 'Reactivate')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final ProviderApi api = ref.read(providerApiProvider);
      if (isActive) {
        await api.deactivateListing(id);
      } else {
        await api.updateListing(id: id, status: 'active');
      }
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('My Listings'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'active', label: Text('Active')),
                ButtonSegment<String>(value: 'inactive', label: Text('Inactive')),
              ],
              selected: <String>{_status},
              onSelectionChanged: (Set<String> sel) => _switchTab(sel.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            snap.error.toString().replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final List<dynamic> listings = snap.data ?? <dynamic>[];
                if (listings.isEmpty) {
                  return RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        SizedBox(
                          height: 400,
                          child: Center(
                            child: Text(
                              _status == 'active'
                                  ? 'No active listings.\nTap + to create one.'
                                  : 'No inactive listings.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: listings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext ctx, int i) {
                      final dynamic raw = listings[i];
                      if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                      return _ListingCard(
                        listing: raw,
                        isActive: _status == 'active',
                        onTap: () => _editListing(raw),
                        onToggle: () => _toggleActive(raw),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addListing,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ── Listing card ──────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.isActive,
    required this.onTap,
    required this.onToggle,
  });

  final Map<String, dynamic> listing;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  static const Map<String, String> _pricingLabels = <String, String>{
    'fixed': 'Fixed',
    'per_sqft': 'Per Sq Ft',
    'hourly': 'Hourly',
    'custom': 'Custom',
  };

  @override
  Widget build(BuildContext context) {
    final dynamic imagesRaw = listing['images'];
    final List<dynamic> images = imagesRaw is List ? imagesRaw : <dynamic>[];
    final String? imageUrl = images.isNotEmpty
        ? ApiEndpoints.resolveImageUrl(images.first?.toString())
        : null;

    final String title = listing['title']?.toString() ?? 'Untitled';
    final String category = listing['category_name']?.toString() ?? '';
    final String pricingType = listing['pricing_type']?.toString() ?? 'fixed';
    final double price = double.tryParse(listing['price']?.toString() ?? '') ?? 0;
    final double? rating = listing['avg_rating'] == null
        ? null
        : double.tryParse(listing['avg_rating'].toString());
    final int reviewCount = int.tryParse(listing['review_count']?.toString() ?? '') ?? 0;
    final bool isEmergency = listing['is_emergency_available'] == true ||
        listing['is_emergency_available'] == 1 ||
        listing['is_emergency_available'] == '1';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEmergency)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'URGENT',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                    if (category.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(category, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          '₱${price.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13),
                        ),
                        Text(
                          ' / ${_pricingLabels[pricingType] ?? pricingType}',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        if (rating != null) ...<Widget>[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, size: 14, color: AppTheme.starColor),
                          Text(' ${rating.toStringAsFixed(1)} ($reviewCount)', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onToggle,
                        icon: Icon(isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
                        label: Text(isActive ? 'Deactivate' : 'Reactivate'),
                        style: TextButton.styleFrom(
                          foregroundColor: isActive ? Colors.red[700] : AppTheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  Widget _placeholder() {
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.08),
      child: const Icon(Icons.pest_control_rounded, color: AppTheme.primary, size: 28),
    );
  }
}

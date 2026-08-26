// ignore_for_file: avoid_dynamic_calls

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/seeker/seeker_api.dart';

class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String _searchQuery = '';
  String _cityFilter = '';

  final List<Map<String, dynamic>> _providers = <Map<String, dynamic>>[];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoad = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cityCtrl.dispose();
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

  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      setState(() {
        _providers.clear();
        _currentPage = 1;
        _hasMore = true;
        _isInitialLoad = true;
        _errorMessage = null;
      });
    }

    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final Map<String, dynamic> result =
          await ref.read(seekerApiProvider).getProviders(
                search: _searchQuery.isNotEmpty ? _searchQuery : null,
                city: _cityFilter.isNotEmpty ? _cityFilter : null,
                page: _currentPage,
              );

      final List<dynamic> items =
          (result['data'] as List<dynamic>?) ?? <dynamic>[];
      final Map<String, dynamic>? meta =
          result['meta'] as Map<String, dynamic>?;
      int? totalPages = meta?['total_pages'] as int?;
      if (totalPages == null && meta != null) {
        final int total = (meta['total'] as int?) ?? 0;
        final int limit = (meta['limit'] as int?) ?? 20;
        totalPages = limit > 0 ? ((total + limit - 1) ~/ limit) : 1;
      }

      if (!mounted) return;
      setState(() {
        for (final dynamic item in items) {
          if (item is Map<String, dynamic>) _providers.add(item);
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
    await _fetch();
    // Roll back page counter if fetch failed so retry starts from the right page.
    if (_errorMessage != null) _currentPage--;
  }

  void _applySearch(String value) {
    setState(() => _searchQuery = value.trim());
    _fetch(reset: true);
  }

  void _applyCityFilter() {
    setState(() => _cityFilter = _cityCtrl.text.trim());
    _fetch(reset: true);
  }

  void _clearCity() {
    _cityCtrl.clear();
    setState(() => _cityFilter = '');
    _fetch(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.seedColor,
          onRefresh: () => _fetch(reset: true),
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              // ── App bar ─────────────────────────────────────────────────────
              const SliverAppBar(
                backgroundColor: AppTheme.seedColor,
                foregroundColor: Colors.white,
                floating: true,
                snap: true,
                elevation: 0,
                title: Text('Browse Providers'),
              ),

              // ── Search + city filter row ─────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _applySearch,
                          decoration: InputDecoration(
                            hintText: 'Search providers…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _applySearch('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _CityFilterButton(
                        active: _cityFilter.isNotEmpty,
                        label: _cityFilter.isNotEmpty ? _cityFilter : 'City',
                        onTap: () => _showCitySheet(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Active filter chip
              if (_cityFilter.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Chip(
                          label: Text('City: $_cityFilter'),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: _clearCity,
                          backgroundColor:
                              AppTheme.primaryLight.withValues(alpha: 0.15),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                            color: AppTheme.seedColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Count label ─────────────────────────────────────────────────
              if (!_isInitialLoad && _errorMessage == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _providers.isEmpty
                          ? 'No providers found'
                          : '${_providers.length}${_hasMore ? '+' : ''} providers',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── Body ────────────────────────────────────────────────────────
              if (_isInitialLoad)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  child: _CenteredMessage(
                    icon: Icons.wifi_off_rounded,
                    message: _errorMessage!,
                    action: TextButton.icon(
                      onPressed: () => _fetch(reset: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ),
                )
              else if (_providers.isEmpty)
                const SliverFillRemaining(
                  child: _CenteredMessage(
                    icon: Icons.store_outlined,
                    message: 'No providers match your search.',
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        if (index == _providers.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ProviderCard(
                            data: _providers[index],
                            onTap: () {
                              final int? id =
                                  _providers[index]['id'] as int?;
                              if (id != null) {
                                context.push('/seeker/provider/$id');
                              }
                            },
                          ),
                        );
                      },
                      childCount:
                          _providers.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCitySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Filter by city',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cityCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'City name',
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
                onSubmitted: (_) {
                  Navigator.of(ctx).pop();
                  _applyCityFilter();
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  if (_cityFilter.isNotEmpty)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _clearCity();
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  if (_cityFilter.isNotEmpty) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _applyCityFilter();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Provider card ─────────────────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? logoUrl = data['logo_url'] as String?;
    final String company =
        (data['company_name'] as String?) ?? 'Unknown Provider';
    final String city = (data['city'] as String?) ?? '';
    final num rating = (data['rating'] as num?) ?? 0;
    final int serviceCount = (data['service_count'] as int?) ?? 0;
    final double ratingVal = rating.toDouble();

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              // Logo
              _ProviderAvatar(logoUrl: logoUrl, company: company),
              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      company,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (city.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.location_on_rounded,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            city,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        // Rating
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              ratingVal > 0
                                  ? ratingVal.toStringAsFixed(1)
                                  : 'New',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Service count
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.cleaning_services_rounded,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$serviceCount service${serviceCount != 1 ? 's' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({required this.logoUrl, required this.company});

  final String? logoUrl;
  final String company;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 60,
        height: 60,
        child: logoUrl != null && logoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _InitialAvatar(name: company),
                errorWidget: (_, __, ___) => _InitialAvatar(name: company),
              )
            : _InitialAvatar(name: company),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String initial =
        name.isNotEmpty ? name[0].toUpperCase() : 'P';
    return Container(
      color: AppTheme.primaryLight.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppTheme.seedColor,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── City filter button ─────────────────────────────────────────────────────────

class _CityFilterButton extends StatelessWidget {
  const _CityFilterButton({
    required this.active,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppTheme.seedColor
          : AppTheme.primaryLight.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.location_city_rounded,
                size: 16,
                color: active ? Colors.white : AppTheme.seedColor,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 72),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.seedColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared centered message ───────────────────────────────────────────────────

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

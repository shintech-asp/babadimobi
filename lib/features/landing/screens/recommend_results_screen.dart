import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';

/// DSS results — ranked provider cards with a match score, an AI/rule-based
/// explanation, real review snippets, and an expandable "Why this match?"
/// score breakdown. Mirrors the web's `seeker/recommend.php` result cards.
///
/// Expects GoRouter extra `{'result': <recommend.php response body>,
/// 'budgetMax': double?, 'urgency': String, 'city': String?}` — the
/// [FindMyMatchScreen] already has the ranked results from its submit call,
/// so this screen renders them directly rather than re-fetching.
class RecommendResultsScreen extends StatelessWidget {
  const RecommendResultsScreen({
    super.key,
    required this.result,
    this.budgetMax,
    this.urgency = 'flexible',
    this.city,
  });

  final Map<String, dynamic> result;
  final double? budgetMax;
  final String urgency;
  final String? city;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> results = result['results'] as List<dynamic>? ?? <dynamic>[];
    final bool degraded = result['degraded'] == true;
    final String? parsedCategoryName = result['parsed_category_name']?.toString();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Your Matches')),
      body: SafeArea(
        child: results.isEmpty
            ? _EmptyState(onEdit: () => context.pop())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: <Widget>[
                  _InterpretationRow(
                    categoryName: parsedCategoryName,
                    budgetMax: budgetMax,
                    urgency: urgency,
                    city: city,
                    onEdit: () => context.pop(),
                  ),
                  if (degraded) ...<Widget>[
                    const SizedBox(height: 12),
                    _DegradedNote(city: city),
                  ],
                  const SizedBox(height: 16),
                  ...results.map((dynamic r) {
                    if (r is! Map<String, dynamic>) return const SizedBox.shrink();
                    final int rank = int.tryParse(r['rank']?.toString() ?? '') ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ResultCard(result: r, isTop: rank == 1),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _InterpretationRow extends StatelessWidget {
  const _InterpretationRow({
    required this.categoryName,
    required this.budgetMax,
    required this.urgency,
    required this.city,
    required this.onEdit,
  });

  final String? categoryName;
  final double? budgetMax;
  final String urgency;
  final String? city;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.15)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.indigo),
          Text('Showing matches for:', style: TextStyle(fontSize: 12, color: AppTheme.navy)),
          _Pill(categoryName ?? 'Any category'),
          if (budgetMax != null) _Pill('Up to ₱${budgetMax!.toStringAsFixed(0)}'),
          if (urgency != 'flexible') _Pill(urgency == 'emergency' ? 'Emergency' : 'Soon'),
          if (city != null && city!.isNotEmpty) _Pill(city!),
          const Spacer(),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
            child: const Text('Edit', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
    );
  }
}

class _DegradedNote extends StatelessWidget {
  const _DegradedNote({required this.city});
  final String? city;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No providers found in ${city ?? 'that city'} — showing the best matches from all cities instead.',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onEdit});
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, size: 52, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No matching services yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.navy),
            ),
            const SizedBox(height: 6),
            Text(
              'Try widening your budget or picking a different category.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onEdit, child: const Text('Edit Search')),
          ],
        ),
      ),
    );
  }
}

// ── Result card ──────────────────────────────────────────────────────────────

class _ResultCard extends StatefulWidget {
  const _ResultCard({required this.result, required this.isTop});
  final Map<String, dynamic> result;
  final bool isTop;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _breakdownOpen = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> r = widget.result;
    final int rank = int.tryParse(r['rank']?.toString() ?? '') ?? 0;
    final double score = double.tryParse(r['score']?.toString() ?? '') ?? 0;
    final double price = double.tryParse(r['price']?.toString() ?? '') ?? 0;
    final double? rating = r['avg_rating'] == null ? null : double.tryParse(r['avg_rating'].toString());
    final int reviewCount = int.tryParse(r['review_count']?.toString() ?? '') ?? 0;
    final List<dynamic> reviews = r['reviews'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, dynamic> breakdown = (r['breakdown'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final int? providerId = int.tryParse(r['provider_id']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.isTop ? AppTheme.primary : AppTheme.border, width: widget.isTop ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.isTop ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: widget.isTop ? Colors.white : AppTheme.primary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      r['title']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String?>[r['company_name']?.toString(), r['city']?.toString()]
                          .where((String? s) => s != null && s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${score.round()}%',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.primary),
                  ),
                  Text('match', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: <Widget>[
              _MetaItem(icon: Icons.sell_outlined, text: '₱${price.toStringAsFixed(0)}'),
              _MetaItem(
                icon: Icons.star_rounded,
                text: reviewCount > 0 ? '${rating?.toStringAsFixed(1)} ($reviewCount)' : 'No reviews yet',
              ),
              _MetaItem(icon: Icons.category_outlined, text: r['category_name']?.toString() ?? 'General'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r['explanation']?.toString() ?? '',
            style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
          ),

          if (reviews.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            ...reviews.take(2).map((dynamic rev) => _ReviewSnippet(review: rev as Map<String, dynamic>)),
          ],

          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _breakdownOpen = !_breakdownOpen),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _breakdownOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Why this match?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ],
            ),
          ),
          if (_breakdownOpen) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: breakdown.entries.map((MapEntry<String, dynamic> e) {
                  final Map<String, dynamic> crit = (e.value as Map<String, dynamic>?) ?? <String, dynamic>{};
                  final double raw = double.tryParse(crit['raw']?.toString() ?? '') ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 78,
                          child: Text(
                            _titleCase(e.key),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.navy),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: raw.clamp(0, 1),
                              minHeight: 6,
                              backgroundColor: AppTheme.border,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Text(
                            crit['label']?.toString() ?? '',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: providerId == null
                  ? null
                  : () => context.push('/seeker/provider/$providerId'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('View Provider & Book', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  static String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: AppTheme.primary),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }
}

class _ReviewSnippet extends StatelessWidget {
  const _ReviewSnippet({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final int rating = int.tryParse(review['rating']?.toString() ?? '') ?? 0;
    final String? feedback = review['feedback']?.toString();
    final String? imagePath = review['feedback_image']?.toString();
    final String? imageUrl = imagePath != null && imagePath.isNotEmpty
        ? ApiEndpoints.resolveImageUrl(imagePath)
        : null;
    String dateLabel = '';
    final dynamic createdAt = review['created_at'];
    if (createdAt != null) {
      try {
        dateLabel = DateFormat('MMM d, yyyy').format(DateTime.parse(createdAt.toString()));
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: const Border(left: BorderSide(color: AppTheme.border, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Row(
                children: List<Widget>.generate(
                  5,
                  (int i) => Icon(
                    Icons.star_rounded,
                    size: 12,
                    color: i < rating ? AppTheme.starColor : AppTheme.border,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${review['author'] ?? 'A'} · $dateLabel',
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
            ],
          ),
          if (feedback != null && feedback.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '"$feedback"',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87),
            ),
          ],
          if (imageUrl != null) ...<Widget>[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 90,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

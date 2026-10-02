import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Subscription tier + plan purchase/renewal — owner-only action (matches
/// the web sidebar's "Upgrade to Pro"/"Subscription" link, gated to
/// `$is_owner`), mirrors `provider-portal/subscriptions.php`.
class PortalSubscriptionScreen extends ConsumerStatefulWidget {
  const PortalSubscriptionScreen({super.key});

  @override
  ConsumerState<PortalSubscriptionScreen> createState() => _PortalSubscriptionScreenState();
}

class _PortalSubscriptionScreenState extends ConsumerState<PortalSubscriptionScreen> {
  late Future<Map<String, dynamic>> _future;
  int? _purchasingPlanId;
  String? _purchasingCycle;
  bool _startingTrial = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getSubscription();
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

  Future<void> _purchase(int planId, String cycle) async {
    setState(() {
      _purchasingPlanId = planId;
      _purchasingCycle = cycle;
    });
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).purchaseSubscription(planId: planId, billingCycle: cycle);
      final String? checkoutUrl = result['checkout_url']?.toString();
      if (!mounted || checkoutUrl == null) return;

      // The WebView pops `true` once it reaches PayMongo's success redirect
      // (never actually loading that web page — it requires a PHP session
      // this app doesn't have). `true` here only means "checkout finished",
      // not "activated" — the confirm screen does the real verify+activate
      // work via api/v1/portal/subscriptions/confirm.php and pops its own
      // true/false for that.
      final Object? reachedSuccess = await context.push<bool>(
        '/portal/subscription-checkout',
        extra: <String, dynamic>{'checkoutUrl': checkoutUrl},
      );
      if (!mounted) return;

      if (reachedSuccess == true) {
        final Object? confirmed = await context.push<bool>('/portal/subscription-confirm');
        if (!mounted) return;
        if (confirmed == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're Pro! All portal features are now unlocked."), backgroundColor: AppTheme.primary),
          );
        }
      }
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() {
          _purchasingPlanId = null;
          _purchasingCycle = null;
        });
      }
    }
  }

  Future<void> _startTrial() async {
    setState(() => _startingTrial = true);
    try {
      await ref.read(portalApiProvider).startTrial();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Your free trial is active! All portal features are unlocked for 1 month."), backgroundColor: AppTheme.primary),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _startingTrial = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Subscription')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(snapshot.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final String tier = body['tier']?.toString() ?? 'free';
          final String? tierExpires = body['tier_expires']?.toString();
          final String? tierGrace = body['tier_grace']?.toString();
          final List<dynamic> plans = body['plans'] as List<dynamic>? ?? <dynamic>[];
          final bool trialEligible = body['trial_eligible'] == true;

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                _TierStatusCard(tier: tier, expiresAt: tierExpires, graceEndsAt: tierGrace),
                if (trialEligible) ...<Widget>[
                  const SizedBox(height: 14),
                  _TrialCard(isBusy: _startingTrial, onStart: _startTrial),
                ],
                const SizedBox(height: 20),
                const Text('PLANS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                if (plans.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No plans available right now.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...plans.map((dynamic p) {
                    final Map<String, dynamic> plan = p as Map<String, dynamic>;
                    final int planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
                    final bool busyMonthly = _purchasingPlanId == planId && _purchasingCycle == 'monthly';
                    final bool busyYearly = _purchasingPlanId == planId && _purchasingCycle == 'yearly';
                    return _PlanCard(
                      plan: plan,
                      isCurrentTierPaid: tier == 'pro' || tier == 'grace',
                      busyMonthly: busyMonthly,
                      busyYearly: busyYearly,
                      anyBusy: _purchasingPlanId != null,
                      onSelectMonthly: () => _purchase(planId, 'monthly'),
                      onSelectYearly: () => _purchase(planId, 'yearly'),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TierStatusCard extends StatelessWidget {
  const _TierStatusCard({required this.tier, this.expiresAt, this.graceEndsAt});

  final String tier;
  final String? expiresAt;
  final String? graceEndsAt;

  String _fmt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPro = tier == 'pro';
    final bool isGrace = tier == 'grace';
    final Color color = isPro ? const Color(0xFF6366F1) : (isGrace ? Colors.orange[800]! : AppTheme.textMuted);
    final String label = isPro ? 'Pro' : (isGrace ? 'Grace Period' : 'Free');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isPro
            ? const LinearGradient(colors: <Color>[Color(0xFF6366F1), Color(0xFF4F46E5)])
            : null,
        color: isPro ? null : AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isPro ? null : Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(isPro ? Icons.star_rounded : Icons.workspace_premium_outlined, color: isPro ? Colors.white : color, size: 22),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isPro ? Colors.white : AppTheme.navy)),
            ],
          ),
          if (isPro || isGrace) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              isGrace ? 'Renew by ${_fmt(graceEndsAt)} to keep Pro access.' : 'Active until ${_fmt(expiresAt)}.',
              style: TextStyle(fontSize: 13, color: isPro ? Colors.white.withValues(alpha: 0.9) : Colors.orange[800]),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 10),
            const Text('Basic staff management only. Upgrade to unlock HR, Finance, and full CRM.', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _TrialCard extends StatelessWidget {
  const _TrialCard({required this.isBusy, required this.onStart});

  final bool isBusy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: <Color>[Color(0xFFEEF2FF), Color(0xFFF5F3FF)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.card_giftcard_rounded, color: Color(0xFF6366F1), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Try Pro free for 1 month', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                SizedBox(height: 2),
                Text('No payment required, no card needed.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: isBusy ? null : onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrentTierPaid,
    required this.busyMonthly,
    required this.busyYearly,
    required this.anyBusy,
    required this.onSelectMonthly,
    required this.onSelectYearly,
  });

  final Map<String, dynamic> plan;
  final bool isCurrentTierPaid;
  final bool busyMonthly;
  final bool busyYearly;
  final bool anyBusy;
  final VoidCallback onSelectMonthly;
  final VoidCallback onSelectYearly;

  double _n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    final double monthly = _n(plan['monthly_price']);
    final double yearly = _n(plan['yearly_price']);
    final double savings = _n(plan['savings']);
    final NumberFormat peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(plan['name']?.toString() ?? 'Plan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.navy)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: anyBusy ? null : onSelectMonthly,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: busyMonthly
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('${peso.format(monthly)}/mo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: anyBusy ? null : onSelectYearly,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: busyYearly
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : Text('${peso.format(yearly)}/yr'),
                ),
              ),
            ],
          ),
          if (savings > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text('Save ${peso.format(savings)} with yearly billing', style: TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Provider-portal home — the role-gated navigation shell every later phase's
/// screens plug into. Direct structural mirror of
/// `provider-portal/includes/portal-sidebar.php`'s gating logic:
///   - `owner` sees every department; `hr`/`finance`/`crm` see only their own
///     (or all of them, if `department == 'all'`).
///   - A plain `portal_employee` account (or a promoted staff member also
///     linked to an `employees` row) additionally gets a "My Account"
///     self-service section.
///   - Free-tier vs Pro-only items within each department follow the exact
///     same split as the web sidebar (e.g. HR's Employees/Leave Requests are
///     always free; Attendance/Timekeeping/Payroll/Recruitment need Pro).
/// Every destination without its own phase built yet is still a "Coming
/// soon" placeholder — this phase only wires up tier visibility/purchase
/// and the resulting lock icons, not the HR/Finance/CRM screens themselves.
class PortalHomeScreen extends ConsumerStatefulWidget {
  const PortalHomeScreen({super.key});

  @override
  ConsumerState<PortalHomeScreen> createState() => _PortalHomeScreenState();
}

class _PortalHomeScreenState extends ConsumerState<PortalHomeScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final PortalApi api = ref.read(portalApiProvider);
      final Map<String, dynamic> me = await api.getMe();
      // Tier is supplementary — if it fails to load for any reason, fall
      // back to 'free' (the safer default: locks Pro items rather than
      // wrongly unlocking them) instead of failing the whole shell.
      Map<String, dynamic> subscription;
      try {
        subscription = await api.getSubscription();
      } catch (_) {
        subscription = <String, dynamic>{'tier': 'free'};
      }
      return <String, dynamic>{'me': me, 'subscription': subscription};
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
    } catch (_) {
      // FutureBuilder surfaces the error via snapshot.hasError.
    }
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }

  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogCtx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Portal')),
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
                    Text(
                      snapshot.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final Map<String, dynamic> body = snapshot.data ?? <String, dynamic>{};
          final Map<String, dynamic> me = (body['me'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final Map<String, dynamic> subscription = (body['subscription'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final String accountType = me['account_type']?.toString() ?? 'staff';
          final Map<String, dynamic> staff = (me['staff'] as Map<String, dynamic>?) ?? <String, dynamic>{};

          final String fullName = staff['full_name']?.toString() ?? 'Staff';
          final String companyName = staff['company_name']?.toString() ?? 'Provider';
          final String role = staff['role']?.toString() ?? 'employee';
          final String department = staff['department']?.toString() ?? '';
          final String staffType = staff['staff_type']?.toString() ?? 'office';
          final bool mustChangePassword = staff['must_change_password'] == true;
          final int employeeId = int.tryParse(staff['employee_id']?.toString() ?? '') ?? 0;

          final bool isOwner = role == 'owner';
          final bool canHr = isOwner || department == 'hr' || department == 'all';
          final bool canFinance = isOwner || department == 'finance' || department == 'all';
          final bool canCrm = isOwner || department == 'crm' || department == 'all';
          final bool hasSelfService = accountType == 'employee' || employeeId > 0;
          final bool isFieldTech = staffType == 'field';

          final String tier = subscription['tier']?.toString() ?? 'free';
          final bool isPaid = tier == 'pro' || tier == 'grace';

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                _CompanyHeader(companyName: companyName, fullName: fullName, role: role, department: department, tier: tier),
                const SizedBox(height: 20),

                if (mustChangePassword) ...<Widget>[
                  _ActionRequiredBanner(onTap: () => context.push('/portal/change-password')),
                  const SizedBox(height: 20),
                  // Was previously a dead end: everything below (including
                  // Logout) lived only in the `else` branch, so an account
                  // that couldn't/wouldn't change its password right away
                  // had no way to sign out short of killing the app.
                  _NavTile(icon: Icons.logout_rounded, label: 'Logout', onTap: _logout, danger: true),
                ] else ...<Widget>[
                  if (hasSelfService) ...<Widget>[
                    _SectionLabel('My Account'),
                    // The web hides this for HR because HR has a separate
                    // Timekeeping link to the same page — but Timekeeping
                    // isn't built on mobile yet, so hiding this here left HR
                    // staff with no working clock-in at all. Always show it
                    // until Timekeeping exists.
                    _NavTile(icon: Icons.qr_code_rounded, label: 'Time In / Out', onTap: () => context.push('/portal/attendance')),
                    _NavTile(icon: Icons.payments_outlined, label: 'My Salary', onTap: () => context.push('/portal/payslips')),
                    _NavTile(icon: Icons.description_outlined, label: 'My Leave Requests', onTap: () => context.push('/portal/leave-requests')),
                    if (isFieldTech)
                      _NavTile(icon: Icons.local_shipping_outlined, label: 'My Assigned Services', onTap: () => context.push('/portal/my-bookings')),
                    const SizedBox(height: 12),
                  ],

                  // HR: Employees + Leave Requests are always free (Leave
                  // Requests shows a "Basic" chip when not paid, matching
                  // web); the rest need Pro.
                  if (canHr) ...<Widget>[
                    _SectionLabel('HR Department'),
                    // /portal/staff manages provider_staff (promoted portal
                    // LOGIN accounts — owner/hr/finance/crm); /portal/employees
                    // manages the employees table (HR personnel records,
                    // salary, gov IDs) — two different things. api/v1/portal/
                    // staff/* is owner-only server-side, so Staff Accounts
                    // stays gated + relabeled to match; Employees is free-tier
                    // and owner-or-hr, matching provider-portal/employees.php.
                    if (isOwner)
                      _NavTile(icon: Icons.badge_outlined, label: 'Staff Accounts', onTap: () => context.push('/portal/staff')),
                    _NavTile(icon: Icons.people_alt_outlined, label: 'Employees', onTap: () => context.push('/portal/employees')),
                    _NavTile(icon: Icons.description_outlined, label: 'Leave Requests', chip: isPaid ? null : 'Basic', onTap: () => context.push('/portal/hr/leave-requests')),
                    if (isPaid) ...<Widget>[
                      _NavTile(icon: Icons.pie_chart_outline_rounded, label: 'HR Dashboard', onTap: () => _comingSoon('HR Dashboard')),
                      _NavTile(icon: Icons.access_time_rounded, label: 'Attendance', onTap: () => _comingSoon('Attendance')),
                      _NavTile(icon: Icons.qr_code_rounded, label: 'Timekeeping', onTap: () => _comingSoon('Timekeeping')),
                      _NavTile(icon: Icons.payments_outlined, label: 'Payroll', onTap: () => context.push('/portal/payroll')),
                      _NavTile(icon: Icons.person_add_alt_1_outlined, label: 'Recruitment', onTap: () => _comingSoon('Recruitment')),
                    ] else ...<Widget>[
                      const _LockedNavTile(icon: Icons.access_time_rounded, label: 'Attendance'),
                      const _LockedNavTile(icon: Icons.qr_code_rounded, label: 'Timekeeping'),
                      const _LockedNavTile(icon: Icons.payments_outlined, label: 'Payroll'),
                      const _LockedNavTile(icon: Icons.person_add_alt_1_outlined, label: 'Recruitment'),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // Finance: Income is always free ("View" chip when not
                  // paid); the rest need Pro.
                  if (canFinance) ...<Widget>[
                    _SectionLabel('Finance Department'),
                    _NavTile(icon: Icons.arrow_circle_up_outlined, label: 'Income', chip: isPaid ? null : 'View', onTap: () => context.push('/portal/income')),
                    if (isPaid) ...<Widget>[
                      _NavTile(icon: Icons.show_chart_rounded, label: 'Finance Dashboard', onTap: () => _comingSoon('Finance Dashboard')),
                      _NavTile(icon: Icons.arrow_circle_down_outlined, label: 'Expenses', onTap: () => context.push('/portal/expenses')),
                      _NavTile(icon: Icons.request_quote_outlined, label: 'Budget Requests', onTap: () => context.push('/portal/budget-requests')),
                      _NavTile(icon: Icons.inventory_2_outlined, label: 'Inventory', onTap: () => context.push('/portal/inventory')),
                      if (!canHr)
                        _NavTile(icon: Icons.payments_outlined, label: 'Payroll (Approve)', onTap: () => context.push('/portal/payroll')),
                    ] else ...<Widget>[
                      const _LockedNavTile(icon: Icons.show_chart_rounded, label: 'Finance Dashboard'),
                      const _LockedNavTile(icon: Icons.arrow_circle_down_outlined, label: 'Expenses'),
                      const _LockedNavTile(icon: Icons.request_quote_outlined, label: 'Budget Requests'),
                      const _LockedNavTile(icon: Icons.inventory_2_outlined, label: 'Inventory'),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // CRM: Bookings/Requests/Services are always free (Services
                  // shows a "View" chip when not paid); the rest need Pro.
                  if (canCrm) ...<Widget>[
                    _SectionLabel('CRM / Operations'),
                    _NavTile(
                      icon: Icons.event_available_outlined,
                      label: 'Bookings',
                      onTap: () => context.push('/portal/crm/bookings', extra: <String, String>{'title': 'Bookings'}),
                    ),
                    _NavTile(
                      icon: Icons.inbox_outlined,
                      label: 'Requests',
                      onTap: () => context.push('/portal/crm/bookings', extra: <String, String>{'status': 'pending', 'title': 'Requests'}),
                    ),
                    _NavTile(icon: Icons.work_outline_rounded, label: 'Services', chip: isPaid ? null : 'View', onTap: () => context.push('/portal/crm/services')),
                    if (isPaid) ...<Widget>[
                      _NavTile(icon: Icons.headset_mic_outlined, label: 'CRM Dashboard', onTap: () => _comingSoon('CRM Dashboard')),
                      _NavTile(icon: Icons.calendar_month_outlined, label: 'Schedules', onTap: () => _comingSoon('Schedules')),
                      _NavTile(icon: Icons.campaign_outlined, label: 'Customer Outreach', onTap: () => context.push('/portal/crm/outreach')),
                    ] else ...<Widget>[
                      const _LockedNavTile(icon: Icons.headset_mic_outlined, label: 'CRM Dashboard'),
                      const _LockedNavTile(icon: Icons.calendar_month_outlined, label: 'Schedules'),
                      const _LockedNavTile(icon: Icons.campaign_outlined, label: 'Customer Outreach'),
                    ],
                    const SizedBox(height: 12),
                  ],

                  if (isOwner) ...<Widget>[
                    _SectionLabel('Management'),
                    if (isPaid)
                      _NavTile(icon: Icons.archive_outlined, label: 'Archive', onTap: () => _comingSoon('Archive'))
                    else
                      const _LockedNavTile(icon: Icons.archive_outlined, label: 'Archive'),
                    _NavTile(icon: Icons.tune_rounded, label: 'Settings', onTap: () => _comingSoon('Settings')),
                    _NavTile(
                      icon: Icons.workspace_premium_outlined,
                      label: tier == 'free' ? 'Upgrade to Pro' : 'Subscription',
                      onTap: () => context.push('/portal/subscription'),
                    ),
                    const SizedBox(height: 12),
                  ],

                  _SectionLabel('Account'),
                  if (canHr || canFinance || canCrm || isOwner || isFieldTech)
                    _NavTile(icon: Icons.chat_bubble_outline_rounded, label: 'Messages', onTap: () => _comingSoon('Messages')),
                  _NavTile(icon: Icons.key_outlined, label: 'Change Password', onTap: () => context.push('/portal/change-password')),
                  _NavTile(icon: Icons.logout_rounded, label: 'Logout', onTap: _logout, danger: true),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompanyHeader extends StatelessWidget {
  const _CompanyHeader({
    required this.companyName,
    required this.fullName,
    required this.role,
    required this.department,
    required this.tier,
  });

  final String companyName;
  final String fullName;
  final String role;
  final String department;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final bool isPro = tier == 'pro';
    final bool isGrace = tier == 'grace';
    final Color tierColor = isPro ? const Color(0xFF6366F1) : (isGrace ? Colors.orange[300]! : Colors.white);
    final String tierLabel = isPro ? 'PRO' : (isGrace ? 'GRACE' : 'FREE');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1A2744), Color(0xFF2D3561)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: <Color>[AppTheme.primary, AppTheme.primaryLight]),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.pest_control_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Pestify Provider Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: isPro ? 1 : 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: isPro ? null : Border.all(color: tierColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(color: isPro ? Colors.white : tierColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary,
                  child: Text(
                    fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(
                        department.isEmpty ? role : '$role · $department',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(companyName, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionRequiredBanner extends StatelessWidget {
  const _ActionRequiredBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFDBA74)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A3412)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Set a new password to access the portal.',
              style: TextStyle(fontSize: 13, color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.chip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? Colors.red[700]! : AppTheme.navy;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (chip != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
                child: Text(chip!.toUpperCase(), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.4)),
              ),
              const SizedBox(width: 6),
            ],
            if (!danger) const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
          ],
        ),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}

/// A Pro-locked nav item — matches the web sidebar's lock chip on gated nav
/// items. Tapping it opens the Subscription screen rather than the feature.
class _LockedNavTile extends StatelessWidget {
  const _LockedNavTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textMuted, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: const Text('PRO', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF6366F1), letterSpacing: 0.4)),
        ),
        dense: true,
        onTap: () => context.push('/portal/subscription'),
      ),
    );
  }
}

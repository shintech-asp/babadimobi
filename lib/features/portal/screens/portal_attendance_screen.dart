import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';
import 'package:pestify_flutter/features/portal/portal_api.dart';

/// Self clock-in/clock-out + this month's attendance history — mirrors
/// `provider-portal/timekeeping.php`'s own self time-in/out section (via the
/// shared `selfClockIn()`/`selfClockOut()` helpers, not a second copy).
class PortalAttendanceScreen extends ConsumerStatefulWidget {
  const PortalAttendanceScreen({super.key});

  @override
  ConsumerState<PortalAttendanceScreen> createState() => _PortalAttendanceScreenState();
}

class _PortalAttendanceScreenState extends ConsumerState<PortalAttendanceScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      return await ref.read(portalApiProvider).getAttendance();
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

  Future<void> _clockIn() async {
    setState(() => _acting = true);
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).clockIn();
      if (!mounted) return;
      final int late = int.tryParse(result['late_min']?.toString() ?? '0') ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(late > 0 ? 'Clocked in — $late min late' : 'Clocked in on time'),
          backgroundColor: AppTheme.primary,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _clockOut() async {
    setState(() => _acting = true);
    try {
      final Map<String, dynamic> result = await ref.read(portalApiProvider).clockOut();
      if (!mounted) return;
      final double hours = double.tryParse(result['hours_worked']?.toString() ?? '0') ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clocked out — ${hours.toStringAsFixed(1)}h worked'), backgroundColor: AppTheme.primary),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Time In / Out')),
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
          final List<dynamic> history = body['data'] as List<dynamic>? ?? <dynamic>[];
          final Map<String, dynamic> today = (body['today'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final bool clockedIn = today['clocked_in'] == true;
          final bool clockedOut = today['clocked_out'] == true;

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                _TodayCard(
                  clockedIn: clockedIn,
                  clockedOut: clockedOut,
                  timeIn: today['time_in']?.toString(),
                  timeOut: today['time_out']?.toString(),
                  acting: _acting,
                  onClockIn: _clockIn,
                  onClockOut: _clockOut,
                ),
                const SizedBox(height: 20),
                Text(
                  'THIS MONTH',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No attendance records yet.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ...history.map((dynamic row) => _HistoryRow(row: row as Map<String, dynamic>)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.clockedIn,
    required this.clockedOut,
    required this.timeIn,
    required this.timeOut,
    required this.acting,
    required this.onClockIn,
    required this.onClockOut,
  });

  final bool clockedIn;
  final bool clockedOut;
  final String? timeIn;
  final String? timeOut;
  final bool acting;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;

  String _fmt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm:ss').parse(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: <Widget>[
          Text(DateFormat('EEEE, MMMM d').format(DateTime.now()), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Column(
                children: <Widget>[
                  const Text('Time In', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(height: 4),
                  Text(_fmt(timeIn), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                ],
              ),
              Container(width: 1, height: 36, color: AppTheme.border),
              Column(
                children: <Widget>[
                  const Text('Time Out', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(height: 4),
                  Text(_fmt(timeOut), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navy)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: acting
                  ? null
                  : clockedOut
                      ? null
                      : clockedIn
                          ? onClockOut
                          : onClockIn,
              icon: Icon(clockedIn && !clockedOut ? Icons.logout_rounded : Icons.login_rounded, size: 18),
              label: Text(
                clockedOut
                    ? 'Done for today'
                    : clockedIn
                        ? 'Clock Out'
                        : 'Clock In',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: clockedIn && !clockedOut ? Colors.orange[700] : AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});
  final Map<String, dynamic> row;

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('MMM d').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _fmtTime(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm:ss').parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int lateMin = int.tryParse(row['late_minutes']?.toString() ?? '0') ?? 0;
    final double hours = double.tryParse(row['hours_worked']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 48, child: Text(_fmtDate(row['work_date']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.navy))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_fmtTime(row['time_in'])} – ${_fmtTime(row['time_out'])}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ),
          if (lateMin > 0)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text('${lateMin}m late', style: TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.w700)),
            ),
          Text('${hours.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.navy)),
        ],
      ),
    );
  }
}

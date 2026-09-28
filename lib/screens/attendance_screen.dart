import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../services/attendance_detail_service.dart';
import '../state/session_provider.dart';

/// The child's full attendance record — totals across everything marked, then
/// day by day, newest first.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Filter { all, absent, late, excused }

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _service = AttendanceDetailService();
  Future<AttendanceHistory>? _future;
  String? _loadedFor;
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final student = context.watch<SessionProvider>().selectedStudent;
    if (student != null && _loadedFor != student.id) {
      _loadedFor = student.id;
      _future = _service.fetchHistory(student);
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.heroBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Attendance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
            if (student != null)
              Text(student.fullName,
                  style: TextStyle(fontSize: 11.5, color: context.colors.textMuted)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border),
        ),
      ),
      body: FutureBuilder<AttendanceHistory>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          final h = snap.data ?? AttendanceHistory.empty;
          if (h.marked == 0) {
            return const _EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Nothing marked yet',
              message: 'Each day the register is taken for your child’s class will appear here.',
            );
          }

          final days = switch (_filter) {
            _Filter.absent => h.days.where((d) => d.isAbsent).toList(),
            _Filter.late => h.days.where((d) => d.isLate).toList(),
            _Filter.excused => h.days.where((d) => d.isExcused).toList(),
            _Filter.all => h.days,
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _RateCard(history: h),
              const SizedBox(height: 14),
              _Filters(
                history: h,
                selected: _filter,
                onChange: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 12),
              if (days.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text('Nothing in this category — good news.',
                        style: TextStyle(fontSize: 12.5, color: context.colors.textMuted)),
                  ),
                )
              else
                ...days.map((d) => _DayRow(day: d)),
            ],
          );
        },
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  final AttendanceHistory history;
  const _RateCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final rate = history.rate;
    // Thresholds a school would recognise: below 90% is usually where a
    // conversation starts, below 75% is a serious concern.
    final tone = rate == null
        ? context.colors.textMuted
        : rate >= 90
            ? context.colors.success
            : rate >= 75
                ? context.colors.warning
                : context.colors.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rate == null ? '—' : '${rate.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 38, fontWeight: FontWeight.w700, color: tone, height: 1)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('attendance rate\nover ${history.marked} marked days',
                    style: TextStyle(fontSize: 11.5, color: context.colors.textMuted, height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: rate == null ? 0 : (rate / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: context.colors.bg,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Tally(label: 'Present', value: history.present, color: context.colors.success),
              _Tally(label: 'Late', value: history.late, color: context.colors.warning),
              _Tally(label: 'Absent', value: history.absent, color: context.colors.danger),
              if (history.excused > 0)
                _Tally(label: 'Excused', value: history.excused, color: context.colors.primary),
            ],
          ),
          if (history.excused > 0)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Excused days are left out of the rate — they neither help nor hurt it.',
                style: TextStyle(fontSize: 10.5, color: context.colors.textMuted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Tally({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 7, height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('$value',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          Text(label, style: TextStyle(fontSize: 10.5, color: context.colors.textMuted)),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final AttendanceHistory history;
  final _Filter selected;
  final ValueChanged<_Filter> onChange;

  const _Filters({required this.history, required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final chips = <(_Filter, String)>[
      (_Filter.all, 'All ${history.marked}'),
      if (history.absent > 0) (_Filter.absent, 'Absent ${history.absent}'),
      if (history.late > 0) (_Filter.late, 'Late ${history.late}'),
      if (history.excused > 0) (_Filter.excused, 'Excused ${history.excused}'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in chips) ...[
            Material(
              color: selected == value ? context.colors.primaryPale : context.colors.cardBg,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => onChange(value),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected == value ? context.colors.primary : context.colors.border),
                  ),
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected == value ? context.colors.primaryDark : context.colors.textSecondary,
                      )),
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

({Color color, IconData icon}) _styleFor(AppColors c, String status) {
  switch (status) {
    case 'Present':
      return (color: c.success, icon: Icons.check_circle_rounded);
    case 'Late':
      return (color: c.warning, icon: Icons.schedule_rounded);
    case 'Absent':
      return (color: c.danger, icon: Icons.cancel_rounded);
    case 'Excused':
      return (color: c.primary, icon: Icons.verified_user_rounded);
    default:
      return (color: c.textMuted, icon: Icons.help_outline_rounded);
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class _DayRow extends StatelessWidget {
  final AttendanceDay day;
  const _DayRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final s = _styleFor(context.colors, day.status);
    final d = day.parsed;
    final label = d == null
        ? day.date
        : '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, size: 18, color: s.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                if (day.remark.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(day.remark,
                        style: TextStyle(fontSize: 11.5, color: context.colors.textSecondary)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(day.status,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: s.color)),
              if (day.time.isNotEmpty)
                Text(day.time,
                    style: TextStyle(fontSize: 10.5, color: context.colors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                  color: context.colors.primaryPale, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, size: 28, color: context.colors.primary),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
            const SizedBox(height: 5),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.colors.textMuted, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

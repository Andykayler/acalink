import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../services/calendar_service.dart';
import '../state/session_provider.dart';

/// The school year, for families.
///
/// A list split into what is coming and what has passed, rather than a month
/// grid. A school year is a few dozen dated things; a grid would spend most of
/// its space on empty squares while burying the two dates a parent opened the
/// app to find.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _service = CalendarService();
  Future<List<SchoolEvent>>? _future;
  String? _loadedFor;
  bool _showPast = false;

  /// Category colours, chosen so exams and holidays are told apart at a
  /// glance — those are the two a parent scans for.
  Color _tint(BuildContext context, String category) {
    final c = context.colors;
    switch (category) {
      case 'exam':
        return c.danger;
      case 'holiday':
        return c.success;
      case 'meeting':
        return c.warning;
      case 'visiting':
      case 'term':
        return c.primary;
      case 'sports':
        return c.secondary;
      default:
        return c.textMuted;
    }
  }

  String _label(String category) {
    switch (category) {
      case 'term':
        return 'TERM';
      case 'exam':
        return 'EXAMS';
      case 'holiday':
        return 'HOLIDAY';
      case 'meeting':
        return 'MEETING';
      case 'visiting':
        return 'VISITING DAY';
      case 'sports':
        return 'SPORTS';
      default:
        return 'SCHOOL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<SessionProvider>().selectedStudent;
    final code = student?.schoolCode ?? '';
    if (code.isNotEmpty && _loadedFor != code) {
      _loadedFor = code;
      _future = _service.fetch(code);
    }

    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.heroBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('School Calendar',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary)),
            Text('Term dates, exams and holidays',
                style: TextStyle(fontSize: 11.5, color: c.textMuted)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: FutureBuilder<List<SchoolEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? const <SchoolEvent>[];
          final today = CalendarService.todayIso();
          final upcoming = all.where((e) => !e.isPast(today)).toList();
          final past = all.where((e) => e.isPast(today)).toList().reversed.toList();

          if (all.isEmpty) {
            return _Empty(
              icon: Icons.event_busy_rounded,
              title: 'Nothing on the calendar yet',
              sub: 'The school has not published any dates. '
                  'Term dates and exam weeks will appear here.',
            );
          }

          final shown = _showPast ? past : upcoming;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Toggle(
                showPast: _showPast,
                upcomingCount: upcoming.length,
                pastCount: past.length,
                onChanged: (v) => setState(() => _showPast = v),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                _Empty(
                  icon: Icons.event_available_rounded,
                  title: _showPast ? 'Nothing has passed yet' : 'Nothing coming up',
                  sub: _showPast
                      ? 'Events move here once their last day is over.'
                      : 'Check back — the school adds dates as the term is planned.',
                )
              else
                ...shown.map((e) => _EventCard(
                      event: e,
                      tint: _tint(context, e.category),
                      label: _label(e.category),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool showPast;
  final int upcomingCount;
  final int pastCount;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.showPast,
    required this.upcomingCount,
    required this.pastCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chip(String text, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? c.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : c.textMuted,
                ),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        chip('Coming up ($upcomingCount)', !showPast, () => onChanged(false)),
        chip('Past ($pastCount)', showPast, () => onChanged(true)),
      ]),
    );
  }
}

class _EventCard extends StatelessWidget {
  final SchoolEvent event;
  final Color tint;
  final String label;

  const _EventCard({required this.event, required this.tint, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = event.daysFrom(DateTime.now());

    // Only near dates get a countdown. "In 214 days" is noise; "in 3 days" is
    // the reason a parent opened the screen.
    String? soon;
    if (days != null) {
      if (days == 0) {
        soon = 'Today';
      } else if (days == 1) {
        soon = 'Tomorrow';
      } else if (days > 1 && days <= 30) {
        soon = 'In $days days';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: tint,
                            )),
                      ),
                      if (soon != null) ...[
                        const SizedBox(width: 8),
                        Text(soon,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary)),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    Text(event.title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary)),
                    const SizedBox(height: 3),
                    Text(event.when,
                        style: TextStyle(fontSize: 12.5, color: c.textMuted)),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(event.description,
                          style: TextStyle(
                              fontSize: 13, height: 1.45, color: c.textSecondary)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;

  const _Empty({required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: c.textMuted),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textMuted)),
        ],
      ),
    );
  }
}

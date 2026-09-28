import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../services/discipline_service.dart';
import '../state/session_provider.dart';

/// A child's conduct record.
///
/// This is the most delicate screen in the app: a parent opening it is being
/// told something about their child they may not want to hear, possibly for
/// the first time, and possibly in front of the child. So it opens with what
/// is *outstanding* rather than a running total of everything ever recorded —
/// a clean record should read as clean, and a resolved incident should read as
/// finished rather than as a permanent mark.
///
/// It is deliberately read-only. A parent who disagrees with an entry needs a
/// conversation with the school, and the app has Messages for that; a dispute
/// button here would only produce a queue nobody owns.
class DisciplineScreen extends StatefulWidget {
  const DisciplineScreen({super.key});

  @override
  State<DisciplineScreen> createState() => _DisciplineScreenState();
}

class _DisciplineScreenState extends State<DisciplineScreen> {
  final _service = DisciplineService();
  Future<List<DisciplineCase>>? _future;
  String? _loadedFor;
  bool _showResolved = false;

  Color _severityColor(BuildContext context, String severity) {
    final c = context.colors;
    switch (severity.toLowerCase()) {
      case 'high':
        return c.danger;
      case 'low':
        return c.success;
      default:
        return c.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<SessionProvider>().selectedStudent;
    if (student != null && _loadedFor != student.id) {
      _loadedFor = student.id;
      _future = _service.fetchCases(student);
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
            Text('Conduct',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary)),
            if (student != null)
              Text(student.fullName,
                  style: TextStyle(fontSize: 11.5, color: c.textMuted)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: FutureBuilder<List<DisciplineCase>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? const <DisciplineCase>[];
          final open = all.where((x) => x.isOpen).toList();
          final resolved = all.where((x) => !x.isOpen).toList();

          if (all.isEmpty) {
            return _Clean(name: student?.fullName ?? 'Your child');
          }

          final shown = _showResolved ? resolved : open;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Summary(open: open.length, resolved: resolved.length),
              const SizedBox(height: 16),
              _Toggle(
                showResolved: _showResolved,
                openCount: open.length,
                resolvedCount: resolved.length,
                onChanged: (v) => setState(() => _showResolved = v),
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    _showResolved
                        ? 'Nothing has been resolved yet.'
                        : 'Nothing outstanding — every incident on record has been resolved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: c.textMuted),
                  ),
                )
              else
                ...shown.map((x) => _CaseCard(
                      item: x,
                      tint: _severityColor(context, x.severity),
                    )),
              const SizedBox(height: 20),
              Text(
                'Recorded by the school. If something here does not look right, '
                'message the class teacher rather than replying to a notification.',
                style: TextStyle(fontSize: 12, height: 1.5, color: c.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int open;
  final int resolved;
  const _Summary({required this.open, required this.resolved});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final good = open == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (good ? c.success : c.warning).withValues(alpha: 0.10),
        border: Border.all(color: (good ? c.success : c.warning).withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(good ? Icons.verified_outlined : Icons.info_outline_rounded,
            color: good ? c.success : c.warning, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                good
                    ? 'Nothing outstanding'
                    : '$open open ${open == 1 ? 'matter' : 'matters'}',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: c.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                resolved == 0
                    ? 'No incidents have been recorded and resolved.'
                    : '$resolved already resolved.',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool showResolved;
  final int openCount;
  final int resolvedCount;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.showResolved,
    required this.openCount,
    required this.resolvedCount,
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
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : c.textMuted,
                  )),
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
        chip('Open ($openCount)', !showResolved, () => onChanged(false)),
        chip('Resolved ($resolvedCount)', showResolved, () => onChanged(true)),
      ]),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final DisciplineCase item;
  final Color tint;
  const _CaseCard({required this.item, required this.tint});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                        child: Text(item.severity.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: tint,
                            )),
                      ),
                      const Spacer(),
                      if (item.date.isNotEmpty)
                        Text(item.date,
                            style: TextStyle(fontSize: 11.5, color: c.textMuted)),
                    ]),
                    const SizedBox(height: 9),
                    Text(item.offense,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: c.textPrimary)),
                    if (item.action.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.gavel_rounded, size: 13, color: c.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(item.action,
                              style: TextStyle(
                                  fontSize: 12.5, height: 1.45, color: c.textSecondary)),
                        ),
                      ]),
                    ],
                    if (item.status.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(item.status,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: item.isOpen ? c.warning : c.success,
                          )),
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

class _Clean extends StatelessWidget {
  final String name;
  const _Clean({required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 28),
      child: Column(
        children: [
          Icon(Icons.verified_outlined, size: 44, color: c.success),
          const SizedBox(height: 16),
          Text('A clean record',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'No conduct incidents have been recorded for $name.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

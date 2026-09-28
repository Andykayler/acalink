import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../models/student.dart';
import '../services/homework_submission_service.dart';
import '../state/session_provider.dart';

/// Homework for the child's class, with where each piece stands.
///
/// The rule the screen enforces: before the due date a guardian can mark work
/// submitted directly; after it, they must ask the teacher first and can only
/// submit once that request is approved. Nothing here can be bypassed by the
/// UI — the same conditions are checked in the service and in the rules.
class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _Item {
  final String id;
  final String title;
  final String subject;
  final String instructions;
  final DateTime dueDate;
  final String teacherId;
  final HomeworkSubmission? submission;
  final SubmissionState state;

  const _Item({
    required this.id,
    required this.title,
    required this.subject,
    required this.instructions,
    required this.dueDate,
    required this.teacherId,
    required this.submission,
    required this.state,
  });
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final _service = HomeworkSubmissionService();
  final _firestore = FirebaseFirestore.instance;
  Future<List<_Item>>? _future;
  String? _loadedFor;
  bool _busy = false;

  Future<List<_Item>> _load(Student student) async {
    final results = await Future.wait([
      fetchAllHomework(_firestore, student),
      _service.fetchForStudent(student),
    ]);
    final rows = results[0] as List<Map<String, dynamic>>;
    final subs = results[1] as Map<String, HomeworkSubmission>;

    final items = <_Item>[];
    for (final r in rows) {
      final raw = r['dueDate'] as String?;
      final due = (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
      if (due == null) continue;
      final sub = subs[r['id']];
      items.add(_Item(
        id: r['id'] as String,
        title: r['title'] as String? ?? 'Homework',
        subject: r['subject'] as String? ?? '',
        instructions: r['instructions'] as String? ?? r['description'] as String? ?? '',
        dueDate: due,
        teacherId: r['teacherId'] as String? ?? '',
        submission: sub,
        state: HomeworkSubmissionService.resolve(sub, due),
      ));
    }
    // Anything still needing action first, then by due date.
    int rank(SubmissionState s) => switch (s) {
      SubmissionState.overdue => 0,
      SubmissionState.approved => 1,
      SubmissionState.open => 2,
      SubmissionState.requested => 3,
      SubmissionState.declined => 4,
      SubmissionState.submitted => 5,
    };
    items.sort((a, b) {
      final r = rank(a.state).compareTo(rank(b.state));
      return r != 0 ? r : a.dueDate.compareTo(b.dueDate);
    });
    return items;
  }

  void _reload(Student student) {
    setState(() {
      _future = _load(student);
    });
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<SessionProvider>().selectedStudent;
    if (student != null && _loadedFor != student.id) {
      _loadedFor = student.id;
      _future = _load(student);
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
            Text('Homework',
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
      body: FutureBuilder<List<_Item>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          final items = snap.data ?? const <_Item>[];
          if (items.isEmpty) {
            return const _Empty();
          }
          final overdue = items.where((i) => i.state == SubmissionState.overdue).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              if (overdue > 0) _OverdueBanner(count: overdue),
              ...items.map((i) => _HomeworkCard(
                    item: i,
                    busy: _busy,
                    onSubmit: () => _submit(student!, i),
                    onRequest: () => _request(student!, i),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit(Student student, _Item item) async {
    final note = await _prompt(
      title: 'Mark as submitted',
      hint: 'Anything the teacher should know (optional)',
      action: 'Submit',
      required: false,
    );
    if (note == null) return; // cancelled

    setState(() => _busy = true);
    final res = await _service.submit(
      student: student,
      homeworkId: item.id,
      homeworkTitle: item.title,
      dueDate: item.dueDate,
      teacherId: item.teacherId,
      note: note,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(res.ok ? 'Recorded as submitted.' : res.error!, ok: res.ok);
    if (res.ok) _reload(student);
  }

  Future<void> _request(Student student, _Item item) async {
    final reason = await _prompt(
      title: 'Request late submission',
      hint: 'Why was it late? The teacher sees this.',
      action: 'Send request',
      required: true,
    );
    if (reason == null) return;

    setState(() => _busy = true);
    final res = await _service.requestLateSubmission(
      student: student,
      homeworkId: item.id,
      homeworkTitle: item.title,
      teacherId: item.teacherId,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(res.ok ? 'Request sent to the teacher.' : res.error!, ok: res.ok);
    if (res.ok) _reload(student);
  }

  void _toast(String message, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? context.colors.success : context.colors.danger,
      content: Text(message, style: const TextStyle(fontSize: 13)),
    ));
  }

  /// Returns the typed text, or null if the sheet was dismissed.
  Future<String?> _prompt({
    required String title,
    required String hint,
    required String action,
    required bool required,
  }) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.heroBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 18,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: context.colors.textMuted),
                filled: true,
                fillColor: context.colors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final text = controller.text.trim();
                      if (required && text.isEmpty) return;
                      Navigator.of(sheetContext).pop(text);
                    },
                    child: Text(action, style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  final int count;
  const _OverdueBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.colors.dangerPale,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 19, color: context.colors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count piece${count == 1 ? '' : 's'} of work past the due date. '
              'Ask the teacher to accept a late submission.',
              style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

({Color color, String label, IconData icon}) _statusStyle(AppColors c, SubmissionState s) {
  switch (s) {
    case SubmissionState.submitted:
      return (color: c.success, label: 'Submitted', icon: Icons.check_circle_rounded);
    case SubmissionState.overdue:
      return (color: c.danger, label: 'Overdue', icon: Icons.warning_amber_rounded);
    case SubmissionState.requested:
      return (color: c.warning, label: 'Awaiting approval', icon: Icons.hourglass_top_rounded);
    case SubmissionState.approved:
      return (color: c.primary, label: 'Late submission allowed', icon: Icons.lock_open_rounded);
    case SubmissionState.declined:
      return (color: c.danger, label: 'Request declined', icon: Icons.block_rounded);
    case SubmissionState.open:
      return (color: c.primary, label: 'Due', icon: Icons.schedule_rounded);
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class _HomeworkCard extends StatelessWidget {
  final _Item item;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onRequest;

  const _HomeworkCard({
    required this.item,
    required this.busy,
    required this.onSubmit,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final s = _statusStyle(context.colors, item.state);
    final d = item.dueDate;
    final due = '${d.day} ${_months[d.month - 1]} ${d.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.state == SubmissionState.overdue
              ? context.colors.danger.withValues(alpha: 0.3)
              : context.colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      [if (item.subject.isNotEmpty) item.subject, 'Due $due'].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 12, color: s.color),
                    const SizedBox(width: 4),
                    Text(s.label,
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700, color: s.color)),
                  ],
                ),
              ),
            ],
          ),

          if (item.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.instructions,
                style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary, height: 1.45)),
          ],

          // Whatever the teacher said about a late request, shown verbatim so
          // the family is not guessing at a decision.
          if (item.submission != null &&
              item.state == SubmissionState.declined &&
              item.submission!.decisionNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Note(
              label: 'Teacher',
              text: item.submission!.decisionNote,
              color: context.colors.danger,
            ),
          ],
          if (item.state == SubmissionState.requested &&
              item.submission!.requestReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Note(
              label: 'Your request',
              text: item.submission!.requestReason,
              color: context.colors.warning,
            ),
          ],
          if (item.state == SubmissionState.submitted) ...[
            const SizedBox(height: 8),
            Text(
              item.submission?.wasLate == true
                  ? 'Submitted late, with the teacher’s approval.'
                  : 'Submitted on time.',
              style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
            ),
          ],

          if (_actionFor(item.state) != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : (item.state == SubmissionState.overdue ? onRequest : onSubmit),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      item.state == SubmissionState.overdue ? context.colors.warning : context.colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                icon: Icon(
                  item.state == SubmissionState.overdue
                      ? Icons.outgoing_mail
                      : Icons.check_rounded,
                  size: 17,
                ),
                label: Text(_actionFor(item.state)!,
                    style: const TextStyle(fontSize: 13.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Null where there is nothing for the family to do — awaiting a teacher,
  /// declined, or already submitted.
  String? _actionFor(SubmissionState s) => switch (s) {
        SubmissionState.open => 'Mark as submitted',
        SubmissionState.overdue => 'Request late submission',
        SubmissionState.approved => 'Submit now',
        _ => null,
      };
}

class _Note extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  const _Note({required this.label, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 2.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(text,
              style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
              child: Icon(Icons.menu_book_rounded, size: 28, color: context.colors.primary),
            ),
            const SizedBox(height: 14),
            Text('No homework set',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
            const SizedBox(height: 5),
            Text(
              'Work assigned to your child’s class appears here, with what still needs doing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';

enum TaskDueStatus { overdue, soon, upcoming }

class HomeworkTask {
  final String id;
  final String title;
  final String subject;
  final DateTime dueDate;
  final TaskDueStatus status;

  const HomeworkTask({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDate,
    required this.status,
  });
}

/// Reads the `homework` collection teachers write from their Homework
/// module — assignment-level records (one per class/subject/due date), not
/// per-student submission tracking. "Upcoming" here means "assigned to
/// this student's class and due soon or already overdue", the same scope
/// the school side sees, not a per-student submitted/not-submitted state.
class HomeworkService {
  final FirebaseFirestore _firestore;
  HomeworkService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<HomeworkTask>> fetchUpcoming(Student student, {int limit = 5}) async {
    if (student.classId.isEmpty) return [];

    final snap = await _firestore
        .collection('homework')
        .where('schoolCode', isEqualTo: student.schoolCode)
        .where('classId', isEqualTo: student.classId)
        .get();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final tasks = snap.docs
        .map((doc) {
          final data = doc.data();
          final raw = data['dueDate'] as String?;
          final due = (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
          if (due == null) return null;

          final days = due.difference(today).inDays;
          final status = days < 0
              ? TaskDueStatus.overdue
              : days <= 2
                  ? TaskDueStatus.soon
                  : TaskDueStatus.upcoming;

          return HomeworkTask(
            id: doc.id,
            title: data['title'] as String? ?? 'Homework',
            subject: data['subject'] as String? ?? '',
            dueDate: due,
            status: status,
          );
        })
        .whereType<HomeworkTask>()
        // Drop anything overdue by more than a week — stale assignments
        // shouldn't crowd out what's actually coming up.
        .where((t) => t.status != TaskDueStatus.overdue || today.difference(t.dueDate).inDays <= 7)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return tasks.take(limit).toList();
  }
}

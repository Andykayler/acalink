import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';

class DisciplineSummary {
  final int openCases;
  final int totalCases;
  const DisciplineSummary({required this.openCases, required this.totalCases});

  static const empty = DisciplineSummary(openCases: 0, totalCases: 0);
}

/// Reads `discipline_cases` the same way DisciplineModule.jsx writes them —
/// "open" mirrors that module's own convention: any status that doesn't
/// contain the word "resolved" (case-insensitive) counts as still open.
class DisciplineService {
  final FirebaseFirestore _firestore;
  DisciplineService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<DisciplineSummary> fetchSummary(Student student) async {
    final snap = await _firestore
        .collection('discipline_cases')
        .where('schoolCode', isEqualTo: student.schoolCode)
        .where('studentId', isEqualTo: student.id)
        .get();

    int open = 0;
    for (final doc in snap.docs) {
      final status = (doc.data()['status'] as String? ?? '').toLowerCase();
      if (!status.contains('resolved')) open++;
    }
    return DisciplineSummary(openCases: open, totalCases: snap.docs.length);
  }
}

/// One recorded incident, as the teacher's Discipline module writes it.
class DisciplineCase {
  final String id;
  final String offense;
  final String severity;
  final String action;
  final String status;
  final String className;
  final String date;
  final DateTime? createdAt;

  const DisciplineCase({
    required this.id,
    required this.offense,
    required this.severity,
    required this.action,
    required this.status,
    required this.className,
    required this.date,
    required this.createdAt,
  });

  factory DisciplineCase.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return DisciplineCase(
      id: doc.id,
      offense: d['offense'] as String? ?? 'Incident',
      severity: d['severity'] as String? ?? 'Medium',
      action: d['action'] as String? ?? '',
      status: d['status'] as String? ?? '',
      className: d['className'] as String? ?? '',
      date: d['date'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Mirrors the web module's own convention: anything whose status does not
  /// contain "resolved" is still open. Kept in one place so the count on the
  /// dashboard and the badge on a card can never disagree.
  bool get isOpen => !status.toLowerCase().contains('resolved');
}

extension DisciplineCases on DisciplineService {
  /// Every incident on this child's record, newest first.
  ///
  /// Filtered on schoolCode and studentId — the same pair the summary uses,
  /// and the pair the security rule tests. Sorted in Dart rather than with
  /// orderBy so no composite index is needed.
  Future<List<DisciplineCase>> fetchCases(Student student) async {
    if (student.id.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('discipline_cases')
          .where('schoolCode', isEqualTo: student.schoolCode)
          .where('studentId', isEqualTo: student.id)
          .get();

      final cases = snap.docs.map(DisciplineCase.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at != null && bt != null) return bt.compareTo(at);
          return b.date.compareTo(a.date);
        });
      return cases;
    } catch (e) {
      // ignore: avoid_print
      print('[discipline] could not read cases: $e');
      return [];
    }
  }
}

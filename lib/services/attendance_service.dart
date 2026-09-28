import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';

class AttendanceSummary {
  final int presentCount;
  final int markedDays;
  final double percent; // 0..100, or -1 when there's nothing marked yet

  const AttendanceSummary({
    required this.presentCount,
    required this.markedDays,
    required this.percent,
  });

  bool get hasData => markedDays > 0;

  static const empty = AttendanceSummary(presentCount: 0, markedDays: 0, percent: -1);
}

/// Reads the same `attendance` collection the teacher's Take Attendance
/// module writes: one doc per class per date
/// (`${schoolCode}_${classId}_${date}`), with a `records` map keyed by
/// studentId. There's no per-record term boundary stored, so — rather than
/// guess at term start/end dates — this looks at the most recent marked
/// school days for the student's class.
///
/// Deliberately avoids `orderBy('date')` alongside the two equality
/// filters: Firestore would need a composite index for that combination,
/// and this codebase's web side already works around the same situation
/// (see the comment in teacher/modules/classplanning.jsx) by sorting
/// client-side instead.
class AttendanceService {
  final FirebaseFirestore _firestore;
  AttendanceService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _recentDaysLimit = 40;

  Future<AttendanceSummary> fetchRecentAttendance(Student student) async {
    if (student.classId.isEmpty) return AttendanceSummary.empty;

    final snap = await _firestore
        .collection('attendance')
        .where('schoolCode', isEqualTo: student.schoolCode)
        .where('classId', isEqualTo: student.classId)
        .get();

    final docsByDate = snap.docs.toList()
      ..sort((a, b) => (b.data()['date'] as String? ?? '')
          .compareTo(a.data()['date'] as String? ?? ''));

    int present = 0;
    int marked = 0;
    for (final doc in docsByDate.take(_recentDaysLimit)) {
      final records = doc.data()['records'] as Map<String, dynamic>?;
      final entry = records?[student.id];
      // Registers have been written both as a bare status string and as a
      // map carrying a status plus a time — mirrors the web side's
      // termSummary.js, which documents the same two shapes. A hard cast to
      // Map here crashed this whole fetch (and the dashboard load with it)
      // for any register written the plain-string way.
      final status = entry is String ? entry : (entry is Map ? entry['status'] as String? : null);
      if (status == null || status.isEmpty) continue;
      marked++;
      if (status == 'Present' || status == 'Late') present++;
    }

    if (marked == 0) return AttendanceSummary.empty;
    return AttendanceSummary(
      presentCount: present,
      markedDays: marked,
      percent: (present / marked) * 100,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';

/// One school day as it was recorded for this child.
class AttendanceDay {
  final String date; // yyyy-MM-dd, as the register stores it
  final String status; // Present | Absent | Late | Excused
  final String time;
  final String remark;
  final String className;

  const AttendanceDay({
    required this.date,
    required this.status,
    required this.time,
    required this.remark,
    required this.className,
  });

  DateTime? get parsed => DateTime.tryParse(date);
  bool get isPresent => status == 'Present';
  bool get isLate => status == 'Late';
  bool get isAbsent => status == 'Absent';
  bool get isExcused => status == 'Excused';
}

/// Totals over whatever has been marked, plus the day-by-day record.
class AttendanceHistory {
  final List<AttendanceDay> days;
  final int present;
  final int absent;
  final int late;
  final int excused;

  const AttendanceHistory({
    required this.days,
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
  });

  int get marked => days.length;

  /// Late still counts as attending — a child who arrived is not absent.
  /// Excused days are removed from the denominator rather than counted as
  /// attendance, so an authorised absence neither helps nor hurts the rate.
  double? get rate {
    final counted = present + late + absent;
    if (counted == 0) return null;
    return (present + late) / counted * 100;
  }

  static const empty = AttendanceHistory(
      days: [], present: 0, absent: 0, late: 0, excused: 0);
}

/// Reads the same `attendance` documents the teacher's register writes — one
/// per class per date, with a `records` map keyed by studentId.
///
/// Deliberately no `orderBy('date')`: combined with the two equality filters
/// Firestore would demand a composite index, so the sort happens in Dart. The
/// same reasoning as AttendanceService, which this complements — that one
/// returns the dashboard's single figure, this one the full history.
class AttendanceDetailService {
  final FirebaseFirestore _firestore;
  AttendanceDetailService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<AttendanceHistory> fetchHistory(Student student) async {
    if (student.classId.isEmpty) return AttendanceHistory.empty;

    final snap = await _firestore
        .collection('attendance')
        .where('schoolCode', isEqualTo: student.schoolCode)
        .where('classId', isEqualTo: student.classId)
        .get();

    final days = <AttendanceDay>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final records = data['records'] as Map<String, dynamic>?;
      final mine = records?[student.id];
      // Same two on-disk shapes as AttendanceService.fetchRecentAttendance —
      // a bare status string, or a map carrying status plus a time/remark.
      // The plain-string shape used to be silently dropped here, which
      // under-counted a child's history rather than crashing outright, but
      // was still wrong for exactly the same registers.
      if (mine == null || (mine is! String && mine is! Map)) continue;
      final status = (mine is String ? mine : (mine as Map)['status'] as String?) ?? '';
      if (status.isEmpty) continue; // unmarked pupils are not a record

      days.add(AttendanceDay(
        date: data['date'] as String? ?? '',
        status: status,
        time: mine is Map ? (mine['time'] as String? ?? '') : '',
        remark: mine is Map ? (mine['remark'] as String? ?? '') : '',
        className: data['className'] as String? ?? student.className,
      ));
    }

    days.sort((a, b) => b.date.compareTo(a.date)); // newest first

    return AttendanceHistory(
      days: days,
      present: days.where((d) => d.isPresent).length,
      absent: days.where((d) => d.isAbsent).length,
      late: days.where((d) => d.isLate).length,
      excused: days.where((d) => d.isExcused).length,
    );
  }
}

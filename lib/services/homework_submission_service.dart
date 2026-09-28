import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';

/// Where a piece of homework stands for one child.
///
/// The late path is the reason this is a state machine rather than a boolean.
/// Once the due date has passed a family cannot simply mark the work done —
/// they ask the teacher for permission, and only an approval unlocks
/// submitting. That keeps the teacher's record honest about what was late and
/// what was accepted, instead of letting a deadline be quietly ignored.
enum SubmissionState {
  /// Nothing recorded, still before the due date — submitting is open.
  open,

  /// Past due with nothing recorded — must request permission first.
  overdue,

  /// Permission asked for, teacher has not answered.
  requested,

  /// Teacher said yes; submitting is unlocked again.
  approved,

  /// Teacher said no.
  declined,

  /// Recorded as done.
  submitted,
}

class HomeworkSubmission {
  final String homeworkId;
  final SubmissionState state;
  final DateTime? submittedAt;
  final String note;
  final String requestReason;
  final DateTime? requestedAt;
  final String decisionNote;
  final String decidedByName;
  final bool wasLate;

  const HomeworkSubmission({
    required this.homeworkId,
    required this.state,
    this.submittedAt,
    this.note = '',
    this.requestReason = '',
    this.requestedAt,
    this.decisionNote = '',
    this.decidedByName = '',
    this.wasLate = false,
  });

  static String docId(String homeworkId, String studentId) =>
      '${homeworkId}__$studentId';

  factory HomeworkSubmission.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc, String homeworkId) {
    final d = doc.data() ?? {};
    final raw = d['status'] as String? ?? '';
    final state = switch (raw) {
      'submitted' => SubmissionState.submitted,
      'late_requested' => SubmissionState.requested,
      'late_approved' => SubmissionState.approved,
      'late_declined' => SubmissionState.declined,
      _ => SubmissionState.open,
    };
    DateTime? at(dynamic v) => v is Timestamp ? v.toDate() : null;
    return HomeworkSubmission(
      homeworkId: homeworkId,
      state: state,
      submittedAt: at(d['submittedAt']),
      note: d['note'] as String? ?? '',
      requestReason: d['requestReason'] as String? ?? '',
      requestedAt: at(d['requestedAt']),
      decisionNote: d['decisionNote'] as String? ?? '',
      decidedByName: d['decidedByName'] as String? ?? '',
      wasLate: d['wasLate'] as bool? ?? false,
    );
  }
}

class HomeworkSubmissionService {
  final FirebaseFirestore _firestore;
  HomeworkSubmissionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _collection = 'homework_submissions';

  /// Every submission record for this child, keyed by homeworkId.
  ///
  /// Filtered on studentId because that is what the security rule tests, and
  /// a list is authorised from the query's constraints rather than per
  /// returned document.
  Future<Map<String, HomeworkSubmission>> fetchForStudent(Student student) async {
    if (student.id.isEmpty) return {};
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('studentId', isEqualTo: student.id)
          .get();
      return {
        for (final d in snap.docs)
          (d.data()['homeworkId'] as String? ?? ''):
              HomeworkSubmission.fromDoc(d, d.data()['homeworkId'] as String? ?? ''),
      };
    } catch (e) {
      // ignore: avoid_print
      print('[homework] could not read submissions: $e');
      return {};
    }
  }

  /// Resolves the state to show, combining any stored record with the due date.
  /// A missing record is not the same as "nothing to do" — past the due date it
  /// means the work is overdue and needs a request.
  static SubmissionState resolve(HomeworkSubmission? stored, DateTime dueDate) {
    if (stored != null && stored.state != SubmissionState.open) return stored.state;
    final now = DateTime.now();
    final endOfDue = DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59);
    return now.isAfter(endOfDue) ? SubmissionState.overdue : SubmissionState.open;
  }

  /// Records the work as done. Refused past the due date unless the teacher has
  /// already approved a late submission — the same condition the security rule
  /// enforces, checked here so the UI can explain rather than just fail.
  Future<({bool ok, String? error})> submit({
    required Student student,
    required String homeworkId,
    required String homeworkTitle,
    required DateTime dueDate,
    required String teacherId,
    String note = '',
  }) async {
    final ref = _firestore
        .collection(_collection)
        .doc(HomeworkSubmission.docId(homeworkId, student.id));

    final existing = await ref.get();
    final stored = existing.exists
        ? HomeworkSubmission.fromDoc(existing, homeworkId)
        : null;
    final state = resolve(stored, dueDate);

    if (state == SubmissionState.submitted) {
      return (ok: false, error: 'This work is already marked as submitted.');
    }
    if (state == SubmissionState.overdue) {
      return (ok: false, error: 'The due date has passed. Request permission to submit first.');
    }
    if (state == SubmissionState.requested) {
      return (ok: false, error: 'Waiting for the teacher to approve your late submission.');
    }
    if (state == SubmissionState.declined) {
      return (ok: false, error: 'The teacher declined this late submission.');
    }

    final late = state == SubmissionState.approved;
    try {
      await ref.set({
        'schoolCode': student.schoolCode,
        'homeworkId': homeworkId,
        'homeworkTitle': homeworkTitle,
        'studentId': student.id,
        'studentName': student.fullName,
        'classId': student.classId,
        'className': student.className,
        'guardianPhone': student.guardianPhone,
        'teacherId': teacherId,
        'status': 'submitted',
        'wasLate': late,
        'note': note.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _notifyTeacher(
        teacherId: teacherId,
        schoolCode: student.schoolCode,
        title: '${student.fullName} submitted ${homeworkTitle}',
        body: late ? 'Late submission, previously approved.' : 'Submitted on time.',
        homeworkId: homeworkId,
        student: student,
      );
      return (ok: true, error: null);
    } catch (e) {
      // ignore: avoid_print
      print('[homework] submit failed: $e');
      return (ok: false, error: 'Could not record the submission. Check your connection.');
    }
  }

  /// Asks the teacher to accept work after the deadline.
  Future<({bool ok, String? error})> requestLateSubmission({
    required Student student,
    required String homeworkId,
    required String homeworkTitle,
    required String teacherId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      return (ok: false, error: 'Give the teacher a reason for the delay.');
    }
    try {
      await _firestore
          .collection(_collection)
          .doc(HomeworkSubmission.docId(homeworkId, student.id))
          .set({
        'schoolCode': student.schoolCode,
        'homeworkId': homeworkId,
        'homeworkTitle': homeworkTitle,
        'studentId': student.id,
        'studentName': student.fullName,
        'classId': student.classId,
        'className': student.className,
        'guardianPhone': student.guardianPhone,
        'teacherId': teacherId,
        'status': 'late_requested',
        'requestReason': reason.trim(),
        'requestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _notifyTeacher(
        teacherId: teacherId,
        schoolCode: student.schoolCode,
        title: 'Late submission request — ${student.fullName}',
        body: '$homeworkTitle · ${reason.trim()}',
        homeworkId: homeworkId,
        student: student,
      );
      return (ok: true, error: null);
    } catch (e) {
      // ignore: avoid_print
      print('[homework] late request failed: $e');
      return (ok: false, error: 'Could not send the request. Check your connection.');
    }
  }

  /// Mirrors the notification document shape the web portal writes, including
  /// the inverted-timestamp id that keeps an inbox newest-first without a
  /// composite index.
  Future<void> _notifyTeacher({
    required String teacherId,
    required String schoolCode,
    required String title,
    required String body,
    required String homeworkId,
    required Student student,
  }) async {
    if (teacherId.isEmpty) return;
    const idCeiling = 9999999999999;
    final inverted = (idCeiling - DateTime.now().millisecondsSinceEpoch)
        .toString()
        .padLeft(13, '0');
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    try {
      await _firestore.collection('notifications').doc('${inverted}_$salt').set({
        'schoolCode': schoolCode,
        'recipientId': teacherId,
        'recipientType': 'staff',
        'recipientName': '',
        'title': title,
        'body': body.length > 140 ? body.substring(0, 140) : body,
        'category': 'homework',
        'priority': 'normal',
        'actorId': '',
        'actorName': student.guardianName.isEmpty ? 'Guardian' : student.guardianName,
        'actorRole': 'guardian',
        'tab': 'Homework',
        'entityType': 'homework_submission',
        'entityId': homeworkId,
        'studentId': student.id,
        'studentName': student.fullName,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[homework] teacher notification failed: $e');
    }
  }
}

/// Fetches every assignment for the child's class, not just the upcoming few
/// the dashboard shows — the Homework screen is the full record.
Future<List<Map<String, dynamic>>> fetchAllHomework(
    FirebaseFirestore firestore, Student student) async {
  if (student.classId.isEmpty) return [];
  final snap = await firestore
      .collection('homework')
      .where('schoolCode', isEqualTo: student.schoolCode)
      .where('classId', isEqualTo: student.classId)
      .get();
  return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
}

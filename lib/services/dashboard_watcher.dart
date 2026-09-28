import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/student.dart';

/// Which part of the dashboard a change affects.
///
/// The dashboard used to be a single `Future.wait` fired once when the screen
/// opened, so a mark entered at school did not appear until the parent killed
/// the app and reopened it. Watching fixes that — but re-reading everything
/// whenever anything moves would multiply Firestore reads for a family that
/// leaves the app open all day.
///
/// So a change is reported as a *section*, and the screen refreshes only that
/// section. A teacher saving a register costs one attendance fetch, not six.
enum DashboardSection { fees, attendance, performance, discipline, homework, announcements, term }

/// Turns the collections behind the dashboard into a stream of "this part
/// changed" signals.
///
/// Every listener mirrors the filters of the corresponding `fetch*` call
/// exactly. That is not tidiness: a Firestore `list` is authorised from the
/// query's own constraints, so a listener that filters differently from the
/// fetch it stands in for would be refused even though the fetch succeeds.
class DashboardWatcher {
  final FirebaseFirestore _firestore;
  DashboardWatcher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final _subs = <StreamSubscription<dynamic>>[];
  StreamController<DashboardSection>? _controller;

  /// Opens the listeners for [student] and returns the change stream.
  ///
  /// Call [stop] before switching child, or the previous child's listeners
  /// keep firing and overwrite the new one's figures.
  Stream<DashboardSection> start(Student student, {required String academicYear}) {
    stop();
    final controller = StreamController<DashboardSection>.broadcast();
    _controller = controller;

    void watch(Query<Map<String, dynamic>> q, DashboardSection section) {
      // skip(1): every Firestore listener fires immediately with the data it
      // already has. Without this, opening the dashboard would report all six
      // sections as changed and refetch everything the initial load just did.
      _subs.add(q.snapshots().skip(1).listen(
        (_) {
          if (!controller.isClosed) controller.add(section);
        },
        onError: (Object e) {
          // A denied or failed listener must not take the dashboard with it —
          // the screen still works, it just stops updating that section on its
          // own until the next manual refresh.
          debugPrint('[dashboard] ${section.name} listener failed: $e');
        },
      ));
    }

    void watchDoc(DocumentReference<Map<String, dynamic>> ref, DashboardSection section) {
      _subs.add(ref.snapshots().skip(1).listen(
        (_) {
          if (!controller.isClosed) controller.add(section);
        },
        onError: (Object e) => debugPrint('[dashboard] ${section.name} listener failed: $e'),
      ));
    }

    final school = student.schoolCode;
    final classId = student.classId;

    if (student.id.isNotEmpty) {
      watch(
        _firestore
            .collection('fee_assignments')
            .where('studentId', isEqualTo: student.id)
            .where('academicYear', isEqualTo: academicYear),
        DashboardSection.fees,
      );
      watch(
        _firestore
            .collection('payments')
            .where('studentId', isEqualTo: student.id)
            .where('academicYear', isEqualTo: academicYear),
        DashboardSection.fees,
      );
      watch(
        _firestore
            .collection('discipline_cases')
            .where('schoolCode', isEqualTo: school)
            .where('studentId', isEqualTo: student.id),
        DashboardSection.discipline,
      );
    }

    if (classId.isNotEmpty) {
      watch(
        _firestore
            .collection('attendance')
            .where('schoolCode', isEqualTo: school)
            .where('classId', isEqualTo: classId),
        DashboardSection.attendance,
      );
      watch(
        _firestore
            .collection('homework')
            .where('schoolCode', isEqualTo: school)
            .where('classId', isEqualTo: classId),
        DashboardSection.homework,
      );
      // Marks are no longer watched here: the class mark sheets can't be read
      // by the app (results come from api/parent/results.js, which withholds
      // them while fees are owed). The grades card refreshes on open, on pull
      // to refresh, and whenever the fees change.
    }

    if (school.isNotEmpty) {
      watch(
        _firestore.collection('announcements').where('schoolCode', isEqualTo: school),
        DashboardSection.announcements,
      );
      watchDoc(_firestore.collection('school_settings').doc(school), DashboardSection.term);
    }

    return controller.stream;
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _controller?.close();
    _controller = null;
  }
}

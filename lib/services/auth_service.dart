import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/phone_utils.dart';
import '../models/student.dart';

class ParentLoginResult {
  final bool success;
  final String? error;

  /// Children this guardian has confirmed. These are visible immediately.
  final List<Student> students;

  /// Children a school has attached to this number but which the guardian has
  /// not yet confirmed. Listed in the picker so they know something is waiting,
  /// but none of their data is reachable until they confirm.
  final List<Student> pending;

  final String normalisedPhone;

  ParentLoginResult({
    required this.success,
    this.error,
    this.students = const [],
    this.pending = const [],
    this.normalisedPhone = '',
  });
}

class AuthService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Ensures we hold *some* Firebase Auth session before touching Firestore,
  /// so security rules can require `request.auth != null` on reads.
  Future<void> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Looks up every student linked to [rawPhone] and checks [password] against
  /// the ones this guardian has already confirmed.
  ///
  /// On success the guardian gets all of their confirmed children, at every
  /// school — the lookup is deliberately not scoped to one school, because a
  /// guardian is one person across ACALink. Children a school has attached but
  /// which are still awaiting confirmation come back separately in [pending].
  ///
  /// Pending records are excluded from the password check on purpose. Accepting
  /// one would mean a school that attached a child to the wrong number could
  /// hand the stranger a working login, which is the exact failure confirmation
  /// exists to prevent.
  Future<ParentLoginResult> loginWithPhonePassword({
    required String rawPhone,
    required String password,
  }) async {
    await ensureSignedIn();

    final phone = normalisePhone(rawPhone);
    if (password.trim().isEmpty) {
      return ParentLoginResult(success: false, error: 'Enter your password.');
    }

    final snap = await _firestore
        .collection('students')
        .where('guardianPhone', isEqualTo: phone)
        .get();

    if (snap.docs.isEmpty) {
      return ParentLoginResult(
        success: false,
        error: 'No students found for this phone number.',
      );
    }

    final all = snap.docs.map(Student.fromDoc).toList();
    final confirmed = all.where((s) => !s.isPendingConfirmation).toList();
    final pending = all.where((s) => s.isPendingConfirmation).toList();

    if (confirmed.isEmpty) {
      // Every record on this number is awaiting confirmation, which means no
      // password has ever been issued for it. Only a school can resolve this.
      return ParentLoginResult(
        success: false,
        error: 'This number has no confirmed account yet. Contact the school.',
      );
    }

    final passwordMatches =
        confirmed.any((s) => s.parentPortalPassword == password.trim());

    if (!passwordMatches) {
      return ParentLoginResult(success: false, error: 'Incorrect password.');
    }

    return ParentLoginResult(
      success: true,
      students: confirmed,
      pending: pending,
      normalisedPhone: phone,
    );
  }

  /// Re-fetches the students for a phone number without a password check —
  /// used to refresh the session on app relaunch once we already trust it
  /// (phone is stored locally after a successful login).
  ///
  /// Split the same way as [loginWithPhonePassword], so a child attached since
  /// the last launch shows up as awaiting confirmation rather than silently
  /// appearing among the confirmed ones.
  Future<ParentLoginResult> fetchStudentsForPhone(String phone) async {
    await ensureSignedIn();
    final snap = await _firestore
        .collection('students')
        .where('guardianPhone', isEqualTo: phone)
        .get();

    final all = snap.docs.map(Student.fromDoc).toList();
    return ParentLoginResult(
      success: true,
      students: all.where((s) => !s.isPendingConfirmation).toList(),
      pending: all.where((s) => s.isPendingConfirmation).toList(),
      normalisedPhone: phone,
    );
  }
}
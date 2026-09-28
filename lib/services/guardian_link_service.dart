import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/phone_utils.dart';

/// Confirming a child a school has attached to this account.
///
/// When a school enrols a student whose guardian phone already belongs to
/// somebody on ACALink, the record is created as `pending` and stays out of
/// this app until the guardian proves the account is theirs by entering the
/// password they already use. Without that step a clerk's mistyped digit would
/// silently drop a stranger's child into someone's app, complete with their
/// marks, fees and discipline record.
///
/// The check itself cannot run here. Comparing the typed password against the
/// family's other records would mean reading documents this app must not be
/// able to read wholesale, and flipping the student's status would mean giving
/// a parent session write access to student documents — at which point the
/// confirmation is decoration. So the app writes a request and waits; the
/// `verifyGuardianLink` Cloud Function decides and stamps the verdict back.
///
/// Deliberately done with a request document rather than a callable function:
/// it keeps this app on `cloud_firestore` alone, with no extra plugin in the
/// Flutter build for one call.
class GuardianLinkService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  GuardianLinkService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const _collection = 'guardian_link_requests';

  /// How long to wait for the function before giving up on this attempt. A cold
  /// start on the Cloud Function can take a few seconds; anything past this is
  /// more likely a connectivity problem, and saying so beats spinning forever.
  static const _timeout = Duration(seconds: 25);

  /// Submits [password] as proof that [studentId] belongs to the holder of
  /// [phone], and waits for the verdict.
  ///
  /// Returns null on success, or a message to show the guardian.
  Future<String?> confirm({
    required String studentId,
    required String phone,
    required String password,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'You are signed out. Close and reopen the app.';
    if (password.trim().isEmpty) return 'Enter your password.';

    final ref = _firestore.collection(_collection).doc();

    try {
      await ref.set({
        'studentId': studentId,
        'phone': normalisePhone(phone),
        'password': password.trim(),
        'requestedByUid': uid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      return 'Could not reach ACALink. Check your connection and try again.';
    }

    try {
      final resolved = await ref
          .snapshots()
          .where((snap) => (snap.data()?['status'] ?? 'pending') != 'pending')
          .first
          .timeout(_timeout);

      final data = resolved.data() ?? {};
      if (data['status'] == 'verified') return null;

      final error = (data['error'] ?? '').toString();
      return error.isEmpty ? 'Incorrect password.' : error;
    } on TimeoutException {
      return 'That is taking longer than expected. Check again in a moment — '
          'if the child appears, it worked.';
    } catch (_) {
      return 'Something went wrong. Try again.';
    }
  }
}

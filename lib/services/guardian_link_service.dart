import 'package:firebase_auth/firebase_auth.dart';

import '../core/api.dart';
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
/// The check cannot run here: it compares the typed password against the
/// family's other records and flips the student's status, neither of which a
/// parent session may do. So it is sent to the Acalink API, which decides and
/// answers in the same request.
class GuardianLinkService {
  final AcalinkApi _api;

  GuardianLinkService({AcalinkApi? api}) : _api = api ?? AcalinkApi();

  /// Submits [password] as proof that [studentId] belongs to the holder of
  /// [phone], and waits for the verdict.
  ///
  /// Returns null on success, or a message to show the guardian.
  Future<String?> confirm({
    required String studentId,
    required String phone,
    required String password,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      return 'You are signed out. Close and reopen the app.';
    }
    if (password.trim().isEmpty) return 'Enter your password.';

    try {
      await _api.post('/api/parent/confirm', {
        'studentId': studentId,
        'phone': normalisePhone(phone),
        'password': password.trim(),
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Try again.';
    }
  }
}

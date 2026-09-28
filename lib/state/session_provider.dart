import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as shared_preferences;

import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/guardian_link_service.dart';
import '../services/push_service.dart';

enum SessionStatus { unknown, loggedOut, needsStudentPick, ready }

class SessionProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final GuardianLinkService _linkService = GuardianLinkService();

  static const _kPhoneKey = 'acalink_parent_phone';
  static const _kSelectedStudentKey = 'acalink_selected_student_id';

  SessionStatus status = SessionStatus.unknown;
  String? parentPhone;
  List<Student> students = [];

  /// Children a school has attached to this number that the guardian has not
  /// confirmed yet. Shown in the picker, but never selectable — confirming is
  /// the only way through, and that needs the password they already hold.
  List<Student> pending = [];

  Student? selectedStudent;
  String? error;
  bool loading = false;

  /// Called once at app start (from SplashScreen) to restore a saved session.
  Future<void> restoreSession() async {
    loading = true;
    notifyListeners();

    final prefs = await shared_preferences.SharedPreferences.getInstance();
    final savedPhone = prefs.getString(_kPhoneKey);

    if (savedPhone == null) {
      status = SessionStatus.loggedOut;
      loading = false;
      notifyListeners();
      return;
    }

    try {
      final fetched = await _authService.fetchStudentsForPhone(savedPhone);
      if (fetched.students.isEmpty && fetched.pending.isEmpty) {
        // Family no longer has any linked students — fall back to login.
        await _clearStoredSession();
        status = SessionStatus.loggedOut;
      } else {
        parentPhone = savedPhone;
        students = fetched.students;
        pending = fetched.pending;
        final savedStudentId = prefs.getString(_kSelectedStudentKey);
        _resolveSelection(savedStudentId);
        // Re-assert this device on every launch: tokens rotate, and the app
        // may have been reinstalled since the last registration.
        unawaited(PushService.instance.register(savedPhone));
      }
    } catch (_) {
      status = SessionStatus.loggedOut;
    }

    loading = false;
    notifyListeners();
  }

  Future<bool> login(String phone, String password) async {
    loading = true;
    error = null;
    notifyListeners();

    final result = await _authService.loginWithPhonePassword(
      rawPhone: phone,
      password: password,
    );

    if (!result.success) {
      error = result.error;
      loading = false;
      notifyListeners();
      return false;
    }

    parentPhone = result.normalisedPhone;
    students = result.students;
    pending = result.pending;

    final prefs = await shared_preferences.SharedPreferences.getInstance();
    await prefs.setString(_kPhoneKey, result.normalisedPhone);
    unawaited(PushService.instance.register(result.normalisedPhone));

    _resolveSelection(null);
    loading = false;
    notifyListeners();
    return true;
  }

  void _resolveSelection(String? savedStudentId) {
    // A lone child normally skips the picker. Not while something is waiting to
    // be confirmed: that notice is only shown on the picker, and jumping past it
    // is how a guardian never learns a school added a child to their account.
    if (students.length == 1 && pending.isEmpty) {
      selectedStudent = students.first;
      status = SessionStatus.ready;
      _persistSelectedStudent(selectedStudent!.id);
      return;
    }

    if (savedStudentId != null) {
      final match = students.where((s) => s.id == savedStudentId);
      if (match.isNotEmpty) {
        selectedStudent = match.first;
        status = SessionStatus.ready;
        return;
      }
    }

    status = SessionStatus.needsStudentPick;
  }

  Future<void> selectStudent(Student student) async {
    selectedStudent = student;
    status = SessionStatus.ready;
    await _persistSelectedStudent(student.id);
    notifyListeners();
  }

  /// Confirms that a child a school attached to this number really is theirs.
  ///
  /// Returns null on success, or a message to show. The decision is made by the
  /// Cloud Function, not here — see GuardianLinkService for why. On success the
  /// whole roll is re-read rather than moving the child between the two lists
  /// locally, because the server may have changed more than we asked about.
  Future<String?> confirmPending(Student student, String password) async {
    final phone = parentPhone;
    if (phone == null) return 'You are signed out. Sign in again.';

    loading = true;
    notifyListeners();

    final error = await _linkService.confirm(
      studentId: student.id,
      phone: phone,
      password: password,
    );

    if (error == null) {
      final refreshed = await _authService.fetchStudentsForPhone(phone);
      students = refreshed.students;
      pending = refreshed.pending;
    }

    loading = false;
    notifyListeners();
    return error;
  }

  /// Lets a parent jump back to the switcher without logging out.
  void openStudentSwitcher() {
    status = SessionStatus.needsStudentPick;
    notifyListeners();
  }

  Future<void> _persistSelectedStudent(String studentId) async {
    final prefs = await shared_preferences.SharedPreferences.getInstance();
    await prefs.setString(_kSelectedStudentKey, studentId);
  }

  Future<void> logout() async {
    // Before the phone number is forgotten, so a shared handset stops
    // receiving this family's notifications.
    await PushService.instance.unregister();
    await _clearStoredSession();
    parentPhone = null;
    students = [];
    pending = [];
    selectedStudent = null;
    status = SessionStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _clearStoredSession() async {
    final prefs = await shared_preferences.SharedPreferences.getInstance();
    await prefs.remove(_kPhoneKey);
    await prefs.remove(_kSelectedStudentKey);
  }
}
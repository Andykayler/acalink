import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the school's current academic term from `school_settings/{schoolCode}`,
/// the value the head teacher sets in the web portal's Academic term card.
///
/// This exists because the term used to be a `static const` in each service:
/// mark entry defaulted to one term while this app queried another, so grades
/// a teacher had genuinely saved never appeared here and nothing reported an
/// error. Anything that filters on a `term` field should come through here.
///
/// Mirrors `src/services/academicTerm.js` — keep the two in step.
class AcademicTermService {
  final FirebaseFirestore _firestore;
  AcademicTermService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // The dashboard loads several services at once and more than one wants the
  // term; caching per school keeps that to a single read.
  static final Map<String, String> _cache = {};

  // Failures are cached too, briefly. Without this a denied read (or a school
  // with no term set) is retried by every caller on every dashboard build,
  // which produced a hundred identical permission-denied lines per launch.
  // The window is short so the app recovers on its own once rules are fixed,
  // rather than needing a restart.
  static const _failureCooldown = Duration(seconds: 30);
  static final Map<String, DateTime> _failedAt = {};

  static void clearCache() {
    _cache.clear();
    _failedAt.clear();
  }

  /// Returns the school's current term, or an empty string if none is set.
  /// An empty result is meaningful: it means the school has not chosen a term
  /// yet, and callers should say so rather than guessing one.
  Future<String> currentTerm(String schoolCode) async {
    if (schoolCode.isEmpty) return '';

    final cached = _cache[schoolCode];
    if (cached != null) return cached;

    final failed = _failedAt[schoolCode];
    if (failed != null && DateTime.now().difference(failed) < _failureCooldown) {
      return '';
    }

    try {
      final snap =
          await _firestore.collection('school_settings').doc(schoolCode).get();
      final term = (snap.data()?['currentTerm'] as String?) ?? '';
      if (term.isNotEmpty) {
        _cache[schoolCode] = term;
        _failedAt.remove(schoolCode);
      } else {
        // Reachable but unset — still worth a cooldown so the dashboard does
        // not re-read it on every rebuild.
        _failedAt[schoolCode] = DateTime.now();
      }
      return term;
    } catch (e) {
      _failedAt[schoolCode] = DateTime.now();
      // ignore: avoid_print
      print('[term] could not read school settings: $e');
      return '';
    }
  }

  /// "Term 2 2026" → "TERM 2 · 2026" for the dashboard hero.
  static String display(String term) {
    final m = RegExp(r'^Term\s+(\d+)\s+(\d{4})$').firstMatch(term.trim());
    if (m == null) return term.toUpperCase();
    return 'TERM ${m.group(1)} · ${m.group(2)}';
  }
}

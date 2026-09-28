import '../core/api.dart';
import '../models/student.dart';
import 'results_service.dart';

class SubjectGrade {
  final String subject;
  final double score;
  const SubjectGrade(this.subject, this.score);
}

class PerformanceSummary {
  final List<SubjectGrade> subjectGrades; // this student, one row per subject
  final double? overallAverage;
  final int? rank;
  final int classSize;

  /// True when the school is holding results back (fees owed, not released).
  final bool withheld;
  final String withheldMessage;

  /// Set when the results couldn't be fetched at all (no connection, server
  /// unavailable). Distinct from "no marks yet" so the card says what's wrong.
  final String loadError;

  const PerformanceSummary({
    required this.subjectGrades,
    required this.overallAverage,
    required this.rank,
    required this.classSize,
    this.withheld = false,
    this.withheldMessage = '',
    this.loadError = '',
  });

  const PerformanceSummary.failed(String message)
      : subjectGrades = const [],
        overallAverage = null,
        rank = null,
        classSize = 0,
        withheld = false,
        withheldMessage = '',
        loadError = message;

  bool get hasData => subjectGrades.isNotEmpty;

  static const empty = PerformanceSummary(
    subjectGrades: [],
    overallAverage: null,
    rank: null,
    classSize: 0,
  );
}

/// Simple letter-grade bucketing for the app's grade chips — not the MANEB
/// 1–9 scale the web dashboards use (that's a bigger, opinionated mapping
/// tied to MSCE reporting); this is just enough to color-code a score.
String letterGrade(double score) {
  if (score >= 80) return 'A';
  if (score >= 70) return 'A-';
  if (score >= 65) return 'B+';
  if (score >= 60) return 'B';
  if (score >= 55) return 'B-';
  if (score >= 50) return 'C+';
  if (score >= 45) return 'C';
  if (score >= 40) return 'C-';
  return 'F';
}

/// Reads `ca_marks` the same way the web Reports module's non-Overall tabs
/// do: every assessment component (CA1/CA2/Mid-Term/End-of-Term) submitted
/// for the term is merged last-write-wins into one figure per subject,
/// rather than the fully weighted 10/10/20/60 combination the web's
/// Performance Analytics "Overall" tab (and the promotion flow) compute.
/// Good enough for an at-a-glance app card. If that precision is needed
/// here too, port ASSESSMENT_TYPES/computeWeighted from
/// headteacher/modules/reports.jsx the same way its own Promotion tab does.
/// The grades card on the home screen. Computed on the server
/// (src/services/resultsCore.js — the same weights, rounding and ranking this
/// class used to apply itself), which also withholds results from a family
/// that owes fees unless the bursar has released them.
class PerformanceService {
  final ResultsApi _api;
  PerformanceService({ResultsApi? api}) : _api = api ?? ResultsApi();

  Future<PerformanceSummary> fetchPerformance(Student student) async {
    if (student.classId.isEmpty) return PerformanceSummary.empty;

    final Map<String, dynamic> data;
    try {
      data = await _api.fetch(student);
    } catch (e) {
      // ignore: avoid_print
      print('[performance] results unavailable: $e');
      return PerformanceSummary.failed(e is ApiException
          ? e.message
          : 'Results could not be loaded. Check your connection and try again.');
    }
    if (((data['term'] as String?) ?? '').isEmpty) return PerformanceSummary.empty;

    if (data['withheld'] == true) {
      return PerformanceSummary(
        subjectGrades: const [],
        overallAverage: null,
        rank: null,
        classSize: 0,
        withheld: true,
        withheldMessage: (data['message'] as String?) ?? '',
      );
    }

    final grades = <SubjectGrade>[];
    for (final raw in (data['subjects'] as List?) ?? []) {
      final m = (raw as Map).cast<String, dynamic>();
      final w = m['weighted'];
      if (w is num) grades.add(SubjectGrade(m['subject'] as String? ?? '', w.toDouble()));
    }

    return PerformanceSummary(
      subjectGrades: grades,
      overallAverage: (data['overallAverage'] as num?)?.toDouble(),
      rank: (data['rank'] as num?)?.toInt(),
      classSize: (data['classSize'] as num?)?.toInt() ?? 0,
    );
  }
}

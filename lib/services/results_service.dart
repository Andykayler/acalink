import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/api.dart';
import '../models/student.dart';

/// The four assessment components, in the order a term runs. Mirrors
/// ASSESSMENT_TYPES in the web portal's PerformanceModule — the ids are the
/// `assessmentType` field on each ca_marks document.
class AssessmentComponent {
  final String id;
  final String label;
  final double weight;
  const AssessmentComponent(this.id, this.label, this.weight);
}

const kComponents = <AssessmentComponent>[
  AssessmentComponent('CA1', 'CA 1', 0.10),
  AssessmentComponent('CA2', 'CA 2', 0.10),
  AssessmentComponent('MidTerm', 'Mid-Term', 0.20),
  AssessmentComponent('EndTerm', 'End of Term', 0.60),
];

/// MANEB (MSCE) grade scale, mirroring MANEB_GRADES in PerformanceModule.
class ManebGrade {
  final int grade;
  final String remark;
  final String tone; // success | primary | warning | danger
  const ManebGrade(this.grade, this.remark, this.tone);
}

ManebGrade gradeFor(num score) {
  if (score >= 80) return const ManebGrade(1, 'Distinction', 'success');
  if (score >= 70) return const ManebGrade(2, 'Distinction', 'success');
  if (score >= 65) return const ManebGrade(3, 'Credit', 'primary');
  if (score >= 60) return const ManebGrade(4, 'Credit', 'primary');
  if (score >= 55) return const ManebGrade(5, 'Credit', 'primary');
  if (score >= 50) return const ManebGrade(6, 'Credit', 'primary');
  if (score >= 45) return const ManebGrade(7, 'Pass', 'warning');
  if (score >= 40) return const ManebGrade(8, 'Pass', 'warning');
  return const ManebGrade(9, 'Fail', 'danger');
}

/// One subject, with whatever components have been published so far.
class SubjectResult {
  final String subject;
  /// componentId -> score. Only components the teacher has PUBLISHED appear.
  final Map<String, num> components;

  const SubjectResult({required this.subject, required this.components});

  bool hasComponent(String id) => components.containsKey(id);

  /// Weighted mean across the components present, so a subject with only
  /// CA 1 entered still reads sensibly rather than looking like a 10% score.
  double? get weighted {
    double sum = 0, used = 0;
    for (final c in kComponents) {
      final v = components[c.id];
      if (v == null) continue;
      sum += v * c.weight;
      used += c.weight;
    }
    if (used == 0) return null;
    return (sum / used * 10).round() / 10;
  }

  /// True once every component has been published — until then the weighted
  /// figure is provisional and the UI says so.
  bool get complete => kComponents.every((c) => components.containsKey(c.id));
}

/// A report card is a snapshot the head teacher releases. Its existence is
/// what makes the combined term result visible to a family — individual
/// components appear as teachers publish them, but the final assessment is
/// deliberately withheld until the school issues it.
class ReportCard {
  final String term;
  final String className;
  final List<SubjectResult> subjects;
  final double? overallAverage;
  final int? position;
  final int? classSize;
  final String? headTeacherRemark;

  /// Automatically generated summary of the term — marks, attendance and
  /// conduct read together. Written by the portal when the school has the AI
  /// insights module on, absent otherwise, so every read has to tolerate null.
  final String? insight;

  final DateTime? generatedAt;

  const ReportCard({
    required this.term,
    required this.className,
    required this.subjects,
    required this.overallAverage,
    required this.position,
    required this.classSize,
    required this.headTeacherRemark,
    required this.insight,
    required this.generatedAt,
  });

  static String docId(String schoolCode, String studentId, String term) =>
      '${schoolCode}__${studentId}__${term.replaceAll(RegExp(r'\s+'), '_')}';

  factory ReportCard.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      ReportCard.fromMap(doc.data() ?? {});

  /// From a Firestore document or the results endpoint's JSON (where
  /// `generatedAt` is an ISO string).
  factory ReportCard.fromMap(Map<String, dynamic> d) {
    final subjects = ((d['subjects'] as List?) ?? []).map((raw) {
      final m = (raw as Map).cast<String, dynamic>();
      final comps = ((m['components'] as Map?) ?? {}).cast<String, dynamic>();
      return SubjectResult(
        subject: m['subject'] as String? ?? '',
        components: {
          for (final e in comps.entries)
            if (e.value is num) e.key: e.value as num,
        },
      );
    }).toList();

    final ts = d['generatedAt'];
    return ReportCard(
      term: d['term'] as String? ?? '',
      className: d['className'] as String? ?? '',
      subjects: subjects,
      overallAverage: (d['overallAverage'] as num?)?.toDouble(),
      position: (d['position'] as num?)?.toInt(),
      classSize: (d['classSize'] as num?)?.toInt(),
      headTeacherRemark: d['headTeacherRemark'] as String?,
      insight: d['insight'] as String?,
      generatedAt: ts is Timestamp
          ? ts.toDate()
          : (ts is String ? DateTime.tryParse(ts) : null),
    );
  }
}

/// Everything the Results screen needs for one child, in one round trip.
class ResultsData {
  final String term;
  final List<SubjectResult> subjects;
  final ReportCard? reportCard;
  /// Components with at least one published subject — drives the filter chips
  /// so a parent is never offered a tab that is empty.
  final Set<String> availableComponents;

  /// True when the school is holding this term's results back — usually
  /// because fees are owed and the bursar has not released them.
  final bool withheld;

  /// What to tell the family when [withheld] — written by the server.
  final String withheldMessage;

  const ResultsData({
    required this.term,
    required this.subjects,
    required this.reportCard,
    required this.availableComponents,
    this.withheld = false,
    this.withheldMessage = '',
  });

  static const empty = ResultsData(
    term: '', subjects: [], reportCard: null, availableComponents: {},
  );
}

/// A child's results come from the server (api/parent/results.js), not from
/// Firestore: the school's mark sheets hold the whole class, and the server is
/// what withholds results from a family that owes fees unless the bursar has
/// released them. It returns only this child's marks.
class ResultsApi {
  final AcalinkApi _api;
  ResultsApi({AcalinkApi? api}) : _api = api ?? AcalinkApi();

  Future<Map<String, dynamic>> fetch(Student student) => _api.post(
        '/api/parent/results',
        {'studentId': student.id, 'phone': student.guardianPhone},
      );
}

class ResultsService {
  final ResultsApi _api;
  ResultsService({ResultsApi? api}) : _api = api ?? ResultsApi();

  Future<ResultsData> fetchResults(Student student) async {
    if (student.classId.isEmpty) return ResultsData.empty;

    final data = await _api.fetch(student);
    final term = (data['term'] as String?) ?? '';
    if (term.isEmpty) return ResultsData.empty;

    if (data['withheld'] == true) {
      return ResultsData(
        term: term,
        subjects: const [],
        reportCard: null,
        availableComponents: const {},
        withheld: true,
        withheldMessage: (data['message'] as String?) ?? '',
      );
    }

    final subjects = ((data['subjects'] as List?) ?? []).map((raw) {
      final m = (raw as Map).cast<String, dynamic>();
      final comps = ((m['components'] as Map?) ?? {}).cast<String, dynamic>();
      return SubjectResult(
        subject: m['subject'] as String? ?? '',
        components: {
          for (final e in comps.entries)
            if (e.value is num) e.key: e.value as num,
        },
      );
    }).toList();

    final available = <String>{};
    for (final s in subjects) {
      available.addAll(s.components.keys);
    }

    final card = data['reportCard'];
    return ResultsData(
      term: term,
      subjects: subjects,
      reportCard: card is Map ? ReportCard.fromMap(card.cast<String, dynamic>()) : null,
      availableComponents: available,
    );
  }
}

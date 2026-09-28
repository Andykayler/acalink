import 'package:cloud_firestore/cloud_firestore.dart';

/// One dated thing on the school year.
///
/// Dates are plain `YYYY-MM-DD` strings, matching what the web portal writes.
/// A school event happens on a date rather than at an instant — a holiday that
/// starts on the 3rd starts on the 3rd wherever the phone thinks it is — so
/// converting these to a Timestamp would introduce a timezone shift that only
/// ever moves the answer away from what the school said.
class SchoolEvent {
  final String id;
  final String title;
  final String description;
  final String category;
  final String startDate;
  final String endDate;
  final String audience;

  const SchoolEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.audience,
  });

  factory SchoolEvent.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return SchoolEvent(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category: d['category'] as String? ?? 'other',
      startDate: d['startDate'] as String? ?? '',
      endDate: d['endDate'] as String? ?? '',
      audience: d['audience'] as String? ?? 'everyone',
    );
  }

  /// The last day this event covers — a week of exams stays current on the
  /// Tuesday rather than disappearing after its first day.
  String get lastDay => endDate.isEmpty ? startDate : endDate;

  bool isPast(String today) => lastDay.isNotEmpty && lastDay.compareTo(today) < 0;

  DateTime? get start => DateTime.tryParse(startDate);

  /// Days until it begins; negative once it has started.
  int? daysFrom(DateTime now) {
    final s = start;
    if (s == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return s.difference(today).inDays;
  }

  String get when {
    String fmt(String iso) {
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    }

    if (startDate.isEmpty) return '';
    if (endDate.isEmpty || endDate == startDate) return fmt(startDate);
    return '${fmt(startDate)} – ${fmt(endDate)}';
  }
}

class CalendarService {
  final FirebaseFirestore _firestore;
  CalendarService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Everything on the school's calendar.
  ///
  /// Filtered on schoolCode alone because a list is authorised from the
  /// query's own constraints — adding a date range or an audience filter here
  /// would require the rule to allow that exact shape, and the saving at a
  /// school's few dozen events is nil. Staff-only events are dropped below.
  Future<List<SchoolEvent>> fetch(String schoolCode) async {
    if (schoolCode.isEmpty) return [];
    try {
      final snap = await _firestore
          .collection('school_events')
          .where('schoolCode', isEqualTo: schoolCode)
          .get();

      final events = snap.docs
          .map(SchoolEvent.fromDoc)
          .where((e) => e.audience != 'staff' && e.startDate.isNotEmpty)
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      return events;
    } catch (e) {
      // ignore: avoid_print
      print('[calendar] could not read events: $e');
      return [];
    }
  }

  static String todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// The next few things, for the dashboard strip.
  static List<SchoolEvent> upcoming(List<SchoolEvent> all, {int count = 3}) {
    final today = todayIso();
    return all.where((e) => !e.isPast(today)).take(count).toList();
  }
}

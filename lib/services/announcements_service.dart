import 'package:cloud_firestore/cloud_firestore.dart';

class AnnouncementItem {
  final String id;
  final String title;
  final String message;
  final DateTime? postedAt;

  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.message,
    required this.postedAt,
  });
}

/// Reads `announcements`, written by the head teacher / admin's
/// Announcements module. Each doc carries an `audience` (e.g.
/// "All Parents", "All Staff") — this only surfaces ones actually meant
/// for parents (or with no audience set at all, treated as everyone).
class AnnouncementsService {
  final FirebaseFirestore _firestore;
  AnnouncementsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Records that [parentId] has seen [announcementId], and bumps the
  /// announcement's counter the first time only.
  ///
  /// The marker document is what makes this idempotent: the app calls it every
  /// time the dashboard renders, so incrementing unconditionally would count
  /// screen refreshes instead of readers.
  Future<void> markRead(String announcementId, String parentId) async {
    if (announcementId.isEmpty || parentId.isEmpty) return;
    final marker = _firestore
        .collection('announcements')
        .doc(announcementId)
        .collection('reads')
        .doc(parentId);
    try {
      if ((await marker.get()).exists) return;
      await marker.set({
        'parentId': parentId,
        'readAt': FieldValue.serverTimestamp(),
      });
      await _firestore
          .collection('announcements')
          .doc(announcementId)
          .update({'readCount': FieldValue.increment(1)});
    } catch (e) {
      // A miscounted read is not worth failing the dashboard over.
      // ignore: avoid_print
      print('[announcements] markRead failed: $e');
    }
  }

  Future<List<AnnouncementItem>> fetchRecent(String schoolCode, {int limit = 5}) async {
    if (schoolCode.isEmpty) return [];

    final snap = await _firestore
        .collection('announcements')
        .where('schoolCode', isEqualTo: schoolCode)
        .orderBy('createdAt', descending: true)
        .limit(limit * 3) // headroom for the audience filter below
        .get();

    final items = <AnnouncementItem>[];
    for (final doc in snap.docs) {
      if (items.length >= limit) break;
      final data = doc.data();
      // "All Staff" contains "all", so a plain contains('all') test used to
      // leak staffroom notices to families. Anything addressed to staff is
      // excluded first, and only then is the inclusive side considered.
      final audience = (data['audience'] as String? ?? '').toLowerCase();
      final forStaff = audience.contains('staff');
      final relevant = !forStaff &&
          (audience.isEmpty ||
              audience.contains('parent') ||
              audience.contains('student') ||
              audience.contains('all'));
      if (!relevant) continue;

      final ts = data['createdAt'];
      items.add(AnnouncementItem(
        id: doc.id,
        title: data['title'] as String? ?? '',
        message: data['message'] as String? ?? '',
        postedAt: ts is Timestamp ? ts.toDate() : null,
      ));
    }
    return items;
  }
}

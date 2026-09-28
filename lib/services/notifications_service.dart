import 'package:cloud_firestore/cloud_firestore.dart';

/// Parent-side reader for the `notifications` collection the web portal writes.
///
/// The recipient id for a guardian is `parent:<E.164 phone>`, which is why the
/// query is a single equality filter — Firestore indexes that automatically, so
/// the app works against a fresh project with no composite index to create.
/// Ordering is done in Dart for the same reason (see the web
/// `src/services/notifications.js` for the matching note).
class ParentNotification {
  final String id;
  final String title;
  final String body;
  final String category;
  final String priority;
  final String actorName;
  final String studentId;
  final String studentName;
  final String entityType;
  final String entityId;
  final bool read;
  final DateTime? createdAt;

  const ParentNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.actorName,
    required this.studentId,
    required this.studentName,
    required this.entityType,
    required this.entityId,
    required this.read,
    required this.createdAt,
  });

  bool get isUrgent => priority == 'urgent';

  factory ParentNotification.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    final ms = d['createdAtMs'];
    return ParentNotification(
      id: doc.id,
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      category: d['category'] as String? ?? 'system',
      priority: d['priority'] as String? ?? 'normal',
      actorName: d['actorName'] as String? ?? '',
      studentId: d['studentId'] as String? ?? '',
      studentName: d['studentName'] as String? ?? '',
      entityType: d['entityType'] as String? ?? '',
      entityId: d['entityId'] as String? ?? '',
      read: d['read'] as bool? ?? false,
      createdAt: ts is Timestamp
          ? ts.toDate()
          : (ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null),
    );
  }
}

String parentRecipientId(String normalisedPhone) =>
    normalisedPhone.isEmpty ? '' : 'parent:$normalisedPhone';

class NotificationsService {
  final FirebaseFirestore _firestore;
  NotificationsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Live inbox for a guardian, newest first. Emits an empty list rather than
  /// an error so a permissions problem shows as "nothing yet" instead of
  /// breaking the screen.
  Stream<List<ParentNotification>> watch(String phone, {int max = 60}) {
    final recipientId = parentRecipientId(phone);
    if (recipientId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: recipientId)
        .limit(max)
        .snapshots()
        .map((snap) {
      final rows = snap.docs.map(ParentNotification.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
      return rows;
    }).handleError((Object e) {
      // ignore: avoid_print
      print('[notifications] stream error: $e');
    });
  }

  /// Convenience stream of just the unread count, for the bell badge.
  Stream<int> watchUnreadCount(String phone) =>
      watch(phone).map((rows) => rows.where((n) => !n.read).length);

  Future<void> markRead(String id) async {
    try {
      await _firestore.collection('notifications').doc(id).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[notifications] markRead failed: $e');
    }
  }

  Future<void> markAllRead(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    try {
      // Firestore caps a batch at 500 writes.
      for (var i = 0; i < list.length; i += 450) {
        final batch = _firestore.batch();
        for (final id in list.skip(i).take(450)) {
          batch.update(_firestore.collection('notifications').doc(id), {
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[notifications] markAllRead failed: $e');
    }
  }

  Future<void> dismiss(String id) async {
    try {
      await _firestore.collection('notifications').doc(id).delete();
    } catch (e) {
      // ignore: avoid_print
      print('[notifications] dismiss failed: $e');
    }
  }
}

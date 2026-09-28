import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';
import 'notifications_service.dart';

/// Parent side of the `conversations` collection. The staff side is
/// `src/components/messaging/MessagesModule.jsx` in the web portal — the two
/// derive the same deterministic document id, so whichever party writes first
/// creates the thread and the other joins it instead of forking a second one.
class StaffContact {
  final String id;
  final String name;
  final String role;
  final List<String> assignedClasses;

  const StaffContact({
    required this.id,
    required this.name,
    required this.role,
    this.assignedClasses = const [],
  });

  String get roleLabel {
    switch (role) {
      case 'head_teacher':
        return 'Head Teacher';
      case 'class_teacher':
        return 'Teacher';
      case 'bursar':
        return 'Bursar';
      default:
        return 'Staff';
    }
  }
}

class Conversation {
  final String id;
  final String schoolCode;
  final String studentId;
  final String studentName;
  final String className;
  final String staffId;
  final String staffName;
  final String staffRole;
  final String parentId;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final Map<String, dynamic> unread;

  const Conversation({
    required this.id,
    required this.schoolCode,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.staffId,
    required this.staffName,
    required this.staffRole,
    required this.parentId,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastMessageAt,
    required this.unread,
  });

  int unreadFor(String participantId) {
    final value = unread[participantId];
    return value is int ? value : 0;
  }

  factory Conversation.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['lastMessageAt'];
    final ms = d['lastMessageAtMs'];
    return Conversation(
      id: doc.id,
      schoolCode: d['schoolCode'] as String? ?? '',
      studentId: d['studentId'] as String? ?? '',
      studentName: d['studentName'] as String? ?? '',
      className: d['className'] as String? ?? '',
      staffId: d['staffId'] as String? ?? '',
      staffName: d['staffName'] as String? ?? 'Staff',
      staffRole: d['staffRole'] as String? ?? '',
      parentId: d['parentId'] as String? ?? '',
      lastMessage: d['lastMessage'] as String? ?? '',
      lastSenderId: d['lastSenderId'] as String? ?? '',
      lastMessageAt: ts is Timestamp
          ? ts.toDate()
          : (ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null),
      unread: (d['unread'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class ChatMessage {
  final String id;
  final String body;
  final String senderId;
  final String senderName;
  final String senderType; // staff | parent
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.body,
    required this.senderId,
    required this.senderName,
    required this.senderType,
    required this.createdAt,
  });

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    final ms = d['createdAtMs'];
    return ChatMessage(
      id: doc.id,
      body: d['body'] as String? ?? '',
      senderId: d['senderId'] as String? ?? '',
      senderName: d['senderName'] as String? ?? '',
      senderType: d['senderType'] as String? ?? 'staff',
      createdAt: ts is Timestamp
          ? ts.toDate()
          : (ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null),
    );
  }
}

class ChatService {
  final FirebaseFirestore _firestore;
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static String conversationId({
    required String schoolCode,
    required String studentId,
    required String staffId,
  }) =>
      '${schoolCode}__${studentId}__$staffId';

  /// Live conversation list for a guardian, most recent first.
  Stream<List<Conversation>> watchConversations(String phone) {
    final parentId = parentRecipientId(phone);
    if (parentId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('conversations')
        .where('participantIds', arrayContains: parentId)
        .snapshots()
        .map((snap) {
      final rows = snap.docs.map(Conversation.fromDoc).toList()
        ..sort((a, b) {
          final at = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
      return rows;
    }).handleError((Object e) {
      // ignore: avoid_print
      print('[chat] conversation stream error: $e');
    });
  }

  Stream<int> watchUnreadTotal(String phone) {
    final parentId = parentRecipientId(phone);
    return watchConversations(phone)
        .map((rows) => rows.fold<int>(0, (n, c) => n + c.unreadFor(parentId)));
  }

  /// Live transcript, oldest first.
  ///
  /// The participantIds filter mirrors the security rule on this subcollection.
  /// Firestore proves a list query is safe from the query constraints alone,
  /// not by checking each returned document, so an unfiltered query here would
  /// be refused outright even though every message in it is readable.
  Stream<List<ChatMessage>> watchMessages(String conversationId, String phone) {
    final parentId = parentRecipientId(phone);
    if (parentId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('participantIds', arrayContains: parentId)
        .snapshots()
        .map((snap) {
      final rows = snap.docs.map(ChatMessage.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return at.compareTo(bt);
        });
      return rows;
    });
  }

  /// Staff a guardian may write to: the school's leadership plus the teachers
  /// assigned to their child's class. If nobody is assigned to that class yet,
  /// every teacher is offered rather than leaving the parent with no one.
  Future<List<StaffContact>> fetchContacts(Student student) async {
    if (student.schoolCode.isEmpty) return const [];
    // The role filter is part of the query, not a post-filter: security rules
    // only let an anonymous parent session read teaching staff, and a list
    // query fails outright if any document it returns is denied.
    final snap = await _firestore
        .collection('users')
        .where('schoolCode', isEqualTo: student.schoolCode)
        .where('role', whereIn: ['head_teacher', 'class_teacher'])
        .get();

    // A deactivated staff member can't read replies, so they aren't offered.
    // ('suspended' is the older name for the same state.)
    final all = snap.docs.where((d) {
      final status = d.data()['status'];
      return status != 'deactivated' && status != 'suspended';
    }).map((d) {
      final data = d.data();
      return StaffContact(
        id: d.id,
        name: (data['name'] ?? data['displayName'] ?? 'Staff') as String,
        role: (data['role'] ?? '') as String,
        assignedClasses:
            ((data['assignedClasses'] as List?)?.cast<String>()) ?? const [],
      );
    }).toList();

    final leadership = all.where((c) => c.role == 'head_teacher').toList();
    final classTeachers = all
        .where((c) =>
            c.role == 'class_teacher' &&
            c.assignedClasses.contains(student.className))
        .toList();

    final teachers = classTeachers.isNotEmpty
        ? classTeachers
        : all.where((c) => c.role == 'class_teacher').toList();

    return [...leadership, ...teachers];
  }

  /// Creates the conversation if it is not there yet and returns its id.
  Future<String> ensureConversation({
    required Student student,
    required StaffContact staff,
    required String parentPhone,
  }) async {
    final id = conversationId(
      schoolCode: student.schoolCode,
      studentId: student.id,
      staffId: staff.id,
    );
    final ref = _firestore.collection('conversations').doc(id);
    final snap = await ref.get();
    final parentId = parentRecipientId(parentPhone);

    if (!snap.exists) {
      await ref.set({
        'schoolCode': student.schoolCode,
        'studentId': student.id,
        'studentName': student.fullName,
        'className': student.className,
        'staffId': staff.id,
        'staffName': staff.name,
        'staffRole': staff.role,
        'parentId': parentId,
        'parentPhone': parentPhone,
        'parentName': student.guardianName.isEmpty ? 'Guardian' : student.guardianName,
        'participantIds': [staff.id, parentId],
        'subject': '',
        'lastMessage': '',
        'lastSenderId': '',
        'unread': {staff.id: 0, parentId: 0},
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    }
    return id;
  }

  /// Appends a message, refreshes the conversation header and drops a
  /// notification in the staff member's bell.
  Future<bool> sendMessage({
    required String conversationId,
    required String parentPhone,
    required String parentName,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return false;

    final parentId = parentRecipientId(parentPhone);
    final ref = _firestore.collection('conversations').doc(conversationId);

    try {
      final snap = await ref.get();
      if (!snap.exists) return false;
      final convo = snap.data()!;
      final participants = ((convo['participantIds'] as List?) ?? const [])
          .cast<String>();
      final otherId = participants.firstWhere(
        (p) => p != parentId,
        orElse: () => '',
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await ref.collection('messages').add({
        'conversationId': conversationId,
        // Denormalised from the conversation so security rules can authorise a
        // message without a get() on its parent doc. Kept in step with the web
        // portal's sendMessage.
        'participantIds': participants,
        'body': text,
        'senderId': parentId,
        'senderName': parentName.isEmpty ? 'Guardian' : parentName,
        'senderRole': 'guardian',
        'senderType': 'parent',
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': now,
      });

      await ref.update({
        'lastMessage': text.length > 160 ? text.substring(0, 160) : text,
        'lastSenderId': parentId,
        'lastSenderName': parentName,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageAtMs': now,
        'status': 'open',
        if (otherId.isNotEmpty) 'unread.$otherId': FieldValue.increment(1),
        'unread.$parentId': 0,
      });

      if (otherId.isNotEmpty) {
        await _pushStaffNotification(
          recipientId: otherId,
          schoolCode: convo['schoolCode'] as String? ?? '',
          senderName: parentName.isEmpty ? 'Guardian' : parentName,
          preview: text,
          conversationId: conversationId,
          studentId: convo['studentId'] as String? ?? '',
          studentName: convo['studentName'] as String? ?? '',
        );
      }
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[chat] send failed: $e');
      return false;
    }
  }

  /// Mirrors the web `pushNotification` write, including the inverted-timestamp
  /// document id that keeps the inbox newest-first without a composite index.
  Future<void> _pushStaffNotification({
    required String recipientId,
    required String schoolCode,
    required String senderName,
    required String preview,
    required String conversationId,
    required String studentId,
    required String studentName,
  }) async {
    const idCeiling = 9999999999999;
    final inverted = (idCeiling - DateTime.now().millisecondsSinceEpoch)
        .toString()
        .padLeft(13, '0');
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final docId = '${inverted}_$salt';

    try {
      await _firestore.collection('notifications').doc(docId).set({
        'schoolCode': schoolCode,
        'recipientId': recipientId,
        'recipientType': 'staff',
        'recipientName': '',
        'title': 'New message from $senderName',
        'body': preview.length > 140 ? preview.substring(0, 140) : preview,
        'category': 'message',
        'priority': 'normal',
        'actorId': '',
        'actorName': senderName,
        'actorRole': 'guardian',
        'tab': 'messages',
        'entityType': 'conversation',
        'entityId': conversationId,
        'studentId': studentId,
        'studentName': studentName,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        // Matches NOTIFICATION_TTL_DAYS in src/services/notifications.js — the
        // Firestore TTL policy reads this field.
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 90)),
        ),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[chat] staff notification failed: $e');
    }
  }

  Future<void> markRead(String conversationId, String parentPhone) async {
    final parentId = parentRecipientId(parentPhone);
    if (parentId.isEmpty) return;
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .update({'unread.$parentId': 0});
    } catch (e) {
      // ignore: avoid_print
      print('[chat] markRead failed: $e');
    }
  }
}

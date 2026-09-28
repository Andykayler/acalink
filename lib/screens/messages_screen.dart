import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/tokens.dart';
import '../theme/app_colors.dart';
import '../models/student.dart';
import '../services/chat_service.dart';
import '../state/session_provider.dart';
import 'chat_screen.dart';

/// Guardian's conversation list, plus the picker for starting a new one with
/// the head teacher or one of their child's teachers.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _chat = ChatService();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final phone = session.parentPhone ?? '';
    final student = session.selectedStudent;
    final parentId = parentIdFor(phone);

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.heroBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Messages',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border),
        ),
      ),
      floatingActionButton: student == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startNew(context, student, phone),
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('New message', style: TextStyle(fontSize: 13.5)),
            ),
      body: StreamBuilder<List<Conversation>>(
        stream: _chat.watchConversations(phone),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          final rows = snapshot.data ?? const <Conversation>[];
          if (rows.isEmpty) {
            return _EmptyMessages(
              onStart: student == null ? null : () => _startNew(context, student, phone),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, i) => _ConversationTile(
              conversation: rows[i],
              unread: rows[i].unreadFor(parentId),
              mineId: parentId,
              onTap: () => _openChat(context, rows[i]),
            ),
          );
        },
      ),
    );
  }

  void _openChat(BuildContext context, Conversation c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
    );
  }

  Future<void> _startNew(BuildContext context, Student student, String phone) async {
    final contacts = await _chat.fetchContacts(student);
    if (!context.mounted) return;

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No teachers are listed for this school yet.', style: TextStyle(fontSize: 13)),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<StaffContact>(
      context: context,
      backgroundColor: context.colors.heroBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ContactPicker(contacts: contacts, student: student),
    );
    if (picked == null || !context.mounted) return;

    final id = await _chat.ensureConversation(
      student: student,
      staff: picked,
      parentPhone: phone,
    );
    if (!context.mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: id,
        staffName: picked.name,
        staffRole: picked.roleLabel,
        studentName: student.fullName,
      ),
    ));
  }
}

String parentIdFor(String phone) => phone.isEmpty ? '' : 'parent:$phone';

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final int unread;
  final String mineId;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.unread,
    required this.mineId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mineLast = conversation.lastSenderId == mineId;
    final preview = conversation.lastMessage.isEmpty
        ? 'No messages yet'
        : '${mineLast ? "You: " : ""}${conversation.lastMessage}';

    return Material(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: unread > 0 ? context.colors.primary.withValues(alpha: 0.4) : context.colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tintFor(conversation.staffId),
                  borderRadius: BorderRadius.circular(21),
                ),
                alignment: Alignment.center,
                child: Text(
                  initialsOf(conversation.staffName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.staffName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          relativeTime(conversation.lastMessageAt),
                          style: TextStyle(fontSize: 10.5, color: context.colors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_roleLabel(conversation.staffRole)} · ${conversation.studentName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: context.colors.primary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: unread > 0 ? context.colors.textSecondary : context.colors.textMuted,
                            ),
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.colors.primary,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _roleLabel(String role) {
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

class _ContactPicker extends StatelessWidget {
  final List<StaffContact> contacts;
  final Student student;

  const _ContactPicker({required this.contacts, required this.student});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 14),
            decoration: BoxDecoration(
              color: context.colors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Who would you like to reach?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  'About ${student.fullName} · ${student.className}',
                  style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: contacts.length,
              itemBuilder: (context, i) {
                final c = contacts[i];
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: CircleAvatar(
                    backgroundColor: tintFor(c.id),
                    child: Text(
                      initialsOf(c.name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    c.roleLabel,
                    style: TextStyle(fontSize: 12, color: context.colors.textMuted),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textMuted),
                  onTap: () => Navigator.of(context).pop(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  final VoidCallback? onStart;
  const _EmptyMessages({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: context.colors.purplePale,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.forum_outlined, size: 28, color: context.colors.purple),
            ),
            const SizedBox(height: 14),
            Text(
              'No conversations yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
            ),
            const SizedBox(height: 5),
            Text(
              'Reach your child’s teacher or the head teacher directly — replies land right here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.textMuted, height: 1.5),
            ),
            if (onStart != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Start a conversation', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

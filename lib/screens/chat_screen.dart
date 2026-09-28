import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/tokens.dart';
import '../theme/app_colors.dart';
import '../services/chat_service.dart';
import '../state/session_provider.dart';

/// One guardian ↔ staff transcript. Opened either from an existing
/// [Conversation] in the list, or straight after creating one, in which case
/// only the id and the header details are known.
class ChatScreen extends StatefulWidget {
  final Conversation? conversation;
  final String? conversationId;
  final String? staffName;
  final String? staffRole;
  final String? studentName;

  const ChatScreen({
    super.key,
    this.conversation,
    this.conversationId,
    this.staffName,
    this.staffRole,
    this.studentName,
  }) : assert(conversation != null || conversationId != null,
            'ChatScreen needs either a conversation or a conversation id');

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chat = ChatService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  String get _id => widget.conversation?.id ?? widget.conversationId!;
  String get _staffName => widget.conversation?.staffName ?? widget.staffName ?? 'Staff';
  String get _staffId => widget.conversation?.staffId ?? _id.split('__').last;
  String get _subtitle {
    final role = widget.conversation?.staffRole ?? '';
    final label = widget.staffRole ?? _roleLabel(role);
    final student = widget.conversation?.studentName ?? widget.studentName ?? '';
    return student.isEmpty ? label : '$label · About $student';
  }

  @override
  void initState() {
    super.initState();
    // Opening the thread clears the badge for this parent.
    final phone = context.read<SessionProvider>().parentPhone ?? '';
    if (phone.isNotEmpty) _chat.markRead(_id, phone);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final session = context.read<SessionProvider>();
    final phone = session.parentPhone ?? '';
    final parentName = session.selectedStudent?.guardianName ?? 'Guardian';

    setState(() => _sending = true);
    _controller.clear();

    final ok = await _chat.sendMessage(
      conversationId: _id,
      parentPhone: phone,
      parentName: parentName,
      body: text,
    );

    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not send. Check your connection.', style: TextStyle(fontSize: 13)),
        ),
      );
    }
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<SessionProvider>().parentPhone ?? '';
    final myId = phone.isEmpty ? '' : 'parent:$phone';

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.heroBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: tintFor(_staffId),
              child: Text(
                initialsOf(_staffName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _staffName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chat.watchMessages(_id, phone),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
                }
                final messages = snapshot.data ?? const <ChatMessage>[];
                if (messages.isEmpty) {
                  return const _ChatIntro();
                }
                _scrollToEnd();

                // Each message carries the day heading it should print above
                // itself, if the day changed since the previous one.
                String lastDay = '';
                final rows = <({ChatMessage message, String? day})>[];
                for (final m in messages) {
                  final day = _dayLabel(m.createdAt);
                  rows.add((message: m, day: day == lastDay ? null : day));
                  lastDay = day;
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final mine = row.message.senderId == myId;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (row.day != null) _DayDivider(label: row.day!),
                        _Bubble(message: row.message, mine: mine),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _controller,
            sending: _sending,
            onSend: _send,
          ),
        ],
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

String _dayLabel(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(dt, now)) return 'Today';
  if (sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${dt.day}/${dt.month}/${dt.year}';
}

class _DayDivider extends StatelessWidget {
  final String label;
  const _DayDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.heroBg,
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.colors.textMuted),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt == null
        ? ''
        : TimeOfDay.fromDateTime(message.createdAt!).format(context);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: mine ? context.colors.primary : context.colors.cardBg,
          border: Border.all(color: mine ? context.colors.primary : context.colors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ),
            Text(
              message.body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: mine ? Colors.white : context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 9.5,
                  color: mine ? Colors.white70 : context.colors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 10, 12, 10 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.heroBg,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 13.5, color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Write a message…',
                hintStyle: TextStyle(fontSize: 13.5, color: context.colors.textMuted),
                filled: true,
                fillColor: context.colors.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: context.colors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: context.colors.primary,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: sending ? null : onSend,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 44,
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatIntro extends StatelessWidget {
  const _ChatIntro();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.colors.primaryPale,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.waving_hand_outlined, size: 25, color: context.colors.primary),
            ),
            const SizedBox(height: 13),
            Text(
              'Say hello',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Messages here reach the school straight away and stay on record for both of you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: context.colors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

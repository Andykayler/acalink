import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/tokens.dart';
import '../theme/app_colors.dart';
import '../services/notifications_service.dart';
import '../state/session_provider.dart';
import 'messages_screen.dart';

/// The guardian's inbox: everything the school has sent about their children,
/// live from Firestore. Written by the web portals via
/// `src/services/notificationHooks.js`.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _Filter { all, unread, school, child }

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationsService();
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final phone = session.parentPhone ?? '';
    final selectedId = session.selectedStudent?.id;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.heroBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Notifications',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border),
        ),
      ),
      body: StreamBuilder<List<ParentNotification>>(
        stream: _service.watch(phone),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          final all = snapshot.data ?? const <ParentNotification>[];
          final unreadIds = all.where((n) => !n.read).map((n) => n.id).toList();

          final rows = all.where((n) {
            switch (_filter) {
              case _Filter.unread:
                return !n.read;
              case _Filter.school:
                return n.category == 'announcement';
              case _Filter.child:
                return selectedId != null && n.studentId == selectedId;
              case _Filter.all:
                return true;
            }
          }).toList();

          return Column(
            children: [
              _FilterBar(
                current: _filter,
                unread: unreadIds.length,
                childName: session.selectedStudent?.firstName ?? 'This child',
                onChange: (f) => setState(() => _filter = f),
                onMarkAll: unreadIds.isEmpty
                    ? null
                    : () => _service.markAllRead(unreadIds),
              ),
              Expanded(
                child: rows.isEmpty
                    ? _EmptyInbox(filter: _filter)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _NotificationTile(
                          item: rows[i],
                          onTap: () => _open(rows[i]),
                          onDismiss: () => _service.dismiss(rows[i].id),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _open(ParentNotification n) {
    if (!n.read) _service.markRead(n.id);
    // A message notification is the one kind that has somewhere to go.
    if (n.entityType == 'conversation') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MessagesScreen()),
      );
    }
  }
}

class _FilterBar extends StatelessWidget {
  final _Filter current;
  final int unread;
  final String childName;
  final ValueChanged<_Filter> onChange;
  final VoidCallback? onMarkAll;

  const _FilterBar({
    required this.current,
    required this.unread,
    required this.childName,
    required this.onChange,
    required this.onMarkAll,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <(_Filter, String)>[
      (_Filter.all, 'All'),
      (_Filter.unread, unread > 0 ? 'Unread ($unread)' : 'Unread'),
      (_Filter.school, 'School'),
      (_Filter.child, childName),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: context.colors.heroBg,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (value, label) in chips) ...[
                    _Chip(
                      label: label,
                      selected: current == value,
                      onTap: () => onChange(value),
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
          if (onMarkAll != null)
            TextButton(
              onPressed: onMarkAll,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Mark all', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.primaryPale : context.colors.bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? context.colors.primary : context.colors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? context.colors.primaryDark : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon + colour for each notification category, matching the web bell.
({IconData icon, Color color, Color pale}) _styleFor(AppColors c, String category) {
  switch (category) {
    case 'announcement':
      return (icon: Icons.campaign_outlined, color: c.primary, pale: c.primaryPale);
    case 'attendance':
      return (icon: Icons.event_available_rounded, color: c.warning, pale: c.warningPale);
    case 'performance':
      return (icon: Icons.grade_rounded, color: c.success, pale: c.successPale);
    // The term's official result, issued by the head teacher — given its own
    // mark so it does not read as one more subject publication in the list.
    case 'report':
      return (icon: Icons.assignment_turned_in_rounded, color: c.success, pale: c.successPale);
    case 'discipline':
      return (icon: Icons.gavel_rounded, color: c.danger, pale: c.dangerPale);
    case 'homework':
      return (icon: Icons.menu_book_rounded, color: c.primary, pale: c.primaryPale);
    case 'fees':
      return (icon: Icons.account_balance_wallet_rounded, color: c.warning, pale: c.warningPale);
    case 'message':
      return (icon: Icons.chat_bubble_outline_rounded, color: c.purple, pale: c.purplePale);
    default:
      return (icon: Icons.notifications_none_rounded, color: c.textSecondary, pale: c.bg);
  }
}

class _NotificationTile extends StatelessWidget {
  final ParentNotification item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context.colors, item.category);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: context.colors.dangerPale,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.colors.danger, size: 20),
      ),
      child: Material(
        color: item.read ? context.colors.cardBg : context.colors.primaryPale,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: item.read ? context.colors.border : context.colors.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.pale,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(style.icon, size: 19, color: style.color),
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
                              item.title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: item.read ? FontWeight.w600 : FontWeight.w700,
                                color: context.colors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (!item.read)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 3),
                              decoration: BoxDecoration(
                                color: context.colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.body,
                          style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            relativeTime(item.createdAt),
                            style: TextStyle(fontSize: 11, color: context.colors.textMuted),
                          ),
                          if (item.studentName.isNotEmpty)
                            Text(
                              '· ${item.studentName}',
                              style: TextStyle(fontSize: 11, color: context.colors.textMuted),
                            ),
                          if (item.actorName.isNotEmpty && item.actorName != 'System')
                            Text(
                              '· ${item.actorName}',
                              style: TextStyle(fontSize: 11, color: context.colors.textMuted),
                            ),
                          if (item.isUrgent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.colors.dangerPale,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'URGENT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: context.colors.danger,
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
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final _Filter filter;
  const _EmptyInbox({required this.filter});

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _Filter.unread => 'You have read everything.',
      _Filter.school => 'No school-wide announcements yet.',
      _Filter.child => 'Nothing for this child yet.',
      _Filter.all => 'Results, attendance, fees and messages from the school will appear here.',
    };

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
                color: context.colors.primaryPale,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.notifications_none_rounded, size: 28, color: context.colors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'All caught up',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/student.dart';
import '../state/session_provider.dart';
import '../services/fees_service.dart';
import '../services/attendance_service.dart';
import '../services/performance_service.dart';
import '../services/discipline_service.dart';
import '../services/homework_service.dart';
import '../services/academic_term_service.dart';
import '../services/announcements_service.dart';
import '../services/notifications_service.dart';
import '../services/chat_service.dart';
import '../services/push_service.dart';
import '../services/dashboard_watcher.dart';
import 'student_select_screen.dart';
import 'fees_screen.dart';
import 'notifications_screen.dart';
import 'results_screen.dart';
import 'attendance_screen.dart';
import 'homework_screen.dart';
import 'calendar_screen.dart';
import 'discipline_screen.dart';
import 'messages_screen.dart';
import '../state/theme_provider.dart';
import '../theme/app_colors.dart';

String _relativeTime(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

/// ─── Screen ────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  final _feesService = FeesService();
  final _attendanceService = AttendanceService();
  final _performanceService = PerformanceService();
  final _disciplineService = DisciplineService();
  final _homeworkService = HomeworkService();
  final _announcementsService = AnnouncementsService();
  final _notificationsService = NotificationsService();
  final _chatService = ChatService();
  final _watcher = DashboardWatcher();

  bool _loading = true;
  String? _error;
  String? _loadedForStudentId;

  FeesData? _fees;
  AttendanceSummary _attendance = AttendanceSummary.empty;
  PerformanceSummary _performance = PerformanceSummary.empty;
  DisciplineSummary _discipline = DisciplineSummary.empty;
  List<HomeworkTask> _homework = const [];
  List<AnnouncementItem> _announcements = const [];
  String _term = '';

  // The badge streams are built once per phone number rather than per build:
  // calling watch* inside build() would tear down and re-open a Firestore
  // listener on every rebuild.
  // Cancelled and rebuilt when the selected child changes, so the previous
  // child's listeners cannot overwrite the new one's figures.
  StreamSubscription<DashboardSection>? _watchSub;
  String? _watchingStudentId;

  String? _streamsForPhone;
  Stream<int> _unreadNotifications = const Stream<int>.empty();
  Stream<int> _unreadMessages = const Stream<int>.empty();

  final _gradesKey = GlobalKey();
  final _statsKey = GlobalKey();
  final _homeworkKey = GlobalKey();
  final _announcementsKey = GlobalKey();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Android raises no system notification while the app is in front, so a
    // push that lands here is shown as an in-app banner instead.
    PushService.instance.onForegroundMessage = (message) {
      if (!mounted) return;
      final title = message.notification?.title ?? 'New notification';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Text(title, style: const TextStyle(fontSize: 13)),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _openFromPush(message),
          ),
        ),
      );
    };
    PushService.instance.onNotificationTap = _openFromPush;

    // A tap from a terminated app is delivered once, on request.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await PushService.instance.initialMessage();
      if (initial != null && mounted) _openFromPush(initial);
    });
  }

  /// Sends the parent to the screen a push refers to. `entityType` mirrors the
  /// field the web portal writes on the notification document.
  void _openFromPush(RemoteMessage message) {
    if (!mounted) return;
    final entityType = message.data['entityType'] ?? '';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => entityType == 'conversation'
          ? const MessagesScreen()
          : const NotificationsScreen(),
    ));
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _watcher.stop();
    _shimmer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // build() schedules a load whenever _loadedForStudentId does not match, but
  // the very first thing a load does is setState — which rebuilds, which
  // schedules another load before the first has finished. Without this guard
  // a single dashboard open fired the whole fetch a dozen times over.
  String? _loadInFlightFor;

  Future<void> _loadDashboard(Student student) async {
    if (_loadInFlightFor == student.id) return;
    _loadInFlightFor = student.id;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _feesService.fetchStudentFees(student),
        _attendanceService.fetchRecentAttendance(student),
        _performanceService.fetchPerformance(student),
        _disciplineService.fetchSummary(student),
        _homeworkService.fetchUpcoming(student),
        _announcementsService.fetchRecent(student.schoolCode),
        AcademicTermService().currentTerm(student.schoolCode),
      ]);

      if (!mounted) return;
      setState(() {
        _fees = results[0] as FeesData;
        _attendance = results[1] as AttendanceSummary;
        _performance = results[2] as PerformanceSummary;
        _discipline = results[3] as DisciplineSummary;
        _homework = results[4] as List<HomeworkTask>;
        _announcements = results[5] as List<AnnouncementItem>;
        _term = results[6] as String;
        _loadedForStudentId = student.id;
        _loading = false;
      });

      _startWatching(student);

      // Announcements shown on the dashboard count as read. markRead is
      // idempotent, so re-rendering does not inflate the count.
      final phone = context.mounted ? _streamsForPhone ?? '' : '';
      if (phone.isNotEmpty) {
        final parentId = parentRecipientId(phone);
        for (final a in _announcements) {
          unawaited(_announcementsService.markRead(a.id, parentId));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your dashboard: $e';
      });
    } finally {
      // Cleared even on the !mounted early return, so a student switch that
      // races a teardown does not leave the guard stuck.
      _loadInFlightFor = null;
    }
  }

  /// Keeps the dashboard current without the parent reopening the app.
  ///
  /// Started only after the first load has succeeded: the listeners report
  /// *changes*, so there is nothing for them to say until there is something
  /// on screen to change.
  void _startWatching(Student student) {
    if (_watchingStudentId == student.id) return;
    _watchingStudentId = student.id;
    _watchSub?.cancel();
    _watchSub = _watcher
        .start(student)
        .listen((section) => _refreshSection(section, student));
  }

  /// Re-reads just the part that moved. A teacher saving a register should
  /// cost one attendance read, not a whole dashboard.
  Future<void> _refreshSection(DashboardSection section, Student student) async {
    try {
      switch (section) {
        case DashboardSection.fees:
          // A payment can lift the hold on results, so the grades refresh too.
          final v = await _feesService.fetchStudentFees(student);
          final p = await _performanceService.fetchPerformance(student);
          if (mounted) {
            setState(() {
              _fees = v;
              _performance = p;
            });
          }
        case DashboardSection.attendance:
          final v = await _attendanceService.fetchRecentAttendance(student);
          if (mounted) setState(() => _attendance = v);
        case DashboardSection.performance:
          final v = await _performanceService.fetchPerformance(student);
          if (mounted) setState(() => _performance = v);
        case DashboardSection.discipline:
          final v = await _disciplineService.fetchSummary(student);
          if (mounted) setState(() => _discipline = v);
        case DashboardSection.homework:
          final v = await _homeworkService.fetchUpcoming(student);
          if (mounted) setState(() => _homework = v);
        case DashboardSection.announcements:
          final v = await _announcementsService.fetchRecent(student.schoolCode);
          if (mounted) setState(() => _announcements = v);
        case DashboardSection.term:
          // The term decides which marks count as current, so a term change
          // invalidates the grades card as well as the label.
          AcademicTermService.clearCache();
          final t = await AcademicTermService().currentTerm(student.schoolCode);
          final p = await _performanceService.fetchPerformance(student);
          if (mounted) {
            setState(() {
              _term = t;
              _performance = p;
            });
          }
      }
    } catch (e) {
      // A failed refresh leaves the last good figure on screen, which is
      // better than blanking a card the parent was reading.
      debugPrint('[dashboard] could not refresh ${section.name}: $e');
    }
  }

  void _ensureBadgeStreams(String phone) {
    if (_streamsForPhone == phone) return;
    _streamsForPhone = phone;
    _unreadNotifications =
        _notificationsService.watchUnreadCount(phone).asBroadcastStream();
    _unreadMessages = _chatService.watchUnreadTotal(phone).asBroadcastStream();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  void _handleQuickAction(BuildContext context, String label, Student? student) {
    switch (label) {
      case 'Fees':
        _openFees(context, student);
        break;
      case 'Grades':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResultsScreen()),
        );
        break;
      case 'Attendance':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
        break;
      case 'Homework':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HomeworkScreen()),
        );
        break;
      case 'Discipline':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DisciplineScreen()),
        );
        break;
      case 'Calendar':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CalendarScreen()),
        );
        break;
      case 'Announcements':
        _scrollTo(_announcementsKey);
        break;
      case 'Messages':
        _openMessages(context);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final student = session.selectedStudent;
    _ensureBadgeStreams(session.parentPhone ?? '');

    if (student != null && _loadedForStudentId != student.id) {
      // The old child's listeners must go before the new child's data lands,
      // or a late callback from the previous subscription overwrites it.
      if (_watchingStudentId != null && _watchingStudentId != student.id) {
        _watchSub?.cancel();
        _watcher.stop();
        _watchingStudentId = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard(student));
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: _DashboardHero(
                student: student,
                term: _term,
                unreadStream: _unreadNotifications,
                onOpenNotifications: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                onSwitchChild: () {
                  session.openStudentSwitcher();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const StudentSelectScreen()),
                  );
                },
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverToBoxAdapter(child: _ErrorBanner(message: _error!)),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _statsKey,
                  child: _loading
                      ? _StatsRowSkeleton(shimmer: _shimmer)
                      : _StatsRow(
                          attendance: _attendance,
                          performance: _performance,
                          fees: _fees,
                          discipline: _discipline,
                          onTapFees: () => _openFees(context, student),
                        ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _QuickActionsGrid(
                  messagesBadgeStream: _unreadMessages,
                  onAction: (label) => _handleQuickAction(context, label, student),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _gradesKey,
                  child: _loading
                      ? _SkeletonCard(shimmer: _shimmer, rows: 4, title: 'Recent Grades')
                      : _RecentGradesCard(performance: _performance),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _homeworkKey,
                  child: _loading
                      ? _SkeletonCard(shimmer: _shimmer, rows: 3, title: 'Upcoming')
                      : _UpcomingList(tasks: _homework),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _announcementsKey,
                  child: _loading
                      ? _SkeletonCard(shimmer: _shimmer, rows: 3, title: 'Announcements')
                      : _AnnouncementsCard(items: _announcements),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _Footer()),
          ],
        ),
      ),
    );
  }

  void _openMessages(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MessagesScreen()),
    );
  }

  void _openFees(BuildContext context, Student? student) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeesScreen(student: student, guardianName: ''),
      ),
    );
  }
}

/// ─── Error banner ──────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.dangerPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: context.colors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: context.colors.danger)),
          ),
        ],
      ),
    );
  }
}

/// ─── Hero ──────────────────────────────────────────────────────────────
class _DashboardHero extends StatelessWidget {
  final Student? student;
  final String term;
  final VoidCallback onSwitchChild;
  final VoidCallback onOpenNotifications;
  final Stream<int> unreadStream;

  const _DashboardHero({
    required this.student,
    required this.term,
    required this.onSwitchChild,
    required this.onOpenNotifications,
    required this.unreadStream,
  });

  @override
  Widget build(BuildContext context) {
    final name = student?.fullName ?? 'Student';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final subtitle = student == null ? '' : '${student!.className} · ${student!.schoolName}';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: context.colors.heroBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.colors.navyStart, context.colors.navyEnd],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 14, height: 1, color: context.colors.warning),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        term.isEmpty ? 'TERM NOT SET' : AcademicTermService.display(term),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: context.colors.fontMono,
                          fontSize: 9,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: context.colors.fontDisplay,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Consumer<ThemeProvider>(
            builder: (context, theme, _) => _IconPillButton(
              icon: theme.mode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              count: 0,
              onTap: () => theme.toggle(),
            ),
          ),
          const SizedBox(width: 8),
          StreamBuilder<int>(
            stream: unreadStream,
            initialData: 0,
            builder: (context, snap) => _IconPillButton(
              icon: Icons.notifications_none_rounded,
              count: snap.data ?? 0,
              onTap: onOpenNotifications,
            ),
          ),
          const SizedBox(width: 8),
          _IconPillButton(icon: Icons.swap_horiz_rounded, count: 0, onTap: onSwitchChild),
        ],
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _IconPillButton({required this.icon, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.bg,
            border: Border.all(color: context.colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 18, color: context.colors.textSecondary),
              if (count > 0)
                Positioned(
                  top: 3,
                  right: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.danger,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: context.colors.heroBg, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─── Stats row (attendance / rank / fees / discipline) — all real data ───
class _StatsRow extends StatelessWidget {
  final AttendanceSummary attendance;
  final PerformanceSummary performance;
  final FeesData? fees;
  final DisciplineSummary discipline;
  final VoidCallback onTapFees;

  const _StatsRow({
    required this.attendance,
    required this.performance,
    required this.fees,
    required this.discipline,
    required this.onTapFees,
  });

  @override
  Widget build(BuildContext context) {
    final attendanceValue = attendance.hasData ? '${attendance.percent.round()}%' : '—';
    final attendanceSub = attendance.hasData
        ? '${attendance.presentCount}/${attendance.markedDays} recent days'
        : 'No attendance recorded yet';

    final rankValue = performance.rank != null ? '${_ordinal(performance.rank!)}' : '—';
    final rankSub = performance.rank != null
        ? 'of ${performance.classSize} · Avg ${performance.overallAverage!.round()}%'
        : 'No marks entered yet';

    final feeBalance = fees?.balance ?? 0;
    final feeValue = fees == null ? '—' : formatCurrency(feeBalance);
    final feeSub = fees == null
        ? 'No fee records yet'
        : feeBalance <= 0
            ? 'Fully paid'
            : 'Outstanding balance';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.event_available_rounded,
                iconColor: context.colors.success,
                iconBg: context.colors.successPale,
                label: 'ATTENDANCE',
                value: attendanceValue,
                subtitle: attendanceSub,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.leaderboard_rounded,
                iconColor: context.colors.primaryLight,
                iconBg: context.colors.primaryPale,
                label: 'CLASS RANK',
                value: rankValue,
                subtitle: rankSub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: context.colors.warning,
                iconBg: context.colors.warningPale,
                label: 'FEE BALANCE',
                value: feeValue,
                subtitle: feeSub,
                onTap: onTapFees,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.shield_moon_rounded,
                iconColor: discipline.openCases > 0 ? context.colors.warning : context.colors.success,
                iconBg: discipline.openCases > 0 ? context.colors.warningPale : context.colors.successPale,
                label: 'DISCIPLINE',
                value: '${discipline.openCases}',
                subtitle: discipline.openCases > 0 ? 'Open case(s)' : 'No open cases',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: iconColor),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 16, color: context.colors.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: context.colors.fontMono,
              fontSize: 9,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
              color: context.colors.textMuted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: context.colors.cardBgHover,
        child: card,
      ),
    );
  }
}

/// ─── Quick actions ─────────────────────────────────────────────────────
class _QuickAction {
  final String label;
  final IconData icon;
  const _QuickAction(this.label, this.icon);
}

const _quickActions = [
  _QuickAction('Grades', Icons.grade_rounded),
  _QuickAction('Attendance', Icons.event_available_rounded),
  _QuickAction('Homework', Icons.menu_book_rounded),
  _QuickAction('Fees', Icons.account_balance_wallet_rounded),
  _QuickAction('Messages', Icons.chat_bubble_outline_rounded),
  _QuickAction('Discipline', Icons.shield_moon_rounded),
  _QuickAction('Calendar', Icons.event_note_rounded),
  _QuickAction('Announcements', Icons.campaign_outlined),
];

class _QuickActionsGrid extends StatelessWidget {
  final ValueChanged<String> onAction;
  final Stream<int> messagesBadgeStream;
  const _QuickActionsGrid({required this.onAction, required this.messagesBadgeStream});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.02,
      children: _quickActions.map((a) {
        // Only the Messages tile carries a count, so only it pays for a stream.
        if (a.label != 'Messages') {
          return _QuickActionTile(
            label: a.label,
            icon: a.icon,
            onTap: () => onAction(a.label),
          );
        }
        return StreamBuilder<int>(
          stream: messagesBadgeStream,
          initialData: 0,
          builder: (context, snap) => _QuickActionTile(
            label: a.label,
            icon: a.icon,
            badgeCount: snap.data ?? 0,
            onTap: () => onAction(a.label),
          ),
        );
      }).toList(),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: context.colors.cardBgHover,
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: context.colors.primaryPale, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 17, color: context.colors.primaryLight),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -5,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.danger,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: context.colors.cardBg, width: 1.5),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.colors.textPrimary),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─── Shared section header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: context.colors.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.colors.primaryLight),
              ),
            ),
        ],
      ),
    );
  }
}

/// ─── Shared empty-state row (mirrors the web dashboards' empty-state
/// convention: a short explanation instead of blank/fake content) ────────
class _EmptyRow extends StatelessWidget {
  final String message;
  const _EmptyRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Text(
        message,
        style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

Widget _cardWrap(BuildContext context, {required List<Widget> children}) {
  return Container(
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.border),
    ),
    child: Column(children: children),
  );
}

/// ─── Recent grades ─────────────────────────────────────────────────────
Color _gradeColor(AppColors c, String grade) {
  if (grade.startsWith('A')) return c.success;
  if (grade.startsWith('B')) return c.primaryLight;
  if (grade.startsWith('C')) return c.warning;
  return c.danger;
}

Color _gradeColorPale(AppColors c, String grade) {
  if (grade.startsWith('A')) return c.successPale;
  if (grade.startsWith('B')) return c.primaryPale;
  if (grade.startsWith('C')) return c.warningPale;
  return c.dangerPale;
}

class _RecentGradesCard extends StatelessWidget {
  final PerformanceSummary performance;
  const _RecentGradesCard({required this.performance});

  @override
  Widget build(BuildContext context) {
    final grades = performance.subjectGrades;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recent Grades'),
        _cardWrap(context,
          children: performance.loadError.isNotEmpty
              ? [_EmptyRow(message: 'Grades couldn\'t be loaded right now. ${performance.loadError}')]
              : performance.withheld
              ? [
                  _EmptyRow(
                    message: performance.withheldMessage.isNotEmpty
                        ? performance.withheldMessage
                        : 'Results are held until fees are cleared.',
                  ),
                ]
              : grades.isEmpty
              ? const [_EmptyRow(message: 'No marks entered for this term yet.')]
              : [
                  for (int i = 0; i < grades.length; i++) ...[
                    _GradeRow(grade: grades[i]),
                    if (i != grades.length - 1)
                      Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
                  ],
                ],
        ),
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  final SubjectGrade grade;
  const _GradeRow({required this.grade});

  @override
  Widget build(BuildContext context) {
    final letter = letterGrade(grade.score);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              grade.subject,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: context.colors.textPrimary),
            ),
          ),
          Text('${grade.score.round()}%', style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary)),
          const SizedBox(width: 10),
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: _gradeColorPale(context.colors, letter), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _gradeColor(context.colors, letter)),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Upcoming (homework & deadlines) ──────────────────────────────────
class _DueStyle {
  final Color color;
  final Color bg;
  final String label;
  const _DueStyle(this.color, this.bg, this.label);
}

Map<TaskDueStatus, _DueStyle> _dueStyles(AppColors c) => {
      TaskDueStatus.overdue: _DueStyle(c.danger, c.dangerPale, 'OVERDUE'),
      TaskDueStatus.soon: _DueStyle(c.warning, c.warningPale, 'DUE SOON'),
      TaskDueStatus.upcoming: _DueStyle(c.textSecondary, c.bg, 'UPCOMING'),
    };

class _UpcomingList extends StatelessWidget {
  final List<HomeworkTask> tasks;
  const _UpcomingList({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Upcoming'),
        _cardWrap(context,
          children: tasks.isEmpty
              ? const [_EmptyRow(message: 'Nothing due — no homework assigned yet.')]
              : [
                  for (int i = 0; i < tasks.length; i++) ...[
                    _TaskRow(task: tasks[i]),
                    if (i != tasks.length - 1)
                      Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
                  ],
                ],
        ),
      ],
    );
  }
}

String _formatDue(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = due.difference(today).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days < 0) return 'Overdue by ${-days} day${-days == 1 ? '' : 's'}';
  return 'Due in $days days';
}

class _TaskRow extends StatelessWidget {
  final HomeworkTask task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final style = _dueStyles(context.colors)[task.status]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: context.colors.textPrimary)),
                const SizedBox(height: 2),
                Text('${task.subject} · ${_formatDue(task.dueDate)}',
                    style: TextStyle(fontSize: 11.5, color: context.colors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(7)),
            child: Text(
              style.label,
              style: TextStyle(
                fontFamily: context.colors.fontMono,
                fontSize: 8.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: style.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Announcements ──────────────────────────────────────────────────────
class _AnnouncementsCard extends StatelessWidget {
  final List<AnnouncementItem> items;
  const _AnnouncementsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Announcements'),
        _cardWrap(context,
          children: items.isEmpty
              ? const [_EmptyRow(message: 'No announcements yet.')]
              : [
                  for (int i = 0; i < items.length; i++) ...[
                    _AnnouncementRow(item: items[i]),
                    if (i != items.length - 1)
                      Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
                  ],
                ],
        ),
      ],
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  final AnnouncementItem item;
  const _AnnouncementRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: SizedBox(width: 7, height: 7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? '(Untitled)' : item.title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                ),
                if (item.message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: context.colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_relativeTime(item.postedAt), style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
        ],
      ),
    );
  }
}

/// ─── Skeleton loaders (Facebook/LinkedIn-style, no spinners) ─────────────
class _Shimmer extends StatelessWidget {
  final Animation<double> controller;
  final double width;
  final double height;
  final double radius;

  const _Shimmer({
    required this.controller,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.lerp(context.colors.border, context.colors.cardBgHover, controller.value),
            borderRadius: BorderRadius.circular(radius),
          ),
        );
      },
    );
  }
}

class _StatsRowSkeleton extends StatelessWidget {
  final Animation<double> shimmer;
  const _StatsRowSkeleton({required this.shimmer});

  Widget _card(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Shimmer(controller: shimmer, width: 32, height: 32, radius: 9),
            const SizedBox(height: 12),
            _Shimmer(controller: shimmer, width: 60, height: 8, radius: 4),
            const SizedBox(height: 8),
            _Shimmer(controller: shimmer, width: 70, height: 16, radius: 4),
            const SizedBox(height: 6),
            _Shimmer(controller: shimmer, width: 90, height: 10, radius: 4),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [Expanded(child: _card(context)), const SizedBox(width: 12), Expanded(child: _card(context))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _card(context)), const SizedBox(width: 12), Expanded(child: _card(context))]),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final Animation<double> shimmer;
  final int rows;
  final String title;

  const _SkeletonCard({required this.shimmer, required this.rows, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Shimmer(controller: shimmer, width: 140, height: 11, radius: 4),
                            const SizedBox(height: 6),
                            _Shimmer(controller: shimmer, width: 90, height: 9, radius: 4),
                          ],
                        ),
                      ),
                      _Shimmer(controller: shimmer, width: 34, height: 18, radius: 7),
                    ],
                  ),
                ),
                if (i != rows - 1) Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// ─── Footer ────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '© 2026 SSP-PEP · Ministry of Education, Malawi',
            style: TextStyle(
              fontFamily: context.colors.fontMono,
              fontSize: 9,
              letterSpacing: 0.5,
              color: context.colors.textMuted.withOpacity(0.8),
            ),
          ),
          Text(
            'v1.4.1',
            style: TextStyle(
              fontFamily: context.colors.fontMono,
              fontSize: 9,
              letterSpacing: 0.5,
              color: context.colors.textMuted.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/student.dart';
import '../state/session_provider.dart';
import '../theme/app_colors.dart';
import 'home_shell.dart';

class StudentSelectScreen extends StatefulWidget {
  const StudentSelectScreen({super.key});

  @override
  State<StudentSelectScreen> createState() => _StudentSelectScreenState();
}

class _StudentSelectScreenState extends State<StudentSelectScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Asks for the guardian's existing password, then hands it to the server.
  ///
  /// Nothing about the child is shown beyond the name and school the enrolment
  /// SMS already carried — if this landed on the wrong number, the holder
  /// should learn nothing new from it.
  Future<void> _confirm(BuildContext context, Student student) async {
    final session = context.read<SessionProvider>();
    final controller = TextEditingController();
    String? error;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> submit() async {
            final result =
                await session.confirmPending(student, controller.text);
            if (result == null) {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
            } else {
              setSheetState(() => error = result);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: sheetContext.colors.modalBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetContext.colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Is ${student.fullName} your child?',
                    style: TextStyle(
                      fontFamily: sheetContext.colors.fontDisplay,
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      color: sheetContext.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${student.schoolName} added them to your account. Enter '
                    'your ACALink password to confirm — the same one you '
                    'already use. You will not be given a new password.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: sheetContext.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: 'Your password',
                      filled: true,
                      fillColor: sheetContext.colors.inputBg,
                      errorText: error,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: sheetContext.colors.inputBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you were not expecting this, do not confirm — contact '
                    '${student.schoolName}.',
                    style: TextStyle(
                      fontSize: 12,
                      color: sheetContext.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(false),
                          child: const Text('Not mine'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: session.loading ? null : submit,
                          child: session.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Confirm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${student.fullName} added to your account.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final all = session.students;
    final filtered = _query.isEmpty
        ? all
        : all.where((s) {
            final q = _query.toLowerCase();
            return s.fullName.toLowerCase().contains(q) ||
                s.className.toLowerCase().contains(q) ||
                s.schoolName.toLowerCase().contains(q) ||
                s.campusName.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                totalStudents: all.length,
                searchCtrl: _searchCtrl,
                onSearchChanged: (v) => setState(() => _query = v),
                onLogout: () => session.logout(),
                showSearch: all.length > 4,
              ),
            ),
            // Anything a school has attached but the guardian has not confirmed
            // sits above the grid, not inside it. It is not a child they can
            // open yet, and mixing the two would invite tapping one expecting
            // records and getting a password prompt instead.
            if (session.pending.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    children: [
                      for (final p in session.pending)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PendingCard(
                            student: p,
                            onConfirm: () => _confirm(context, p),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (all.isEmpty && session.pending.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else if (filtered.isEmpty && all.isNotEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _NoResultsState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.crossAxisExtent > 520;
                    return SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: wide ? 2 : 1,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: wide ? 3.1 : 3.6,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final Student s = filtered[i];
                          return _StudentCard(
                            student: s,
                            onTap: () async {
                              await session.selectStudent(s);
                              if (context.mounted) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                      builder: (_) => const HomeShell()),
                                );
                              }
                            },
                          );
                        },
                        childCount: filtered.length,
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: _Footer()),
          ],
        ),
      ),
    );
  }
}

/// ─── Hero header, matching .overview-hero + .search-wrap ────────────────
class _Hero extends StatelessWidget {
  final int totalStudents;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onLogout;
  final bool showSearch;

  const _Hero({
    required this.totalStudents,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onLogout,
    required this.showSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        color: context.colors.heroBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 16, height: 1, color: context.colors.warning),
                        const SizedBox(width: 8),
                        Text(
                          'ACALink',
                          style: TextStyle(
                            fontFamily: context.colors.fontMono,
                            fontSize: 9,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose a child',
                      style: TextStyle(
                        fontFamily: context.colors.fontDisplay,
                        fontSize: 28,
                        letterSpacing: 0.3,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalStudents == 0
                          ? 'No students linked to this account yet'
                          : 'Select a student profile to continue',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _LogoutPill(onTap: onLogout),
            ],
          ),
          if (showSearch) ...[
            const SizedBox(height: 20),
            _SearchField(controller: searchCtrl, onChanged: onSearchChanged),
          ],
        ],
      ),
    );
  }
}

class _LogoutPill extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.colors.bg,
            border: Border.all(color: context.colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 15, color: context.colors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Sign out',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13.5, color: context.colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Search by name, class, or school',
          hintStyle: TextStyle(fontSize: 13.5, color: context.colors.textMuted),
          prefixIcon: Icon(Icons.search, size: 18, color: context.colors.textMuted),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// ─── Student card, matching .module-card in light mode ──────────────────
class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback onTap;
  const _StudentCard({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = student.fullName.isNotEmpty ? student.fullName[0] : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        hoverColor: context.colors.cardBgHover,
        splashColor: context.colors.primaryPale,
        child: Ink(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [context.colors.navyStart, context.colors.navyEnd],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial.toUpperCase(),
                  style: TextStyle(
                    fontFamily: context.colors.fontDisplay,
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // The campus is named only when the school records one,
                      // which is only when it runs more than one site. A
                      // guardian with children at the town and rural campuses
                      // of the same school otherwise sees two identical cards.
                      student.campusName.isEmpty
                          ? '${student.className} · ${student.schoolName}'
                          : '${student.className} · ${student.campusName}',
                      style: TextStyle(
                        fontFamily: context.colors.fontMono,
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: context.colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: context.colors.primaryPale,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: context.colors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─── Empty / no-results states ───────────────────────────────────────────
/// A child a school has attached to this number but which is not yet confirmed.
///
/// Deliberately shows the name and the school and nothing else. If a clerk
/// mistyped a digit this card is sitting in a stranger's app, and the stranger
/// should be able to learn no more from it than the enrolment SMS already told
/// them.
class _PendingCard extends StatelessWidget {
  final Student student;
  final VoidCallback onConfirm;

  const _PendingCard({required this.student, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.warningPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1_outlined, size: 22, color: c.warningDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${student.schoolName} added this child. Confirm to see '
                  'their records.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: c.warningDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Confirm', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.colors.primaryPale,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.person_off_outlined,
                  color: context.colors.primaryLight, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'No students linked yet',
              style: TextStyle(
                fontFamily: context.colors.fontDisplay,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Ask the school to link a student to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.colors.warningPale,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.search_off, color: context.colors.warning, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'No matches',
              style: TextStyle(
                fontFamily: context.colors.fontDisplay,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different name, class, or school.',
              style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─── Footer, matching .dashboard-footer ──────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
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
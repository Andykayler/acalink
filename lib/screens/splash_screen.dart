import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import '../widgets/acalink_loader.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'student_select_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// The logo animation needs a moment to play. Restoring a session is often
  /// near-instant, and without this the loader would flash by and read as a
  /// glitch instead of a brand moment. Long enough to see the cap assemble;
  /// never held longer than that — a slow start is not made slower.
  // On the web the page's own loader has already played the intro, so there is
  // little left to wait for.
  static final _minimumShow = Duration(milliseconds: kIsWeb ? 500 : 1900);

  bool _shownLongEnough = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_minimumShow, () {
      if (mounted) setState(() => _shownLongEnough = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SessionProvider>().restoreSession();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        final loading = session.status == SessionStatus.unknown || !_shownLongEnough;

        final Widget page;
        if (loading) {
          page = const AcalinkLoader(key: ValueKey('loader'), skipIntro: kIsWeb);
        } else {
          switch (session.status) {
            case SessionStatus.ready:
              page = const HomeShell(key: ValueKey('home'));
            case SessionStatus.needsStudentPick:
              page = const StudentSelectScreen(key: ValueKey('pick'));
            case SessionStatus.loggedOut:
            case SessionStatus.unknown:
              page = const LoginScreen(key: ValueKey('login'));
          }
        }

        // The loader dissolves into the app rather than cutting to it.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 550),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: page,
        );
      },
    );
  }
}

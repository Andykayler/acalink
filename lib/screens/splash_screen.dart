import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'student_select_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SessionProvider>().restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        switch (session.status) {
          case SessionStatus.ready:
            return const HomeShell();
          case SessionStatus.needsStudentPick:
            return const StudentSelectScreen();
          case SessionStatus.loggedOut:
            return const LoginScreen();
          case SessionStatus.unknown:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }
}
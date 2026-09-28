import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import '../state/theme_provider.dart';
import '../theme/app_colors.dart';
import 'home_shell.dart';
import 'student_select_screen.dart';

/// Parent sign-in — mirrors the web portal's dark-navy "Staff Portal" look
/// (`src/pages/signin.jsx` / `signin.css`): gradient hero background, a
/// wordmark badge, an icon-prefixed field card, a gradient accent submit
/// button, and a sun/moon theme toggle in the same top-right spot.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<SessionProvider>();
    final ok = await session.login(
      _phoneController.text,
      _passwordController.text,
    );

    if (!mounted || !ok) return;

    final next = session.status == SessionStatus.ready
        ? const HomeShell()
        : const StudentSelectScreen();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.heroGradient,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 6,
                right: 12,
                child: _ThemeToggleButton(
                  isDark: context.watch<ThemeProvider>().mode == ThemeMode.dark,
                  onTap: () => context.read<ThemeProvider>().toggle(),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
                  child: _EntranceFade(
                    child: Consumer<SessionProvider>(
                      builder: (context, session, _) => _LoginCard(
                        formKey: _formKey,
                        phoneController: _phoneController,
                        passwordController: _passwordController,
                        obscure: _obscure,
                        onToggleObscure: () => setState(() => _obscure = !_obscure),
                        loading: session.loading,
                        error: session.error,
                        onSubmit: _submit,
                      ),
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

/// Simple fade + rise entrance, run once on first build.
class _EntranceFade extends StatefulWidget {
  final Widget child;
  const _EntranceFade({required this.child});

  @override
  State<_EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<_EntranceFade> {
  double _t = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _t = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _t,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: Offset(0, (1 - _t) * 0.04),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _ThemeToggleButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cardBg,
            border: Border.all(color: c.border),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              key: ValueKey(isDark),
              size: 19,
              color: c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  const _LoginCard({
    required this.formKey,
    required this.phoneController,
    required this.passwordController,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Wordmark badge, matching web's .form-badge ──
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 22, height: 1.5, color: c.warning),
                const SizedBox(width: 9),
                Text(
                  'ACALINK',
                  style: TextStyle(
                    fontFamily: c.fontMono,
                    fontSize: 11,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(width: 9),
                Container(width: 22, height: 1.5, color: c.warning),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Parent Portal',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: c.fontDisplay,
              fontSize: 40,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One password covers all your children, at every school on ACALink.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),

          // ── Field card ──
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLabel('Guardian phone number', c),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(fontSize: 13.5, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: '099 xxx xxxx or +265...',
                      prefixIcon: Icon(Icons.phone_outlined, size: 19, color: c.textMuted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null,
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel('Password', c),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscure,
                    style: TextStyle(fontSize: 13.5, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Sent to you via SMS when your child enrolled',
                      prefixIcon: Icon(Icons.lock_outline, size: 19, color: c.textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 18,
                          color: c.textMuted,
                        ),
                        onPressed: onToggleObscure,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),

                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _ErrorAlert(message: error!, c: c),
                          ),
                  ),

                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.primary, c.primaryLight],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: c.primary.withValues(alpha: 0.38),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: loading ? null : onSubmit,
                          child: Center(
                            child: loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 12, color: c.textMuted),
              const SizedBox(width: 6),
              Text(
                'Encrypted · School-verified accounts only',
                style: TextStyle(fontSize: 11, color: c.textMuted, letterSpacing: 0.2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final AppColors c;
  const _FieldLabel(this.text, this.c);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: c.fontMono,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: c.textMuted,
      ),
    );
  }
}

class _ErrorAlert extends StatelessWidget {
  final String message;
  final AppColors c;
  const _ErrorAlert({required this.message, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.dangerPale,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: c.danger, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

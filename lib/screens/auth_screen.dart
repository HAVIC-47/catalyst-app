// Sign in / sign up — same Supabase auth (email + password) as the web, so the
// same account works in both places.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signup = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty || (_signup && password.length < 8)) {
      setState(() => _error = _signup
          ? 'Enter your email and a password of at least 8 characters.'
          : 'Enter your email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_signup) {
        final res = await auth.signUp(email: email, password: password);
        // If email confirmation is on, there's no session yet.
        if (res.session == null && mounted) {
          setState(() => _notice = 'Account created. Check your email to confirm, then log in.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(children: [
              Text('Catalyst', style: displayStyle(p, 24)),
              const SizedBox(width: 8),
              Label('৳ BD', color: p.accentA(0.94)),
              const Spacer(),
              HairlineIconButton(
                icon: theme.dark ? LucideIcons.sun : LucideIcons.moon,
                tooltip: theme.dark ? 'Switch to light mode' : 'Switch to dark mode',
                onPressed: theme.toggle,
              ),
            ]),
            const SizedBox(height: 36),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: p.inkA(0.1)),
                  color: p.inkA(0.03),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.sparkles, size: 13, color: p.accent),
                  const SizedBox(width: 8),
                  Text('MOOD × MONEY', style: bodyStyle(p, 11.5, weight: FontWeight.w500, color: p.accent).copyWith(letterSpacing: 2.6)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Money meets\n'),
                TextSpan(text: 'mood.', style: accentItalic(p, 46, alpha: 0.95)),
              ]),
              style: displayStyle(p, 46),
            ),
            const SizedBox(height: 14),
            Text(
              'Catalyst maps every taka against how you actually felt that day. Spot the days they collide.',
              style: bodyStyle(p, 15, color: p.muted(0.55), height: 1.5),
            ),
            const SizedBox(height: 28),
            CardBox(
              padding: const EdgeInsets.all(22),
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_signup ? 'Create account' : 'Welcome back', style: displayStyle(p, 28, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_signup ? 'Start mapping your money against your mood.' : 'Log in to your dashboard.',
                      style: bodyStyle(p, 14, color: p.muted(0.5))),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'you@email.com',
                      prefixIcon: Icon(LucideIcons.mail, size: 16, color: p.muted(0.35)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: _signup ? 'Create a password (min 8)' : 'Password',
                      prefixIcon: Icon(LucideIcons.lock, size: 16, color: p.muted(0.35)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _Banner(text: _error!, color: p.expense),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    _Banner(text: _notice!, color: p.saving),
                  ],
                  const SizedBox(height: 14),
                  PrimaryButton(expand: true, height: 48, busy: _loading, label: _signup ? 'Sign up' : 'Log in', onPressed: _submit),
                  const SizedBox(height: 18),
                  Divider(color: p.line, height: 1),
                  const SizedBox(height: 14),
                  Text(_signup ? 'Already have an account?' : 'No account yet?',
                      textAlign: TextAlign.center, style: bodyStyle(p, 12.5, color: p.muted(0.45))),
                  const SizedBox(height: 10),
                  HairlineButton(
                    height: 46,
                    borderColor: p.inkA(0.15),
                    onPressed: () => setState(() {
                      _signup = !_signup;
                      _error = null;
                      _notice = null;
                    }),
                    child: Text(_signup ? 'Log in instead' : 'Create account', style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.muted(0.9))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: bodyStyle(p, 12.5, color: color)),
    );
  }
}

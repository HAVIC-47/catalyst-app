// Sign in / sign up — same Supabase auth (email + password) as the web, so the
// same account works in both places. Also "Forgot password?" (the email's link
// opens the app, which then asks for a new password — NewPasswordScreen) and,
// once Google is set up in Supabase, "Continue with Google". Both come back
// into the app through com.havic47.catalyst://login-callback.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../util/i18n.dart';
import '../widgets/ui.dart';

enum _Mode { login, signup, forgot }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.login;
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

  void _switch(_Mode m) => setState(() {
        _mode = m;
        _error = null;
        _notice = null;
      });

  Future<void> _run(Future<void> Function(GoTrueClient auth) fn) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await fn(Supabase.instance.client.auth);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('Something went wrong. Check your connection and try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (_mode == _Mode.forgot) {
      if (email.isEmpty) {
        setState(() => _error = tr('Enter the email you signed up with.'));
        return;
      }
      await _run((auth) async {
        await auth.resetPasswordForEmail(email, redirectTo: authRedirect);
        if (mounted) setState(() => _notice = tr('If that email has an account, a reset link is on its way. Open it on this phone.'));
      });
      return;
    }
    final signup = _mode == _Mode.signup;
    if (email.isEmpty || password.isEmpty || (signup && password.length < 8)) {
      setState(() => _error = signup ? tr('Enter your email and a password of at least 8 characters.') : tr('Enter your email and password.'));
      return;
    }
    await _run((auth) async {
      if (signup) {
        final res = await auth.signUp(email: email, password: password);
        // If email confirmation is on, there's no session yet.
        if (res.session == null && mounted) setState(() => _notice = tr('Account created. Check your email to confirm, then log in.'));
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    });
  }

  Future<void> _google() => _run((auth) async {
        await auth.signInWithOAuth(OAuthProvider.google, redirectTo: authRedirect, authScreenLaunchMode: LaunchMode.externalApplication);
      });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = context.watch<ThemeController>();
    final app = context.watch<AppState>();
    final title = switch (_mode) {
      _Mode.login => tr('Welcome back'),
      _Mode.signup => tr('Create account'),
      _Mode.forgot => tr('Reset password'),
    };
    final sub = switch (_mode) {
      _Mode.login => tr('Log in to your dashboard.'),
      _Mode.signup => tr('Start mapping your money against your mood.'),
      _Mode.forgot => tr("We'll email you a link to set a new one."),
    };
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(children: [
              const BrandLogo(size: 30),
              const SizedBox(width: 10),
              Text(tr('Catalyst'), style: displayStyle(p, 24)),
              const SizedBox(width: 8),
              Label(tr('৳ BD'), color: p.accentA(0.94)),
              const Spacer(),
              HairlineButton(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: () => app.setLang(app.lang == 'bn' ? 'en' : 'bn'),
                child: Text(app.lang == 'bn' ? tr('English') : 'বাংলা', style: bodyStyle(p, 13, color: p.muted(0.7))),
              ),
              const SizedBox(width: 8),
              HairlineIconButton(
                icon: theme.dark ? LucideIcons.sun : LucideIcons.moon,
                tooltip: theme.dark ? tr('Switch to light mode') : tr('Switch to dark mode'),
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
                  Text(tr('MOOD × MONEY'), style: bodyStyle(p, 11.5, weight: FontWeight.w500, color: p.accent).copyWith(letterSpacing: isBangla ? 0 : 2.6)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${tr('Money meets')}\n'),
                TextSpan(text: tr('mood.'), style: accentItalic(p, 46, alpha: 0.95)),
              ]),
              style: displayStyle(p, 46),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Catalyst maps every taka against how you actually felt that day. Spot the days they collide.'),
              style: bodyStyle(p, 15, color: p.muted(0.55), height: 1.5),
            ),
            const SizedBox(height: 28),
            CardBox(
              padding: const EdgeInsets.all(22),
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: displayStyle(p, 28, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(sub, style: bodyStyle(p, 14, color: p.muted(0.5))),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: _mode == _Mode.forgot ? TextInputAction.send : TextInputAction.next,
                    onSubmitted: _mode == _Mode.forgot ? (_) => _submit() : null,
                    decoration: InputDecoration(
                      hintText: tr('you@email.com'),
                      prefixIcon: Icon(LucideIcons.mail, size: 16, color: p.muted(0.35)),
                    ),
                  ),
                  if (_mode != _Mode.forgot) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [_mode == _Mode.signup ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: _mode == _Mode.signup ? tr('Create a password (min 8)') : tr('Password'),
                        prefixIcon: Icon(LucideIcons.lock, size: 16, color: p.muted(0.35)),
                      ),
                    ),
                  ],
                  if (_mode == _Mode.login)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _switch(_Mode.forgot),
                        child: Text(tr('Forgot password?'), style: bodyStyle(p, 12.5, color: p.muted(0.55))),
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
                  PrimaryButton(
                    expand: true,
                    height: 48,
                    busy: _loading,
                    label: switch (_mode) {
                      _Mode.login => tr('Log in'),
                      _Mode.signup => tr('Sign up'),
                      _Mode.forgot => tr('Send reset link'),
                    },
                    onPressed: _submit,
                  ),
                  if (googleSignIn && _mode != _Mode.forgot) ...[
                    const SizedBox(height: 10),
                    HairlineButton(
                      height: 48,
                      borderColor: p.inkA(0.15),
                      onPressed: _loading ? null : _google,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('G', style: bodyStyle(p, 16, weight: FontWeight.w700, color: p.muted(0.8))),
                        const SizedBox(width: 10),
                        Text(tr('Continue with Google'), style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.muted(0.9))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Divider(color: p.line, height: 1),
                  const SizedBox(height: 14),
                  if (_mode == _Mode.forgot)
                    HairlineButton(
                      height: 46,
                      borderColor: p.inkA(0.15),
                      onPressed: () => _switch(_Mode.login),
                      child: Text(tr('Back to log in'), style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.muted(0.9))),
                    )
                  else ...[
                    Text(_mode == _Mode.signup ? tr('Already have an account?') : tr('No account yet?'),
                        textAlign: TextAlign.center, style: bodyStyle(p, 12.5, color: p.muted(0.45))),
                    const SizedBox(height: 10),
                    HairlineButton(
                      height: 46,
                      borderColor: p.inkA(0.15),
                      onPressed: () => _switch(_mode == _Mode.signup ? _Mode.login : _Mode.signup),
                      child: Text(_mode == _Mode.signup ? tr('Log in instead') : tr('Create account'),
                          style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.muted(0.9))),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// After a reset link: the account is signed in for this one step — set the new password.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = tr('Use at least 8 characters.'));
      return;
    }
    if (_password.text != _again.text) {
      setState(() => _error = tr("The two passwords don't match."));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password changed.'))));
      widget.onDone();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('Something went wrong. Check your connection and try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
          children: [
            Text.rich(
              TextSpan(children: [TextSpan(text: '${tr('New')} '), TextSpan(text: tr('password.'), style: accentItalic(p, 42))]),
              style: displayStyle(p, 42),
            ),
            const SizedBox(height: 10),
            Text(tr('Choose a new password for your Catalyst account.'), style: bodyStyle(p, 14.5, color: p.muted(0.55))),
            const SizedBox(height: 24),
            CardBox(
              padding: const EdgeInsets.all(22),
              radius: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(hintText: tr('New password (min 8)'), prefixIcon: Icon(LucideIcons.lock, size: 16, color: p.muted(0.35))),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _again,
                  obscureText: true,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(hintText: tr('Type it again'), prefixIcon: Icon(LucideIcons.lock, size: 16, color: p.muted(0.35))),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _Banner(text: _error!, color: p.expense),
                ],
                const SizedBox(height: 14),
                PrimaryButton(expand: true, height: 48, busy: _busy, label: tr('Save password'), onPressed: _save),
                const SizedBox(height: 6),
                TextButton(onPressed: _busy ? null : widget.onDone, child: Text(tr('Skip for now'), style: bodyStyle(p, 13, color: p.muted(0.5)))),
              ]),
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

// Catalyst — mood × money. Android app for the Catalyst web app: same Supabase
// project (accounts and data are shared), same screens and design.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_state.dart';
import 'data/remember.dart';
import 'data/secure_session_storage.dart';
import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'services/notifications.dart';
import 'services/widget_sync.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/theme_controller.dart';
import 'util/i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  if (isConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage(supabaseUrl)),
    );
    // "Remember me" was off and the app has been closed a while: log in again.
    await RememberMe.forgetIfExpired();
  }
  final theme = await ThemeController.load();
  // The language chosen last on this phone, until the account's loads.
  await setAppLang((await SharedPreferences.getInstance()).getString('lang'));
  await Notifications.init();
  HomeWidget.init();
  if (testSemantics) SemanticsBinding.instance.ensureSemantics();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const CatalystApp(),
    ),
  );
}

/// The bundled fonts are SIL OFL — list them on the licenses page.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Newsreader', 'HankenGrotesk', 'IBMPlexMono']) {
      final text = await rootBundle.loadString('assets/fonts/licenses/$f-OFL.txt');
      yield LicenseEntryWithLineBreaks([f], text);
    }
  });
}

class CatalystApp extends StatelessWidget {
  const CatalystApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final lang = context.select<AppState, String>((a) => a.lang);
    return MaterialApp(
      title: 'Catalyst',
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Palette.light),
      darkTheme: buildTheme(Palette.night),
      themeMode: theme.mode,
      home: isConfigured ? const AuthGate() : const _NotConfigured(),
    );
  }
}

/// Shows the app when signed in, the auth screen otherwise — and, right after a
/// password-reset link, the screen that sets the new password.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recovering = false;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snap) {
        if (snap.data?.event == AuthChangeEvent.passwordRecovery && !_recovering) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _recovering = true);
          });
        }
        final session = auth.currentSession;
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.read<AppState>().reset();
            Notifications.clear();
            HomeWidget.signedOut();
          });
          return const AuthScreen();
        }
        if (_recovering) return NewPasswordScreen(onDone: () => setState(() => _recovering = false));
        return const AppShell();
      },
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This build has no Supabase settings.\nBuild it with build_apk.ps1 (reads env.json).',
            textAlign: TextAlign.center,
            style: bodyStyle(p, 15, color: p.muted(0.6), height: 1.5),
          ),
        ),
      ),
    );
  }
}

// Catalyst — mood × money. Android app for the Catalyst web app: same Supabase
// project (accounts and data are shared), same screens and design.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  if (isConfigured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  final theme = await ThemeController.load();
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
    return MaterialApp(
      title: 'Catalyst',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Palette.light),
      darkTheme: buildTheme(Palette.night),
      themeMode: theme.mode,
      home: isConfigured ? const AuthGate() : const _NotConfigured(),
    );
  }
}

/// Shows the app when signed in, the auth screen otherwise.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.read<AppState>().reset();
          });
          return const AuthScreen();
        }
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

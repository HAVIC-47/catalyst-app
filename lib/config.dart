// Supabase project — the SAME one the Catalyst web app uses, so both share data.
// Values are injected at build time (build_apk.ps1 passes env.json via
// --dart-define-from-file). The anon key is public by design; row-level security
// on every table keeps each user's data private.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// The web app, whose /api/scan-memo reads memo photos with Gemini. The Gemini key
/// lives only on that server — the app sends the user's Supabase session token.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://catalyst-hishab.vercel.app');

/// Where Supabase sends people back into the app after a password-reset email or
/// Google sign-in. Add it to Supabase → Authentication → URL Configuration →
/// Redirect URLs.
const authRedirect = 'com.havic47.catalyst://login-callback';

/// "Continue with Google" — turn on once the Google provider is set up in
/// Supabase: add "GOOGLE_SIGN_IN": "on" to env.json (or --dart-define).
const googleSignIn = String.fromEnvironment('GOOGLE_SIGN_IN') == 'on';

/// The Google Play build (build_aab.ps1 passes "STORE": "play"). Google Play
/// updates that one itself, so it never looks for releases on GitHub or
/// downloads an APK — Play doesn't allow an app to update itself any other way.
const playStore = String.fromEnvironment('STORE') == 'play';

/// The app's page on Google Play.
const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.havic47.catalyst';

/// The website's public pages: the Privacy Policy and the Terms.
const siteUrl = 'https://catalyst-hishab.vercel.app';
const privacyUrl = '$siteUrl/privacy';
const termsUrl = '$siteUrl/terms';

/// Test-only: exposes the semantics tree so browser automation can drive the
/// Flutter-web build. Never set for the APK.
const testSemantics = bool.fromEnvironment('TEST_SEMANTICS');

bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

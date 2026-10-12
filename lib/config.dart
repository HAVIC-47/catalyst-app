// Supabase project — the SAME one the Catalyst web app uses, so both share data.
// Values are injected at build time (build_apk.ps1 passes env.json via
// --dart-define-from-file). The anon key is public by design; row-level security
// on every table keeps each user's data private.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Test-only: exposes the semantics tree so browser automation can drive the
/// Flutter-web build. Never set for the APK.
const testSemantics = bool.fromEnvironment('TEST_SEMANTICS');

bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

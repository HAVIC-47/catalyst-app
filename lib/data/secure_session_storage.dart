// Keeps the Supabase session (access + refresh token) in the platform's secure
// store — Android Keystore-backed encryption — instead of plain SharedPreferences,
// so the tokens aren't readable from the app's data files or a device backup.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(String supabaseUrl)
      : _key = 'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  // The key supabase_flutter's default SharedPreferences storage uses, which is
  // where 1.0.0 kept the session.
  final String _key;

  static const _store = FlutterSecureStorage();

  @override
  Future<void> initialize() async {
    // One-time move for installs from 1.0.0: copy the plaintext session into the
    // secure store, then delete the plaintext copy.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_key);
    if (legacy == null) return;
    if (!await _store.containsKey(key: _key)) {
      await _store.write(key: _key, value: legacy);
    }
    await prefs.remove(_key);
  }

  @override
  Future<bool> hasAccessToken() => _store.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _store.read(key: _key);

  @override
  Future<void> removePersistedSession() => _store.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(key: _key, value: persistSessionString);
}

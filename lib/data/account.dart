// Account actions: changing the password (straight with Supabase) and deleting
// the account, which goes through the web app's server — it needs the
// service-role key, which only the server has (POST /api/account/delete with the
// user's own login token).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../util/i18n.dart';

/// Deletes the signed-in account and everything in it. Throws with a message
/// the screen can show.
Future<void> deleteAccount() async {
  final auth = Supabase.instance.client.auth;
  var session = auth.currentSession;
  if (session != null && session.isExpired) session = (await auth.refreshSession()).session;
  if (session == null) throw Exception(tr('Log in again to delete your account.'));
  http.Response res;
  try {
    res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/account/delete'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
          body: jsonEncode({'confirm': 'DELETE'}),
        )
        .timeout(const Duration(seconds: 30));
  } on TimeoutException {
    throw Exception(tr('The server took too long — try again.'));
  } catch (_) {
    throw Exception(tr('No connection — try again.'));
  }
  if (res.statusCode != 200) {
    Object? data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {}
    final msg = data is Map ? data['error'] : null;
    throw Exception(msg is String && msg.isNotEmpty ? msg : tr("Couldn't delete the account — try again."));
  }
}

/// Whether the signed-in account has a password (false for Google-only sign-in).
bool accountHasPassword() {
  final meta = Supabase.instance.client.auth.currentUser?.appMetadata ?? const {};
  final providers = meta['providers'] is List ? [for (final p in meta['providers'] as List) '$p'] : ['${meta['provider'] ?? 'email'}'];
  return providers.contains('email');
}

/// Change the password. The current one is checked first by signing in with it,
/// which also counts as the "recent login" Supabase can require before a password
/// change. Throws with a message the screen can show.
Future<void> changePassword({required String current, required String next}) async {
  final auth = Supabase.instance.client.auth;
  final email = auth.currentUser?.email;
  if (email == null) throw Exception(tr('Log in again to change your password.'));
  try {
    await auth.signInWithPassword(email: email, password: current);
  } on AuthException catch (e) {
    final wrong = e.code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login');
    throw Exception(wrong ? tr('The current password is wrong.') : e.message);
  } catch (_) {
    throw Exception(tr('No connection — try again.'));
  }
  try {
    await auth.updateUser(UserAttributes(password: next));
  } on AuthException catch (e) {
    throw Exception(e.message);
  } catch (_) {
    throw Exception(tr('No connection — try again.'));
  }
}

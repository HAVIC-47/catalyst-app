// Account actions that go through the web app's server: deleting the account
// needs the service-role key, which only the server has (POST /api/account/delete
// with the user's own login token).
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

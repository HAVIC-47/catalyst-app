// "Remember me" — the login screen's checkbox, like the web's. On (the default)
// the app stays signed in. Off, the sign-in lasts only while the app is in use:
// once it has been closed or in the background for a few minutes, it asks to log
// in again. Kept on this phone only.
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline.dart';

class RememberMe {
  static const _key = 'remember';
  static const _awayKey = 'awaySince';

  /// Long enough for a trip to the camera or another app and back; short enough
  /// that a phone left on a table doesn't stay signed in.
  static const grace = Duration(minutes: 5);

  static Future<bool> isOn() async => (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  /// Set at sign-in, from the checkbox.
  static Future<void> set(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
    await prefs.remove(_awayKey);
  }

  /// The app went to the background: start the clock (only with Remember me off).
  static Future<void> away() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) ?? true) return;
    await prefs.setInt(_awayKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Back (or started again): whether the sign-in should be forgotten — Remember
  /// me off and away longer than [grace]. Back in time, the clock stops; too late,
  /// it stays until the next sign-in, so the sign-in is forgotten even if this
  /// start is cut short.
  static Future<bool> expired() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) ?? true) return false;
    final since = prefs.getInt(_awayKey);
    final gone = since != null && DateTime.now().millisecondsSinceEpoch - since > grace.inMilliseconds;
    if (!gone) await prefs.remove(_awayKey);
    return gone;
  }

  /// At start, before anything shows: sign out here (and drop the saved copy of
  /// the data) when the sign-in wasn't to be remembered and the app was closed a
  /// while. The session ends at once; telling the server runs in the background.
  static Future<void> forgetIfExpired() async {
    if (!await expired()) return;
    final auth = Supabase.instance.client.auth;
    final uid = auth.currentUser?.id;
    if (uid == null) return;
    await OfflineCopy.clear(uid);
    unawaited(auth.signOut().catchError((Object _) {}));
  }
}

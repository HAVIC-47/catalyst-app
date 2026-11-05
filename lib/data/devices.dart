// The logins on this account (Settings → Account → Signed-in devices) — the web's
// src/lib/db/devices.ts. Each one is a Supabase session; db/supabase.sql's functions
// read and end them, only ever the caller's own. Signing out of every device needs
// none of this: that's Supabase's own sign-out.
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/i18n.dart';

/// The browser and system a user agent describes: "Chrome · Windows"; '' for neither.
String browserName(String ua) {
  bool has(String re) => RegExp(re).hasMatch(ua);
  final browser = has(r'\bEdg(e|A|iOS)?/')
      ? 'Edge'
      : has(r'\bOPR/|\bOpera\b')
          ? 'Opera'
          : has(r'SamsungBrowser/')
              ? 'Samsung Internet'
              : has(r'\b(Firefox|FxiOS)/')
                  ? 'Firefox'
                  : has(r'\b(Chrome|CriOS)/')
                      ? 'Chrome'
                      : has(r'\bSafari/')
                          ? 'Safari'
                          : '';
  // Only a browser's user agent names one; a server's or an app's (node, Dart) doesn't.
  if (browser.isEmpty) return '';
  final system = has('Windows')
      ? 'Windows'
      : has('Android')
          ? 'Android'
          : has('iPhone')
              ? 'iPhone'
              : has('iPad')
                  ? 'iPad'
                  : has('Macintosh|Mac OS X')
                      ? 'Mac'
                      : has('CrOS')
                          ? 'ChromeOS'
                          : has('Linux')
                              ? 'Linux'
                              : '';
  return system.isEmpty ? browser : '$browser · $system';
}

/// One login.
class DeviceLogin {
  const DeviceLogin({required this.id, required this.name, required this.onPhone, required this.signedInAt, required this.lastSeen, required this.current});

  final String id; // the session
  final String name; // what it calls itself, or what its user agent says; '' when neither tells
  final bool onPhone;
  final DateTime signedInAt;
  final DateTime lastSeen;
  final bool current; // this phone

  /// What the list calls it. A login that never named itself signed in before the
  /// list existed: an older app's user agent says Dart, a browser's says what it is,
  /// and a server's refresh says nothing.
  String get label => name.isNotEmpty ? name : (onPhone ? tr('Android phone') : tr('Unknown device'));

  factory DeviceLogin.fromRow(Map<String, dynamic> r) {
    final own = (r['name'] as String?) ?? '';
    final agent = (r['user_agent'] as String?) ?? '';
    final name = own.isNotEmpty ? own : browserName(agent);
    final android = r['platform'] == 'android' || (own.isEmpty && agent.startsWith('Dart/'));
    DateTime at(String key) => DateTime.tryParse('${r[key]}')?.toLocal() ?? DateTime.now();
    return DeviceLogin(
      id: r['session_id'] as String,
      name: name,
      onPhone: android || RegExp('Android|iPhone|iPad').hasMatch(name),
      signedInAt: at('signed_in_at'),
      lastSeen: at('last_seen'),
      current: r['is_current'] == true,
    );
  }
}

abstract final class Devices {
  static const _channel = MethodChannel('catalyst/widget');

  /// This phone's login was just removed from another device: the login screen says so (once).
  static bool removedHere = false;

  // Tests swap these.
  static Future<List<DeviceLogin>> Function() list = _list;
  static Future<void> Function(String id) remove = _remove;
  static Future<void> Function() touch = _touch;

  static Future<List<DeviceLogin>> _list() async {
    final rows = await Supabase.instance.client.rpc('my_devices') as List;
    return [for (final r in rows) DeviceLogin.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  /// Signs that login out. Its device notices at its next look (AppState.checkSession).
  static Future<void> _remove(String id) async {
    await Supabase.instance.client.rpc('remove_device', params: {'target': id});
  }

  /// This phone says what it is, and that it's open now.
  static Future<void> _touch() async {
    await Supabase.instance.client.rpc('touch_device', params: {'device_name': await _phoneName(), 'device_platform': 'android'});
  }

  /// "Samsung SM-S918B" (MainActivity.kt); '' when it can't tell, and the list says Android phone.
  static Future<String> _phoneName() async {
    try {
      return await _channel.invokeMethod<String>('deviceName') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }
}

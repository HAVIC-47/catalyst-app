// New-version check. Releases are published on GitHub (HAVIC-47/catalyst-app);
// when the latest one is newer than this install, the app shows a banner (and a
// notification once per version). "Update" opens the release's APK in the
// browser, which downloads it — Android then offers to install it over this one.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const releasesRepo = 'HAVIC-47/catalyst-app';
const latestApkUrl = 'https://github.com/$releasesRepo/releases/latest/download/Catalyst.apk';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, required this.page});

  final String version; // "1.4.0"
  final String url; // the APK
  final String page; // the release notes
}

abstract final class Updates {
  /// The newer release, while there is one (and it isn't dismissed).
  static final available = ValueNotifier<UpdateInfo?>(null);

  /// This install's version ("1.3.0"), once read.
  static String current = '';

  static const _checkedKey = 'update:checked';
  static const _dismissedKey = 'update:dismissed';
  static const _notifiedKey = 'update:notified';
  static const _every = Duration(hours: 6);

  /// Fetches the latest release's JSON — tests swap in an answer.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function() fetchLatest = _fetchLatest;

  /// Reads this install's version — tests swap in one.
  @visibleForTesting
  static Future<String> Function() readVersion = () async => (await PackageInfo.fromPlatform()).version;

  /// This install's version (read once).
  static Future<String> version() async => current.isNotEmpty ? current : current = await readVersion();

  /// Look for a newer release (at most every few hours unless [force]). Returns
  /// the update when there is one, and calls [onNew] the first time a version is seen.
  static Future<UpdateInfo?> check({bool force = false, void Function(UpdateInfo)? onNew}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await version();
      final last = prefs.getInt(_checkedKey) ?? 0;
      if (!force && DateTime.now().millisecondsSinceEpoch - last < _every.inMilliseconds) return available.value;
      final json = await fetchLatest();
      if (json == null) return available.value;
      await prefs.setInt(_checkedKey, DateTime.now().millisecondsSinceEpoch);
      final info = parseRelease(json);
      if (info == null || !isNewer(info.version, current)) {
        available.value = null;
        return null;
      }
      if (prefs.getString(_notifiedKey) != info.version) {
        await prefs.setString(_notifiedKey, info.version);
        onNew?.call(info);
      }
      // A dismissed banner stays away for that version (Settings still shows it).
      available.value = prefs.getString(_dismissedKey) == info.version && !force ? null : info;
      return info;
    } catch (e) {
      debugPrint('[catalyst] update check failed: $e');
      return available.value;
    }
  }

  static Future<void> dismiss(UpdateInfo u) async {
    available.value = null;
    (await SharedPreferences.getInstance()).setString(_dismissedKey, u.version);
  }

  /// Open the APK link in the browser (which downloads it).
  static Future<bool> download(UpdateInfo u) => launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);

  static Future<Map<String, dynamic>?> _fetchLatest() async {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : null;
  }

  /// The version and APK of a GitHub release (null if it isn't usable).
  @visibleForTesting
  static UpdateInfo? parseRelease(Map<String, dynamic> j) {
    if (j['draft'] == true || j['prerelease'] == true) return null;
    final tag = '${j['tag_name'] ?? ''}'.trim();
    final version = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(tag)?.group(0);
    if (version == null) return null;
    final assets = (j['assets'] as List? ?? const []).whereType<Map>();
    final apk = assets.where((a) => a['name'] == 'Catalyst.apk').firstOrNull ??
        assets.where((a) => '${a['name']}'.toLowerCase().endsWith('.apk')).firstOrNull;
    return UpdateInfo(
      version: version,
      url: apk?['browser_download_url'] as String? ?? latestApkUrl,
      page: j['html_url'] as String? ?? 'https://github.com/$releasesRepo/releases/latest',
    );
  }

  /// Whether [a] ("1.4.0") is a later version than [b] ("1.3.0").
  static bool isNewer(String a, String b) {
    List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0];
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }
}

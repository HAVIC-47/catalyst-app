// "What's new" after an update: the first launch on a newer version pops up what
// the releases since the last version opened brought (lib/data/features.dart).
// A fresh install has nothing to announce — it only remembers the version.
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/features.dart';
import 'updates.dart';

typedef Install = ({String version, bool updated});

abstract final class WhatsNew {
  static const _seenKey = 'whatsnew:seen';

  /// This install's version, and whether it replaced an older one — tests swap in an answer.
  @visibleForTesting
  static Future<Install> Function() readInstall = _readInstall;

  static Future<Install> _readInstall() async {
    final info = await PackageInfo.fromPlatform();
    final first = info.installTime, last = info.updateTime;
    return (version: info.version, updated: first != null && last != null && last.isAfter(first));
  }

  /// The releases to tell about now, newest first — empty when there's nothing new.
  /// Remembers this version, so each update is announced once.
  static Future<List<Release>> due() async {
    try {
      final install = await readInstall();
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(_seenKey);
      if (seen == install.version) return const [];
      await prefs.setString(_seenKey, install.version);
      // A fresh install (versions before 1.4.0 didn't remember one: an update from
      // them has no "seen" either, but the phone knows it was updated).
      if (seen == null && !install.updated) return const [];
      return [
        for (final r in releases())
          if (!Updates.isNewer(r.version, install.version) && (seen == null || Updates.isNewer(r.version, seen))) r,
      ];
    } catch (e) {
      debugPrint("[catalyst] what's new check failed: $e");
      return const [];
    }
  }
}

/// The notes for [version]: the newest release at or before it (the newest of all
/// when the version isn't known yet). Null when every release is newer.
Release? releaseFor(String version) {
  final all = releases();
  if (version.isEmpty) return all.first;
  for (final r in all) {
    if (!Updates.isNewer(r.version, version)) return r;
  }
  return null;
}

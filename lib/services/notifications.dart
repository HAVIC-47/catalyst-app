// Reminders on the phone — the app's side of the web's reminders (lib/reminders.ts
// there; the same settings, shared through the account). Scheduled locally, so
// they work offline: the evening check-in for the next two weeks (skipping a day
// that already has a mood), the day before a bill or a dhar is due, and one-off
// notices (an app update). Rebuilt whenever the data or the settings change.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/app_state.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';

/// What a notification opens when tapped.
abstract final class NoticeTarget {
  static const mood = 'mood';
  static const bills = 'bills';
  static const dhar = 'dhar';
  static const update = 'update';
}

abstract final class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static String _scheduled = ''; // signature of what's scheduled now

  /// Taps on a notification while the app runs.
  static final taps = StreamController<String>.broadcast();

  /// The notification the app was opened from (read once by the shell).
  static String? launchTarget;

  static const _channelReminders = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Evening check-in, bills and dhar due',
    icon: 'ic_stat_catalyst',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _channelUpdates = AndroidNotificationDetails(
    'updates',
    'App updates',
    channelDescription: 'When a new version of Catalyst is out',
    icon: 'ic_stat_catalyst',
    importance: Importance.low,
    priority: Priority.low,
  );

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> init() async {
    if (_ready || !supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_catalyst')),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) taps.add(r.payload!);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) launchTarget = launch!.notificationResponse?.payload;
      _ready = true;
    } catch (e) {
      debugPrint('[catalyst] notifications unavailable: $e');
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Whether the phone lets the app post notifications (Android 13+ asks).
  static Future<bool> enabled() async => _ready && (await _android?.areNotificationsEnabled() ?? false);

  /// Ask for permission (shows the system prompt once; later it's in Android settings).
  static Future<bool> request() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Open the app's notification settings in Android (after the prompt was refused).
  static Future<void> openSettings() async {
    await _plugin.openAppNotificationSettings();
  }

  /// Show something now (an update notice).
  static Future<void> showNow(int id, String title, String body, String target) async {
    if (!_ready) return;
    try {
      await _plugin.show(id: id, title: title, body: body, payload: target, notificationDetails: const NotificationDetails(android: _channelUpdates));
    } catch (e) {
      debugPrint('[catalyst] could not show a notification: $e');
    }
  }

  // Id ranges: check-ins 1000+, bills 2000+, dhar 3000+.
  static const _days = 14;

  /// Schedule (or clear) the reminders from the current data and settings.
  static Future<void> sync(AppState app) async {
    if (!_ready || app.loading) return;
    final plan = _plan(app, DateTime.now());
    final signature = [appLang, for (final n in plan) '${n.id}|${n.at.millisecondsSinceEpoch}|${n.body}'].join('#');
    if (signature == _scheduled) return;
    _scheduled = signature;
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final n in plan) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          payload: n.target,
          // An absolute moment: the phone's local time is already in [n.at].
          scheduledDate: tz.TZDateTime.from(n.at.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(android: _channelReminders),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      _scheduled = '';
      debugPrint('[catalyst] could not schedule reminders: $e');
    }
  }

  /// Forget everything scheduled (sign-out).
  static Future<void> clear() async {
    _scheduled = '';
    if (_ready) await _plugin.cancelAll();
  }

  /// What to schedule from [now] on.
  @visibleForTesting
  static List<PlannedNotice> plan(AppState app, DateTime now) => _plan(app, now);

  static List<PlannedNotice> _plan(AppState app, DateTime now) {
    final r = app.reminders;
    final out = <PlannedNotice>[];
    final today = DateTime(now.year, now.month, now.day);
    final hm = r.checkinTime.split(':');
    final hour = int.tryParse(hm[0]) ?? 21, minute = int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0;

    if (r.checkin) {
      final loggedToday = app.moods.any((m) => m.loggedOn == toDateKey(today));
      for (var i = 0; i < _days; i++) {
        final at = DateTime(today.year, today.month, today.day + i, hour, minute);
        if (!at.isAfter(now) || (i == 0 && loggedToday)) continue;
        out.add(PlannedNotice(1000 + i, at, tr('How was today?'), tr('Log your mood — it takes a few seconds.'), NoticeTarget.mood));
      }
    }

    // The day before, mid-morning — early enough to sort it out.
    DateTime dayBefore(String key) {
      final d = fromDateKey(key);
      return DateTime(d.year, d.month, d.day - 1, 10);
    }

    if (r.bills) {
      var i = 0;
      for (final b in app.bills.where((b) => !b.isPaid)) {
        final at = dayBefore(b.dueOn);
        if (!at.isAfter(now) || at.difference(now).inDays > 60) continue;
        out.add(PlannedNotice(
          2000 + i++,
          at,
          tr('{name} is due tomorrow', {'name': b.name}),
          tr('{amount} — tap Paid on the Bills page once it\'s done.', {'amount': formatCurrency(b.amount)}),
          NoticeTarget.bills,
        ));
        if (i >= 200) break;
      }
    }

    if (r.dhar) {
      var i = 0;
      for (final d in app.debts.where((d) => d.dueOn != null && debtIsOpen(d, app.debtPayments))) {
        final at = dayBefore(d.dueOn!);
        if (!at.isAfter(now) || at.difference(now).inDays > 60) continue;
        final left = formatCurrency(debtRemaining(d, app.debtPayments));
        out.add(PlannedNotice(
          3000 + i++,
          at,
          d.lent ? tr('{person} owes you {amount}', {'person': d.person, 'amount': left}) : tr('You owe {person} {amount}', {'person': d.person, 'amount': left}),
          tr('Due back tomorrow.'),
          NoticeTarget.dhar,
        ));
        if (i >= 200) break;
      }
    }
    return out;
  }
}

/// One scheduled reminder.
class PlannedNotice {
  const PlannedNotice(this.id, this.at, this.title, this.body, this.target);

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String target;
}

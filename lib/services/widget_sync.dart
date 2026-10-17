// Home-screen widget (android/…/CatalystWidget.kt): today's spending and a quick
// add. The app writes the figures — already in its language and currency — each
// time today's entries change; the widget's + opens the app on a new entry.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/i18n.dart';

abstract final class HomeWidget {
  static const _channel = MethodChannel('catalyst/widget');
  static String _sent = '';

  /// "add" when the widget's + was tapped (while the app runs).
  static final actions = StreamController<String>.broadcast();

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) actions.add(call.arguments as String);
    });
  }

  /// The widget tap that opened the app, if any (read once).
  static Future<String?> launchAction() async {
    try {
      return await _channel.invokeMethod<String>('launchAction');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// What the widget shows for [app]'s entries now.
  @visibleForTesting
  static Map<String, String> figures(AppState app, DateTime now) {
    final today = toDateKey(now);
    final spent = app.transactions.where((t) => t.kind == Kind.expense && t.occurredOn == today).toList();
    final total = spent.fold<double>(0, (s, t) => s + t.amount);
    return {
      'date': today,
      'label': tr('Spent today'),
      'amount': formatCurrency(total),
      'sub': spent.isEmpty
          ? tr('Nothing yet · {date}', {'date': fmt(now, 'MMM d')})
          : '${trn(spent.length, '{n} expense', '{n} expenses')} · ${fmt(now, 'MMM d')}',
      'stale': tr('Open Catalyst to update'),
      'add': tr('New entry'),
    };
  }

  /// Signed out: the widget stops showing the last account's figures.
  static Future<void> signedOut() async {
    _sent = '';
    try {
      await _channel.invokeMethod('update', {
        'date': '',
        'label': tr('Spent today'),
        'amount': '—',
        'sub': tr('Sign in to Catalyst'),
        'stale': tr('Sign in to Catalyst'),
        'add': tr('New entry'),
      });
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Nothing placed, or the widget isn't available.
    }
  }

  /// Send the figures when they've changed.
  static Future<void> sync(AppState app) async {
    if (app.loading) return;
    final data = figures(app, DateTime.now());
    final key = data.values.join('|');
    if (key == _sent) return;
    _sent = key;
    try {
      await _channel.invokeMethod('update', data);
    } on MissingPluginException {
      // Not on Android (tests, web preview).
    } on PlatformException catch (e) {
      _sent = '';
      debugPrint('[catalyst] widget update failed: $e');
    }
  }
}

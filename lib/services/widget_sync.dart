// Home-screen widgets (android/…/Widgets.kt): spent today with a quick add, this
// month, wallets, bills due, and a mood check-in. The app writes every widget's
// figures — already in its language and currency — in one map each time its data
// changes. A widget tap comes back as "add", "open:<section>" or "mood:<1-5>".
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';

abstract final class HomeWidget {
  static const _channel = MethodChannel('catalyst/widget');
  static String _sent = '';

  /// A widget tap while the app runs: "add", "open:<section>" or "mood:<1-5>".
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

  /// What the widgets show for [app]'s data now.
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
      ..._month(app, now),
      ..._wallets(app),
      ..._bills(app),
      ..._mood(app, today),
    };
  }

  /// This month: spent, earned and what's left (earned − spent, like the dashboard).
  static Map<String, String> _month(AppState app, DateTime now) {
    final month = toDateKey(now).substring(0, 7);
    var spent = 0.0, earned = 0.0;
    for (final t in app.transactions) {
      if (!t.occurredOn.startsWith(month)) continue;
      if (t.kind == Kind.expense) spent += t.amount;
      if (t.kind == Kind.income) earned += t.amount;
    }
    final saved = earned - spent;
    return {
      'm_month': month,
      'm_title': fmt(now, 'MMMM yyyy'),
      'm_spent_l': tr('Spent'),
      'm_spent': formatCurrency(spent),
      'm_earned_l': tr('Earned'),
      'm_earned': formatCurrency(earned),
      'm_saved_l': tr('Saved'),
      'm_saved': formatCurrency(saved),
      'm_saved_neg': saved < 0 ? '1' : '0',
    };
  }

  /// Up to four wallets (in their order) and the total of all of them.
  static Map<String, String> _wallets(AppState app) {
    final live = app.walletsReady ? app.wallets.where((w) => !w.archived).toList() : const <Wallet>[];
    final balances = walletBalances(app.wallets, app.transactions, app.transfers, app.debts, app.debtPayments);
    final total = live.fold<double>(0, (s, w) => s + (balances[w.id] ?? 0));
    final out = {
      'w_title': tr('Wallets'),
      'w_total': live.isEmpty ? '' : formatCurrency(total),
      'w_empty': app.walletsReady ? tr('No wallets yet — add one in Catalyst.') : tr('Open Catalyst to see your wallets'),
    };
    for (var i = 0; i < 4; i++) {
      final w = i < live.length ? live[i] : null;
      final balance = w == null ? 0.0 : balances[w.id] ?? 0;
      out['w${i + 1}_name'] = w == null ? '' : tr(w.name);
      out['w${i + 1}_amount'] = w == null ? '' : formatCurrency(balance);
      out['w${i + 1}_neg'] = balance < 0 ? '1' : '0';
    }
    return out;
  }

  /// The next three unpaid bills, earliest first (the widget reds out the overdue ones).
  static Map<String, String> _bills(AppState app) {
    final due = app.bills.where((b) => !b.isPaid).toList()..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    final out = {'b_title': tr('Bills due'), 'b_empty': tr('Nothing due — all paid.')};
    for (var i = 0; i < 3; i++) {
      final b = i < due.length ? due[i] : null;
      out['b${i + 1}_name'] = b?.name ?? '';
      out['b${i + 1}_when'] = b == null ? '' : fmt(fromDateKey(b.dueOn), 'MMM d');
      out['b${i + 1}_amount'] = b == null ? '' : formatCurrency(b.amount);
      out['b${i + 1}_due'] = b?.dueOn ?? '';
    }
    return out;
  }

  /// Today's mood, if logged, and the five faces' names.
  static Map<String, String> _mood(AppState app, String today) {
    final logged = app.moods.where((m) => m.loggedOn == today).toList()..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return {
      'md_date': today,
      'md_title': tr('How was today?'),
      'md_sub': logged.isEmpty ? tr('Not logged yet') : tr('Today: {mood}', {'mood': moodPreset(logged.last.mood).label}),
      'md_new': tr('Not logged yet'),
      for (final m in moodPresets) 'md${m.value}': m.label,
    };
  }

  /// Signed out: the widgets stop showing the last account's figures.
  static Map<String, String> _signedOut() {
    final out = <String, String>{
      'date': '',
      'label': tr('Spent today'),
      'amount': '—',
      'sub': tr('Sign in to Catalyst'),
      'stale': tr('Sign in to Catalyst'),
      'add': tr('New entry'),
      'm_month': '', // not this month: the month widget shows "Sign in" and dashes
      'w_title': tr('Wallets'),
      'w_total': '',
      'w_empty': tr('Sign in to Catalyst'),
      'b_title': tr('Bills due'),
      'b_empty': tr('Sign in to Catalyst'),
      'md_date': '',
      'md_title': tr('How was today?'),
      'md_sub': '',
      'md_new': tr('Sign in to Catalyst'),
    };
    for (var i = 1; i <= 4; i++) {
      out['w${i}_name'] = '';
    }
    for (var i = 1; i <= 3; i++) {
      out['b${i}_name'] = '';
    }
    return out;
  }

  static Future<void> signedOut() async {
    _sent = '';
    try {
      await _channel.invokeMethod('update', _signedOut());
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Nothing placed, or the widgets aren't available.
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

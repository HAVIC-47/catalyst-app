// bKash / Nagad SMS capture — opt-in, on the phone only. With the user's say-so
// (Settings) and Android's READ_SMS permission, the app reads messages from those
// two senders (MainActivity filters by sender before anything reaches Dart),
// turns each confirmation into a suggested entry here on the phone, and shows
// them for review. Nothing is sent anywhere until the user adds an entry — and
// then only that entry, like one typed by hand. The messages themselves never
// leave the phone.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/i18n.dart';

enum SmsAction { received, cashIn, addMoney, payment, sendMoney, cashOut, recharge, bill, toBank }

/// One money message, read.
class SmsTxn {
  const SmsTxn({
    required this.key,
    required this.provider,
    required this.action,
    required this.amount,
    required this.fee,
    required this.party,
    required this.when,
    required this.text,
  });

  final String key; // TrxID (or the message id) — never imported twice
  final String provider; // 'bKash' or 'Nagad'
  final SmsAction action;
  final double amount;
  final double fee;
  final String party; // shop, person (last digits of a number) or agent
  final DateTime when;
  final String text; // the message, for the review screen only

  /// Money that left the wallet as spending.
  bool get isExpense => action == SmsAction.payment || action == SmsAction.sendMoney || action == SmsAction.recharge || action == SmsAction.bill;

  /// Money that came in from someone else.
  bool get isIncome => action == SmsAction.received;

  /// Money moved between the user's own wallets (cash, bank).
  bool get isTransfer => !isExpense && !isIncome;
}

double _num(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;

final _amountRe = RegExp(r'(?:Tk\.?|BDT|৳)\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
final _amountBnRe = RegExp(r'([\d,]+(?:\.\d{1,2})?)\s?টাকা');
final _feeRe = RegExp(r'(?:Fee|Charge|ফি|চার্জ)\s*:?\s*(?:Tk\.?|BDT|৳)?\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
final _trxRe = RegExp(r'(?:Trx\s?ID|Txn\s?ID|Transaction\s?ID|TrxId|ট্রানজেকশন\s?আইডি)\s*:?\s*([A-Za-z0-9]{6,})', caseSensitive: false);
final _dateRe = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2})');
final _fieldRe = RegExp(
  r'(?:Sender|Receiver|Merchant|Biller|Uddokta|Agent|Recipient)\s*:\s*(.+?)(?=\s+(?:Fee|Charge|Ref|Reference|TxnID|TrxID|Balance|Amount|Counter)\b|[.,]\s|$)',
  caseSensitive: false,
);
final _partyRe = RegExp(r'\b(?:from|to)\s+(.+?)(?=\s+(?:successful|is successful|Fee|Ref|Reference|Balance|TrxID|TxnID)\b|\.\s|\.$|$)', caseSensitive: false);

/// A phone number keeps only its last digits; a shop or name stays as written.
String _party(String raw) {
  var s = raw.replaceAll(RegExp(r'\s*\((?:\+?88)?0?1\d{9}\)'), '').trim();
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 10 && RegExp(r'^[\d\s+()-]+$').hasMatch(s)) s = '…${digits.substring(digits.length - 4)}';
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

SmsAction? _action(String t) {
  bool has(String p) => t.contains(p);
  if (has('cash out') || has('cashout') || has('ক্যাশ আউট')) return SmsAction.cashOut;
  if (has('cash in') || has('cashin') || has('ক্যাশ ইন')) return SmsAction.cashIn;
  if (has('add money') || has('added money') || has('অ্যাড মানি')) return SmsAction.addMoney;
  if (has('to bank') || has('bkash to bank') || has('nagad to bank') || has('ব্যাংকে')) return SmsAction.toBank;
  if (has('recharge') || has('top-up') || has('top up') || has('topup') || has('রিচার্জ')) return SmsAction.recharge;
  if ((has('bill') && (has('paid') || has('payment') || has('successful'))) || has('বিল পরিশোধ')) return SmsAction.bill;
  if (has('payment') || has('paid to') || has('merchant') || has('পেমেন্ট')) return SmsAction.payment;
  if (has('send money') || has('sent') || has('সেন্ড মানি') || has('পাঠিয়েছেন')) return SmsAction.sendMoney;
  if (has('received') || has('cashback') || has('পেয়েছেন') || has('ক্যাশব্যাক')) return SmsAction.received;
  return null;
}

/// Read one message; null when it isn't a completed money movement (OTPs,
/// offers, failed payments, balance checks).
SmsTxn? parseSms(String body, {required String address, required DateTime received, required String smsId}) {
  final text = asciiDigits(body).replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = text.toLowerCase();
  if (RegExp(r'\b(otp|verification code|pin|password)\b').hasMatch(lower)) return null;
  if (lower.contains('fail') || lower.contains('unsuccessful') || lower.contains('insufficient') || lower.contains('ব্যর্থ')) return null;

  final action = _action(lower);
  if (action == null) return null;
  final amountMatch = _amountRe.firstMatch(text) ?? _amountBnRe.firstMatch(text);
  final amount = amountMatch == null ? 0.0 : _num(amountMatch.group(1)!);
  if (amount <= 0) return null;
  final trx = _trxRe.firstMatch(text)?.group(1);
  // Without a transaction id it has to say it went through.
  if (trx == null && !RegExp(r'successful|received|সফল|পেয়েছেন').hasMatch(lower)) return null;

  final feeMatch = _feeRe.firstMatch(text);
  final fee = feeMatch == null ? 0.0 : _num(feeMatch.group(1)!);
  final d = _dateRe.firstMatch(text);
  var when = received;
  if (d != null) {
    final parsed = DateTime(int.parse(d.group(3)!), int.parse(d.group(2)!), int.parse(d.group(1)!), int.parse(d.group(4)!), int.parse(d.group(5)!));
    // A date that reads oddly (swapped day/month) falls back to when it arrived.
    if (parsed.difference(received).inDays.abs() <= 3) when = parsed;
  }
  final sender = '$address $lower'.toLowerCase();
  final provider = sender.contains('nagad') ? 'Nagad' : 'bKash';
  final party = _fieldRe.firstMatch(text)?.group(1) ?? _partyRe.firstMatch(text)?.group(1) ?? '';
  return SmsTxn(
    key: trx != null ? '${provider.toLowerCase()}:${trx.toUpperCase()}' : 'sms:$smsId',
    provider: provider,
    action: action,
    amount: amount,
    fee: fee,
    party: _party(party),
    when: when,
    text: body.trim(),
  );
}

/// The note a suggested entry gets ("Payment to Daraz", "Cash out").
String smsNote(SmsTxn s) {
  final who = s.party.isEmpty ? '' : s.party;
  return switch (s.action) {
    SmsAction.payment => who.isEmpty ? tr('{provider} payment', {'provider': s.provider}) : tr('Payment to {who}', {'who': who}),
    SmsAction.sendMoney => who.isEmpty ? tr('Send money') : tr('Send money to {who}', {'who': who}),
    SmsAction.recharge => tr('Mobile recharge'),
    SmsAction.bill => who.isEmpty ? tr('Bill payment') : tr('Bill: {who}', {'who': who}),
    SmsAction.received => who.isEmpty ? tr('Money received') : tr('Received from {who}', {'who': who}),
    SmsAction.cashIn => tr('Cash in'),
    SmsAction.cashOut => tr('Cash out'),
    SmsAction.addMoney => tr('Add money'),
    SmsAction.toBank => tr('To bank'),
  };
}

/// The phone side: permission, the opt-in setting, and what's been handled.
abstract final class SmsCapture {
  static const _channel = MethodChannel('catalyst/sms');
  static const _onKey = 'sms:on';
  static const _sinceKey = 'sms:since';
  static const _seenKey = 'sms:seen';

  /// Reads messages — tests swap in a fake inbox.
  @visibleForTesting
  static Future<List<Map<String, Object?>>> Function(int since) readInbox = _readInbox;

  static Future<bool> isOn() async => (await SharedPreferences.getInstance()).getBool(_onKey) ?? false;

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Turn it on: asks Android for permission; starts from the last week's messages.
  static Future<bool> enable() async {
    final granted = await _channel.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onKey, true);
    if (!prefs.containsKey(_sinceKey)) {
      await prefs.setInt(_sinceKey, DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch);
    }
    return true;
  }

  static Future<void> disable() async => (await SharedPreferences.getInstance()).setBool(_onKey, false);

  /// New suggestions since the last review (nothing when it's off or not allowed).
  static Future<List<SmsTxn>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_onKey) ?? false)) return const [];
    final since = prefs.getInt(_sinceKey) ?? DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
    final List<Map<String, Object?>> rows;
    try {
      rows = await readInbox(since);
    } catch (e) {
      debugPrint('[catalyst] could not read SMS: $e');
      return const [];
    }
    final out = <String, SmsTxn>{};
    for (final r in rows) {
      final s = parseSms(
        '${r['body'] ?? ''}',
        address: '${r['address'] ?? ''}',
        received: DateTime.fromMillisecondsSinceEpoch((r['date'] as num?)?.toInt() ?? 0),
        smsId: '${r['id'] ?? ''}',
      );
      if (s != null && !seen.contains(s.key)) out.putIfAbsent(s.key, () => s);
    }
    return out.values.toList()..sort((a, b) => b.when.compareTo(a.when));
  }

  /// Mark suggestions handled (added or skipped) so they never come back.
  static Future<void> markSeen(Iterable<SmsTxn> items) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = [...?prefs.getStringList(_seenKey), for (final s in items) s.key];
    await prefs.setStringList(_seenKey, seen.length > 600 ? seen.sublist(seen.length - 600) : seen);
    final newest = items.fold<int>(0, (m, s) => s.when.millisecondsSinceEpoch > m ? s.when.millisecondsSinceEpoch : m);
    // Move the window on, keeping a day of overlap (ids keep that from doubling up).
    if (newest > 0) {
      final next = newest - const Duration(days: 1).inMilliseconds;
      if (next > (prefs.getInt(_sinceKey) ?? 0)) await prefs.setInt(_sinceKey, next);
    }
  }

  static Future<List<Map<String, Object?>>> _readInbox(int since) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('read', {'since': since}) ?? const [];
    return [for (final r in rows) r.map((k, v) => MapEntry('$k', v))];
  }
}

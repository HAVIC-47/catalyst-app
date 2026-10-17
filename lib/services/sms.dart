// bKash / Nagad messages -> suggested entries, on the phone only. The app has no
// SMS permission (Play Protect blocks sideloaded apps that ask for one): a message
// reaches it when the user shares it (Messages -> press and hold -> Share ->
// Catalyst) or pastes it in Settings. Each confirmation is turned into a suggested
// entry here and shown for review. Nothing is sent anywhere until the user adds
// an entry — and then only that entry, like one typed by hand. The messages
// themselves never leave the phone.
import 'dart:async';

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
/// offers, failed payments, balance checks). [address] is the sender when known
/// (empty for a shared message); with [messageDate] the message's own date counts
/// even when it's old — a shared or pasted message has no arrival time.
SmsTxn? parseSms(String body, {required String address, required DateTime received, required String smsId, bool messageDate = false}) {
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
    final day = int.parse(d.group(1)!), month = int.parse(d.group(2)!);
    final parsed = DateTime(int.parse(d.group(3)!), month, day, int.parse(d.group(4)!), int.parse(d.group(5)!));
    final real = parsed.month == month && parsed.day == day;
    // A date that reads oddly (swapped day/month) falls back to when it arrived;
    // a shared message keeps its own date unless that's in the future.
    final fits = messageDate ? !parsed.isAfter(received.add(const Duration(days: 1))) : parsed.difference(received).inDays.abs() <= 3;
    if (real && fits) when = parsed;
  }
  // The sender says which wallet it was; without one (a shared message), Nagad
  // writes "TxnID" where bKash writes "TrxID".
  final sender = '$address $lower'.toLowerCase();
  final nagad = sender.contains('nagad') || (address.trim().isEmpty && RegExp(r'\btxn\s?id\b').hasMatch(lower));
  final provider = nagad ? 'Nagad' : 'bKash';
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

/// Every money message in shared or pasted text — one message, or several with a
/// blank line between them. The same transaction twice counts once; newest first.
List<SmsTxn> parseMessages(String text, {required DateTime now}) {
  final all = text.trim();
  if (all.isEmpty) return const [];
  final out = <String, SmsTxn>{};
  void read(String body) {
    final s = parseSms(body, address: '', received: now, smsId: _stableId(body), messageDate: true);
    if (s != null) out.putIfAbsent(s.key, () => s);
  }

  final parts = all.split(RegExp(r'\n\s*\n'));
  if (parts.length > 1) parts.forEach(read);
  if (out.isEmpty) read(all);
  return out.values.toList()..sort((a, b) => b.when.compareTo(a.when));
}

/// The same text gives the same id on every run (FNV-1a), so a message without a
/// transaction id is still recognised the second time it's shared.
String _stableId(String text) {
  var h = 0x811c9dc5;
  for (final c in text.trim().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

/// Messages shared to the app, and which ones were already added or skipped.
abstract final class SmsShare {
  static const _channel = MethodChannel('catalyst/sms');
  static const _seenKey = 'sms:seen';
  static bool _listening = false;
  static String? _waiting; // shared while nothing was listening (signed out)

  /// Text shared while the app is open (Share -> Catalyst) — the shell listens.
  static final shared = StreamController<String>.broadcast();

  /// The text the app was opened with by a share, once; null when it wasn't.
  static Future<String?> launchText() async {
    _listen();
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null) return waiting;
    try {
      return await _channel.invokeMethod<String>('sharedText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final text = call.arguments;
      if (call.method != 'shared' || text is! String) return;
      if (shared.hasListener) {
        shared.add(text);
      } else {
        _waiting = text;
      }
    });
  }

  /// The money messages in [text]: the ones not added or skipped before, and how
  /// many of them were.
  static Future<({List<SmsTxn> fresh, int already})> read(String text, {DateTime? now}) async {
    final seen = ((await SharedPreferences.getInstance()).getStringList(_seenKey) ?? const []).toSet();
    final found = parseMessages(text, now: now ?? DateTime.now());
    final fresh = [for (final s in found) if (!seen.contains(s.key)) s];
    return (fresh: fresh, already: found.length - fresh.length);
  }

  /// Mark suggestions handled (added or skipped) so the same message isn't suggested twice.
  static Future<void> markSeen(Iterable<SmsTxn> items) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = [...?prefs.getStringList(_seenKey), for (final s in items) s.key];
    await prefs.setStringList(_seenKey, seen.length > 600 ? seen.sublist(seen.length - 600) : seen);
  }
}

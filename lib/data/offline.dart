// Offline use. After every load the app keeps a copy of the account's rows on the
// phone (app-private storage, never backed up), so with no connection it still
// opens on everything — this month and every other. Money entries and moods made
// offline get their own ids, wait in an outbox, and are sent in order once the
// phone is back online; a retried send can't add one twice.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A random (v4) UUID, for rows created on the phone.
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Whether [e] means "no connection" (as opposed to the server saying no).
bool isOffline(Object e) {
  if (e is SocketException || e is TimeoutException || e is http.ClientException || e is HandshakeException) return true;
  if (e is AuthRetryableFetchException) return true;
  final s = '$e';
  return const [
    'SocketException',
    'Failed host lookup',
    'Connection refused',
    'Connection reset',
    'Connection closed',
    'Network is unreachable',
    'ClientException',
  ].any(s.contains);
}

/// The saved copy of the account's rows.
abstract final class OfflineCopy {
  /// Where the copy lives — tests point it at a temp folder.
  @visibleForTesting
  static Future<Directory> Function() folder = getApplicationSupportDirectory;

  static Future<File> _file(String userId) async => File('${(await folder()).path}/offline-$userId.json');

  static Future<void> save(String userId, Map<String, List<Map<String, dynamic>>> tables, {required bool walletsReady}) async {
    try {
      final f = await _file(userId);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'savedAt': DateTime.now().toUtc().toIso8601String(), 'walletsReady': walletsReady, 'tables': tables}));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('[catalyst] could not save the offline copy: $e');
    }
  }

  static Future<({DateTime savedAt, bool walletsReady, Map<String, List<Map<String, dynamic>>> tables})?> read(String userId) async {
    try {
      final f = await _file(userId);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final tables = <String, List<Map<String, dynamic>>>{
        for (final e in (j['tables'] as Map<String, dynamic>).entries)
          e.key: [for (final r in e.value as List) Map<String, dynamic>.from(r as Map)],
      };
      return (
        savedAt: DateTime.tryParse('${j['savedAt']}')?.toLocal() ?? DateTime.now(),
        walletsReady: j['walletsReady'] == true,
        tables: tables,
      );
    } catch (e) {
      debugPrint('[catalyst] could not read the offline copy: $e');
      return null;
    }
  }

  /// Sign-out: the copy goes with the session.
  static Future<void> clear(String userId) async {
    try {
      final f = await _file(userId);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// One change waiting to be sent.
class OutboxOp {
  const OutboxOp(this.op, this.id, this.row);

  final String op; // addTxn | editTxn | deleteTxn | addMood
  final String id;
  final Map<String, dynamic> row;

  Map<String, dynamic> toJson() => {'op': op, 'id': id, 'row': row};

  static OutboxOp? fromJson(Object? j) {
    if (j is! Map || j['op'] is! String || j['id'] is! String) return null;
    return OutboxOp(j['op'] as String, j['id'] as String, Map<String, dynamic>.from((j['row'] as Map?) ?? const {}));
  }
}

/// Changes made offline, in order, for one account.
class Outbox {
  Outbox._();

  static final instance = Outbox._();

  String _owner = '';
  final List<OutboxOp> ops = [];
  bool _sending = false;

  /// Sends one change — tests swap in a fake server.
  @visibleForTesting
  static Future<void> Function(OutboxOp op) send = _send;

  String _key(String owner) => 'outbox:$owner';

  /// Read this account's queue (another account's stays where it is).
  Future<void> load(String owner) async {
    if (owner == _owner) return;
    _owner = owner;
    ops.clear();
    final raw = (await SharedPreferences.getInstance()).getString(_key(owner));
    if (raw == null) return;
    try {
      ops.addAll((jsonDecode(raw) as List).map(OutboxOp.fromJson).whereType<OutboxOp>());
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (ops.isEmpty) {
      await prefs.remove(_key(_owner));
    } else {
      await prefs.setString(_key(_owner), jsonEncode([for (final o in ops) o.toJson()]));
    }
  }

  /// Ids of rows that exist only on the phone so far.
  Set<String> get unsentIds => {for (final o in ops) if (o.op == 'addTxn' || o.op == 'addMood') o.id};

  bool hasUnsent(String id) => unsentIds.contains(id);

  Future<void> add(OutboxOp op) async {
    ops.add(op);
    await _save();
  }

  /// An edit: folded into the entry's own unsent add, else queued.
  Future<void> edit(String id, Map<String, dynamic> row) async {
    final i = ops.indexWhere((o) => o.op == 'addTxn' && o.id == id);
    if (i >= 0) {
      ops[i] = OutboxOp('addTxn', id, row);
    } else {
      ops.removeWhere((o) => o.op == 'editTxn' && o.id == id);
      ops.add(OutboxOp('editTxn', id, row));
    }
    await _save();
  }

  /// A delete: an entry that was never sent simply disappears.
  Future<void> delete(String id) async {
    final unsent = ops.any((o) => o.op == 'addTxn' && o.id == id);
    ops.removeWhere((o) => o.id == id);
    if (!unsent) ops.add(OutboxOp('deleteTxn', id, const {}));
    await _save();
  }

  /// Send what's waiting, oldest first. Stops at the first connection problem;
  /// a change the server refuses is dropped and reported through [onRefused].
  /// Returns how many were sent.
  Future<int> flush({void Function(String message)? onRefused}) async {
    if (_sending || ops.isEmpty) return 0;
    _sending = true;
    var sent = 0;
    try {
      while (ops.isNotEmpty) {
        final op = ops.first;
        try {
          await send(op);
          sent++;
        } catch (e) {
          if (isOffline(e)) break;
          onRefused?.call(e is PostgrestException ? e.message : '$e');
        }
        ops.removeAt(0);
        await _save();
      }
    } finally {
      _sending = false;
    }
    return sent;
  }

  /// Forget the queue (sign-out of this account).
  Future<void> clear() async {
    ops.clear();
    await _save();
    _owner = '';
  }

  static Future<void> _send(OutboxOp op) async {
    final db = Supabase.instance.client;
    try {
      switch (op.op) {
        case 'addTxn':
          await db.from('transactions').insert({...op.row, 'id': op.id});
        case 'addMood':
          await db.from('mood_logs').insert({...op.row, 'id': op.id});
        case 'editTxn':
          await db.from('transactions').update(op.row).eq('id', op.id);
        case 'deleteTxn':
          await db.from('transactions').delete().eq('id', op.id);
      }
    } on PostgrestException catch (e) {
      // Already there: an earlier try got through before the connection dropped.
      if (e.code == '23505') return;
      rethrow;
    }
  }
}

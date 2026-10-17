// Photo readers on the web app's server: /api/scan-memo (memos, receipts and
// screenshots of notes) and /api/scan-list (screenshots of to-do and shopping
// lists). Gemini runs there; the app sends the photo with the user's Supabase
// session token, never a key.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../util/i18n.dart';

class ScanError implements Exception {
  const ScanError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The photo's real type, from its first bytes.
String? imageMime(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 12 && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
  if (b.length > 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') return 'image/heic';
  return null;
}

/// Where photos come from and where they're read. Tests swap in answers that
/// need no camera or server.
class Scan {
  /// A photo from the camera or the gallery (screenshots live there); null when cancelled.
  static Future<Uint8List?> Function(ImageSource source) pick = _pick;

  /// POSTs [body] to a reader ([path] like '/api/scan-list') as the signed-in user.
  static Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body) send = _send;
}

final _picker = ImagePicker();

Future<Uint8List?> _pick(ImageSource source) async {
  XFile? file;
  try {
    // The readers only need ~1600px; this keeps the upload small.
    file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  } on PlatformException {
    throw ScanError(source == ImageSource.camera ? tr('Couldn\'t open the camera — choose a photo instead.') : tr('Couldn\'t open your photos.'));
  }
  return file?.readAsBytes();
}

Future<Map<String, dynamic>> _send(String path, Map<String, dynamic> body) async {
  final auth = Supabase.instance.client.auth;
  var session = auth.currentSession;
  if (session != null && session.isExpired) session = (await auth.refreshSession()).session;
  if (session == null) throw ScanError(tr('Log in again to scan photos.'));

  final http.Response res;
  try {
    res = await http
        .post(
          Uri.parse('$apiBaseUrl$path'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 75));
  } on TimeoutException {
    throw ScanError(tr('The reader took too long — try again.'));
  }
  Map<String, dynamic>? data;
  try {
    data = jsonDecode(res.body) as Map<String, dynamic>?;
  } catch (_) {
    data = null;
  }
  if (res.statusCode != 200 || data == null) {
    throw ScanError(data?['error'] as String? ?? tr('The reader couldn\'t process this photo.'));
  }
  return data;
}

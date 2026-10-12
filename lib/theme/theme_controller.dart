import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark by default (like the web); light when the user picks it. Persisted.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._dark);

  final SharedPreferences _prefs;
  bool _dark;

  bool get dark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemeController._(prefs, prefs.getString('theme') != 'light');
  }

  void toggle() {
    _dark = !_dark;
    _prefs.setString('theme', _dark ? 'dark' : 'light');
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart' as shared_preferences;

/// Persists the parent's dark/light choice, mirroring the web portal's
/// `src/utils/theme.js` (a plain two-way toggle, no "system" option, dark by
/// default). Load [load] once before first paint; [toggle] flips and saves.
class ThemeProvider extends ChangeNotifier {
  static const _kThemeKey = 'acalink_theme_mode';

  ThemeMode mode = ThemeMode.dark;

  Future<void> load() async {
    final prefs = await shared_preferences.SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeKey);
    if (saved == 'light') mode = ThemeMode.light;
    if (saved == 'dark') mode = ThemeMode.dark;
    notifyListeners();
  }

  Future<void> toggle() async {
    mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await shared_preferences.SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

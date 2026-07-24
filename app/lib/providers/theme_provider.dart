import 'package:flutter/material.dart';

/// Theme mode: system (default), light or dark. Not persisted between launches.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void setMode(ThemeMode m) {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
  }

  /// System -> light -> dark -> system.
  void cycle() {
    _mode = ThemeMode.values[(_mode.index + 1) % ThemeMode.values.length];
    notifyListeners();
  }

  IconData get icon => switch (_mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      };

  String get label => switch (_mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

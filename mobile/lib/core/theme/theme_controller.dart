import "package:flutter/material.dart";
import "../services/session_service.dart";

class ThemeController extends ChangeNotifier {
  static ThemeController? _instance;
  final SessionService sessionService;
  late ThemeMode _themeMode;

  ThemeController._(this.sessionService) {
    _themeMode = sessionService.themeMode;
  }

  static ThemeController init(SessionService sessionService) {
    _instance = ThemeController._(sessionService);
    return _instance!;
  }

  static ThemeController get instance {
    if (_instance == null) {
      throw StateError("ThemeController has not been initialized. Call init() first.");
    }
    return _instance!;
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await sessionService.setThemeMode(_themeMode);
  }
}

import "package:flutter/material.dart";
import "../services/session_service.dart";

class ThemeController extends ChangeNotifier {
  static ThemeController? _instance;
  final SessionService sessionService;
  ThemeController._(this.sessionService);

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

  ThemeMode get themeMode => ThemeMode.light;
  bool get isDarkMode => false;

  Future<void> toggleTheme() async {
    notifyListeners();
    await sessionService.setThemeMode(ThemeMode.light);
  }
}

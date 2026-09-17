import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Dynamic Accessibility Typography Scale
enum AccessibilityTextScale {
  normal,
  large,
  extraLarge,
}

/// Service managing Child Safety, DSWD Compliance & Universal Accessibility
/// for elementary and lower-grade learners (Grades 1-6).
class ChildSafetyService extends ChangeNotifier {
  static const String keyJuniorMode = "child_safety_junior_mode";
  static const String keyGradeLevel = "child_safety_grade_level";
  static const String keyTextScale = "accessibility_text_scale";
  static const String keyDyslexiaFont = "accessibility_dyslexia_font";
  static const String keyReadAloud = "accessibility_read_aloud";
  static const String keyEyeBreakMinutes = "wellness_eye_break_minutes";
  static const String keyKidSafeAi = "safety_kid_safe_ai_filter";

  static ChildSafetyService? _instance;
  final SharedPreferences? _prefs;

  bool _isJuniorMode = false;
  int _gradeLevel = 3; // Grade 1 to 6
  AccessibilityTextScale _textScale = AccessibilityTextScale.normal;
  bool _dyslexiaFriendlyFont = false;
  bool _readAloudEnabled = true;
  int _eyeBreakMinutes = 20; // 20-20-20 screen rule per DSWD PES
  bool _kidSafeAiFilter = true;
  DateTime _lastEyeBreakTime = DateTime.now();

  ChildSafetyService._([this._prefs]) {
    _loadFromPrefs();
  }

  static Future<ChildSafetyService> init([SharedPreferences? prefs]) async {
    final effectivePrefs = prefs ?? await SharedPreferences.getInstance();
    _instance = ChildSafetyService._(effectivePrefs);
    return _instance!;
  }

  static ChildSafetyService get instance {
    return _instance ??= ChildSafetyService._(null);
  }

  void _loadFromPrefs() {
    if (_prefs == null) return;
    _isJuniorMode = _prefs!.getBool(keyJuniorMode) ?? false;
    _gradeLevel = _prefs!.getInt(keyGradeLevel) ?? 3;
    final scaleStr = _prefs!.getString(keyTextScale) ?? "normal";
    _textScale = AccessibilityTextScale.values.firstWhere(
      (e) => e.name == scaleStr,
      orElse: () => AccessibilityTextScale.normal,
    );
    _dyslexiaFriendlyFont = _prefs!.getBool(keyDyslexiaFont) ?? false;
    _readAloudEnabled = _prefs!.getBool(keyReadAloud) ?? true;
    _eyeBreakMinutes = _prefs!.getInt(keyEyeBreakMinutes) ?? 20;
    _kidSafeAiFilter = _prefs!.getBool(keyKidSafeAi) ?? true;
    _lastEyeBreakTime = DateTime.now();
  }

  // Getters
  bool get isJuniorMode => _isJuniorMode;
  int get gradeLevel => _gradeLevel;
  String get gradeLevelText => "Grade $_gradeLevel";
  AccessibilityTextScale get textScale => _textScale;
  double get textScaleFactor {
    switch (_textScale) {
      case AccessibilityTextScale.normal:
        return 1.0;
      case AccessibilityTextScale.large:
        return 1.2;
      case AccessibilityTextScale.extraLarge:
        return 1.35;
    }
  }
  bool get dyslexiaFriendlyFont => _dyslexiaFriendlyFont;
  bool get useDyslexicFont => _dyslexiaFriendlyFont;
  bool get readAloudEnabled => _readAloudEnabled;
  int get eyeBreakMinutes => _eyeBreakMinutes;
  bool get kidSafeAiFilter => _kidSafeAiFilter;

  // Eye Break Timers
  int get minutesSinceLastBreak => DateTime.now().difference(_lastEyeBreakTime).inMinutes;
  bool get shouldPromptEyeBreak {
    if (_eyeBreakMinutes <= 0) return false;
    return minutesSinceLastBreak >= _eyeBreakMinutes;
  }
  void resetEyeBreakTimer() {
    _lastEyeBreakTime = DateTime.now();
    notifyListeners();
  }

  // Actions
  Future<void> setJuniorMode(bool value) async {
    _isJuniorMode = value;
    if (value && _textScale == AccessibilityTextScale.normal) {
      _textScale = AccessibilityTextScale.large; // Automatically scale for readability
      await _prefs?.setString(keyTextScale, _textScale.name);
    }
    await _prefs?.setBool(keyJuniorMode, value);
    notifyListeners();
  }

  Future<void> toggleJuniorMode() async {
    await setJuniorMode(!_isJuniorMode);
  }

  Future<void> setGradeLevel(dynamic level) async {
    if (level is int) {
      _gradeLevel = level.clamp(1, 6);
    } else if (level is String) {
      final parsed = int.tryParse(RegExp(r'\d+').firstMatch(level)?.group(0) ?? '');
      _gradeLevel = parsed != null ? parsed.clamp(1, 6) : 3;
    }
    await _prefs?.setInt(keyGradeLevel, _gradeLevel);
    notifyListeners();
  }

  Future<void> setTextScale(AccessibilityTextScale scale) async {
    _textScale = scale;
    await _prefs?.setString(keyTextScale, scale.name);
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double scale) async {
    if (scale >= 1.3) {
      _textScale = AccessibilityTextScale.extraLarge;
    } else if (scale >= 1.15) {
      _textScale = AccessibilityTextScale.large;
    } else {
      _textScale = AccessibilityTextScale.normal;
    }
    await _prefs?.setString(keyTextScale, _textScale.name);
    notifyListeners();
  }

  Future<void> toggleDyslexiaFont() async {
    _dyslexiaFriendlyFont = !_dyslexiaFriendlyFont;
    await _prefs?.setBool(keyDyslexiaFont, _dyslexiaFriendlyFont);
    notifyListeners();
  }

  Future<void> setReadAloudEnabled(bool value) async {
    _readAloudEnabled = value;
    await _prefs?.setBool(keyReadAloud, value);
    notifyListeners();
  }

  Future<void> toggleReadAloud() async {
    await setReadAloudEnabled(!_readAloudEnabled);
  }

  Future<void> setEyeBreakMinutes(int minutes) async {
    _eyeBreakMinutes = minutes;
    await _prefs?.setInt(keyEyeBreakMinutes, minutes);
    resetEyeBreakTimer();
    notifyListeners();
  }

  Future<void> toggleKidSafeAiFilter() async {
    _kidSafeAiFilter = !_kidSafeAiFilter;
    await _prefs?.setBool(keyKidSafeAi, _kidSafeAiFilter);
    notifyListeners();
  }

  /// Child-Friendly label mapping for main app tabs
  String getFriendlyTabName(int index, String standardName) {
    if (!_isJuniorMode) return standardName;
    switch (index) {
      case 0:
        return "My Subjects 📚";
      case 1:
        return "Cards 🃏";
      case 2:
        return "Notes 📝";
      case 3:
        return "Studio 🎨";
      case 4:
        return "Buddy AI 🤖";
      default:
        return standardName;
    }
  }

  /// Enriches student prompt with DSWD child-safe elementary pedagogical calibration
  String enrichPromptForChildSafety(String rawPrompt) {
    if (!_isJuniorMode) return rawPrompt;
    return "[DSWD Child Protection / Grade $_gradeLevel Learner Mode]\n"
        "Please respond in simple, child-friendly terms suitable for a Grade $_gradeLevel student. "
        "Use positive encouragement, simple analogies, and gentle explanations without complex jargon.\n\n"
        "$rawPrompt";
  }

  /// Growth mindset non-punitive feedback
  String getEncouragingFeedback({required bool isCorrect, String? topic}) {
    if (isCorrect) {
      final praises = [
        "🌟 Super Job! You nailed this!",
        "🎉 Hooray! You're learning so fast!",
        "✨ Brilliant thinking! Keep shining!",
        "🚀 Awesome work! You understand this well!",
        "🏆 Champion answer! Great effort!"
      ];
      return praises[DateTime.now().millisecond % praises.length];
    } else {
      final gentleNudges = [
        "🌱 Good try! Every mistake helps your brain grow!",
        "💡 Making mistakes is how we learn! Check the answer below:",
        "⭐ Keep going! You're getting better every time!",
        "🌈 Great effort! Take your time to review:",
        "🎈 You're doing well! Here's how to remember it:"
      ];
      return gentleNudges[DateTime.now().millisecond % gentleNudges.length];
    }
  }
}

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class SessionService {
  static const String _keyToken = "jwt_token";
  static const String _keyUserId = "user_id";
  static const String _keyEmail = "user_email";
  static const String _keyFullName = "user_full_name";
  static const String _keyBaseUrl = "api_base_url";
  static const String _keyLastSync = "last_sync_timestamp";
  static const String _keyThemeMode = "app_theme_mode";
  static const String _keyGeminiApiKey = "gemini_api_key";
  static const String _keyOnboardingCompleted = "onboarding_completed";
  static const String _keySchoolLevel = "student_school_level";
  static const String _keyGradingScale = "student_grading_scale";
  static const String _keyMinorConsent = "student_minor_consent";
  static const String _keySampleDataLoaded = "is_sample_data_loaded";

  final SharedPreferences _prefs;

  SessionService(this._prefs);

  static Future<SessionService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionService(prefs);
  }

  SharedPreferences get prefs => _prefs;
  String? get token => _prefs.getString(_keyToken);
  String? get userId => _prefs.getString(_keyUserId);
  String? get email => _prefs.getString(_keyEmail);
  String? get fullName => _prefs.getString(_keyFullName);
  String? get baseUrl {
    // Release builds strictly enforce the configured/production HTTPS endpoint with no local override
    if (kReleaseMode) return null;
    return _prefs.getString(_keyBaseUrl);
  }
  String? get geminiApiKey => _prefs.getString(_keyGeminiApiKey);

  bool get isOnboardingCompleted => _prefs.getBool(_keyOnboardingCompleted) ?? false;
  String get schoolLevel => _prefs.getString(_keySchoolLevel) ?? "College";
  String get gradingScale => _prefs.getString(_keyGradingScale) ?? "USJ-R (1.00 - 5.00)";
  bool get hasMinorConsent => _prefs.getBool(_keyMinorConsent) ?? false;
  bool get isSampleDataLoaded => _prefs.getBool(_keySampleDataLoaded) ?? false;

  Future<void> setOnboardingCompleted({
    required String schoolLevel,
    required String gradingScale,
    bool hasMinorConsent = false,
  }) async {
    await _prefs.setBool(_keyOnboardingCompleted, true);
    await _prefs.setString(_keySchoolLevel, schoolLevel);
    await _prefs.setString(_keyGradingScale, gradingScale);
    await _prefs.setBool(_keyMinorConsent, hasMinorConsent);
  }

  Future<void> setSchoolLevel(String level) async {
    await _prefs.setString(_keySchoolLevel, level);
  }

  Future<void> setGradingScale(String scale) async {
    await _prefs.setString(_keyGradingScale, scale);
  }

  Future<void> setSampleDataLoaded(bool loaded) async {
    await _prefs.setBool(_keySampleDataLoaded, loaded);
  }

  Future<void> setGeminiApiKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await _prefs.remove(_keyGeminiApiKey);
    } else {
      await _prefs.setString(_keyGeminiApiKey, key.trim());
    }
  }

  DateTime? get lastSyncAt {
    final str = _prefs.getString(_keyLastSync);
    return str != null ? DateTime.tryParse(str) : null;
  }

  ThemeMode get themeMode {
    final mode = _prefs.getString(_keyThemeMode);
    if (mode == "light") return ThemeMode.light;
    if (mode == "system") return ThemeMode.system;
    return ThemeMode.dark;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final val = mode == ThemeMode.light
        ? "light"
        : mode == ThemeMode.system
            ? "system"
            : "dark";
    await _prefs.setString(_keyThemeMode, val);
  }

  static const String _keyLastActive = "last_active_timestamp";
  static const Duration inactivityTimeout = Duration(hours: 4);

  static const _keepKeys = {_keyThemeMode, _keyBaseUrl};

  Future<void> clearAllUserData() async {
    for (final k in _prefs.getKeys().toList()) {
      if (!_keepKeys.contains(k)) {
        await _prefs.remove(k);
      }
    }
  }

  DateTime? get lastActiveAt {
    final str = _prefs.getString(_keyLastActive);
    return str != null ? DateTime.tryParse(str) : null;
  }

  bool get isSessionExpired {
    final dt = lastActiveAt;
    if (dt == null) return false;
    return DateTime.now().difference(dt) > inactivityTimeout;
  }

  Future<void> recordActivity() async {
    await _prefs.setString(_keyLastActive, DateTime.now().toIso8601String());
  }

  // Side-effect free getter
  bool get isAuthenticated =>
      token != null && token!.isNotEmpty && !isSessionExpired;

  Future<void> expireIfInactive() async {
    if (isSessionExpired) {
      await clearAllUserData();
    }
  }

  bool get hasValidToken => isAuthenticated;

  Future<void> saveAuth({
    required String token,
    required String userId,
    required String email,
    required String fullName,
  }) async {
    final prev = _prefs.getString("last_user_id");
    if (prev != null && prev != userId) {
      await clearAllUserData();
    }
    await _prefs.setString("last_user_id", userId);

    await _prefs.setString(_keyToken, token);
    await _prefs.setString(_keyUserId, userId);
    await _prefs.setString(_keyEmail, email);
    await _prefs.setString(_keyFullName, fullName);
    await recordActivity();
  }

  Future<void> setBaseUrl(String url) async {
    if (kReleaseMode) return;
    await _prefs.setString(_keyBaseUrl, url);
  }

  Future<void> setLastSync(DateTime timestamp) async {
    await _prefs.setString(_keyLastSync, timestamp.toIso8601String());
  }

  Future<void> clear() async => clearAllUserData();
  Future<void> clearSession() async => clearAllUserData();
  Future<void> clearAuth() async => clearAllUserData();
}

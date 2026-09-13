import "dart:convert";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../../core/network/api_client.dart";
import "../models/study_settings_model.dart";

class SettingsService extends ChangeNotifier {
  static const String _storageKey = "user_study_settings_cache";

  final SharedPreferences _prefs;
  final ApiClient? _apiClient;
  StudySettingsModel _settings;

  SettingsService(this._prefs, [this._apiClient])
      : _settings = _loadCachedSettings(_prefs);

  StudySettingsModel get settings => _settings;

  static StudySettingsModel _loadCachedSettings(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return StudySettingsModel.defaultSettings();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return StudySettingsModel.fromJson(map);
    } catch (_) {
      return StudySettingsModel.defaultSettings();
    }
  }

  Future<void> _persistLocal(StudySettingsModel newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _prefs.setString(_storageKey, jsonEncode(newSettings.toJson()));
  }

  Future<StudySettingsModel> fetchRemoteSettings() async {
    if (_apiClient == null) return _settings;
    try {
      final response = await _apiClient.dio.get("/api/v1/settings");
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final remote = StudySettingsModel.fromJson(response.data as Map<String, dynamic>);
        await _persistLocal(remote);
        return remote;
      }
    } catch (_) {
      // Offline fallback: continue with cached local settings
    }
    return _settings;
  }

  Future<StudySettingsModel> saveSettings(StudySettingsModel updated) async {
    await _persistLocal(updated);
    if (_apiClient != null) {
      try {
        final response = await _apiClient.dio.put("/api/v1/settings", data: updated.toJson());
        if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
          final saved = StudySettingsModel.fromJson(response.data as Map<String, dynamic>);
          await _persistLocal(saved);
          return saved;
        }
      } catch (_) {
        // Will sync once connectivity resumes
      }
    }
    return _settings;
  }

  Future<StudySettingsModel> resetSettings() async {
    final baseline = StudySettingsModel.defaultSettings();
    await _persistLocal(baseline);
    if (_apiClient != null) {
      try {
        final response = await _apiClient.dio.post("/api/v1/settings/reset");
        if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
          final reset = StudySettingsModel.fromJson(response.data as Map<String, dynamic>);
          await _persistLocal(reset);
          return reset;
        }
      } catch (_) {
        // Local baseline already saved
      }
    }
    return _settings;
  }
}

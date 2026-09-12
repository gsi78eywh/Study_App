import "package:shared_preferences/shared_preferences.dart";

class SessionService {
  static const String _keyToken = "jwt_token";
  static const String _keyUserId = "user_id";
  static const String _keyEmail = "user_email";
  static const String _keyFullName = "user_full_name";
  static const String _keyBaseUrl = "api_base_url";
  static const String _keyLastSync = "last_sync_timestamp";

  final SharedPreferences _prefs;

  SessionService(this._prefs);

  static Future<SessionService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionService(prefs);
  }

  String? get token => _prefs.getString(_keyToken);
  String? get userId => _prefs.getString(_keyUserId);
  String? get email => _prefs.getString(_keyEmail);
  String? get fullName => _prefs.getString(_keyFullName);
  String? get baseUrl => _prefs.getString(_keyBaseUrl);
  DateTime? get lastSyncAt {
    final str = _prefs.getString(_keyLastSync);
    return str != null ? DateTime.tryParse(str) : null;
  }

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  Future<void> saveAuth({
    required String token,
    required String userId,
    required String email,
    required String fullName,
  }) async {
    await _prefs.setString(_keyToken, token);
    await _prefs.setString(_keyUserId, userId);
    await _prefs.setString(_keyEmail, email);
    await _prefs.setString(_keyFullName, fullName);
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_keyBaseUrl, url);
  }

  Future<void> setLastSync(DateTime timestamp) async {
    await _prefs.setString(_keyLastSync, timestamp.toIso8601String());
  }

  Future<void> clear() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyEmail);
    await _prefs.remove(_keyFullName);
  }
}

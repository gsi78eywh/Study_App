import "package:flutter/foundation.dart";

class ApiConstants {
  // Configurable base URL:
  // For local development: uses the Android emulator loopback when applicable.
  // For production (e.g. Railway): pass via flutter build --dart-define=API_BASE_URL=https://your-api.up.railway.app
  static const String _configuredBaseUrl = String.fromEnvironment("API_BASE_URL");

  static String get defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return "http://localhost:5000";
    return defaultTargetPlatform == TargetPlatform.android
        ? "http://10.0.2.2:5000"
        : "http://localhost:5000";
  }

  // Auth endpoints
  static const String login = "/api/v1/auth/login";
  static const String register = "/api/v1/auth/register";
  static const String me = "/api/v1/auth/me";

  // Ingestion endpoints
  static const String ingestText = "/api/v1/ingestion/text";
  static const String ingestFile = "/api/v1/ingestion/file";
  static const String ingestUrl = "/api/v1/ingestion/url";
  static const String scanContent = "/api/v1/ingestion/scan";
  static const String scanUrl = "/api/v1/ingestion/scan-url";

  // Bi-directional Sync
  static const String sync = "/api/v1/sync";

  // Server-authoritative practice sessions
  static const String practiceSessions = "/api/v1/practice/sessions";
  static String question(String id) => "/api/v1/questions/$id";
  static String studySetQuestions(String studySetId) => "/api/v1/studysets/$studySetId/questions";

  // Courses & Starter Pack
  static const String demoPack = "/api/v1/courses/demo-pack";

  // Backend AI endpoints. The mobile app never calls an AI provider directly.
  static const String aiTutor = "/api/v1/ai/tutor";
  static const String aiExplain = "/api/v1/ai/explain";
  static const String aiStatus = "/api/v1/ai/status";
}

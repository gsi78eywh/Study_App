import "package:flutter/foundation.dart";

class ApiConstants {
  // Preset URLs for different runtime environments
  static const String railwayProductionUrl = "https://studyapp-backend.up.railway.app";
  static const String androidEmulatorUrl = "http://10.0.2.2:5000";
  static const String localWifiUrl = "http://172.23.249.209:5000";
  static const String localhostUrl = "http://localhost:5000";

  // Configurable base URL:
  // For production (e.g. Railway): pass via flutter build --dart-define=API_BASE_URL=https://studyapp-backend.up.railway.app
  static const String _configuredBaseUrl = String.fromEnvironment("API_BASE_URL");

  static String get defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    // In release builds, Android blocks plain http:// by default, so use HTTPS Railway as default
    if (kReleaseMode) return railwayProductionUrl;
    if (kIsWeb) return localhostUrl;
    return defaultTargetPlatform == TargetPlatform.android
        ? androidEmulatorUrl
        : localhostUrl;
  }

  // Auth endpoints
  static const String login = "/api/v1/auth/login";
  static const String register = "/api/v1/auth/register";
  static const String me = "/api/v1/auth/me";
  static const String forgotPassword = "/api/v1/auth/forgot-password";
  static const String resetPassword = "/api/v1/auth/reset-password";
  static const String oauth = "/api/v1/auth/oauth";

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
  static const String aiTutorStatus = "/api/v1/ai/tutor-status";
  static const String aiChatLogs = "/api/v1/ai/chat-logs";
}

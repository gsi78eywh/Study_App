class ApiConstants {
  // Default development baseUrl
  // For Android Emulator: "http://10.0.2.2:5000"
  // For Windows / Web / iOS Simulator: "http://localhost:5000"
  static const String defaultBaseUrl = "http://localhost:5000";
  
  // Auth endpoints
  static const String login = "/api/v1/auth/login";
  static const String register = "/api/v1/auth/register";
  static const String me = "/api/v1/auth/me";

  // Ingestion endpoints
  static const String ingestText = "/api/v1/ingestion/text";
  static const String ingestFile = "/api/v1/ingestion/file";
  static const String ingestUrl = "/api/v1/ingestion/url";

  // Bi-directional Sync
  static const String sync = "/api/v1/sync";

  // Google Gemini AI endpoints
  static const String aiTutor = "/api/v1/ai/tutor";
  static const String aiExplain = "/api/v1/ai/explain";
  static const String aiStatus = "/api/v1/ai/status";
}
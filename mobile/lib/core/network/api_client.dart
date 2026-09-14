import "package:dio/dio.dart";
import "../constants/api_constants.dart";
import "../services/session_service.dart";

class ApiClient {
  final SessionService sessionService;
  late final Dio dio;

  ApiClient(this.sessionService) {
    dio = Dio(
      BaseOptions(
        baseUrl: sessionService.baseUrl ?? ApiConstants.defaultBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 40),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Dynamic baseUrl update if changed in settings
          final currentBase = sessionService.baseUrl ?? ApiConstants.defaultBaseUrl;
          if (options.baseUrl != currentBase) {
            options.baseUrl = currentBase;
          }

          final token = sessionService.token;
          if (token != null && token.isNotEmpty) {
            options.headers["Authorization"] = "Bearer $token";
          }

          final geminiKey = sessionService.geminiApiKey;
          if (geminiKey != null && geminiKey.isNotEmpty) {
            options.headers["X-Gemini-ApiKey"] = geminiKey;
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          String errorMessage = "A network error occurred.";
          if (e.response?.statusCode == 401) {
            errorMessage = "Session expired (401 Unauthorized). Please sign in again.";
          } else if (e.response?.data is Map && (e.response?.data as Map).containsKey("message")) {
            errorMessage = e.response?.data["message"];
          } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
            errorMessage = "Server connection timed out. Please check if the C# backend is running.";
          } else if (e.type == DioExceptionType.connectionError) {
            errorMessage = "Cannot connect to C# backend at ${dio.options.baseUrl}. Ensure it is listening.";
          }
          return handler.next(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: errorMessage,
            ),
          );
        },
      ),
    );
  }

  void updateBaseUrl(String newUrl) {
    dio.options.baseUrl = newUrl;
  }
}

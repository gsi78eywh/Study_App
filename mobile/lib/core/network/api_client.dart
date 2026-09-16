import "package:dio/dio.dart";
import "../constants/api_constants.dart";
import "../services/session_service.dart";
import "../../features/practice/models/adaptive_models.dart";

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

  Future<TodayStudyPlanModel?> getTodayStudyPlan() async {
    try {
      final res = await dio.get("/api/v1/practice/today-plan");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return TodayStudyPlanModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<SmartSessionPayloadModel?> getSmartSession({String? courseId}) async {
    try {
      final res = await dio.get(
        "/api/v1/practice/smart-session",
        queryParameters: courseId != null ? {"courseId": courseId} : null,
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return SmartSessionPayloadModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<List<MistakeBankItemModel>> getMistakeBank({String? courseId}) async {
    try {
      final res = await dio.get(
        "/api/v1/practice/mistake-bank",
        queryParameters: courseId != null ? {"courseId": courseId} : null,
      );
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .map((item) => MistakeBankItemModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> resolveMistake(String questionId, {bool isResolved = true}) async {
    try {
      final res = await dio.post(
        "/api/v1/practice/mistake-bank/resolve",
        data: {"questionId": questionId, "isResolved": isResolved},
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<ExplainableReadinessModel?> getExamReadiness(String courseId) async {
    try {
      final res = await dio.get("/api/v1/practice/exam-readiness/$courseId");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return ExplainableReadinessModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateCourseExam(String courseId, DateTime? examDate, String? examTitle) async {
    try {
      final res = await dio.put(
        "/api/v1/courses/$courseId/exam",
        data: {
          "examDate": examDate?.toIso8601String(),
          "examTitle": examTitle,
        },
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}


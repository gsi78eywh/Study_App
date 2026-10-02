import "package:flutter/foundation.dart";
import "package:dio/dio.dart";
import "../constants/api_constants.dart";
import "../services/session_service.dart";
import "../../features/practice/models/adaptive_models.dart";
import "../../features/courses/models/grade_models.dart";

class ApiClient {
  final SessionService sessionService;
  late final Dio dio;

  ApiClient(this.sessionService) {
    dio = Dio(
      BaseOptions(
        baseUrl: sessionService.baseUrl ?? ApiConstants.defaultBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        // AI synthesis and OCR can legitimately take longer than a normal API
        // call. This must outlive the backend's 90-second AI provider timeout.
        receiveTimeout: const Duration(seconds: 120),
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
        onResponse: (response, handler) {
          sessionService.recordActivity();
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          final isGet = e.requestOptions.method.toUpperCase() == "GET";
          final isRateLimited = e.response?.statusCode == 429;
          final isReceiveTimeout = e.type == DioExceptionType.receiveTimeout;
          final retryCount = (e.requestOptions.extra["retry_count"] as num?)?.toInt() ?? 0;

          // Quick single retry for transient rate limits or receive delays (never duplicate connection errors)
          if ((isReceiveTimeout || isRateLimited) && isGet && retryCount < 1) {
            e.requestOptions.extra["retry_count"] = retryCount + 1;
            final waitMs = isRateLimited ? 1000 : 500;
            await Future.delayed(Duration(milliseconds: waitMs));
            try {
              final retryResponse = await dio.fetch(e.requestOptions);
              return handler.resolve(retryResponse);
            } catch (_) {}
          }

          // Fast candidate host discovery (1.5s health probe instead of blocking 20s fetches)
          if (kDebugMode &&
              isGet &&
              e.type == DioExceptionType.connectionError &&
              defaultTargetPlatform == TargetPlatform.android &&
              e.requestOptions.extra["tried_alternate_host"] != true) {
            e.requestOptions.extra["tried_alternate_host"] = true;
            final currentUrl = dio.options.baseUrl;
            final candidates = [
              "http://127.0.0.1:5000",
              "http://192.168.1.11:5000",
              "http://10.0.2.2:5000",
            ];

            for (final candidate in candidates) {
              if (candidate == currentUrl) continue;
              try {
                final probeDio = Dio(BaseOptions(
                  baseUrl: candidate,
                  connectTimeout: const Duration(milliseconds: 1500),
                  receiveTimeout: const Duration(milliseconds: 1500),
                ));
                final healthResp = await probeDio.get("/health");
                if (healthResp.statusCode == 200) {
                  dio.options.baseUrl = candidate;
                  e.requestOptions.baseUrl = candidate;
                  await sessionService.setBaseUrl(candidate);
                  final fallbackResponse = await dio.fetch(e.requestOptions);
                  return handler.resolve(fallbackResponse);
                }
              } catch (_) {}
            }
            dio.options.baseUrl = currentUrl;
          }

          String errorMessage = "A network error occurred.";
          if (e.response?.statusCode == 401) {
            errorMessage = "Session expired (401 Unauthorized). Please sign in again.";
          } else if (e.response?.data is Map) {
            final map = e.response!.data as Map;
            if (map.containsKey("message") && map["message"] != null && map["message"].toString().trim().isNotEmpty) {
              errorMessage = map["message"].toString().trim();
            } else if (map.containsKey("errors") && map["errors"] is Map) {
              final errMap = map["errors"] as Map;
              final msgs = <String>[];
              for (final val in errMap.values) {
                if (val is List) {
                  msgs.addAll(val.map((item) => item.toString()));
                } else if (val != null) {
                  msgs.add(val.toString());
                }
              }
              if (msgs.isNotEmpty) {
                errorMessage = msgs.join(" ");
              } else if (map.containsKey("title") && map["title"] != null) {
                errorMessage = map["title"].toString().trim();
              }
            } else if (map.containsKey("title") && map["title"] != null && map["title"].toString().trim().isNotEmpty) {
              errorMessage = map["title"].toString().trim();
            } else if (map.containsKey("error") && map["error"] != null && map["error"].toString().trim().isNotEmpty) {
              errorMessage = map["error"].toString().trim();
            }
          } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
            errorMessage = "Server connection timed out. Please check if the C# backend is running.";
          } else if (e.type == DioExceptionType.connectionError) {
            errorMessage = "Cannot connect to C# backend at ${dio.options.baseUrl}. Ensure it is listening.";
          } else if (e.message != null && e.message!.trim().isNotEmpty) {
            errorMessage = e.message!.trim();
          }
          return handler.next(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: errorMessage,
              message: errorMessage,
            ),
          );
        },
      ),
    );
  }

  TodayStudyPlanModel? _cachedTodayStudyPlan;
  GradeSummaryModel? _cachedGradeSummary;

  void updateBaseUrl(String newUrl) {
    dio.options.baseUrl = newUrl;
  }

  void clearCaches() {
    _cachedTodayStudyPlan = null;
    _cachedGradeSummary = null;
  }

  Future<bool> deleteAccount() async {
    try {
      final res = await dio.delete(ApiConstants.deleteAccount);
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkBackendHealth() async {
    try {
      final res = await dio.get(
        "/api/v1/auth/health",
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<TodayStudyPlanModel?> getTodayStudyPlan() async {
    try {
      final res = await dio.get("/api/v1/practice/today-plan");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final plan = TodayStudyPlanModel.fromJson(res.data as Map<String, dynamic>);
        _cachedTodayStudyPlan = plan;
        return plan;
      }
    } catch (_) {
      // Graceful offline degradation: return cached plan on network delay
      if (_cachedTodayStudyPlan != null) {
        return _cachedTodayStudyPlan;
      }
    }
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

  Future<StudentBrainProfileModel?> getStudentBrainProfile() async {
    try {
      final res = await dio.get("/api/v1/practice/student-brain");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return StudentBrainProfileModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<List<AcademicTaskModel>> getAcademicTasks() async {
    try {
      final res = await dio.get("/api/v1/practice/planner/tasks");
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .map((item) => AcademicTaskModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<AcademicTaskModel?> createAcademicTask({
    String? courseId,
    required String title,
    required String type,
    required DateTime dueDate,
    String estimatedDifficulty = "Medium",
    List<String>? actionSteps,
  }) async {
    try {
      final res = await dio.post(
        "/api/v1/practice/planner/tasks",
        data: {
          "courseId": courseId,
          "title": title,
          "type": type,
          "dueDate": dueDate.toIso8601String(),
          "estimatedDifficulty": estimatedDifficulty,
          "actionSteps": actionSteps ?? [],
        },
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return AcademicTaskModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<BreakdownResponseModel?> generateAssignmentBreakdown({
    required String title,
    required String type,
    required DateTime dueDate,
    String? contextNotes,
  }) async {
    try {
      final res = await dio.post(
        "/api/v1/practice/planner/generate-breakdown",
        data: {
          "title": title,
          "type": type,
          "dueDate": dueDate.toIso8601String(),
          "contextNotes": contextNotes,
        },
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return BreakdownResponseModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> toggleAcademicTask(String taskId) async {
    try {
      final res = await dio.put("/api/v1/practice/planner/tasks/$taskId/toggle");
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<RecoveryPlanResponseModel?> buildRecoveryPlan({
    String? studySetId,
    required List<String> missedQuestionIds,
  }) async {
    try {
      final res = await dio.post(
        "/api/v1/practice/recovery-plan",
        data: {
          "studySetId": studySetId,
          "missedQuestionIds": missedQuestionIds,
        },
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return RecoveryPlanResponseModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<GradeSummaryModel?> getGradesSummary() async {
    try {
      final res = await dio.get("/api/v1/grades/summary");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final summary = GradeSummaryModel.fromJson(res.data as Map<String, dynamic>);
        _cachedGradeSummary = summary;
        return summary;
      }
    } catch (_) {
      if (_cachedGradeSummary != null) {
        return _cachedGradeSummary;
      }
    }
    return null;
  }

  Future<bool> updateCourseGrades(String courseId, Map<String, dynamic> data) async {
    try {
      final res = await dio.put("/api/v1/grades/courses/$courseId", data: data);
      if (res.statusCode == 200) {
        _cachedGradeSummary = null;
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<WhatIfResultModel?> calculateWhatIf({
    required String courseId,
    required double targetGwa,
    double? prelimGrade,
    double? midtermGrade,
    double? semiFinalGrade,
    double prelimWeight = 0.20,
    double midtermWeight = 0.20,
    double semiFinalWeight = 0.20,
    double finalWeight = 0.40,
  }) async {
    try {
      final res = await dio.post(
        "/api/v1/grades/calculator/what-if",
        data: {
          "courseId": courseId,
          "targetGwa": targetGwa,
          "prelimGrade": prelimGrade,
          "midtermGrade": midtermGrade,
          "semiFinalGrade": semiFinalGrade,
          "prelimWeight": prelimWeight,
          "midtermWeight": midtermWeight,
          "semiFinalWeight": semiFinalWeight,
          "finalWeight": finalWeight,
        },
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return WhatIfResultModel.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> saveNotebookNote({
    required String courseId,
    required String title,
    required String markdown,
    String? tags,
  }) async {
    try {
      final res = await dio.post(
        "/api/v1/notebooks",
        data: {
          "courseId": courseId,
          "title": title,
          "contentMarkdown": markdown,
          "tags": tags ?? "#Notes",
        },
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> transcriptToNotes({
    String? courseId,
    String? title,
    String? content,
    String? url,
    bool generateFlashcards = true,
  }) async {
    try {
      final validCourseId = (courseId != null &&
              RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                  .hasMatch(courseId.trim()))
          ? courseId.trim()
          : null;
      final res = await dio.post(
        "/api/v1/ingestion/transcript-to-notes",
        data: {
          "courseId": validCourseId,
          "title": title,
          "content": content,
          "url": url,
          "generateFlashcards": generateFlashcards,
        },
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

import "package:dio/dio.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../courses/models/course_models.dart";
import "../../quiz/models/quiz_models.dart";

class SyncResult {
  final bool success;
  final String message;
  final int coursesReceived;
  final int studySetsReceived;
  final int questionsReceived;

  SyncResult({
    required this.success,
    required this.message,
    this.coursesReceived = 0,
    this.studySetsReceived = 0,
    this.questionsReceived = 0,
  });
}

class SyncService {
  final ApiClient apiClient;
  final SessionService sessionService;

  SyncService({required this.apiClient, required this.sessionService});

  Future<SyncResult> performSync({
    List<CourseModel> localCourses = const [],
    List<StudySetModel> localStudySets = const [],
    List<TestSessionSubmission> pendingSessions = const [],
  }) async {
    try {
      final lastSync = sessionService.lastSyncAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final payload = {
        "lastSyncedAt": lastSync.toIso8601String(),
        "courses": localCourses.map((c) => {
          "id": c.id,
          "code": c.code,
          "name": c.name,
          "colorHex": c.colorHex,
          "updatedAt": (c.updatedAt ?? c.createdAt).toIso8601String(),
          "isDeleted": false,
        }).toList(),
        "studySets": localStudySets.map((s) => {
          "id": s.id,
          "courseId": s.courseId,
          "title": s.title,
          "description": s.description ?? "",
          "updatedAt": s.createdAt.toIso8601String(),
          "isDeleted": false,
        }).toList(),
        "questions": [],
        "testSessions": pendingSessions.map((ts) => ts.toJson()).toList(),
      };

      final response = await apiClient.dio.post(ApiConstants.sync, data: payload);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final serverTime = DateTime.tryParse(data["serverTimestamp"] ?? "") ?? DateTime.now();
        await sessionService.setLastSync(serverTime);

        final updatedCourses = (data["updatedCourses"] as List?)?.length ?? 0;
        final updatedSets = (data["updatedStudySets"] as List?)?.length ?? 0;
        final updatedQuestions = (data["updatedQuestions"] as List?)?.length ?? 0;

        return SyncResult(
          success: true,
          message: "Sync complete. Up to date with server.",
          coursesReceived: updatedCourses,
          studySetsReceived: updatedSets,
          questionsReceived: updatedQuestions,
        );
      } else {
        return SyncResult(success: false, message: "Sync returned unexpected status: ${response.statusCode}");
      }
    } on DioException catch (e) {
      return SyncResult(success: false, message: e.error?.toString() ?? e.message ?? "Sync failed.");
    } catch (e) {
      return SyncResult(success: false, message: "Sync error: $e");
    }
  }
}

import "package:dio/dio.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../courses/models/course_models.dart";

class SyncResult {
  final bool success;
  final String message;
  final List<CourseModel> syncedCourses;
  final int coursesReceived;
  final int studySetsReceived;
  final int questionsReceived;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedCourses = const [],
    this.coursesReceived = 0,
    this.studySetsReceived = 0,
    this.questionsReceived = 0,
  });
}

class SyncService {
  final ApiClient apiClient;
  final SessionService sessionService;

  SyncService({required this.apiClient, required this.sessionService});

  Future<SyncResult> performSync({bool fullFetch = false}) async {
    try {
      final lastSync = fullFetch
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : (sessionService.lastSyncAt ??
                DateTime.fromMillisecondsSinceEpoch(0));

      final payload = {
        "lastSyncedAt": lastSync.toIso8601String(),
        // Courses, study sets, questions, and scored sessions are server-owned.
        // Sending cached UI state here previously allowed an older device to
        // overwrite newer server data and allowed client-calculated scores.
        "courses": [],
        "studySets": [],
        "questions": [],
        "testSessions": [],
      };

      final response = await apiClient.dio.post(
        ApiConstants.sync,
        data: payload,
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final serverTime =
            DateTime.tryParse(data["serverTimestamp"] ?? "") ?? DateTime.now();
        await sessionService.setLastSync(serverTime);

        final rawCourses = data["updatedCourses"] as List? ?? [];
        final rawSets = data["updatedStudySets"] as List? ?? [];

        // Build merged course list
        final Map<String, CourseModel> courseMap = {};

        for (final raw in rawCourses) {
          final id = raw["id"]?.toString() ?? "";
          if (id.isEmpty) continue;
          final existing = courseMap[id];
          courseMap[id] = CourseModel(
            id: id,
            code: raw["code"] ?? existing?.code ?? "COURSE",
            name: raw["name"] ?? existing?.name ?? "Untitled Course",
            colorHex: raw["colorHex"] ?? existing?.colorHex ?? "#6366F1",
            createdAt:
                DateTime.tryParse(raw["updatedAt"] ?? "") ??
                existing?.createdAt ??
                DateTime.now(),
            studySets: existing?.studySets ?? [],
          );
        }

        // Attach updated sets
        for (final raw in rawSets) {
          final setId = raw["id"]?.toString() ?? "";
          final courseId = raw["courseId"]?.toString() ?? "";
          if (setId.isEmpty || !courseMap.containsKey(courseId)) continue;

          final targetCourse = courseMap[courseId]!;
          final setList = List<StudySetModel>.from(targetCourse.studySets);
          final existingSetIndex = setList.indexWhere((s) => s.id == setId);

          final newSet = StudySetModel(
            id: setId,
            courseId: courseId,
            title: raw["title"] ?? "Untitled Set",
            description: raw["description"],
            questionCount:
                (raw["questions"] as List?)?.length ??
                (raw["questionCount"] ?? 0),
            createdAt:
                DateTime.tryParse(raw["updatedAt"] ?? "") ?? DateTime.now(),
          );

          if (existingSetIndex >= 0) {
            setList[existingSetIndex] = newSet;
          } else {
            setList.add(newSet);
          }

          courseMap[courseId] = CourseModel(
            id: targetCourse.id,
            code: targetCourse.code,
            name: targetCourse.name,
            colorHex: targetCourse.colorHex,
            createdAt: targetCourse.createdAt,
            studySets: setList,
          );
        }

        return SyncResult(
          success: true,
          message: "Synchronized with server.",
          syncedCourses: courseMap.values.toList(),
          coursesReceived: rawCourses.length,
          studySetsReceived: rawSets.length,
        );
      } else {
        return SyncResult(
          success: false,
          message: "Sync returned unexpected status: ${response.statusCode}",
        );
      }
    } on DioException catch (e) {
      return SyncResult(
        success: false,
        message: e.error?.toString() ?? e.message ?? "Sync failed.",
      );
    } catch (e) {
      return SyncResult(success: false, message: "Sync error: $e");
    }
  }
}

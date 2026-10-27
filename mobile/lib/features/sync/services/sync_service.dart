import "dart:convert";
import "package:dio/dio.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../courses/models/course_models.dart";

class SyncResult {
  final bool success;
  final String message;
  final bool isUnauthorized;
  final List<CourseModel> syncedCourses;
  final int coursesReceived;
  final int studySetsReceived;
  final int questionsReceived;

  SyncResult({
    required this.success,
    required this.message,
    this.isUnauthorized = false,
    this.syncedCourses = const [],
    this.coursesReceived = 0,
    this.studySetsReceived = 0,
    this.questionsReceived = 0,
  });
}

class SyncService {
  final ApiClient apiClient;
  final SessionService sessionService;

  static const String _offlineCoursesKey = "offline_cached_courses_v2";
  static List<CourseModel> _cachedCourses = [];
  static List<CourseModel> get cachedCourses => List.unmodifiable(_cachedCourses);
  static set cachedCourses(List<CourseModel> courses) => _cachedCourses = List.from(courses);

  /// Clears in-memory course cache to prevent cross-session data leakage
  static void clearCache() {
    _cachedCourses = [];
  }

  SyncService({required this.apiClient, required this.sessionService}) {
    _restoreOfflineCache();
  }

  void _restoreOfflineCache() {
    if (_cachedCourses.isNotEmpty) return;
    try {
      final raw = sessionService.prefs.getString(_offlineCoursesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _cachedCourses = decoded
            .map((e) => CourseModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> saveOfflineCache(List<CourseModel> courses) async {
    _cachedCourses = List.from(courses);
    try {
      final jsonStr = jsonEncode(courses.map((c) => c.toJson()).toList());
      await sessionService.prefs.setString(_offlineCoursesKey, jsonStr);
    } catch (_) {}
  }

  bool isDataStale({int staleMinutes = 5}) {
    final lastSync = sessionService.lastSyncAt;
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) >= Duration(minutes: staleMinutes);
  }

  Future<SyncResult?> syncIfStale({
    int staleMinutes = 5,
    List<CourseModel> currentCourses = const [],
  }) async {
    if (!isDataStale(staleMinutes: staleMinutes)) return null;
    return await performSync(fullFetch: false, currentCourses: currentCourses);
  }

  Future<SyncResult> performSync({
    bool fullFetch = false,
    List<CourseModel> currentCourses = const [],
  }) async {
    try {
      final lastSync = fullFetch
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (sessionService.lastSyncAt?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final payload = {
        "lastSyncedAt": lastSync.toUtc().toIso8601String(),
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
            DateTime.tryParse(data["serverTimestamp"] ?? "")?.toUtc() ?? DateTime.now().toUtc();
        await sessionService.setLastSync(serverTime);

        final rawCourses = data["updatedCourses"] as List? ?? [];
        final rawSets = data["updatedStudySets"] as List? ?? [];

        // Build merged course list, seeded with current in-memory or cached courses
        final Map<String, CourseModel> courseMap = {};
        final seedList = currentCourses.isNotEmpty ? currentCourses : _cachedCourses;
        for (final c in seedList) {
          courseMap[c.id] = c;
        }

        for (final raw in rawCourses) {
          final id = raw["id"]?.toString() ?? "";
          if (id.isEmpty) continue;
          if (raw["isDeleted"] == true) {
            courseMap.remove(id);
            continue;
          }
          final existing = courseMap[id];
          courseMap[id] = existing != null
              ? existing.copyWith(
                  code: raw["code"] ?? existing.code,
                  name: raw["name"] ?? existing.name,
                  colorHex: raw["colorHex"] ?? existing.colorHex,
                  updatedAt: DateTime.tryParse(raw["updatedAt"] ?? "") ?? DateTime.now(),
                  examDate: raw["examDate"] != null
                      ? DateTime.tryParse(raw["examDate"])
                      : existing.examDate,
                  examTitle: raw["examTitle"]?.toString() ?? existing.examTitle,
                )
              : CourseModel(
                  id: id,
                  code: raw["code"] ?? "COURSE",
                  name: raw["name"] ?? "Untitled Course",
                  colorHex: raw["colorHex"] ?? "#2E7D5B",
                  createdAt:
                      DateTime.tryParse(raw["updatedAt"] ?? "") ?? DateTime.now(),
                  updatedAt:
                      DateTime.tryParse(raw["updatedAt"] ?? "") ?? DateTime.now(),
                  examDate: raw["examDate"] != null
                      ? DateTime.tryParse(raw["examDate"])
                      : null,
                  examTitle: raw["examTitle"]?.toString(),
                  studySets: [],
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

          if (raw["isDeleted"] == true) {
            if (existingSetIndex >= 0) {
              setList.removeAt(existingSetIndex);
            }
          } else {
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
          }

          courseMap[courseId] = targetCourse.copyWith(studySets: setList);
        }

        final syncedList = courseMap.values.toList();
        await saveOfflineCache(syncedList);

        return SyncResult(
          success: true,
          message: "Synchronized with server.",
          syncedCourses: syncedList,
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
      final isAuth = e.response?.statusCode == 401;
      if (!isAuth && _cachedCourses.isNotEmpty) {
        return SyncResult(
          success: true,
          message: "Loaded from fast offline cache.",
          syncedCourses: _cachedCourses,
          coursesReceived: _cachedCourses.length,
        );
      }
      return SyncResult(
        success: false,
        isUnauthorized: isAuth,
        message: e.error?.toString() ?? e.message ?? "Sync failed.",
      );
    } catch (e) {
      if (_cachedCourses.isNotEmpty) {
        return SyncResult(
          success: true,
          message: "Loaded from fast offline cache.",
          syncedCourses: _cachedCourses,
          coursesReceived: _cachedCourses.length,
        );
      }
      return SyncResult(success: false, message: "Sync error: $e");
    }
  }
}

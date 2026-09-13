import "package:flutter_test/flutter_test.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/sync/services/sync_service.dart";

void main() {
  group("SyncService Model and Merging Unit Tests", () {
    test("SyncResult stores success and populated collections accurately", () {
      final course = CourseModel(
        id: "course-123",
        code: "CS-101",
        name: "Intro to Computer Science",
        colorHex: "#6366F1",
        createdAt: DateTime.now(),
        studySets: [
          StudySetModel(
            id: "set-1",
            courseId: "course-123",
            title: "Algorithms",
            questionCount: 15,
            createdAt: DateTime.now(),
          ),
        ],
      );

      final result = SyncResult(
        success: true,
        message: "Synchronized with server.",
        syncedCourses: [course],
        coursesReceived: 1,
        studySetsReceived: 1,
      );

      expect(result.success, true);
      expect(result.message, "Synchronized with server.");
      expect(result.syncedCourses.length, 1);
      expect(result.syncedCourses.first.code, "CS-101");
      expect(result.syncedCourses.first.studySets.length, 1);
      expect(result.syncedCourses.first.studySets.first.title, "Algorithms");
    });

    test("CourseModel preserves immutable copy operations when modifying study sets", () {
      final original = CourseModel(
        id: "course-1",
        code: "BIO-101",
        name: "Biology",
        colorHex: "#10B981",
        createdAt: DateTime.now(),
        studySets: [
          StudySetModel(
            id: "set-1",
            courseId: "course-1",
            title: "Photosynthesis",
            questionCount: 10,
            createdAt: DateTime.now(),
          ),
          StudySetModel(
            id: "set-2",
            courseId: "course-1",
            title: "Genetics",
            questionCount: 12,
            createdAt: DateTime.now(),
          ),
        ],
      );

      // Verify immutable deletion produces new list without modifying original
      final updatedSets = List<StudySetModel>.from(original.studySets)
        ..removeWhere((s) => s.id == "set-1");

      final updatedCourse = CourseModel(
        id: original.id,
        code: original.code,
        name: original.name,
        colorHex: original.colorHex,
        createdAt: original.createdAt,
        updatedAt: DateTime.now(),
        studySets: updatedSets,
      );

      expect(original.studySets.length, 2);
      expect(updatedCourse.studySets.length, 1);
      expect(updatedCourse.studySets.first.id, "set-2");
    });
  });
}

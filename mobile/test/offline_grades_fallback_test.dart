import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_app_mobile/core/network/api_client.dart';
import 'package:study_app_mobile/core/services/session_service.dart';
import 'package:study_app_mobile/features/courses/models/course_models.dart';
import 'package:study_app_mobile/features/sync/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Grade Tracker On-Device Fallback Tests', () {
    late ApiClient apiClient;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService(prefs);
      apiClient = ApiClient(sessionService);

      SyncService.cachedCourses = [
        CourseModel(
          id: 'c1',
          code: 'CS201',
          name: 'Data Structures',
          colorHex: '#6366F1',
          createdAt: DateTime.now(),
        ),
        CourseModel(
          id: 'c2',
          code: 'MATH101',
          name: 'Discrete Math',
          colorHex: '#10B981',
          createdAt: DateTime.now(),
        ),
      ];
    });

    test('getGradesSummary returns valid local summary when backend is unreachable', () async {
      final summary = await apiClient.getGradesSummary();

      expect(summary, isNotNull);
      expect(summary!.courses.length, equals(2));
      expect(summary.cumulativeGwa, isNotNull);
      expect(summary.honorsStatus, isNotNull);
      expect(summary.courses.any((c) => c.courseName == 'Data Structures'), isTrue);
    });

    test('calculateWhatIf computes needed final exam grade on device without crashing', () async {
      final whatIf = await apiClient.calculateWhatIf(
        courseId: 'c1',
        targetGwa: 1.5,
        prelimWeight: 0.2,
        midtermWeight: 0.2,
        semiFinalWeight: 0.2,
        finalWeight: 0.4,
      );

      expect(whatIf, isNotNull);
      expect(whatIf!.targetGwa, equals(1.5));
      expect(whatIf.neededFinalGrade, isNotNull);
    });

    test('updateCourseGrades stores grades locally and succeeds offline', () async {
      final success = await apiClient.updateCourseGrades(
        'c1',
        {
          'prelimGrade': 95.0,
          'midtermGrade': 96.0,
          'semiFinalGrade': 94.0,
          'finalGrade': 98.0,
        },
      );

      expect(success, isTrue);

      final updatedSummary = await apiClient.getGradesSummary();
      expect(updatedSummary, isNotNull);
      final c1 = updatedSummary!.courses.firstWhere((c) => c.courseId == 'c1');
      expect(c1.prelimGrade, equals(95.0));
      expect(c1.finalGrade, equals(98.0));
    });
  });
}

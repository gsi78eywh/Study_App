import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/ingestion/widgets/camera_scanner_modal.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient apiClient;
  late List<CourseModel> testCourses;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sessionService = await SessionService.init();
    apiClient = ApiClient(sessionService);

    testCourses = [
      CourseModel(
        id: "c1-bio",
        code: "BIO-101",
        name: "General Biology",
        colorHex: "#10B981",
        createdAt: DateTime.now(),
        studySets: [],
      ),
      CourseModel(
        id: "c2-cs",
        code: "CS-201",
        name: "Data Structures",
        colorHex: "#6366F1",
        createdAt: DateTime.now(),
        studySets: [],
      ),
    ];
  });

  Widget buildTestWidget({
    required void Function(String courseId, String title, String scannedText) onExportAndCreateExam,
    void Function(String title, String scannedText)? onExportToEditor,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CameraScannerModal(
          courses: testCourses,
          initialCourseId: "c1-bio",
          apiClient: apiClient,
          onExportAndCreateExam: onExportAndCreateExam,
          onExportToEditor: onExportToEditor,
        ),
      ),
    );
  }

  testWidgets("CameraScannerModal renders viewfinder HUD, reticle, and mode chips", (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        onExportAndCreateExam: (text, courseId, autoGen) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("In-App Camera Scanner"), findsOneWidget);
    expect(find.text("Handwritten Notes"), findsOneWidget);
    expect(find.text("Book & Printed"), findsOneWidget);
    expect(find.text("Exam & Quiz Sheet"), findsOneWidget);
    expect(find.text("Take Photo"), findsOneWidget);
    expect(find.text("Pick Image"), findsOneWidget);
  });

  testWidgets("CameraScannerModal loading sample preset populates text and auto-exports", (tester) async {
    String exportedCourseId = "";
    String exportedTitle = "";
    String exportedText = "";

    await tester.pumpWidget(
      buildTestWidget(
        onExportAndCreateExam: (cId, title, text) {
          exportedCourseId = cId;
          exportedTitle = title;
          exportedText = text;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on sample preset
    final sampleButton = find.text("🧬 Biology: Cellular Respiration & ATP");
    expect(sampleButton, findsOneWidget);
    await tester.tap(sampleButton);
    await tester.pump(const Duration(milliseconds: 200));

    // Verify text inspector displays extracted content
    expect(find.text("Cellular Respiration & Energy Notes"), findsOneWidget);
    expect(find.textContaining("Glycolysis"), findsOneWidget);
    expect(find.text("🚀 Auto-Export & Slowly Create Exam Kinds"), findsOneWidget);

    // Scroll to & tap Auto-Export
    final autoExportButton = find.text("🚀 Auto-Export & Slowly Create Exam Kinds");
    await tester.ensureVisible(autoExportButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(autoExportButton);
    await tester.pump(const Duration(milliseconds: 100));

    expect(exportedCourseId, equals("c1-bio"));
    expect(exportedTitle, equals("Cellular Respiration & Energy Notes"));
    expect(exportedText, contains("Glycolysis"));
  });

  testWidgets("CameraScannerModal mode chip selection switches scanner mode", (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        onExportAndCreateExam: (text, courseId, autoGen) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final bookChip = find.text("Book & Printed");
    await tester.tap(bookChip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Book & Printed"), findsOneWidget);
  });
}

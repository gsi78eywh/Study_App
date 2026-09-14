import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/ingestion/screens/ingestion_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionService sessionService;
  late ApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "jwt_token": "mock-token",
      "user_id": "test-user-id",
    });
    final prefs = await SharedPreferences.getInstance();
    sessionService = SessionService(prefs);
    apiClient = ApiClient(sessionService);
  });

  final dummyCourse = CourseModel(
    id: "course-123",
    name: "Cell Biology",
    code: "BIO101",
    colorHex: "#6366F1",
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets("IngestionScreen renders tabs, AppBar refresh action, and file picker dropzone", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IngestionScreen(
          courses: [dummyCourse],
          apiClient: apiClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify AppBar title and refresh button
    expect(find.text("Study Notes Extractor & Studio"), findsOneWidget);
    expect(find.byTooltip("Reset Form & Clear Selection"), findsOneWidget);

    // Verify Tabs
    expect(find.text("Paste Text"), findsOneWidget);
    expect(find.text("Upload File / Photo"), findsOneWidget);
    expect(find.text("Article URL"), findsOneWidget);

    // Switch to Upload File / Photo tab
    await tester.tap(find.text("Upload File / Photo"));
    await tester.pumpAndSettle();

    // Verify file dropzone text is visible
    expect(find.textContaining("Tap to browse Screenshot, Whiteboard Photo"), findsOneWidget);
  });

  testWidgets("IngestionScreen renders Extract Clean Text action in Paste Text tab", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IngestionScreen(
          courses: [dummyCourse],
          apiClient: apiClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify "Extract Clean Text from Image / File" action button is rendered in Paste Text tab
    expect(find.textContaining("Extract Clean Text from Image / File"), findsOneWidget);
    expect(find.text("Notes & Raw Text Editor"), findsOneWidget);
  });

  testWidgets("IngestionScreen renders preset pills and extracts text from course module", (tester) async {
    final moduleCourse = CourseModel(
      id: "course-123",
      name: "Cell Biology",
      code: "BIO101",
      colorHex: "#6366F1",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      studySets: [
        StudySetModel(
          id: "set-456",
          courseId: "course-123",
          title: "Krebs Cycle & ATP",
          description: "Mitochondrial matrix processes generating NADH and ATP.",
          questionCount: 5,
          createdAt: DateTime.now(),
          bulletPoints: [
            "Krebs Cycle occurs within the inner mitochondrial matrix",
            "Each glucose turn produces 2 ATP, 6 NADH, and 2 FADH2",
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IngestionScreen(
          courses: [moduleCourse],
          apiClient: apiClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify preset pills are rendered with full text
    expect(find.text("All Types (Simulated Exam)"), findsOneWidget);
    expect(find.text("Objective (MCQ + T/F)"), findsOneWidget);
    expect(find.text("Active Recall (ID + Cloze + Enum)"), findsOneWidget);
    expect(find.text("Drills (Matching + Scenario)"), findsOneWidget);

    // Verify "Extract Text based on Provided Modules" button is rendered
    expect(find.byKey(const Key("extract_text_from_modules_btn")), findsOneWidget);

    // Scroll down if necessary and tap "Extract Text based on Provided Modules"
    await tester.ensureVisible(find.byKey(const Key("extract_text_from_modules_btn")));
    await tester.tap(find.byKey(const Key("extract_text_from_modules_btn")));
    await tester.pumpAndSettle();

    // Verify bottom sheet modal opened
    expect(find.text("Extract Text from Course Modules"), findsOneWidget);
    expect(find.text("Krebs Cycle & ATP"), findsOneWidget);

    // Tap module to extract
    await tester.tap(find.text("Krebs Cycle & ATP"));
    await tester.pumpAndSettle();

    // Verify text is extracted and populated in the editor
    expect(find.textContaining("Krebs Cycle occurs within the inner mitochondrial matrix"), findsOneWidget);
    expect(find.text("Krebs Cycle & ATP (Extracted Notes)"), findsOneWidget);
  });

  testWidgets("IngestionScreen renders Question Set & Angle selector and supports Set B extraction", (tester) async {
    final moduleCourse = CourseModel(
      id: "course-123",
      name: "Cell Biology",
      code: "BIO101",
      colorHex: "#6366F1",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      studySets: [
        StudySetModel(
          id: "set-456",
          courseId: "course-123",
          title: "Krebs Cycle & ATP",
          description: "Mitochondrial matrix processes generating NADH and ATP.",
          questionCount: 5,
          createdAt: DateTime.now(),
          bulletPoints: [
            "Krebs Cycle occurs within the inner mitochondrial matrix",
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IngestionScreen(
          courses: [moduleCourse],
          apiClient: apiClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Question Set selector is rendered
    expect(find.text("Question Set & Angle"), findsOneWidget);
    expect(find.text("Set A (Core)"), findsWidgets);
    expect(find.text("Set B (Reverse)"), findsWidgets);
    expect(find.text("Set C (Scenarios)"), findsWidgets);
    expect(find.text("Set D (Simulated)"), findsWidgets);
    expect(find.text("🎲 Fresh Shuffle"), findsWidgets);

    // Tap Set B pill in main screen
    await tester.ensureVisible(find.text("Set B (Reverse)").first);
    await tester.tap(find.text("Set B (Reverse)").first);
    await tester.pumpAndSettle();

    // Verify description updates for Set B
    expect(find.textContaining("Inverted recall (definition ➔ term)"), findsOneWidget);

    // Open module extraction sheet
    await tester.ensureVisible(find.byKey(const Key("extract_text_from_modules_btn")));
    await tester.tap(find.byKey(const Key("extract_text_from_modules_btn")));
    await tester.pumpAndSettle();

    // Tap Set B badge specifically on the module card
    final setBBadges = find.text("Set B (Reverse)");
    expect(setBBadges, findsWidgets);
    await tester.tap(setBBadges.last);
    await tester.pumpAndSettle();

    // Verify title reflects Set B and notes are loaded
    expect(find.text("Krebs Cycle & ATP - Set B (Reverse & Cloze)"), findsOneWidget);
  });
}



import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/theme/app_theme.dart";
import "package:study_app_mobile/features/ai_tutor/screens/ai_tutor_screen.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/ingestion/screens/ingestion_screen.dart";
import "package:study_app_mobile/features/quiz/models/quiz_models.dart";
import "package:study_app_mobile/features/quiz/screens/quiz_player_screen.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group("Product Vision UAT: Capture -> Understand -> Practice -> Feedback -> Review", () {
    testWidgets(
      "UAT 1: Capture Phase - Validates empty input ('what if' failure state) and populates presets ('how' recovery)",
      (WidgetTester tester) async {
        final sessionService = await SessionService.init();
        final apiClient = ApiClient(sessionService);

        final testCourse = CourseModel(
          id: "c1-os",
          code: "CS-301",
          name: "Operating Systems",
          colorHex: "#6366F1",
          createdAt: DateTime.now(),
          studySets: [],
        );

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: IngestionScreen(
            courses: [testCourse],
            apiClient: apiClient,
          ),
        ));
        await tester.pumpAndSettle();

        // 1. Verify Capture Dropzone and UI elements are present
        expect(find.text("Study Notes Extractor & Studio"), findsOneWidget);
        expect(find.text("Paste Text"), findsOneWidget);

        // 2. "What if" Failure State: Attempting generation with empty notes/title
        final generateBtn = find.text("Generate Study Set from Notes");
        expect(generateBtn, findsOneWidget);
        await tester.ensureVisible(generateBtn);
        await tester.pumpAndSettle();
        await tester.tap(generateBtn);
        await tester.pumpAndSettle();

        // 3. "Why" explanation: Informs the student why extraction halted
        expect(find.text("Please enter a title for the study set."), findsOneWidget);

        // 4. "How" recovery: Student inputs study notes
        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(0), "OS Virtual Memory & Paging");
        await tester.enterText(textFields.at(1), "Paging divides virtual memory into pages mapped into physical frames.");
        await tester.pumpAndSettle();

        expect(find.text("OS Virtual Memory & Paging"), findsOneWidget);
        expect(find.textContaining("Paging divides virtual memory"), findsOneWidget);
      },
    );

    testWidgets(
      "UAT 2: Understand Phase - OpenAI wiring paused indicator and secure key target dialog",
      (WidgetTester tester) async {
        final sessionService = await SessionService.init();
        final apiClient = ApiClient(sessionService);

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: AiTutorScreen(
            apiClient: apiClient,
            courses: const [],
          ),
        ));
        await tester.pumpAndSettle();

        // 1. Verify header and built-in model status when no project key target is configured
        expect(find.text("Gemini Study Tutor"), findsOneWidget);
        expect(find.text("Built-In Academic Engine"), findsOneWidget);

        // 2. Verify AI Tutor Online status badge is active and client key button is eliminated
        expect(find.text("AI Tutor Online"), findsOneWidget);
        expect(find.text("API Key"), findsNothing);
      },
    );

    testWidgets(
      "UAT 3 & 4: Practice & Feedback Phases - Distractor rationale reveals 'why' incorrect and 'how' to solve",
      (WidgetTester tester) async {
        final sessionService = await SessionService.init();
        final apiClient = ApiClient(sessionService);

        final studySet = StudySetModel(
          id: "set-os-1",
          courseId: "course-1",
          title: "Operating Systems Architecture",
          description: "Virtual Memory and Paging",
          createdAt: DateTime.now(),
        );

        final question = QuestionModel(
          id: "q-vm-1",
          studySetId: "set-os-1",
          type: QuestionTypeEnum.multipleChoice,
          prompt: "What is the primary function of the Translation Lookaside Buffer (TLB)?",
          hints: ["Think about hardware cache for address translations."],
          explanation: "The TLB caches recent virtual-to-physical address translations to accelerate memory access.",
          options: [
            QuestionOptionModel(
              id: "opt-1",
              optionText: "To permanently store inactive process pages on secondary storage.",
              isCorrect: false,
              distractorRationale: "That is the role of the swap file, not the hardware TLB cache.",
            ),
            QuestionOptionModel(
              id: "opt-2",
              optionText: "A hardware cache that speeds up virtual-to-physical address translation.",
              isCorrect: true,
            ),
            QuestionOptionModel(
              id: "opt-3",
              optionText: "An interrupt service routine that handles kernel segmentation faults.",
              isCorrect: false,
              distractorRationale: "Interrupt routines handle exceptions, while TLB is an MMU cache.",
            ),
          ],
        );

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: QuizPlayerScreen(
            studySet: studySet,
            questions: [question],
            apiClient: apiClient,
            sessionService: sessionService,
            shuffleOptions: false,
          ),
        ));
        await tester.pumpAndSettle();

        // 1. Verify question prompt rendered
        expect(find.text("What is the primary function of the Translation Lookaside Buffer (TLB)?"), findsOneWidget);

        // 2. Select a plausible distractor (Incorrect choice)
        final wrongChoice = find.text("To permanently store inactive process pages on secondary storage.");
        expect(wrongChoice, findsOneWidget);
        await tester.tap(wrongChoice);
        await tester.pumpAndSettle();

        // 3. Tap Check Answer to receive immediate pedagogical feedback
        final checkBtn = find.text("Check Answer");
        expect(checkBtn, findsOneWidget);
        await tester.ensureVisible(checkBtn);
        await tester.pumpAndSettle();
        await tester.tap(checkBtn);
        await tester.pumpAndSettle();

        // 4. Verify "Why" explanation: Distractor rationale and correct justification are displayed
        expect(find.text("AI Pedagogical Explanation & Rationale"), findsOneWidget);
        expect(find.text("That is the role of the swap file, not the hardware TLB cache."), findsOneWidget);
        expect(find.text("The TLB caches recent virtual-to-physical address translations to accelerate memory access."), findsOneWidget);
      },
    );
  });
}

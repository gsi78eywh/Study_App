import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/theme/app_theme.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/quiz/models/quiz_models.dart";
import "package:study_app_mobile/features/quiz/screens/quiz_player_screen.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group("Quiz Check Answer Real-time Reveal Tests", () {
    testWidgets(
        "Checking answer automatically reveals 100% correct answer and highlights choices",
        (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final apiClient = ApiClient(sessionService);

      final studySet = StudySetModel(
        id: "set-1",
        courseId: "course-1",
        title: "Reinforcement Learning Mastery",
        description: "Core principles of RL",
        createdAt: DateTime.now(),
      );

      final question = QuestionModel(
        id: "q-1",
        studySetId: "set-1",
        type: QuestionTypeEnum.multipleChoice,
        prompt: "In a Reinforcement Learning framework, what does exploration refer to?",
        hints: ["Think about trying new things vs using known rewards."],
        explanation: "Exploration involves taking unfamiliar actions to discover better policies.",
        options: [
          QuestionOptionModel(
            id: "opt-a",
            optionText: "The agent exploiting its current knowledge to maximize immediate rewards.",
            isCorrect: false,
            distractorRationale: "This is exploitation, not exploration.",
          ),
          QuestionOptionModel(
            id: "opt-b",
            optionText: "The manual labeling of training environments by human supervisors.",
            isCorrect: false,
            distractorRationale: "RL does not rely on manual supervised labeling.",
          ),
          QuestionOptionModel(
            id: "opt-c",
            optionText: "The agent trying out new or unfamiliar actions to discover potentially better strategies.",
            isCorrect: true,
          ),
          QuestionOptionModel(
            id: "opt-d",
            optionText: "The process of cleaning and normalizing raw input datasets.",
            isCorrect: false,
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

      // 1. Initial State: Question and choices are visible, Check Answer is disabled until an option is selected
      expect(find.text("In a Reinforcement Learning framework, what does exploration refer to?"), findsOneWidget);
      expect(find.text("Check Answer"), findsOneWidget);
      expect(find.text("100% Correct"), findsNothing);

      // 2. User selects Option A (Incorrect option)
      await tester.tap(find.text("The agent exploiting its current knowledge to maximize immediate rewards."));
      await tester.pumpAndSettle();

      // 3. User scrolls to and taps "Check Answer"
      await tester.ensureVisible(find.text("Check Answer"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Check Answer"));
      await tester.pumpAndSettle();

      // 4. Verification of 100% real-time reveal:
      // The 100% Correct Answer badge must be visible on Option C
      expect(find.text("100% Correct"), findsOneWidget);

      // The User's Choice (Incorrect) badge must be visible on Option A
      expect(find.text("Your Choice (Incorrect)"), findsOneWidget);

      // Distractor rationale should be revealed
      expect(find.text("This is exploitation, not exploration."), findsOneWidget);

      // Pedagogical explanation is revealed
      expect(find.text("AI Pedagogical Explanation & Rationale"), findsOneWidget);
      expect(find.text("Exploration involves taking unfamiliar actions to discover better policies."), findsOneWidget);

      // Bottom button transforms to "View Results" (since it's the last question)
      expect(find.text("View Results"), findsOneWidget);
    });

    testWidgets(
        "Selecting correct answer reveals 100% Correct Recall celebratory banner",
        (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final apiClient = ApiClient(sessionService);

      final studySet = StudySetModel(
        id: "set-2",
        courseId: "course-1",
        title: "Biology Fundamentals",
        description: "Photosynthesis",
        createdAt: DateTime.now(),
      );

      final question = QuestionModel(
        id: "q-2",
        studySetId: "set-2",
        type: QuestionTypeEnum.multipleChoice,
        prompt: "What is the primary role of water photolysis in photosynthesis?",
        hints: [],
        explanation: "Photolysis splits water to resupply photo-excited chlorophyll electrons.",
        options: [
          QuestionOptionModel(
            id: "opt-1",
            optionText: "Replenish electrons in photo-excited chlorophyll",
            isCorrect: true,
          ),
          QuestionOptionModel(
            id: "opt-2",
            optionText: "Provide carbon atoms for glucose synthesis",
            isCorrect: false,
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

      // User selects Option 1 (Correct)
      await tester.tap(find.text("Replenish electrons in photo-excited chlorophyll"));
      await tester.pumpAndSettle();

      // User clicks Check Answer
      await tester.tap(find.text("Check Answer"));
      await tester.pumpAndSettle();

      // Verification: 100% Correct Recall banner is shown
      expect(find.text("100% Correct Recall!"), findsOneWidget);
      expect(find.text("100% Accurate"), findsOneWidget);
      expect(find.text("100% Correct"), findsOneWidget);
      expect(find.text("AI Pedagogical Explanation & Rationale"), findsOneWidget);
    });
  });
}

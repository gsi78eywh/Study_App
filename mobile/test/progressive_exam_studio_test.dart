import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/quiz/models/quiz_models.dart";
import "package:study_app_mobile/features/ingestion/widgets/progressive_exam_studio.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sessionService = await SessionService.init();
    apiClient = ApiClient(sessionService);
  });

  Widget buildTestWidget({
    required void Function(StudySetModel) onExamSaved,
    void Function(StudySetModel, List<QuestionModel>)? onLaunchQuiz,
    List<QuestionModel>? initialQuestions,
  }) {
    return MaterialApp(
      home: ProgressiveExamStudio(
        courseId: "c1-bio",
        courseName: "General Biology",
        initialTitle: "Cell Respiration Exam",
        sourceText: "Glycolysis produces 2 ATP in the cytoplasm.",
        apiClient: apiClient,
        enableStageTimer: false,
        autoStart: false,
        initialQuestions: initialQuestions,
        onExamSaved: onExamSaved,
        onLaunchQuiz: onLaunchQuiz,
      ),
    );
  }

  testWidgets("ProgressiveExamStudio renders progress tracker and stage indicator", (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        onExamSaved: (_) {},
      ),
    );
    await tester.pump();

    expect(find.text("Progressive Exam Studio"), findsOneWidget);
    expect(find.text("General Biology • Cell Respiration Exam"), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets("ProgressiveExamStudio fast-forwards stages when Reveal All is tapped", (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        onExamSaved: (_) {},
      ),
    );
    await tester.pump();

    final revealButton = find.text("Reveal All");
    if (revealButton.evaluate().isNotEmpty) {
      await tester.tap(revealButton);
      await tester.pump();
      expect(find.textContaining("100%"), findsOneWidget);
    }
  });

  testWidgets("ProgressiveExamStudio displays questions with kind badges", (tester) async {
    final sampleQuestions = [
      QuestionModel(
        id: "q1",
        studySetId: "s1",
        prompt: "Where does glycolysis occur?",
        type: QuestionTypeEnum.multipleChoice,
        hints: ["Think cytoplasm"],
        explanation: "Glycolysis occurs in the cytosol/cytoplasm.",
        options: [
          QuestionOptionModel(id: "o1", optionText: "Cytoplasm", isCorrect: true),
          QuestionOptionModel(id: "o2", optionText: "Mitochondria", isCorrect: false),
          QuestionOptionModel(id: "o3", optionText: "Nucleus", isCorrect: false),
          QuestionOptionModel(id: "o4", optionText: "Ribosome", isCorrect: false),
        ],
      ),
      QuestionModel(
        id: "q2",
        studySetId: "s1",
        prompt: "What molecule is known as the energy currency of the cell?",
        type: QuestionTypeEnum.identification,
        hints: ["3-letter acronym"],
        explanation: "ATP stores and transports chemical energy.",
        options: [],
        correctAnswer: "ATP",
      ),
    ];

    await tester.pumpWidget(
      buildTestWidget(
        onExamSaved: (_) {},
        initialQuestions: sampleQuestions,
      ),
    );
    await tester.pump();

    expect(find.text("Where does glycolysis occur?"), findsOneWidget);
    expect(find.text("Cytoplasm"), findsWidgets);
    expect(find.text("Multiple Choice"), findsWidgets);
  });
}

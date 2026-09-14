import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:study_app_mobile/features/courses/models/course_models.dart";
import "package:study_app_mobile/features/flashcards/screens/flashcards_screen.dart";
import "package:study_app_mobile/features/flashcards/utils/flashcard_text_sanitizer.dart";

void main() {
  group("FlashcardTextSanitizer Unit Tests", () {
    test("Cleans raw fill-in-the-blank prompt with leaked distractor option letter", () {
      const input = 'Fill in the blank from your study notes: "* A) A set of _______ rules hard-coded by programmers to solve specific tasks"';
      final cleaned = FlashcardTextSanitizer.cleanFront(input);

      expect(cleaned, "A set of _______ rules hard-coded by programmers to solve specific tasks");
      expect(cleaned.contains("Fill in the blank"), false);
      expect(cleaned.contains("* A)"), false);
      expect(cleaned.startsWith('"'), false);
    });

    test("Cleans missing word prompt without bullet points", () {
      const input = 'Fill in the missing word from your study notes: "________ is a subset of AI where systems learn from data"';
      final cleaned = FlashcardTextSanitizer.cleanFront(input);

      expect(cleaned, "________ is a subset of AI where systems learn from data");
    });

    test("Cleans True/False prompt prefix", () {
      const input = 'True or False: According to your study material: "Supervised Learning requires labeled training data."';
      final cleaned = FlashcardTextSanitizer.cleanFront(input);

      expect(cleaned, "Supervised Learning requires labeled training data.");
    });

    test("Preserves standard clean questions unchanged", () {
      const input = "What is the primary function of the mitochondria in eukaryotic cells?";
      final cleaned = FlashcardTextSanitizer.cleanFront(input);

      expect(cleaned, "What is the primary function of the mitochondria in eukaryotic cells?");
    });

    test("Cleans option prefixes from verified answers", () {
      expect(FlashcardTextSanitizer.cleanAnswer("* A) Machine Learning"), "Machine Learning");
      expect(FlashcardTextSanitizer.cleanAnswer("- B. Deep Learning"), "Deep Learning");
      expect(FlashcardTextSanitizer.cleanAnswer("• C) Neural Networks"), "Neural Networks");
      expect(FlashcardTextSanitizer.cleanAnswer("D) Gradient Descent"), "Gradient Descent");
      expect(FlashcardTextSanitizer.cleanAnswer("Gradient Descent"), "Gradient Descent");
    });

    test("Cleans explanation blocks with leaked bullets", () {
      const input = 'Full text from your study notes: "* A) A set of rigid rules hard-coded by programmers."';
      final cleaned = FlashcardTextSanitizer.cleanExplanation(input);

      expect(cleaned.contains("Full text from your study notes:"), false);
      expect(cleaned.contains("* A)"), false);
      expect(cleaned.startsWith("Source notes:"), true);
    });
  });

  group("FlashcardsScreen Deletion Widget Tests", () {
    testWidgets("Renders flashcard with delete button and deletes upon confirmation", (WidgetTester tester) async {
      final courses = [
        CourseModel(
          id: "c1",
          code: "CS101",
          name: "Intro to AI",
          colorHex: "#6366F1",
          createdAt: DateTime.now(),
          studySets: [
            StudySetModel(
              id: "s1",
              courseId: "c1",
              title: "Foundations & Definitions",
              questionCount: 2,
              createdAt: DateTime.now(),
              bulletPoints: [
                "Narrow AI: Systems designed for one specific task",
                "General AI: Flexible systems possessing human-level reasoning",
              ],
            ),
          ],
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlashcardsScreen(courses: courses),
        ),
      ));
      await tester.pumpAndSettle();

      // Card 1 is rendered
      expect(find.text("Card 1 of 2"), findsOneWidget);
      expect(find.byKey(const Key("delete_flashcard_icon")), findsOneWidget);

      // Tap the delete icon
      await tester.tap(find.byKey(const Key("delete_flashcard_icon")));
      await tester.pumpAndSettle();

      // Confirmation dialog is shown
      expect(find.text("Delete Flashcard?"), findsOneWidget);
      expect(find.byKey(const Key("cancel_delete_card_button")), findsOneWidget);
      expect(find.byKey(const Key("confirm_delete_card_button")), findsOneWidget);

      // Cancel first
      await tester.tap(find.byKey(const Key("cancel_delete_card_button")));
      await tester.pumpAndSettle();

      // Dialog dismissed, still 2 cards
      expect(find.text("Card 1 of 2"), findsOneWidget);

      // Tap delete icon again and confirm
      await tester.tap(find.byKey(const Key("delete_flashcard_icon")));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("confirm_delete_card_button")));
      await tester.pumpAndSettle();

      // Card 1 deleted, deck now has 1 card
      expect(find.text("Card 1 of 1"), findsOneWidget);
      expect(find.text("Flashcard deleted successfully."), findsOneWidget);
    });
  });
}


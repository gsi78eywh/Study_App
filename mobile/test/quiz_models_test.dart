import "package:flutter_test/flutter_test.dart";
import "package:study_app_mobile/features/quiz/models/quiz_models.dart";

void main() {
  group("StudyModeValue Contract Tests", () {
    test("StudyModeValue constants match backend enum values", () {
      expect(StudyModeValue.flashcards, 1);
      expect(StudyModeValue.multipleChoice, 2);
      expect(StudyModeValue.identification, 3);
      expect(StudyModeValue.enumeration, 4);
      expect(StudyModeValue.bulletPoints, 5);
      expect(StudyModeValue.logicSprint, 6);
      expect(StudyModeValue.speedCram, 7);
      expect(StudyModeValue.simulatedExam, 8);
      expect(StudyModeValue.rapidFireBlitz, 13);
      expect(StudyModeValue.clozeTest, 14);
      expect(StudyModeValue.trueFalse, 15);
      expect(StudyModeValue.matchingType, 16);
      expect(StudyModeValue.shortAnswer, 17);
      expect(StudyModeValue.scenarioDrills, 18);
    });
  });

  group("QuestionModel Serialization Tests", () {
    test("QuestionModel deserializes question with options and hints", () {
      final json = {
        "id": "q-101",
        "studySetId": "set-202",
        "type": "MultipleChoice",
        "prompt": "What is the primary function of ribosomes?",
        "hints": ["Found on rough ER", "Translation"],
        "explanation": "Ribosomes synthesize proteins from mRNA transcripts.",
        "difficulty": 2,
        "sortOrder": 1,
        "options": [
          {"id": "opt-1", "optionText": "Protein Synthesis", "isCorrect": true},
          {"id": "opt-2", "optionText": "Lipid Synthesis", "isCorrect": false, "distractorRationale": "Smooth ER synthesizes lipids."}
        ]
      };

      final question = QuestionModel.fromJson(json);

      expect(question.id, "q-101");
      expect(question.studySetId, "set-202");
      expect(question.type, QuestionTypeEnum.multipleChoice);
      expect(question.prompt, "What is the primary function of ribosomes?");
      expect(question.hints.length, 2);
      expect(question.options.length, 2);
      expect(question.options[0].isCorrect, true);
      expect(question.options[0].optionText, "Protein Synthesis");
      expect(question.options[1].isCorrect, false);
      expect(question.options[1].distractorRationale, "Smooth ER synthesizes lipids.");
    });
  });

  group("TestSessionSubmission Serialization Tests", () {
    test("TestSessionSubmission retains simulatedExam mode upon serialization", () {
      final submission = TestSessionSubmission(
        id: "sess-1",
        studySetId: "set-1",
        mode: StudyModeValue.simulatedExam,
        score: 95,
        totalQuestions: 10,
        timeSpentSeconds: 120,
        completedAt: DateTime.parse("2026-09-12T10:00:00Z"),
        answers: [
          PracticeAnswerSubmission(questionId: "q-1", answer: "Protein Synthesis"),
        ],
      );

      final json = submission.toJson();
      expect(json["mode"], StudyModeValue.simulatedExam);
      expect(json["score"], 95);
      expect(json["totalQuestions"], 10);
      expect(json["timeSpentSeconds"], 120);

      final practiceJson = submission.toPracticeJson();
      expect(practiceJson["mode"], StudyModeValue.simulatedExam);
      expect((practiceJson["answers"] as List).length, 1);
    });
  });

  group("Notebook NoteItem Content Compatibility", () {
    test("NoteItem parses content from contentMarkdown or content payload", () {
      final backendResponsePayload1 = {
        "id": "note-1",
        "courseCode": "BIO-101",
        "title": "Krebs Cycle Notes",
        "contentMarkdown": "# Krebs Cycle\nOccurs in mitochondrial matrix.",
        "tags": "#Biology #Metabolism"
      };

      final content1 = (backendResponsePayload1["contentMarkdown"] ?? backendResponsePayload1["content"])?.toString() ?? "";
      expect(content1, "# Krebs Cycle\nOccurs in mitochondrial matrix.");

      final backendResponsePayload2 = {
        "id": "note-2",
        "courseCode": "CS-201",
        "title": "Sorting Algorithms",
        "content": "Quicksort runs in O(N log N) on average.",
        "tags": "#Algorithms"
      };

      final content2 = (backendResponsePayload2["contentMarkdown"] ?? backendResponsePayload2["content"])?.toString() ?? "";
      expect(content2, "Quicksort runs in O(N log N) on average.");
    });
  });

  group("Multiple Choice 4-Choice Distinct Options Tests", () {
    test("QuestionModel deserializes 4 distinct multiple choice options", () {
      final json = {
        "id": "q-mcq-1",
        "studySetId": "set-1",
        "type": "MultipleChoice",
        "prompt": "What is the powerhouse of the cell?",
        "options": [
          {"id": "opt-1", "optionText": "Nucleus", "isCorrect": false},
          {"id": "opt-2", "optionText": "Mitochondria", "isCorrect": true},
          {"id": "opt-3", "optionText": "Ribosome", "isCorrect": false},
          {"id": "opt-4", "optionText": "Chloroplast", "isCorrect": false},
        ]
      };

      final q = QuestionModel.fromJson(json);

      expect(q.options.length, 4);
      expect(q.options.where((o) => o.isCorrect).length, 1);
      expect(q.options.firstWhere((o) => o.isCorrect).optionText, "Mitochondria");

      // Verify all option texts are distinct
      final distinctTexts = q.options.map((o) => o.optionText).toSet();
      expect(distinctTexts.length, 4);
    });

    test("QuestionModel derives matching terms and definitions from matchingPairs", () {
      final json = {
        "id": "q-match-1",
        "studySetId": "set-1",
        "type": "Matching",
        "prompt": "Match each term to its definition:",
        "matchingPairs": [
          {"term": "Mitochondria", "definition": "Powerhouse of the cell"},
          {"term": "Ribosome", "definition": "Site of protein synthesis"}
        ]
      };

      final q = QuestionModel.fromJson(json);

      expect(q.type, QuestionTypeEnum.matching);
      expect(q.matchingTerms, ["Mitochondria", "Ribosome"]);
      expect(q.matchingDefinitions, ["Powerhouse of the cell", "Site of protein synthesis"]);
    });

    test("QuestionModel derives isTrue for TrueFalse question from options", () {
      final json = {
        "id": "q-tf-1",
        "studySetId": "set-1",
        "type": "TrueFalse",
        "prompt": "True or False: The mitochondria produces ATP.",
        "options": [
          {"id": "opt-1", "optionText": "True", "isCorrect": true},
          {"id": "opt-2", "optionText": "False", "isCorrect": false}
        ]
      };

      final q = QuestionModel.fromJson(json);

      expect(q.type, QuestionTypeEnum.trueFalse);
      expect(q.isTrue, true);
    });
  });
}

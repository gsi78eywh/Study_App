import "dart:convert";

enum QuestionTypeEnum {
  multipleChoice,
  identification,
  enumeration,
  bulletPoints,
  logicalThinking,
  cloze,
  trueFalse,
  matching,
  shortAnswer,
  scenario,
}

/// Numeric values are the API contract with backend StudyMode.
abstract final class StudyModeValue {
  static const int flashcards = 1;
  static const int multipleChoice = 2;
  static const int identification = 3;
  static const int enumeration = 4;
  static const int bulletPoints = 5;
  static const int logicSprint = 6;
  static const int speedCram = 7;
  static const int simulatedExam = 8;
  static const int rapidFireBlitz = 13;
  static const int clozeTest = 14;
  static const int trueFalse = 15;
  static const int matchingType = 16;
  static const int shortAnswer = 17;
  static const int scenarioDrills = 18;
}

class QuestionOptionModel {
  final String id;
  final String optionText;
  final bool isCorrect;
  final String? distractorRationale;

  QuestionOptionModel({
    required this.id,
    required this.optionText,
    required this.isCorrect,
    this.distractorRationale,
  });

  String get text => optionText;

  factory QuestionOptionModel.fromJson(Map<String, dynamic> json) {
    return QuestionOptionModel(
      id: json["id"]?.toString() ?? "",
      optionText: json["optionText"] ?? json["text"] ?? "",
      isCorrect: json["isCorrect"] ?? false,
      distractorRationale: json["distractorRationale"],
    );
  }
}

class QuestionModel {
  final String id;
  final String studySetId;
  final QuestionTypeEnum type;
  final String prompt;
  final List<String> hints;
  final String? explanation;
  final List<QuestionOptionModel> options;
  final List<String> matchingTerms;
  final List<String> matchingDefinitions;
  final int difficulty;
  final int sortOrder;
  final bool? isTrue; // for true_false questions
  final List<Map<String, String>>? matchingPairs; // for matching questions
  final String? correctAnswer;
  final List<String> thinkingBreakdown;
  final String? dimensionTag;

  QuestionModel({
    required this.id,
    required this.studySetId,
    required this.type,
    required this.prompt,
    required this.hints,
    this.explanation,
    required this.options,
    this.matchingTerms = const [],
    this.matchingDefinitions = const [],
    this.difficulty = 2,
    this.sortOrder = 1,
    this.isTrue,
    this.matchingPairs,
    this.correctAnswer,
    this.thinkingBreakdown = const [],
    this.dimensionTag,
  });

  QuestionOptionModel? get correctOption {
    try {
      return options.firstWhere((o) => o.isCorrect);
    } catch (_) {
      return null;
    }
  }

  String get exactAnswerText {
    if (correctOption != null && correctOption!.optionText.isNotEmpty) {
      return correctOption!.optionText;
    }
    if (type == QuestionTypeEnum.trueFalse) {
      return isTrue == true ? "TRUE" : "FALSE";
    }
    if (correctAnswer != null && correctAnswer!.isNotEmpty) {
      return correctAnswer!;
    }
    return "";
  }

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedHints = [];
    if (json["hintsJson"] != null && json["hintsJson"] is String) {
      try {
        final decoded = jsonDecode(json["hintsJson"]);
        if (decoded is List) {
          parsedHints = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (json["hints"] is List) {
      parsedHints = (json["hints"] as List).map((e) => e.toString()).toList();
    }

    final rawType = json["type"];
    QuestionTypeEnum qType = QuestionTypeEnum.multipleChoice;
    if (rawType is int) {
      switch (rawType) {
        case 2:
          {
            qType = QuestionTypeEnum.identification;
            break;
          }
        case 3:
          {
            qType = QuestionTypeEnum.enumeration;
            break;
          }
        case 4:
          {
            qType = QuestionTypeEnum.bulletPoints;
            break;
          }
        case 5:
          {
            qType = QuestionTypeEnum.logicalThinking;
            break;
          }
        case 6:
          {
            qType = QuestionTypeEnum.cloze;
            break;
          }
        case 7:
          {
            qType = QuestionTypeEnum.trueFalse;
            break;
          }
        case 8:
          {
            qType = QuestionTypeEnum.matching;
            break;
          }
        case 9:
          {
            qType = QuestionTypeEnum.shortAnswer;
            break;
          }
        case 10:
          {
            qType = QuestionTypeEnum.scenario;
            break;
          }
      }
    } else if (rawType is String) {
      final s = rawType.toLowerCase();
      if (s.contains("ident")) {
        qType = QuestionTypeEnum.identification;
      } else if (s.contains("enum")) {
        qType = QuestionTypeEnum.enumeration;
      } else if (s.contains("bullet")) {
        qType = QuestionTypeEnum.bulletPoints;
      } else if (s.contains("logic")) {
        qType = QuestionTypeEnum.logicalThinking;
      } else if (s.contains("cloze") || s.contains("fill")) {
        qType = QuestionTypeEnum.cloze;
      } else if (s.contains("true") || s.contains("tf")) {
        qType = QuestionTypeEnum.trueFalse;
      } else if (s.contains("match")) {
        qType = QuestionTypeEnum.matching;
      } else if (s.contains("short")) {
        qType = QuestionTypeEnum.shortAnswer;
      } else if (s.contains("scenario") || s.contains("case")) {
        qType = QuestionTypeEnum.scenario;
      }
    }

    // Parse matching pairs if present
    List<Map<String, String>>? matchingPairs;
    final pairsRaw = json["matchingPairs"] ?? json["correctAnswer"];
    if (qType == QuestionTypeEnum.matching && pairsRaw is List) {
      matchingPairs = pairsRaw
          .whereType<Map<String, dynamic>>()
          .map(
            (p) => {
              "term": p["term"]?.toString() ?? "",
              "definition": p["definition"]?.toString() ?? "",
            },
          )
          .toList();
    }

    final parsedOptions = (json["options"] as List<dynamic>?)
            ?.map(
              (o) => QuestionOptionModel.fromJson(o as Map<String, dynamic>),
            )
            .toList() ??
        [];

    final rawMatchingTerms = (json["matchingTerms"] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    final rawMatchingDefinitions = (json["matchingDefinitions"] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];

    final matchingTerms = rawMatchingTerms.isNotEmpty
        ? rawMatchingTerms
        : (matchingPairs?.map((p) => p["term"] ?? "").where((s) => s.isNotEmpty).toList() ?? const <String>[]);
    final matchingDefinitions = rawMatchingDefinitions.isNotEmpty
        ? rawMatchingDefinitions
        : (matchingPairs?.map((p) => p["definition"] ?? "").where((s) => s.isNotEmpty).toList() ?? const <String>[]);

    final String? correctAnswer = json["correctAnswer"]?.toString();

    bool? isTrue = json["isTrue"] as bool?;
    if (isTrue == null && qType == QuestionTypeEnum.trueFalse) {
      for (final opt in parsedOptions) {
        final text = opt.optionText.trim().toLowerCase();
        if (text == "true" && opt.isCorrect) isTrue = true;
        if (text == "false" && opt.isCorrect) isTrue = false;
      }
      if (isTrue == null && correctAnswer != null) {
        final lower = correctAnswer.trim().toLowerCase();
        if (lower == "true" || lower == "t" || lower == "1") isTrue = true;
        if (lower == "false" || lower == "f" || lower == "0") isTrue = false;
      }
    }

    List<String> parsedThinking = [];
    if (json["thinkingBreakdown"] is List) {
      parsedThinking = (json["thinkingBreakdown"] as List).map((e) => e.toString()).toList();
    }

    String? dimensionTag;
    for (final step in parsedThinking) {
      final upper = step.toUpperCase();
      if (upper.startsWith("DIMENSION:")) {
        dimensionTag = step.substring("DIMENSION:".length).trim();
        break;
      }
    }

    return QuestionModel(
      id: json["id"]?.toString() ?? "",
      studySetId: json["studySetId"]?.toString() ?? "",
      type: qType,
      prompt: json["prompt"] ?? "",
      hints: parsedHints,
      explanation: json["explanation"],
      options: parsedOptions,
      difficulty: json["difficulty"] ?? 2,
      sortOrder: json["sortOrder"] ?? 1,
      isTrue: isTrue,
      matchingTerms: matchingTerms,
      matchingDefinitions: matchingDefinitions,
      matchingPairs: matchingPairs,
      correctAnswer: correctAnswer,
      thinkingBreakdown: parsedThinking,
      dimensionTag: dimensionTag,
    );
  }
}

class PracticeAnswerSubmission {
  final String questionId;
  final String answer;

  const PracticeAnswerSubmission({
    required this.questionId,
    required this.answer,
  });

  Map<String, dynamic> toJson() => {"questionId": questionId, "answer": answer};
}

class TestSessionSubmission {
  final String id;
  final String studySetId;
  final int mode; // 0: Flashcards, 1: PracticeQuiz, 2: ExamSimulation
  final int score;
  final int totalQuestions;
  final int timeSpentSeconds;
  final DateTime completedAt;
  final List<PracticeAnswerSubmission> answers;

  TestSessionSubmission({
    required this.id,
    required this.studySetId,
    required this.mode,
    required this.score,
    required this.totalQuestions,
    required this.timeSpentSeconds,
    required this.completedAt,
    this.answers = const [],
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "studySetId": studySetId,
    "mode": mode,
    "score": score,
    "totalQuestions": totalQuestions,
    "timeSpentSeconds": timeSpentSeconds,
    "completedAt": completedAt.toIso8601String(),
  };

  Map<String, dynamic> toPracticeJson() => {
    "studySetId": studySetId,
    "mode": mode,
    "timeSpentSeconds": timeSpentSeconds,
    "answers": answers.map((answer) => answer.toJson()).toList(),
  };
}

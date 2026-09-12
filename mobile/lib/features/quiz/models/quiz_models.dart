import "dart:convert";

enum QuestionTypeEnum {
  multipleChoice,
  identification,
  enumeration,
  bulletPoints,
  logicalThinking,
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
  final int difficulty;
  final int sortOrder;

  QuestionModel({
    required this.id,
    required this.studySetId,
    required this.type,
    required this.prompt,
    required this.hints,
    this.explanation,
    required this.options,
    this.difficulty = 2,
    this.sortOrder = 1,
  });

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
      if (rawType == 1) qType = QuestionTypeEnum.identification;
      if (rawType == 2) qType = QuestionTypeEnum.enumeration;
      if (rawType == 3) qType = QuestionTypeEnum.bulletPoints;
      if (rawType == 4) qType = QuestionTypeEnum.logicalThinking;
    } else if (rawType is String) {
      final s = rawType.toLowerCase();
      if (s.contains("ident")) qType = QuestionTypeEnum.identification;
      if (s.contains("enum")) qType = QuestionTypeEnum.enumeration;
      if (s.contains("bullet")) qType = QuestionTypeEnum.bulletPoints;
      if (s.contains("logic")) qType = QuestionTypeEnum.logicalThinking;
    }

    return QuestionModel(
      id: json["id"]?.toString() ?? "",
      studySetId: json["studySetId"]?.toString() ?? "",
      type: qType,
      prompt: json["prompt"] ?? "",
      hints: parsedHints,
      explanation: json["explanation"],
      options: (json["options"] as List<dynamic>?)
              ?.map((o) => QuestionOptionModel.fromJson(o as Map<String, dynamic>))
              .toList() ??
          [],
      difficulty: json["difficulty"] ?? 2,
      sortOrder: json["sortOrder"] ?? 1,
    );
  }
}

class TestSessionSubmission {
  final String id;
  final String studySetId;
  final int mode; // 0: Flashcards, 1: PracticeQuiz, 2: ExamSimulation
  final int score;
  final int totalQuestions;
  final int timeSpentSeconds;
  final DateTime completedAt;

  TestSessionSubmission({
    required this.id,
    required this.studySetId,
    required this.mode,
    required this.score,
    required this.totalQuestions,
    required this.timeSpentSeconds,
    required this.completedAt,
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
}

class TodayStudyPlanModel {
  final String? courseId;
  final String courseName;
  final String courseCode;
  final DateTime? examDate;
  final int? daysUntilExam;
  final int totalEstimatedMinutes;
  final List<CoursePriorityModel> priorities;
  final List<StudyPlanStepModel> steps;
  final String aiRecommendation;
  final ExplainableReadinessModel readiness;

  TodayStudyPlanModel({
    this.courseId,
    required this.courseName,
    required this.courseCode,
    this.examDate,
    this.daysUntilExam,
    required this.totalEstimatedMinutes,
    required this.priorities,
    required this.steps,
    required this.aiRecommendation,
    required this.readiness,
  });

  factory TodayStudyPlanModel.fromJson(Map<String, dynamic> json) {
    return TodayStudyPlanModel(
      courseId: json["courseId"]?.toString(),
      courseName: json["courseName"]?.toString() ?? "General",
      courseCode: json["courseCode"]?.toString() ?? "COURSE",
      examDate: json["examDate"] != null ? DateTime.tryParse(json["examDate"]) : null,
      daysUntilExam: json["daysUntilExam"] as int?,
      totalEstimatedMinutes: (json["totalEstimatedMinutes"] as int?) ?? 25,
      priorities: (json["priorities"] as List<dynamic>?)
              ?.map((p) => CoursePriorityModel.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      steps: (json["steps"] as List<dynamic>?)
              ?.map((s) => StudyPlanStepModel.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      aiRecommendation: json["aiRecommendation"]?.toString() ??
          "Maintain daily spacing consistency to reinforce neural memory traces.",
      readiness: json["readiness"] != null
          ? ExplainableReadinessModel.fromJson(json["readiness"] as Map<String, dynamic>)
          : ExplainableReadinessModel.defaultEmpty(),
    );
  }

  int get unresolvedMistakesCount => readiness.unresolvedMistakesCount;
  CoursePriorityModel? get topPriorityCourse =>
      priorities.isNotEmpty ? priorities.first : null;
}


class CoursePriorityModel {
  final String topicName;
  final double masteryPercent;
  final String status;
  final int missedCount;
  final String? courseId;

  CoursePriorityModel({
    required this.topicName,
    required this.masteryPercent,
    required this.status,
    required this.missedCount,
    this.courseId,
  });

  factory CoursePriorityModel.fromJson(Map<String, dynamic> json) {
    return CoursePriorityModel(
      topicName: json["topicName"]?.toString() ?? "Topic",
      masteryPercent: (json["masteryPercent"] as num?)?.toDouble() ?? 50.0,
      status: json["status"]?.toString() ?? "Needs Review",
      missedCount: (json["missedCount"] as int?) ?? 0,
      courseId: json["courseId"]?.toString(),
    );
  }
}

class TopicMasteryItemModel {
  final String topicName;
  final double masteryPercentage;

  TopicMasteryItemModel({
    required this.topicName,
    required this.masteryPercentage,
  });
}

class StudyPlanStepModel {
  final int stepNumber;
  final String stepType;
  final String title;
  final int durationMinutes;
  final String reason;
  final int itemCount;
  final String? targetStudySetId;
  final String? targetTopic;

  StudyPlanStepModel({
    required this.stepNumber,
    required this.stepType,
    required this.title,
    required this.durationMinutes,
    required this.reason,
    required this.itemCount,
    this.targetStudySetId,
    this.targetTopic,
  });

  factory StudyPlanStepModel.fromJson(Map<String, dynamic> json) {
    return StudyPlanStepModel(
      stepNumber: (json["stepNumber"] as int?) ?? 1,
      stepType: json["stepType"]?.toString() ?? "retrieval_practice",
      title: json["title"]?.toString() ?? "Review",
      durationMinutes: (json["durationMinutes"] as int?) ?? 5,
      reason: json["reason"]?.toString() ?? "Reinforce memory retention.",
      itemCount: (json["itemCount"] as int?) ?? 5,
      targetStudySetId: json["targetStudySetId"]?.toString(),
      targetTopic: json["targetTopic"]?.toString(),
    );
  }
}

class ExplainableReadinessModel {
  final double overallReadinessPercent;
  final double questionAccuracyPercent;
  final double flashcardRetentionPercent;
  final int spacingDaysActive;
  final int unresolvedMistakesCount;
  final String summaryExplanation;
  final String? courseId;
  final String? courseName;
  final int? daysUntilExam;
  final List<TopicMasteryItemModel> topicMastery;

  ExplainableReadinessModel({
    required this.overallReadinessPercent,
    required this.questionAccuracyPercent,
    required this.flashcardRetentionPercent,
    required this.spacingDaysActive,
    required this.unresolvedMistakesCount,
    required this.summaryExplanation,
    this.courseId,
    this.courseName,
    this.daysUntilExam,
    this.topicMastery = const [],
  });

  double get readinessScore => overallReadinessPercent / 100.0;
  double get recentAccuracy => questionAccuracyPercent / 100.0;
  double get flashcardRetention => flashcardRetentionPercent / 100.0;
  double get spacingConsistencyScore => (spacingDaysActive / 7.0).clamp(0.0, 1.0);
  String get recommendationSummary => summaryExplanation;
  String get readinessStatus => overallReadinessPercent >= 80
      ? "Exam Ready"
      : (overallReadinessPercent >= 60 ? "Needs Review" : "High Priority");

  factory ExplainableReadinessModel.fromJson(Map<String, dynamic> json) {
    return ExplainableReadinessModel(
      overallReadinessPercent: (json["overallReadinessPercent"] as num?)?.toDouble() ?? 70.0,
      questionAccuracyPercent: (json["questionAccuracyPercent"] as num?)?.toDouble() ?? 70.0,
      flashcardRetentionPercent: (json["flashcardRetentionPercent"] as num?)?.toDouble() ?? 75.0,
      spacingDaysActive: (json["spacingDaysActive"] as int?) ?? 1,
      unresolvedMistakesCount: (json["unresolvedMistakesCount"] as int?) ?? 0,
      summaryExplanation: json["summaryExplanation"]?.toString() ??
          "Balanced retention based on active recall practice and spacing consistency.",
      courseId: json["courseId"]?.toString(),
      courseName: json["courseName"]?.toString(),
      daysUntilExam: json["daysUntilExam"] as int?,
      topicMastery: (json["topicMastery"] as List<dynamic>?)
              ?.map((t) => TopicMasteryItemModel(
                    topicName: t["topicName"]?.toString() ?? "Topic",
                    masteryPercentage: (t["masteryPercentage"] as num?)?.toDouble() ?? 0.5,
                  ))
              .toList() ??
          [],
    );
  }

  factory ExplainableReadinessModel.defaultEmpty() {
    return ExplainableReadinessModel(
      overallReadinessPercent: 65.0,
      questionAccuracyPercent: 70.0,
      flashcardRetentionPercent: 70.0,
      spacingDaysActive: 1,
      unresolvedMistakesCount: 0,
      summaryExplanation: "Begin practice sessions to calculate personalized readiness metrics.",
    );
  }
}

class MistakeBankItemModel {
  final String questionId;
  final String studySetId;
  final String studySetTitle;
  final String courseCode;
  final String courseName;
  final String prompt;
  final String type;
  final List<String> options;
  final String correctAnswer;
  final String explanation;
  final int missCount;
  final DateTime lastMissedAt;
  final String? lastSubmittedAnswer;
  final String misconceptionPattern;
  final bool isResolved;

  MistakeBankItemModel({
    required this.questionId,
    required this.studySetId,
    required this.studySetTitle,
    required this.courseCode,
    required this.courseName,
    required this.prompt,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.missCount,
    required this.lastMissedAt,
    this.lastSubmittedAnswer,
    required this.misconceptionPattern,
    required this.isResolved,
  });

  factory MistakeBankItemModel.fromJson(Map<String, dynamic> json) {
    return MistakeBankItemModel(
      questionId: json["questionId"]?.toString() ?? "",
      studySetId: json["studySetId"]?.toString() ?? "",
      studySetTitle: json["studySetTitle"]?.toString() ?? "Study Set",
      courseCode: json["courseCode"]?.toString() ?? "COURSE",
      courseName: json["courseName"]?.toString() ?? "General",
      prompt: json["prompt"]?.toString() ?? "",
      type: json["type"]?.toString() ?? "multiple_choice",
      options: (json["options"] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      correctAnswer: json["correctAnswer"]?.toString() ?? "",
      explanation: json["explanation"]?.toString() ?? "",
      missCount: (json["missCount"] as int?) ?? 1,
      lastMissedAt: DateTime.tryParse(json["lastMissedAt"] ?? "") ?? DateTime.now(),
      lastSubmittedAnswer: json["lastSubmittedAnswer"]?.toString(),
      misconceptionPattern: json["misconceptionPattern"]?.toString() ?? "Missed concept in practice.",
      isResolved: json["isResolved"] as bool? ?? false,
    );
  }
}

class SmartSessionPayloadModel {
  final String sessionTitle;
  final int estimatedMinutes;
  final List<SmartSessionFlashcardModel> flashcards;
  final List<SmartSessionQuestionModel> retrievalQuestions;
  final List<SmartSessionQuestionModel> mistakeDrillQuestions;

  SmartSessionPayloadModel({
    required this.sessionTitle,
    required this.estimatedMinutes,
    required this.flashcards,
    required this.retrievalQuestions,
    required this.mistakeDrillQuestions,
  });

  int get totalItems =>
      flashcards.length + retrievalQuestions.length + mistakeDrillQuestions.length;

  factory SmartSessionPayloadModel.fromJson(Map<String, dynamic> json) {
    return SmartSessionPayloadModel(
      sessionTitle: json["sessionTitle"]?.toString() ?? "⚡ Smart Study Session",
      estimatedMinutes: (json["estimatedMinutes"] as int?) ?? 25,
      flashcards: (json["flashcards"] as List<dynamic>?)
              ?.map((f) => SmartSessionFlashcardModel.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      retrievalQuestions: (json["retrievalQuestions"] as List<dynamic>?)
              ?.map((q) => SmartSessionQuestionModel.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
      mistakeDrillQuestions: (json["mistakeDrillQuestions"] as List<dynamic>?)
              ?.map((q) => SmartSessionQuestionModel.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SmartSessionFlashcardModel {
  final String questionId;
  final String studySetId;
  final String prompt;
  final String answer;
  final String dimensionTag;
  final String reasonWhy;

  SmartSessionFlashcardModel({
    required this.questionId,
    required this.studySetId,
    required this.prompt,
    required this.answer,
    required this.dimensionTag,
    required this.reasonWhy,
  });

  factory SmartSessionFlashcardModel.fromJson(Map<String, dynamic> json) {
    return SmartSessionFlashcardModel(
      questionId: json["questionId"]?.toString() ?? "",
      studySetId: json["studySetId"]?.toString() ?? "",
      prompt: json["prompt"]?.toString() ?? "",
      answer: json["answer"]?.toString() ?? "",
      dimensionTag: json["dimensionTag"]?.toString() ?? "CORE CONCEPT",
      reasonWhy: json["reasonWhy"]?.toString() ?? "Spaced retrieval prompt.",
    );
  }
}

class SmartSessionQuestionModel {
  final String questionId;
  final String studySetId;
  final String prompt;
  final String type;
  final List<SmartSessionOptionModel> options;
  final String correctAnswer;
  final String explanation;
  final String stageName;
  final String reasonWhy;

  SmartSessionQuestionModel({
    required this.questionId,
    required this.studySetId,
    required this.prompt,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.stageName,
    required this.reasonWhy,
  });

  factory SmartSessionQuestionModel.fromJson(Map<String, dynamic> json) {
    return SmartSessionQuestionModel(
      questionId: json["questionId"]?.toString() ?? "",
      studySetId: json["studySetId"]?.toString() ?? "",
      prompt: json["prompt"]?.toString() ?? "",
      type: json["type"]?.toString() ?? "multiple_choice",
      options: (json["options"] as List<dynamic>?)
              ?.map((o) => SmartSessionOptionModel.fromJson(o as Map<String, dynamic>))
              .toList() ??
          [],
      correctAnswer: json["correctAnswer"]?.toString() ?? "",
      explanation: json["explanation"]?.toString() ?? "",
      stageName: json["stageName"]?.toString() ?? "Retrieval Practice",
      reasonWhy: json["reasonWhy"]?.toString() ?? "Targeted concept mastery.",
    );
  }
}

class SmartSessionOptionModel {
  final String id;
  final String text;
  final bool isCorrect;
  final String? distractorRationale;

  SmartSessionOptionModel({
    required this.id,
    required this.text,
    required this.isCorrect,
    this.distractorRationale,
  });

  factory SmartSessionOptionModel.fromJson(Map<String, dynamic> json) {
    return SmartSessionOptionModel(
      id: json["id"]?.toString() ?? "",
      text: json["text"]?.toString() ?? "",
      isCorrect: json["isCorrect"] as bool? ?? false,
      distractorRationale: json["distractorRationale"]?.toString(),
    );
  }
}

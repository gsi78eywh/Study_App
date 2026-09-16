import 'dart:math' as math;

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

class StudentBrainProfileModel {
  final int coursesCount;
  final int activeSubjectsCount;
  final int upcomingDeadlinesCount;
  final int weakConceptsCount;
  final int masteredConceptsCount;
  final int pendingReviewsCount;
  final int upcomingExamsCount;
  final String priorityCourse;
  final String priorityCourseCode;
  final double priorityMasteryPercent;
  final String priorityWhy;
  final StudentBrainDailyAnswersModel dailyAnswers;

  StudentBrainProfileModel({
    required this.coursesCount,
    required this.activeSubjectsCount,
    required this.upcomingDeadlinesCount,
    required this.weakConceptsCount,
    required this.masteredConceptsCount,
    required this.pendingReviewsCount,
    required this.upcomingExamsCount,
    required this.priorityCourse,
    required this.priorityCourseCode,
    required this.priorityMasteryPercent,
    required this.priorityWhy,
    required this.dailyAnswers,
  });

  factory StudentBrainProfileModel.fromJson(Map<String, dynamic> json) {
    return StudentBrainProfileModel(
      coursesCount: (json["coursesCount"] as int?) ?? 0,
      activeSubjectsCount: (json["activeSubjectsCount"] as int?) ?? 0,
      upcomingDeadlinesCount: (json["upcomingDeadlinesCount"] as int?) ?? 0,
      weakConceptsCount: (json["weakConceptsCount"] as int?) ?? 0,
      masteredConceptsCount: (json["masteredConceptsCount"] as int?) ?? 0,
      pendingReviewsCount: (json["pendingReviewsCount"] as int?) ?? 0,
      upcomingExamsCount: (json["upcomingExamsCount"] as int?) ?? 0,
      priorityCourse: json["priorityCourse"]?.toString() ?? "General",
      priorityCourseCode: json["priorityCourseCode"]?.toString() ?? "COURSE",
      priorityMasteryPercent: (json["priorityMasteryPercent"] as num?)?.toDouble() ?? 50.0,
      priorityWhy: json["priorityWhy"]?.toString() ?? "Maintain consistent spacing practice.",
      dailyAnswers: json["dailyAnswers"] != null
          ? StudentBrainDailyAnswersModel.fromJson(json["dailyAnswers"] as Map<String, dynamic>)
          : StudentBrainDailyAnswersModel.defaultEmpty(),
    );
  }
}

class StudentBrainDailyAnswersModel {
  final String whatDoINeedToDo;
  final String whatShouldIStudy;
  final String whatAmIStrugglingWith;
  final String howCanILearnIt;
  final String whatShouldIDoNext;

  StudentBrainDailyAnswersModel({
    required this.whatDoINeedToDo,
    required this.whatShouldIStudy,
    required this.whatAmIStrugglingWith,
    required this.howCanILearnIt,
    required this.whatShouldIDoNext,
  });

  factory StudentBrainDailyAnswersModel.fromJson(Map<String, dynamic> json) {
    return StudentBrainDailyAnswersModel(
      whatDoINeedToDo: json["whatDoINeedToDo"]?.toString() ?? "Review spaced flashcards.",
      whatShouldIStudy: json["whatShouldIStudy"]?.toString() ?? "Focus on lowest mastery topics.",
      whatAmIStrugglingWith: json["whatAmIStrugglingWith"]?.toString() ?? "No severe misconceptions detected.",
      howCanILearnIt: json["howCanILearnIt"]?.toString() ?? "Follow retrieval and spacing practice.",
      whatShouldIDoNext: json["whatShouldIDoNext"]?.toString() ?? "Start today's Smart Session.",
    );
  }

  factory StudentBrainDailyAnswersModel.defaultEmpty() {
    return StudentBrainDailyAnswersModel(
      whatDoINeedToDo: "Organize academic goals and complete daily retrieval practice.",
      whatShouldIStudy: "Target lowest mastery areas first.",
      whatAmIStrugglingWith: "Check Mistake Bank for recurring error patterns.",
      howCanILearnIt: "Active recall -> targeted practice -> Socratic review.",
      whatShouldIDoNext: "Launch 25-Minute Smart Study Session.",
    );
  }
}

class AcademicTaskModel {
  final String id;
  final String? courseId;
  final String courseCode;
  final String title;
  final String type; // "assignment", "quiz", "project", "exam", "presentation"
  final DateTime dueDate;
  final String estimatedDifficulty;
  bool isCompleted;
  final List<String> actionSteps;

  AcademicTaskModel({
    required this.id,
    this.courseId,
    required this.courseCode,
    required this.title,
    required this.type,
    required this.dueDate,
    required this.estimatedDifficulty,
    required this.isCompleted,
    required this.actionSteps,
  });

  int get daysRemaining => math.max(0, dueDate.difference(DateTime.now()).inDays);

  factory AcademicTaskModel.fromJson(Map<String, dynamic> json) {
    return AcademicTaskModel(
      id: json["id"]?.toString() ?? "",
      courseId: json["courseId"]?.toString(),
      courseCode: json["courseCode"]?.toString() ?? "COURSE",
      title: json["title"]?.toString() ?? "Task",
      type: json["type"]?.toString() ?? "assignment",
      dueDate: DateTime.tryParse(json["dueDate"]?.toString() ?? "") ?? DateTime.now().add(const Duration(days: 3)),
      estimatedDifficulty: json["estimatedDifficulty"]?.toString() ?? "Medium",
      isCompleted: json["isCompleted"] as bool? ?? false,
      actionSteps: (json["actionSteps"] as List<dynamic>?)?.map((s) => s.toString()).toList() ?? [],
    );
  }
}

class BreakdownResponseModel {
  final String title;
  final List<String> actionSteps;
  final String strategySummary;

  BreakdownResponseModel({
    required this.title,
    required this.actionSteps,
    required this.strategySummary,
  });

  factory BreakdownResponseModel.fromJson(Map<String, dynamic> json) {
    return BreakdownResponseModel(
      title: json["title"]?.toString() ?? "Assignment",
      actionSteps: (json["actionSteps"] as List<dynamic>?)?.map((s) => s.toString()).toList() ?? [],
      strategySummary: json["strategySummary"]?.toString() ?? "Personalized milestone execution plan.",
    );
  }
}

class RecoveryPlanResponseModel {
  final int missedCount;
  final List<String> targetedTopics;
  final String recoveryAction;
  final int recommendedMinutes;
  final String message;

  RecoveryPlanResponseModel({
    required this.missedCount,
    required this.targetedTopics,
    required this.recoveryAction,
    required this.recommendedMinutes,
    required this.message,
  });

  factory RecoveryPlanResponseModel.fromJson(Map<String, dynamic> json) {
    return RecoveryPlanResponseModel(
      missedCount: (json["missedCount"] as int?) ?? 0,
      targetedTopics: (json["targetedTopics"] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [],
      recoveryAction: json["recoveryAction"]?.toString() ?? "Targeted retrieval practice",
      recommendedMinutes: (json["recommendedMinutes"] as int?) ?? 15,
      message: json["message"]?.toString() ?? "Recovery plan synthesized.",
    );
  }
}

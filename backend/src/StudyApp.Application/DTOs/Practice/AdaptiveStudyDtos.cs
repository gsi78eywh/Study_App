namespace StudyApp.Application.DTOs.Practice;

public record TodayStudyPlanDto(
    Guid? CourseId,
    string CourseName,
    string CourseCode,
    DateTime? ExamDate,
    int? DaysUntilExam,
    int TotalEstimatedMinutes,
    List<CoursePriorityDto> Priorities,
    List<StudyPlanStepDto> Steps,
    string AiRecommendation,
    ExplainableReadinessDto Readiness
);

public record CoursePriorityDto(
    string TopicName,
    decimal MasteryPercent,
    string Status,
    int MissedCount
);

public record StudyPlanStepDto(
    int StepNumber,
    string StepType,
    string Title,
    int DurationMinutes,
    string Reason,
    int ItemCount,
    Guid? TargetStudySetId,
    string? TargetTopic
);

public record ExplainableReadinessDto(
    decimal OverallReadinessPercent,
    decimal QuestionAccuracyPercent,
    decimal FlashcardRetentionPercent,
    int SpacingDaysActive,
    int UnresolvedMistakesCount,
    string SummaryExplanation
);

public record MistakeBankItemDto(
    Guid QuestionId,
    Guid StudySetId,
    string StudySetTitle,
    string CourseCode,
    string CourseName,
    string Prompt,
    string Type,
    List<string> Options,
    string CorrectAnswer,
    string Explanation,
    int MissCount,
    DateTime LastMissedAt,
    string? LastSubmittedAnswer,
    string MisconceptionPattern,
    bool IsResolved
);

public record SmartSessionPayloadDto(
    string SessionTitle,
    int EstimatedMinutes,
    List<SmartSessionFlashcardDto> Flashcards,
    List<SmartSessionQuestionDto> RetrievalQuestions,
    List<SmartSessionQuestionDto> MistakeDrillQuestions
);

public record SmartSessionFlashcardDto(
    Guid QuestionId,
    Guid StudySetId,
    string Prompt,
    string Answer,
    string DimensionTag,
    string ReasonWhy
);

public record SmartSessionOptionDto(
    Guid Id,
    string Text,
    bool IsCorrect,
    string? DistractorRationale
);

public record SmartSessionQuestionDto(
    Guid QuestionId,
    Guid StudySetId,
    string Prompt,
    string Type,
    List<SmartSessionOptionDto> Options,
    string CorrectAnswer,
    string Explanation,
    string StageName,
    string ReasonWhy
);

public record ResolveMistakeRequest(
    Guid QuestionId,
    bool IsResolved
);


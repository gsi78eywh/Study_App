namespace StudyApp.Application.DTOs.Ingestion;

public record GenerateFromTextRequest(
    Guid CourseId,
    string Title,
    string Content,
    List<string>? QuestionTypes, // "mcq", "identification", "enumeration", "bullet_points", "logical_thinking"
    int TargetCount = 15
);

public record GenerateFromUrlRequest(
    Guid CourseId,
    string Title,
    string Url,
    List<string>? QuestionTypes,
    int TargetCount = 15
);

public record GeneratedQuestionDto(
    string Type,
    string Prompt,
    List<string> Hints,
    string CorrectAnswer,
    List<GeneratedOptionDto>? Options,
    List<string>? ValidSynonyms,
    List<string>? EnumerationItems,
    bool IsOrdered,
    string Explanation,
    List<string>? ThinkingBreakdown,
    string? SourceReference = null
);

public record GeneratedOptionDto(string Text, bool IsCorrect, string? DistractorRationale);

public record GeneratedStudySetResult(
    Guid StudySetId,
    string Title,
    string Summary,
    List<string> HighYieldBulletPoints,
    List<GeneratedQuestionDto> Questions,
    string? ExtractedText = null
);

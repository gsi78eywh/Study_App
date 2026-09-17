namespace StudyApp.Application.DTOs.Ingestion;

public record GenerateFromTextRequest(
    Guid? CourseId = null,
    string Title = "",
    string Content = "",
    List<string>? QuestionTypes = null, // "mcq", "identification", "enumeration", "bullet_points", "logical_thinking"
    int TargetCount = 15,
    int SetIndex = 0,
    string? Variant = null,
    string? ApiKey = null
);

public record GenerateFromUrlRequest(
    Guid? CourseId = null,
    string Title = "",
    string Url = "",
    List<string>? QuestionTypes = null,
    int TargetCount = 15,
    int SetIndex = 0,
    string? Variant = null
);

public record ScanUrlRequest(string Url);

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

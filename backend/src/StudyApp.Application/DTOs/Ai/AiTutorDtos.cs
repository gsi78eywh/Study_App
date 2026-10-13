namespace StudyApp.Application.DTOs.Ai;

public record ChatMessageDto(
    string Role, // "user" or "assistant"
    string Content
);

public record AskTutorRequest(
    string Message,
    string? ContextTopic = null,
    List<ChatMessageDto>? History = null,
    string? ApiKey = null,
    bool IsSocraticMode = false,
    bool IsTeachMeMode = false,
    string? WeakConceptsContext = null,
    string? RecentMistakesContext = null,
    string? StudySetId = null,
    string? CourseId = null
);

public record AskTutorResponse(
    string Reply,
    string ModelUsed,
    DateTime Timestamp,
    double LatencySeconds = 0.0,
    int? TokenCount = null,
    bool NotesAttached = false,
    List<GroundedSource>? Sources = null
);

public record GroundedSource(string Title, string Url);

public record TutorStatusResponse(
    bool Online,
    string Engine,
    string Model,
    double LatencyMs = 0.0,
    string? Message = null
)
{
    public bool Reachable => Online;
}

public record ExplainQuestionRequest(
    string Prompt,
    string CorrectAnswer,
    string? StudentAnswer = null,
    string? SubjectContext = null,
    string? ApiKey = null
);

public record QuestionExplanationResult(
    string CoreConcept,
    string WhyCorrect,
    string? WhyStudentWasIncorrect,
    string TakeawayTip
);

public record OpenAnswerEvaluationResult(
    decimal Score,
    string Feedback,
    bool IsAiEvaluation
);

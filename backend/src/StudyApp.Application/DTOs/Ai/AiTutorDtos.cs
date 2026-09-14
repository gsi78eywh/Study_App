namespace StudyApp.Application.DTOs.Ai;

public record ChatMessageDto(
    string Role, // "user" or "assistant"
    string Content
);

public record AskTutorRequest(
    string Message,
    string? ContextTopic = null,
    List<ChatMessageDto>? History = null,
    string? ApiKey = null
);

public record AskTutorResponse(
    string Reply,
    string ModelUsed,
    DateTime Timestamp
);

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

using StudyApp.Application.DTOs.Ai;

namespace StudyApp.Application.Common.Interfaces;

public interface IAiTutorService
{
    Task<AskTutorResponse> AskTutorAsync(
        AskTutorRequest request,
        CancellationToken cancellationToken = default);

    Task<QuestionExplanationResult> ExplainQuestionAsync(
        ExplainQuestionRequest request,
        CancellationToken cancellationToken = default);

    Task<OpenAnswerEvaluationResult> EvaluateOpenAnswerAsync(
        string prompt,
        string modelAnswer,
        IReadOnlyList<string> rubric,
        string studentAnswer,
        CancellationToken cancellationToken = default);

    Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default);
}

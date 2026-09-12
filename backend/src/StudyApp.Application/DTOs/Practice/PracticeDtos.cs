using StudyApp.Domain.Enums;

namespace StudyApp.Application.DTOs.Practice;

/// <summary>
/// A server-authoritative submission.  <see cref="Answer"/> may be an option id,
/// free text, a delimited enumeration, or a JSON object for matching questions.
/// </summary>
public record PracticeAnswerRequest(Guid QuestionId, string Answer, int? RecallRating = null);

public record CompletePracticeSessionRequest(
    Guid StudySetId,
    StudyMode Mode,
    int TimeSpentSeconds,
    List<PracticeAnswerRequest> Answers);

public record AnswerGradeDto(
    Guid QuestionId,
    bool IsCorrect,
    decimal PartialScore,
    string Feedback,
    string CorrectAnswer,
    DateTime? NextReviewAt = null);

public record CompletePracticeSessionResponse(
    Guid SessionId,
    int Score,
    int TotalQuestions,
    decimal ScorePercent,
    List<AnswerGradeDto> Answers);

public record WeakSpotDto(
    Guid QuestionId,
    Guid StudySetId,
    string Prompt,
    QuestionType Type,
    int Attempts,
    int Misses,
    decimal AccuracyPercent);

public record MasteryTopicDto(
    Guid StudySetId,
    string Title,
    int Attempts,
    int Correct,
    decimal AccuracyPercent,
    string Status);

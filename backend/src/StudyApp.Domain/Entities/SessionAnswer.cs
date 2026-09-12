namespace StudyApp.Domain.Entities;

public class SessionAnswer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid TestSessionId { get; set; }
    public Guid QuestionId { get; set; }
    public string UserSubmittedAnswer { get; set; } = string.Empty;
    public bool IsCorrect { get; set; } = false;
    public decimal PartialScore { get; set; } = 0m;
    public string? AiFeedback { get; set; }

    public TestSession? TestSession { get; set; }
    public Question? Question { get; set; }
}

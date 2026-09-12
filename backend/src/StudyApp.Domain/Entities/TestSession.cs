using StudyApp.Domain.Enums;

namespace StudyApp.Domain.Entities;

public class TestSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StudySetId { get; set; }
    public StudyMode Mode { get; set; }
    public int Score { get; set; } = 0;
    public int TotalQuestions { get; set; } = 0;
    public int TimeSpentSeconds { get; set; } = 0;
    public DateTime CompletedAt { get; set; } = DateTime.UtcNow;

    public StudySet? StudySet { get; set; }
    public ICollection<SessionAnswer> Answers { get; set; } = new List<SessionAnswer>();
}

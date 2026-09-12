namespace StudyApp.Domain.Entities;

public class StudySet
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CourseId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public Course? Course { get; set; }
    public ICollection<Question> Questions { get; set; } = new List<Question>();
    public ICollection<SourceDocument> SourceDocuments { get; set; } = new List<SourceDocument>();
    public ICollection<TestSession> TestSessions { get; set; } = new List<TestSession>();
}

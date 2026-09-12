namespace StudyApp.Domain.Entities;

public class Course
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string ColorHex { get; set; } = "#4F46E5";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public User? User { get; set; }
    public ICollection<StudySet> StudySets { get; set; } = new List<StudySet>();
    public ICollection<NotebookPage> NotebookPages { get; set; } = new List<NotebookPage>();
}

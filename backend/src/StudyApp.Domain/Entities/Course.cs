namespace StudyApp.Domain.Entities;

public class Course
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string ColorHex { get; set; } = "#4F46E5";
    public DateTime? ExamDate { get; set; }
    public string? ExamTitle { get; set; }
    public double Units { get; set; } = 3.0;
    public double TargetGrade { get; set; } = 1.5;
    public double? PrelimGrade { get; set; }
    public double? MidtermGrade { get; set; }
    public double? SemiFinalGrade { get; set; }
    public double? FinalGrade { get; set; }
    public double PrelimWeight { get; set; } = 0.20;
    public double MidtermWeight { get; set; } = 0.20;
    public double SemiFinalWeight { get; set; } = 0.20;
    public double FinalWeight { get; set; } = 0.40;
    public string GradingScale { get; set; } = "USJ-R";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public User? User { get; set; }
    public ICollection<StudySet> StudySets { get; set; } = new List<StudySet>();
    public ICollection<NotebookPage> NotebookPages { get; set; } = new List<NotebookPage>();
}

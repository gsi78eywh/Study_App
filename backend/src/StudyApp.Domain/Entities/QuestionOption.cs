namespace StudyApp.Domain.Entities;

public class QuestionOption
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid QuestionId { get; set; }
    public string OptionText { get; set; } = string.Empty;
    public bool IsCorrect { get; set; }
    public string? DistractorRationale { get; set; }

    public Question? Question { get; set; }
}

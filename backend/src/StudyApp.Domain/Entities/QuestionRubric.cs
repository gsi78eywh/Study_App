namespace StudyApp.Domain.Entities;

public class QuestionRubric
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid QuestionId { get; set; }
    public string ItemText { get; set; } = string.Empty;
    public int Points { get; set; } = 1;
    public int SortOrder { get; set; } = 0;
    public bool IsRequired { get; set; } = false;

    public Question? Question { get; set; }
}

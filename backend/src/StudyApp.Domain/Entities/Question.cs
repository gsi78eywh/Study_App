using StudyApp.Domain.Enums;

namespace StudyApp.Domain.Entities;

public class Question
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StudySetId { get; set; }
    public QuestionType Type { get; set; }
    public string Prompt { get; set; } = string.Empty;
    public string HintsJson { get; set; } = "[]";
    public string Explanation { get; set; } = string.Empty;
    public string? ThinkingBreakdownJson { get; set; }
    public int Difficulty { get; set; } = 1;
    public int SortOrder { get; set; } = 0;

    public StudySet? StudySet { get; set; }
    public ICollection<QuestionOption> Options { get; set; } = new List<QuestionOption>();
    public ICollection<QuestionRubric> Rubrics { get; set; } = new List<QuestionRubric>();
}

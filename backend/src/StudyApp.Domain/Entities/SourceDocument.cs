using StudyApp.Domain.Enums;

namespace StudyApp.Domain.Entities;

public class SourceDocument
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StudySetId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FileType { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public DocumentStatus Status { get; set; } = DocumentStatus.Uploading;
    public string? ExtractedText { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public StudySet? StudySet { get; set; }
}

namespace StudyApp.Domain.Entities;

/// <summary>A database-backed, application-wide branding resource.</summary>
public sealed class AppBrandAsset
{
    public string Key { get; set; } = string.Empty;
    public string ContentType { get; set; } = "image/svg+xml";
    public string Content { get; set; } = string.Empty;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

using StudyApp.Application.DTOs.Ingestion;

namespace StudyApp.Application.Common.Interfaces;

public interface IAiQuestionGenerator
{
    Task<GeneratedStudySetResult> GenerateStudySetAsync(
        string rawText,
        string title,
        List<string> requestedTypes,
        int targetCount,
        CancellationToken cancellationToken = default);

    Task<GeneratedStudySetResult> GenerateStudySetFromImageAsync(
        byte[] imageBytes,
        string mimeType,
        string title,
        int targetCount,
        CancellationToken cancellationToken = default);
}

public interface IDocumentExtractor
{
    Task<string> ExtractPdfTextAsync(Stream pdfStream, CancellationToken cancellationToken = default);
    Task<string> ExtractDocxTextAsync(Stream docxStream, CancellationToken cancellationToken = default);
    Task<string> ExtractUrlContentAsync(string url, CancellationToken cancellationToken = default);
}
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ingestion;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/ingestion")]
[Authorize]
public class IngestionController : ControllerBase
{
    private readonly IAiQuestionGenerator _aiGenerator;
    private readonly IDocumentExtractor _documentExtractor;
    private readonly IApplicationDbContext _context;

    public IngestionController(
        IAiQuestionGenerator aiGenerator,
        IDocumentExtractor documentExtractor,
        IApplicationDbContext context)
    {
        _aiGenerator = aiGenerator;
        _documentExtractor = documentExtractor;
        _context = context;
    }

    [HttpPost("text")]
    public async Task<IActionResult> GenerateFromText([FromBody] GenerateFromTextRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new { message = "Content cannot be empty." });
        }

        var result = await _aiGenerator.GenerateStudySetAsync(
            request.Content,
            request.Title,
            request.QuestionTypes ?? new List<string>(),
            request.TargetCount);

        var studySet = await SaveGeneratedSetAsync(request.CourseId, result);
        return Ok(new { studySet.Id, studySet.Title, result.Summary, result.HighYieldBulletPoints, QuestionCount = studySet.Questions.Count });
    }

    [HttpPost("file")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> GenerateFromFile([FromForm] IFormFile file, [FromForm] Guid courseId, [FromForm] string? title)
    {
        if (file == null || file.Length == 0)
        {
            return BadRequest(new { message = "Please select a valid file." });
        }

        if (file.Length > 30 * 1024 * 1024)
        {
            return BadRequest(new { message = "File exceeds 30MB limit." });
        }

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var setHeader = title ?? Path.GetFileNameWithoutExtension(file.FileName);
        GeneratedStudySetResult result;

        using var stream = file.OpenReadStream();

        if (ext is ".png" or ".jpg" or ".jpeg" or ".webp")
        {
            // Multimodal Whiteboard / Handwritten Note / Textbook Photo Analysis
            using var ms = new MemoryStream();
            await stream.CopyToAsync(ms);
            var mimeType = ext switch
            {
                ".png" => "image/png",
                ".webp" => "image/webp",
                _ => "image/jpeg"
            };
            result = await _aiGenerator.GenerateStudySetFromImageAsync(ms.ToArray(), mimeType, setHeader, 10);
        }
        else if (ext == ".pdf")
        {
            var extractedText = await _documentExtractor.ExtractPdfTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, new List<string>(), 15);
        }
        else if (ext == ".docx")
        {
            var extractedText = await _documentExtractor.ExtractDocxTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, new List<string>(), 15);
        }
        else if (ext is ".txt" or ".md")
        {
            using var reader = new StreamReader(stream);
            var extractedText = await reader.ReadToEndAsync();
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, new List<string>(), 15);
        }
        else
        {
            return BadRequest(new { message = "Unsupported file type. Please upload a PDF, DOCX, TXT, or Image file (.png, .jpg, .jpeg, .webp)." });
        }

        var studySet = await SaveGeneratedSetAsync(courseId, result);
        return Ok(new { studySet.Id, studySet.Title, result.Summary, result.HighYieldBulletPoints, QuestionCount = studySet.Questions.Count });
    }

    [HttpPost("url")]
    public async Task<IActionResult> GenerateFromUrl([FromBody] GenerateFromUrlRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Url))
        {
            return BadRequest(new { message = "URL cannot be empty." });
        }

        var extractedText = await _documentExtractor.ExtractUrlContentAsync(request.Url);
        var result = await _aiGenerator.GenerateStudySetAsync(extractedText, request.Title, request.QuestionTypes ?? new List<string>(), request.TargetCount);

        var studySet = await SaveGeneratedSetAsync(request.CourseId, result);
        return Ok(new { studySet.Id, studySet.Title, result.Summary, result.HighYieldBulletPoints, QuestionCount = studySet.Questions.Count });
    }

    private async Task<StudySet> SaveGeneratedSetAsync(Guid courseId, GeneratedStudySetResult result)
    {
        var studySet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = courseId,
            Title = result.Title,
            Description = result.Summary,
            CreatedAt = DateTime.UtcNow
        };

        int sort = 1;
        foreach (var q in result.Questions)
        {
            var qType = q.Type.ToLower() switch
            {
                "multiple_choice" => QuestionType.MultipleChoice,
                "identification" => QuestionType.Identification,
                "enumeration" => QuestionType.Enumeration,
                "bullet_points" => QuestionType.BulletPoints,
                "logical_thinking" => QuestionType.LogicalThinking,
                _ => QuestionType.MultipleChoice
            };

            var question = new Question
            {
                Id = Guid.NewGuid(),
                StudySetId = studySet.Id,
                Type = qType,
                Prompt = q.Prompt,
                HintsJson = JsonSerializer.Serialize(q.Hints),
                Explanation = q.Explanation,
                ThinkingBreakdownJson = q.ThinkingBreakdown != null ? JsonSerializer.Serialize(q.ThinkingBreakdown) : null,
                Difficulty = 2,
                SortOrder = sort++
            };

            if (q.Options != null)
            {
                foreach (var opt in q.Options)
                {
                    question.Options.Add(new QuestionOption
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        OptionText = opt.Text,
                        IsCorrect = opt.IsCorrect,
                        DistractorRationale = opt.DistractorRationale
                    });
                }
            }

            studySet.Questions.Add(question);
        }

        _context.StudySets.Add(studySet);
        await _context.SaveChangesAsync();

        return studySet;
    }
}

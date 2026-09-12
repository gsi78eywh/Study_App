using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

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
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count
        });
    }

    [HttpPost("file")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> GenerateFromFile(
        [FromForm] IFormFile file,
        [FromForm] Guid courseId,
        [FromForm] string? title,
        [FromForm] string? questionTypes,
        [FromForm] int? targetCount)
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
        var setHeader = !string.IsNullOrWhiteSpace(title) ? title.Trim() : Path.GetFileNameWithoutExtension(file.FileName);
        var targetNum = targetCount.HasValue && targetCount.Value >= 4 ? targetCount.Value : 10;
        
        var typesList = !string.IsNullOrWhiteSpace(questionTypes)
            ? questionTypes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
            : new List<string>();

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
            result = await _aiGenerator.GenerateStudySetFromImageAsync(ms.ToArray(), mimeType, setHeader, typesList, targetNum);
        }
        else if (ext == ".pdf")
        {
            var extractedText = await _documentExtractor.ExtractPdfTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, typesList, targetNum);
        }
        else if (ext == ".docx")
        {
            var extractedText = await _documentExtractor.ExtractDocxTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, typesList, targetNum);
        }
        else if (ext is ".txt" or ".md")
        {
            using var reader = new StreamReader(stream);
            var extractedText = await reader.ReadToEndAsync();
            result = await _aiGenerator.GenerateStudySetAsync(extractedText, setHeader, typesList, targetNum);
        }
        else
        {
            return BadRequest(new { message = "Unsupported file type. Please upload a PDF, DOCX, TXT, or Image file (.png, .jpg, .jpeg, .webp)." });
        }

        var studySet = await SaveGeneratedSetAsync(courseId, result);
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count
        });
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
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count
        });
    }

    [HttpGet("/api/v1/studysets/{id:guid}/questions")]
    public async Task<IActionResult> GetStudySetQuestions(Guid id)
    {
        var setExists = await _context.StudySets.AnyAsync(s => s.Id == id);
        if (!setExists) return NotFound(new { message = "Study set not found." });

        var questions = await _context.Questions
            .Where(q => q.StudySetId == id)
            .Include(q => q.Options)
            .OrderBy(q => q.SortOrder)
            .ToListAsync();

        var dtos = questions.Select(q => new
        {
            Id = q.Id.ToString(),
            StudySetId = q.StudySetId.ToString(),
            Type = q.Type.ToString(),
            q.Prompt,
            Hints = !string.IsNullOrEmpty(q.HintsJson) ? JsonSerializer.Deserialize<List<string>>(q.HintsJson, JsonOptions) : new List<string>(),
            q.Explanation,
            Options = q.Options.Select(o => new
            {
                Id = o.Id.ToString(),
                OptionText = o.OptionText,
                IsCorrect = o.IsCorrect,
                DistractorRationale = o.DistractorRationale
            }).ToList()
        }).ToList();

        return Ok(dtos);
    }

    [HttpDelete("/api/v1/studysets/{id:guid}")]
    public async Task<IActionResult> DeleteStudySet(Guid id)
    {
        var set = await _context.StudySets
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (set == null) return NotFound(new { message = "Study set not found." });

        if (set.Questions != null && set.Questions.Any())
        {
            _context.Questions.RemoveRange(set.Questions);
        }
        _context.StudySets.Remove(set);
        await _context.SaveChangesAsync();

        return Ok(new { message = "Study set deleted successfully.", id = id.ToString() });
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
            var qType = q.Type.ToLowerInvariant() switch
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

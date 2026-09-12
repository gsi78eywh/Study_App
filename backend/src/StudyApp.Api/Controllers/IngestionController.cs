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
        if (request.CourseId == Guid.Empty || string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new { message = "A course and non-empty content are required." });
        }
        if (!await OwnsCourseAsync(request.CourseId)) return NotFound(new { message = "Course not found." });

        var sourceText = LimitSourceText(request.Content);
        var result = await _aiGenerator.GenerateStudySetAsync(
            sourceText,
            CleanTitle(request.Title),
            request.QuestionTypes ?? new List<string>(),
            ClampTargetCount(request.TargetCount));

        var studySet = await SaveGeneratedSetAsync(request.CourseId, result, "Manual note input", "text/markdown", sourceText);
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
        if (courseId == Guid.Empty) return BadRequest(new { message = "A course is required." });
        if (!await OwnsCourseAsync(courseId)) return NotFound(new { message = "Course not found." });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var setHeader = CleanTitle(!string.IsNullOrWhiteSpace(title) ? title : Path.GetFileNameWithoutExtension(file.FileName));
        var targetNum = ClampTargetCount(targetCount ?? 10);

        var typesList = !string.IsNullOrWhiteSpace(questionTypes)
            ? questionTypes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
            : new List<string>();

        GeneratedStudySetResult result;
        string? extractedSourceText = null;

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
            extractedSourceText = await _documentExtractor.ExtractPdfTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedSourceText, setHeader, typesList, targetNum);
        }
        else if (ext == ".docx")
        {
            extractedSourceText = await _documentExtractor.ExtractDocxTextAsync(stream);
            result = await _aiGenerator.GenerateStudySetAsync(extractedSourceText, setHeader, typesList, targetNum);
        }
        else if (ext is ".txt" or ".md")
        {
            using var reader = new StreamReader(stream);
            extractedSourceText = LimitSourceText(await reader.ReadToEndAsync());
            result = await _aiGenerator.GenerateStudySetAsync(extractedSourceText, setHeader, typesList, targetNum);
        }
        else
        {
            return BadRequest(new { message = "Unsupported file type. Please upload a PDF, DOCX, TXT, or Image file (.png, .jpg, .jpeg, .webp)." });
        }

        var studySet = await SaveGeneratedSetAsync(courseId, result, file.FileName, ext, extractedSourceText);
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
        if (request.CourseId == Guid.Empty || string.IsNullOrWhiteSpace(request.Url))
        {
            return BadRequest(new { message = "A course and URL are required." });
        }
        if (!Uri.TryCreate(request.Url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
        {
            return BadRequest(new { message = "Only valid HTTP(S) URLs can be imported." });
        }
        if (!await OwnsCourseAsync(request.CourseId)) return NotFound(new { message = "Course not found." });

        string extractedText;
        try
        {
            extractedText = await _documentExtractor.ExtractUrlContentAsync(uri.ToString());
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        if (string.IsNullOrWhiteSpace(extractedText))
        {
            return BadRequest(new { message = "No readable study text was found at that URL." });
        }
        var result = await _aiGenerator.GenerateStudySetAsync(extractedText, CleanTitle(request.Title), request.QuestionTypes ?? new List<string>(), ClampTargetCount(request.TargetCount));

        var studySet = await SaveGeneratedSetAsync(request.CourseId, result, uri.ToString(), "text/html", extractedText);
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
        var setExists = await _context.StudySets.AnyAsync(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId());
        if (!setExists) return NotFound(new { message = "Study set not found." });

        var questions = await _context.Questions
            .Where(q => q.StudySetId == id)
            .Include(q => q.Options)
            .Include(q => q.Rubrics)
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
            SourceReference = ReadSourceReference(q.ThinkingBreakdownJson),
            MatchingPairs = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics) : null,
            q.Difficulty,
            q.SortOrder,
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
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId())
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

    [HttpGet("/api/v1/studysets/{id:guid}/sources")]
    public async Task<IActionResult> GetStudySetSources(Guid id)
    {
        var ownsSet = await _context.StudySets.AnyAsync(set => set.Id == id && set.Course != null && set.Course.UserId == CurrentUserId());
        if (!ownsSet) return NotFound(new { message = "Study set not found." });

        var sources = await _context.SourceDocuments
            .Where(source => source.StudySetId == id)
            .OrderBy(source => source.CreatedAt)
            .Select(source => new
            {
                source.Id,
                source.FileName,
                source.FileType,
                source.FileUrl,
                source.Status,
                source.CreatedAt,
                HasExtractedText = !string.IsNullOrEmpty(source.ExtractedText)
            })
            .ToListAsync();
        return Ok(sources);
    }

    private async Task<StudySet> SaveGeneratedSetAsync(
        Guid courseId,
        GeneratedStudySetResult result,
        string? sourceName = null,
        string? sourceType = null,
        string? extractedText = null)
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
                "multiple_choice" or "multiplechoice" or "mcq" => QuestionType.MultipleChoice,
                "identification" or "identify" => QuestionType.Identification,
                "enumeration" or "enumerate" => QuestionType.Enumeration,
                "bullet_points" or "bulletpoints" or "summary" => QuestionType.BulletPoints,
                "logical_thinking" or "logicalthinking" => QuestionType.LogicalThinking,
                "cloze" or "fill_in" or "fillintheblank" or "cloze_deletion" => QuestionType.Cloze,
                "true_false" or "truefalse" or "tf" => QuestionType.TrueFalse,
                "matching" or "matching_type" or "matchingtype" => QuestionType.Matching,
                "short_answer" or "shortanswer" or "short" => QuestionType.ShortAnswer,
                "scenario" or "scenario_drills" or "casestudy" => QuestionType.Scenario,
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
                // Keep answer-order metadata with the private question metadata; the
                // player only receives the presentation hints and cannot alter grading.
                ThinkingBreakdownJson = JsonSerializer.Serialize(new
                {
                    steps = q.ThinkingBreakdown,
                    isOrdered = q.IsOrdered,
                    sourceReference = q.SourceReference
                }),
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

            // Typed answers, cloze deletions and open response questions still need
            // a durable answer key even though they do not render as a list of choices.
            if (!question.Options.Any(option => option.IsCorrect) && !string.IsNullOrWhiteSpace(q.CorrectAnswer))
            {
                question.Options.Add(new QuestionOption
                {
                    Id = Guid.NewGuid(),
                    QuestionId = question.Id,
                    OptionText = q.CorrectAnswer.Trim(),
                    IsCorrect = true
                });
            }

            // Synonyms are accepted by identification and cloze grading without
            // changing the visible question. Duplicate values are intentionally skipped.
            foreach (var synonym in qType is QuestionType.Identification or QuestionType.Cloze
                         ? q.ValidSynonyms ?? Enumerable.Empty<string>()
                         : Enumerable.Empty<string>())
            {
                if (string.IsNullOrWhiteSpace(synonym) || question.Options.Any(o => string.Equals(o.OptionText, synonym.Trim(), StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                question.Options.Add(new QuestionOption
                {
                    Id = Guid.NewGuid(),
                    QuestionId = question.Id,
                    OptionText = synonym.Trim(),
                    IsCorrect = true
                });
            }

            if (qType is QuestionType.Enumeration or QuestionType.BulletPoints)
            {
                var enumerationItems = q.EnumerationItems?.Where(item => !string.IsNullOrWhiteSpace(item)).ToList()
                    ?? SplitEnumerationAnswer(q.CorrectAnswer);
                var itemOrder = 1;
                foreach (var item in enumerationItems.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = item.Trim(),
                        Points = 1,
                        SortOrder = itemOrder++,
                        IsRequired = true
                    });
                }
            }
            else if (qType == QuestionType.Matching)
            {
                foreach (var pair in ParseMatchingPairs(q.CorrectAnswer))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = JsonSerializer.Serialize(pair),
                        Points = 1,
                        SortOrder = question.Rubrics.Count + 1,
                        IsRequired = true
                    });
                }
            }
            else if (qType is QuestionType.ShortAnswer or QuestionType.LogicalThinking ||
                     qType == QuestionType.Scenario && !question.Options.Any(option => !option.IsCorrect))
            {
                var rubricOrder = 1;
                foreach (var keyword in q.Hints.Where(item => !string.IsNullOrWhiteSpace(item)).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = keyword.Trim(),
                        Points = 1,
                        SortOrder = rubricOrder++,
                        IsRequired = false
                    });
                }
            }

            studySet.Questions.Add(question);
        }

        if (!string.IsNullOrWhiteSpace(sourceName))
        {
            studySet.SourceDocuments.Add(new SourceDocument
            {
                Id = Guid.NewGuid(),
                StudySetId = studySet.Id,
                FileName = sourceName,
                FileType = sourceType ?? "text/plain",
                FileUrl = sourceType == "text/html" ? sourceName : string.Empty,
                ExtractedText = extractedText,
                Status = DocumentStatus.Ready,
                CreatedAt = DateTime.UtcNow
            });
        }

        _context.StudySets.Add(studySet);
        await _context.SaveChangesAsync();

        return studySet;
    }

    private static List<string> SplitEnumerationAnswer(string answer) =>
        System.Text.RegularExpressions.Regex.Split(answer ?? string.Empty, @"(?:\r?\n|,|;|\||\s+\d+[.)]\s*)")
            .Select(item => System.Text.RegularExpressions.Regex.Replace(item, @"^\s*(?:[-*â€¢]|\d+[.)])\s*", string.Empty).Trim())
            .Where(item => item.Length > 0)
            .ToList();

    private static List<MatchingPair> ParseMatchingPairs(string answer)
    {
        if (string.IsNullOrWhiteSpace(answer)) return new List<MatchingPair>();
        try
        {
            var pairs = JsonSerializer.Deserialize<List<MatchingPair>>(answer, JsonOptions);
            return pairs?.Where(pair => !string.IsNullOrWhiteSpace(pair.Term) && !string.IsNullOrWhiteSpace(pair.Definition)).ToList()
                ?? new List<MatchingPair>();
        }
        catch (JsonException)
        {
            return new List<MatchingPair>();
        }
    }

    private sealed record MatchingPair(string Term, string Definition);

    private static List<MatchingPair> ReadMatchingPairs(IEnumerable<QuestionRubric> rubrics) =>
        rubrics.OrderBy(rubric => rubric.SortOrder)
            .Select(rubric => ParseMatchingPairs($"[{rubric.ItemText}]").FirstOrDefault())
            .Where(pair => pair is not null)
            .Cast<MatchingPair>()
            .ToList();

    private static string? ReadSourceReference(string? metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata)) return null;
        try
        {
            using var document = JsonDocument.Parse(metadata);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("sourceReference", out var reference)
                ? reference.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private Guid? CurrentUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    private async Task<bool> OwnsCourseAsync(Guid courseId)
    {
        var userId = CurrentUserId();
        return userId.HasValue && await _context.Courses.AnyAsync(course => course.Id == courseId && course.UserId == userId.Value);
    }

    private static int ClampTargetCount(int targetCount) => Math.Clamp(targetCount, 4, 50);

    private static string CleanTitle(string? title)
    {
        var cleaned = (title ?? string.Empty).Trim();
        return string.IsNullOrWhiteSpace(cleaned) ? "Untitled study set" : cleaned[..Math.Min(cleaned.Length, 160)];
    }

    private static string LimitSourceText(string content)
    {
        const int maxCharacters = 150_000;
        return content.Length <= maxCharacters ? content : $"{content[..maxCharacters]}\n\n[Content truncated at {maxCharacters:N0} characters]";
    }
}

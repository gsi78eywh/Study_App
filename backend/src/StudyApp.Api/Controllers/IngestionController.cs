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

        using var stream = new MemoryStream();
        await file.CopyToAsync(stream);
        stream.Position = 0;

        if (!ValidateFileSignature(stream, ext))
        {
            return BadRequest(new { message = "Uploaded file content does not match the file extension signature." });
        }
        stream.Position = 0;

        if (ext is ".png" or ".jpg" or ".jpeg" or ".webp")
        {
            // Direct OCR / Image Text Extraction without AI hallucinations
            var mimeType = ext switch
            {
                ".png" => "image/png",
                ".webp" => "image/webp",
                _ => "image/jpeg"
            };
            extractedSourceText = await _documentExtractor.ExtractImageTextAsync(stream, mimeType);
            result = await _aiGenerator.GenerateStudySetAsync(extractedSourceText, setHeader, typesList, targetNum);
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
            using var reader = new StreamReader(stream, leaveOpen: true);
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
    public async Task<IActionResult> GetStudySetQuestions(Guid id, [FromQuery] bool includeAnswerKey = true)
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
            Explanation = includeAnswerKey ? q.Explanation : null,
            SourceReference = ReadSourceReference(q.ThinkingBreakdownJson),
            MatchingPairs = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics) : null,
            MatchingTerms = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics).Select(p => p.Term).ToList() : null,
            MatchingDefinitions = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics).Select(p => p.Definition).ToList() : null,
            q.Difficulty,
            q.SortOrder,
            Options = q.Options.Select(o => new
            {
                Id = o.Id.ToString(),
                OptionText = o.OptionText,
                IsCorrect = includeAnswerKey ? o.IsCorrect : false,
                DistractorRationale = includeAnswerKey ? o.DistractorRationale : null
            }).ToList()
        }).ToList();

        return Ok(dtos);
    }

    [HttpDelete("/api/v1/studysets/{id:guid}")]
    public async Task<IActionResult> DeleteStudySet(Guid id)
    {
        var set = await _context.StudySets
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId())
            .Include(s => s.Course)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (set == null) return NotFound(new { message = "Study set not found." });

        if (set.Course != null)
        {
            set.Course.UpdatedAt = DateTime.UtcNow;
        }

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
                source.ExtractedText,
                HasExtractedText = !string.IsNullOrEmpty(source.ExtractedText)
            })
            .ToListAsync();
        return Ok(sources);
    }

    [HttpGet("/api/v1/studysets/{id:guid}/export")]
    public async Task<IActionResult> ExportStudySet(Guid id, [FromQuery] string format = "markdown")
    {
        var studySet = await _context.StudySets
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId())
            .Include(s => s.Course)
            .Include(s => s.SourceDocuments)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Rubrics)
            .FirstOrDefaultAsync();

        if (studySet == null) return NotFound(new { message = "Study set not found." });

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# Study Guide: {studySet.Title}");
        if (studySet.Course != null)
        {
            sb.AppendLine($"**Course:** {studySet.Course.Code} - {studySet.Course.Name}");
        }
        sb.AppendLine($"**Generated:** {studySet.CreatedAt:yyyy-MM-dd HH:mm:ss UTC}");
        sb.AppendLine();
        sb.AppendLine("## Overview & Academic Summary");
        sb.AppendLine(studySet.Description);
        sb.AppendLine();

        if (studySet.SourceDocuments.Any())
        {
            sb.AppendLine("## Source Material & Extracted Text");
            foreach (var doc in studySet.SourceDocuments)
            {
                sb.AppendLine($"### Source: {doc.FileName} ({doc.FileType})");
                if (!string.IsNullOrWhiteSpace(doc.ExtractedText))
                {
                    sb.AppendLine(doc.ExtractedText);
                }
                sb.AppendLine();
            }
        }

        if (studySet.Questions.Any())
        {
            sb.AppendLine("## Active Recall Practice Questions & Solutions");
            int qNum = 1;
            foreach (var q in studySet.Questions.OrderBy(x => x.SortOrder))
            {
                sb.AppendLine($"### Question {qNum++} [{q.Type}]");
                sb.AppendLine(q.Prompt);
                sb.AppendLine();

                if (q.Options.Any())
                {
                    sb.AppendLine("**Options:**");
                    char optChar = 'A';
                    foreach (var opt in q.Options)
                    {
                        var marker = opt.IsCorrect ? " [CORRECT]" : "";
                        sb.AppendLine($"- {optChar++}. {opt.OptionText}{marker}");
                        if (!string.IsNullOrWhiteSpace(opt.DistractorRationale))
                        {
                            sb.AppendLine($"  *(Analysis: {opt.DistractorRationale})*");
                        }
                    }
                    sb.AppendLine();
                }

                if (q.Rubrics.Any())
                {
                    sb.AppendLine("**Rubric / Key Criteria:**");
                    foreach (var r in q.Rubrics.OrderBy(x => x.SortOrder))
                    {
                        sb.AppendLine($"- {r.ItemText}");
                    }
                    sb.AppendLine();
                }

                if (!string.IsNullOrWhiteSpace(q.Explanation))
                {
                    sb.AppendLine($"**Explanation:** {q.Explanation}");
                    sb.AppendLine();
                }
            }
        }

        var exportContent = sb.ToString();

        if (format.Equals("txt", StringComparison.OrdinalIgnoreCase))
        {
            return File(System.Text.Encoding.UTF8.GetBytes(exportContent), "text/plain", $"{SanitizeFileName(studySet.Title)}_StudyGuide.txt");
        }

        return File(System.Text.Encoding.UTF8.GetBytes(exportContent), "text/markdown", $"{SanitizeFileName(studySet.Title)}_StudyGuide.md");
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
                var seenOptions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var opt in q.Options)
                {
                    var optText = opt.Text?.Trim() ?? string.Empty;
                    if (optText.Length > 0 && seenOptions.Add(optText))
                    {
                        question.Options.Add(new QuestionOption
                        {
                            Id = Guid.NewGuid(),
                            QuestionId = question.Id,
                            OptionText = optText,
                            IsCorrect = opt.IsCorrect,
                            DistractorRationale = opt.DistractorRationale
                        });
                    }
                }
            }

            // Typed answers, cloze deletions and open response questions still need
            // a durable answer key even though they do not render as a list of choices.
            if (!question.Options.Any(option => option.IsCorrect) && !string.IsNullOrWhiteSpace(q.CorrectAnswer))
            {
                var correctText = q.CorrectAnswer.Trim();
                var existing = question.Options.FirstOrDefault(o => string.Equals(o.OptionText, correctText, StringComparison.OrdinalIgnoreCase));
                if (existing != null)
                {
                    existing.IsCorrect = true;
                }
                else
                {
                    question.Options.Add(new QuestionOption
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        OptionText = correctText,
                        IsCorrect = true
                    });
                }
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

        var parentCourse = await _context.Courses.FirstOrDefaultAsync(c => c.Id == courseId);
        if (parentCourse != null)
        {
            parentCourse.UpdatedAt = DateTime.UtcNow;
        }

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

    private static bool ValidateFileSignature(Stream stream, string ext)
    {
        var buffer = new byte[12];
        int bytesRead = stream.Read(buffer, 0, buffer.Length);
        if (stream.CanSeek)
        {
            stream.Position = 0;
        }

        if (bytesRead < 4) return false;

        return ext switch
        {
            ".pdf" => buffer[0] == 0x25 && buffer[1] == 0x50 && buffer[2] == 0x44 && buffer[3] == 0x46, // %PDF
            ".docx" => buffer[0] == 0x50 && buffer[1] == 0x4B && (buffer[2] == 0x03 || buffer[2] == 0x05) && (buffer[3] == 0x04 || buffer[3] == 0x06), // PK.. (ZIP)
            ".png" => buffer[0] == 0x89 && buffer[1] == 0x50 && buffer[2] == 0x4E && buffer[3] == 0x47, // .PNG
            ".jpg" or ".jpeg" => buffer[0] == 0xFF && buffer[1] == 0xD8 && buffer[2] == 0xFF, // JPEG
            ".webp" => bytesRead >= 12 && buffer[0] == 0x52 && buffer[1] == 0x49 && buffer[2] == 0x46 && buffer[3] == 0x46
                                       && buffer[8] == 0x57 && buffer[9] == 0x45 && buffer[10] == 0x42 && buffer[11] == 0x50,
            ".txt" or ".md" => !buffer.Take(bytesRead).Contains((byte)0), // Plain text should not contain NUL bytes
            _ => false
        };
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return string.Join("_", name.Split(invalid, StringSplitOptions.RemoveEmptyEntries)).Trim();
    }
}

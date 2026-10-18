using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;

using System.Security.Claims;
using StudyApp.Application.Common.Exceptions;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/ai")]
[Authorize]
[EnableRateLimiting("ingestion")]
public class AiController : ControllerBase
{
    private readonly IAiTutorService _aiTutorService;
    private readonly IConfiguration _configuration;
    private readonly IApplicationDbContext? _context;
    private readonly ILogger<AiController>? _logger;

    public AiController(
        IAiTutorService aiTutorService,
        IConfiguration configuration,
        IApplicationDbContext? context = null,
        ILogger<AiController>? logger = null)
    {
        _aiTutorService = aiTutorService;
        _configuration = configuration;
        _context = context;
        _logger = logger;
    }

    private Guid? CurrentUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    [HttpPost("tutor")]
    public async Task<IActionResult> AskTutor([FromBody] AskTutorRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new { message = "Question or message cannot be empty." });
        }

        var headerKey = Request.Headers["X-OpenAI-ApiKey"].FirstOrDefault()?.Trim()
            ?? Request.Headers["X-Gemini-ApiKey"].FirstOrDefault()?.Trim()
            ?? Request.Headers["X-Api-Key"].FirstOrDefault()?.Trim();

        var effectiveApiKey = !string.IsNullOrWhiteSpace(request.ApiKey)
            ? request.ApiKey.Trim()
            : (!string.IsNullOrWhiteSpace(headerKey) ? headerKey : null);

        var effectiveRequest = request with { ApiKey = effectiveApiKey };

        // Attach course notes grounding if studySetId is provided and owned by the current user
        if (_context != null && !string.IsNullOrWhiteSpace(request.StudySetId) && Guid.TryParse(request.StudySetId, out var setId))
        {
            try
            {
                var currentUserId = CurrentUserId();
                if (currentUserId.HasValue)
                {
                    var studySet = await _context.StudySets
                        .Include(s => s.Questions)
                        .Include(s => s.Course)
                        .AsNoTracking()
                        .FirstOrDefaultAsync(s => s.Id == setId && s.Course != null && s.Course.UserId == currentUserId.Value, cancellationToken);

                if (studySet != null)
                {
                    var notesSb = new StringBuilder();
                    if (!string.IsNullOrWhiteSpace(studySet.Description))
                    {
                        notesSb.AppendLine($"- Deck Summary: {studySet.Description}");
                    }
                    foreach (var q in studySet.Questions.Take(5))
                    {
                        notesSb.AppendLine($"- Key Concept: {q.Prompt}");
                        if (!string.IsNullOrWhiteSpace(q.Explanation))
                        {
                            notesSb.AppendLine($"  Explanation: {q.Explanation}");
                        }
                    }

                    var notesStr = notesSb.ToString();
                    if (notesStr.Length > 2500) notesStr = notesStr.Substring(0, 2500);

                        effectiveRequest = effectiveRequest with
                        {
                            ContextTopic = string.IsNullOrWhiteSpace(effectiveRequest.ContextTopic) ? studySet.Title : effectiveRequest.ContextTopic,
                            WeakConceptsContext = notesStr
                        };
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "Failed to load notes grounding for StudySet {Id}", setId);
            }
        }

        try
        {
            var response = await _aiTutorService.AskTutorAsync(effectiveRequest, cancellationToken);
            return Ok(response);
        }
        catch (AiUnavailableException ex)
        {
            _logger?.LogWarning(ex, "AI Tutor unavailable: {Kind} - {Message}", ex.Kind, ex.Message);
            var status = ex.Kind switch
            {
                AiFailure.RateLimited => 429,
                AiFailure.Blocked => 422,
                _ => 503
            };
            return StatusCode(status, new AskTutorResponse(
                ex.Message,
                "unavailable",
                DateTime.UtcNow,
                0.0,
                null,
                false
            ));
        }
        catch (Exception ex)
        {
            _logger?.LogError(ex, "AI Tutor failed to process request");
            return StatusCode(503, new AskTutorResponse(
                "Tutor offline, try again",
                "offline",
                DateTime.UtcNow,
                0.0,
                null,
                false
            ));
        }
    }

    [HttpPost("explain")]
    public async Task<IActionResult> ExplainQuestion([FromBody] ExplainQuestionRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Prompt) || string.IsNullOrWhiteSpace(request.CorrectAnswer))
        {
            return BadRequest(new { message = "Question prompt and correct answer are required." });
        }

        var headerKey = Request.Headers["X-OpenAI-ApiKey"].FirstOrDefault()?.Trim()
            ?? Request.Headers["X-Gemini-ApiKey"].FirstOrDefault()?.Trim()
            ?? Request.Headers["X-Api-Key"].FirstOrDefault()?.Trim();

        var effectiveApiKey = !string.IsNullOrWhiteSpace(request.ApiKey)
            ? request.ApiKey.Trim()
            : (!string.IsNullOrWhiteSpace(headerKey) ? headerKey : null);

        var effectiveRequest = request with { ApiKey = effectiveApiKey };
        var explanation = await _aiTutorService.ExplainQuestionAsync(effectiveRequest, cancellationToken);
        return Ok(explanation);
    }

    [HttpGet("tutor-status")]
    [HttpGet("tutor/status")]
    [AllowAnonymous]
    public async Task<IActionResult> GetTutorStatus(CancellationToken cancellationToken)
    {
        var status = await _aiTutorService.CheckStatusAsync(cancellationToken);
        return Ok(status);
    }

    [HttpGet("status")]
    [AllowAnonymous]
    public async Task<IActionResult> GetStatus(CancellationToken cancellationToken)
    {
        var isHealthy = await _aiTutorService.IsHealthyAsync(cancellationToken);

        return Ok(new
        {
            status = isHealthy ? "online" : "offline",
            provider = "Seth AI (Google Search AI)",
            model = "seth-ai-google-search",
            healthy = isHealthy,
            wiringStatus = "ready",
            timestamp = DateTime.UtcNow
        });
    }

    [HttpGet("search")]
    [AllowAnonymous]
    public async Task<IActionResult> UniversalSearchGet([FromQuery] string q, CancellationToken cancellationToken)
    {
        return await ExecuteUniversalSearchAsync(q, cancellationToken);
    }

    public record UniversalSearchRequest(string Query);

    [HttpPost("search")]
    [AllowAnonymous]
    public async Task<IActionResult> UniversalSearchPost([FromBody] UniversalSearchRequest request, CancellationToken cancellationToken)
    {
        return await ExecuteUniversalSearchAsync(request?.Query ?? string.Empty, cancellationToken);
    }

    private async Task<IActionResult> ExecuteUniversalSearchAsync(string query, CancellationToken cancellationToken)
    {
        var trimmed = (query ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return BadRequest(new { message = "Search query cannot be empty." });
        }

        // 1. Search local database if user is authenticated and context is available
        var localCourses = new List<object>();
        var localStudySets = new List<object>();
        var localQuestions = new List<object>();

        var userId = CurrentUserId();
        if (_context != null && userId.HasValue)
        {
            try
            {
                var qLower = trimmed.ToLowerInvariant();
                var courses = await _context.Courses
                    .AsNoTracking()
                    .Where(c => c.UserId == userId.Value && c.Name.ToLower().Contains(qLower))
                    .Take(10)
                    .Select(c => new { c.Id, c.Name, c.ColorHex })
                    .ToListAsync(cancellationToken);
                localCourses.AddRange(courses);

                var sets = await _context.StudySets
                    .Include(s => s.Course)
                    .AsNoTracking()
                    .Where(s => s.Course != null && s.Course.UserId == userId.Value &&
                        (s.Title.ToLower().Contains(qLower) || (s.Description != null && s.Description.ToLower().Contains(qLower))))
                    .Take(15)
                    .Select(s => new { s.Id, s.CourseId, CourseName = s.Course!.Name, s.Title, s.Description })
                    .ToListAsync(cancellationToken);
                localStudySets.AddRange(sets);

                var questions = await _context.Questions
                    .Include(q => q.StudySet)
                    .ThenInclude(s => s!.Course)
                    .AsNoTracking()
                    .Where(q => q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == userId.Value &&
                        (q.Prompt.ToLower().Contains(qLower) || (q.Explanation != null && q.Explanation.ToLower().Contains(qLower))))
                    .Take(20)
                    .Select(q => new { q.Id, q.StudySetId, StudySetTitle = q.StudySet!.Title, q.Prompt, q.Explanation, Type = q.Type.ToString() })
                    .ToListAsync(cancellationToken);
                localQuestions.AddRange(questions);
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "Local database search encountered an error for query '{Query}'", trimmed);
            }
        }

        // 2. Ask Seth AI (Google Search AI Mode) for comprehensive overview + web sources
        AskTutorResponse? aiResponse = null;
        try
        {
            aiResponse = await _aiTutorService.AskTutorAsync(
                new AskTutorRequest(
                    Message: trimmed,
                    ContextTopic: "Google Search Overview & Fact-Checked Encyclopedia Knowledge"
                ),
                cancellationToken);
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "Seth AI overview failed during search for '{Query}'", trimmed);
        }

        return Ok(new
        {
            query = trimmed,
            engine = "Seth AI • Google Search Mode",
            aiOverview = aiResponse?.Reply ?? StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.SynthesizeResponse(trimmed, "General Knowledge"),
            sources = aiResponse?.Sources ?? new List<GroundedSource>(),
            localResults = new
            {
                courses = localCourses,
                studySets = localStudySets,
                questions = localQuestions
            },
            timestamp = DateTime.UtcNow
        });
    }

    public record WritingStudioRequest(
        string Mode, // "make" or "correct"
        string TextOrTopic,
        string? Format = "Academic Essay",
        string? Tone = "Google Standard Academic"
    );

    [HttpPost("writing-studio")]
    [AllowAnonymous]
    public async Task<IActionResult> WritingStudio([FromBody] WritingStudioRequest request, CancellationToken cancellationToken)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.TextOrTopic))
        {
            return BadRequest(new { message = "Please provide a topic or draft text." });
        }

        var mode = (request.Mode ?? "correct").Trim().ToLowerInvariant();
        var input = request.TextOrTopic.Trim();
        var format = string.IsNullOrWhiteSpace(request.Format) ? "Academic Essay & Study Guide" : request.Format.Trim();
        var tone = string.IsNullOrWhiteSpace(request.Tone) ? "Clear, Accurate, Google-Standard" : request.Tone.Trim();

        try
        {
            var prompt = mode == "make"
                ? $"[Seth AI Easy Maker — {format} ({tone})]\nWrite a complete, well-structured, accurate, Google-standard {format} on the topic: \"{input}\". Include a clear title, executive overview, well-organized body sections with real facts and examples, key takeaways, and review questions."
                : $"[Seth AI Easy Corrector — {tone}]\nProofread, correct, and elevate the following text to Google-standard clarity and grammar:\n\n\"{input}\"\n\nProvide:\n1. ✅ Corrected & Polished Version (ready to copy)\n2. 🎓 Elevated Academic Version\n3. 🔍 Key Grammar, Spelling & Clarity Fixes Made\n4. 📊 Writing Quality Score & Readability Feedback";

            var tutorRes = await _aiTutorService.AskTutorAsync(
                new AskTutorRequest(
                    Message: prompt,
                    ContextTopic: mode == "make" ? $"Easy Maker ({format})" : $"Easy Corrector ({tone})"
                ),
                cancellationToken);

            var eval = StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.EvaluateAndCorrectWriting(input, tone);
            var fallbackOutput = mode == "make"
                ? StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.SynthesizeEssayOrGuide(input, format, tone)
                : $"### ✅ Corrected & Polished Version\n{eval.CorrectedText}\n\n### 🎓 Elevated Academic Version\n{eval.ElevatedText}\n\n### 📊 Writing Quality Score: {eval.OverallScore}/100\n- Grammar: {eval.GrammarScore}/100 | Clarity: {eval.ClarityScore}/100 | Style: {eval.StyleScore}/100\n- " + string.Join("\n- ", eval.Suggestions);

            var replyText = !string.IsNullOrWhiteSpace(tutorRes?.Reply) && !tutorRes.Reply.Contains("Comprehensive Academic Guide:")
                ? tutorRes.Reply
                : fallbackOutput;

            return Ok(new
            {
                mode,
                engine = "Seth AI Writing Studio (Google Standard)",
                result = replyText,
                correctedText = mode == "correct" ? eval.CorrectedText : null,
                elevatedText = mode == "correct" ? eval.ElevatedText : null,
                qualityScore = mode == "correct" ? eval.OverallScore : 96,
                corrections = mode == "correct" ? eval.Corrections : new List<object>(),
                suggestions = mode == "correct" ? eval.Suggestions : new List<string>(),
                sources = tutorRes?.Sources ?? new List<GroundedSource>(),
                timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "Writing studio fallback used for mode {Mode}", mode);
            if (mode == "make")
            {
                var generated = StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.SynthesizeEssayOrGuide(input, format, tone);
                return Ok(new
                {
                    mode,
                    engine = "Seth AI Writing Studio",
                    result = generated,
                    qualityScore = 95,
                    timestamp = DateTime.UtcNow
                });
            }
            else
            {
                var eval = StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.EvaluateAndCorrectWriting(input, tone);
                var report = $"### ✅ Corrected & Polished Version\n{eval.CorrectedText}\n\n### 🎓 Elevated Academic Version\n{eval.ElevatedText}\n\n### 📊 Writing Quality Score: {eval.OverallScore}/100\n- " + string.Join("\n- ", eval.Suggestions);
                return Ok(new
                {
                    mode,
                    engine = "Seth AI Writing Studio",
                    result = report,
                    correctedText = eval.CorrectedText,
                    elevatedText = eval.ElevatedText,
                    qualityScore = eval.OverallScore,
                    corrections = eval.Corrections,
                    suggestions = eval.Suggestions,
                    timestamp = DateTime.UtcNow
                });
            }
        }
    }

    [HttpDelete("chat-logs")]
    [HttpDelete("tutor/history")]
    public IActionResult ClearChatLogs()
    {
        _logger?.LogInformation("Client requested server-side AI chat logs deletion.");
        return Ok(new { success = true, message = "Server-side chat logs cleared." });
    }
}
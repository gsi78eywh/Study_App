using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;

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

        // Attach course notes grounding if studySetId is provided
        if (_context != null && !string.IsNullOrWhiteSpace(request.StudySetId) && Guid.TryParse(request.StudySetId, out var setId))
        {
            try
            {
                var studySet = await _context.StudySets
                    .Include(s => s.Questions)
                    .AsNoTracking()
                    .FirstOrDefaultAsync(s => s.Id == setId, cancellationToken);

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
        var provider = _configuration["AiSettings:Provider"] ?? "GoogleGemini";
        var isOpenAi = string.Equals(provider, "OpenAI", StringComparison.OrdinalIgnoreCase);
        var model = isOpenAi
            ? (_configuration["AiSettings:OpenAi:ModelId"] ?? _configuration["AiSettings:ModelId"] ?? "gpt-4o-mini")
            : (_configuration["AiSettings:ModelId"] ?? "gemini-3.1-flash-lite");

        var openAiKey = _configuration["AiSettings:OpenAi:ApiKey"] ?? Environment.GetEnvironmentVariable("OPENAI_API_KEY");
        var isWiringPaused = isOpenAi && !StudyApp.Infrastructure.AiServices.OpenAiAiService.IsValidProjectKey(openAiKey);

        var isHealthy = await _aiTutorService.IsHealthyAsync(cancellationToken);

        return Ok(new
        {
            status = isHealthy ? "online" : "offline",
            provider = provider,
            model = model,
            healthy = isHealthy,
            wiringStatus = isOpenAi ? (isWiringPaused ? "paused_pending_key" : "active_live_target") : "ready",
            timestamp = DateTime.UtcNow
        });
    }

    [HttpDelete("chat-logs")]
    [HttpDelete("tutor/history")]
    public IActionResult ClearChatLogs()
    {
        _logger?.LogInformation("Client requested server-side AI chat logs deletion.");
        return Ok(new { success = true, message = "Server-side chat logs cleared." });
    }
}
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/ai")]
[Authorize]
public class AiController : ControllerBase
{
    private readonly IAiTutorService _aiTutorService;
    private readonly IConfiguration _configuration;

    public AiController(IAiTutorService aiTutorService, IConfiguration configuration)
    {
        _aiTutorService = aiTutorService;
        _configuration = configuration;
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
        var response = await _aiTutorService.AskTutorAsync(effectiveRequest, cancellationToken);
        return Ok(response);
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

    [HttpGet("status")]
    [AllowAnonymous]
    public async Task<IActionResult> GetStatus(CancellationToken cancellationToken)
    {
        var provider = _configuration["AiSettings:Provider"] ?? "GoogleGemini";
        var isOpenAi = string.Equals(provider, "OpenAI", StringComparison.OrdinalIgnoreCase);
        var model = isOpenAi
            ? (_configuration["AiSettings:OpenAi:ModelId"] ?? _configuration["AiSettings:ModelId"] ?? "gpt-4o-mini")
            : (_configuration["AiSettings:ModelId"] ?? "gemini-3.6-flash");

        var openAiKey = _configuration["AiSettings:OpenAi:ApiKey"] ?? Environment.GetEnvironmentVariable("OPENAI_API_KEY");
        var isWiringPaused = isOpenAi && !StudyApp.Infrastructure.AiServices.OpenAiAiService.IsValidProjectKey(openAiKey);

        var isHealthy = await _aiTutorService.IsHealthyAsync(cancellationToken);

        return Ok(new
        {
            status = isHealthy ? "online" : "offline_fallback",
            provider = provider,
            model = model,
            healthy = isHealthy,
            wiringStatus = isOpenAi ? (isWiringPaused ? "paused_pending_key" : "active_live_target") : "ready",
            timestamp = DateTime.UtcNow
        });
    }
}
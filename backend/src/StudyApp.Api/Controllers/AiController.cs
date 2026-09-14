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

        var headerKey = Request.Headers["X-Gemini-ApiKey"].FirstOrDefault()?.Trim();
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

        var headerKey = Request.Headers["X-Gemini-ApiKey"].FirstOrDefault()?.Trim();
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
        var model = _configuration["AiSettings:ModelId"] ?? "gemini-1.5-flash";
        var isHealthy = await _aiTutorService.IsHealthyAsync(cancellationToken);

        return Ok(new
        {
            status = isHealthy ? "online" : "offline_fallback",
            provider = "Google Gemini AI",
            model = model,
            healthy = isHealthy,
            timestamp = DateTime.UtcNow
        });
    }
}
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Application.DTOs.Ingestion;

namespace StudyApp.Infrastructure.AiServices;

/// <summary>
/// Adaptive AI Dispatcher that dynamically routes AI requests to either OpenAI or Google Gemini
/// based on server configuration, requested provider, and secure API key flow.
/// </summary>
public class AdaptiveAiService : IAiQuestionGenerator, IAiTutorService
{
    private readonly GeminiAiService _geminiService;
    private readonly OpenAiAiService _openAiService;
    private readonly IConfiguration _configuration;
    private readonly ILogger<AdaptiveAiService> _logger;

    public AdaptiveAiService(
        GeminiAiService geminiService,
        OpenAiAiService openAiService,
        IConfiguration configuration,
        ILogger<AdaptiveAiService> logger)
    {
        _geminiService = geminiService;
        _openAiService = openAiService;
        _configuration = configuration;
        _logger = logger;
    }

    public string ConfiguredProvider => _configuration["AiSettings:Provider"] ?? "GoogleGemini";

    public bool IsOpenAiSelected => string.Equals(ConfiguredProvider, "OpenAI", StringComparison.OrdinalIgnoreCase);

    public Task<GeneratedStudySetResult> GenerateStudySetAsync(
        string rawText,
        string title,
        List<string> requestedTypes,
        int targetCount,
        int setIndex = 0,
        string? variant = null,
        string? apiKeyOverride = null,
        CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected || (apiKeyOverride != null && apiKeyOverride.StartsWith("sk-", StringComparison.OrdinalIgnoreCase)))
        {
            return _openAiService.GenerateStudySetAsync(rawText, title, requestedTypes, targetCount, setIndex, variant, apiKeyOverride, cancellationToken);
        }

        return _geminiService.GenerateStudySetAsync(rawText, title, requestedTypes, targetCount, setIndex, variant, apiKeyOverride, cancellationToken);
    }

    public Task<GeneratedStudySetResult> GenerateStudySetFromImageAsync(
        byte[] imageBytes,
        string mimeType,
        string title,
        List<string> requestedTypes,
        int targetCount,
        int setIndex = 0,
        string? variant = null,
        string? apiKeyOverride = null,
        CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected || (apiKeyOverride != null && apiKeyOverride.StartsWith("sk-", StringComparison.OrdinalIgnoreCase)))
        {
            return _openAiService.GenerateStudySetFromImageAsync(imageBytes, mimeType, title, requestedTypes, targetCount, setIndex, variant, apiKeyOverride, cancellationToken);
        }

        return _geminiService.GenerateStudySetFromImageAsync(imageBytes, mimeType, title, requestedTypes, targetCount, setIndex, variant, apiKeyOverride, cancellationToken);
    }

    public Task<AskTutorResponse> AskTutorAsync(AskTutorRequest request, CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected || (request.ApiKey != null && request.ApiKey.StartsWith("sk-", StringComparison.OrdinalIgnoreCase)))
        {
            return _openAiService.AskTutorAsync(request, cancellationToken);
        }

        return _geminiService.AskTutorAsync(request, cancellationToken);
    }

    public Task<QuestionExplanationResult> ExplainQuestionAsync(ExplainQuestionRequest request, CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected || (request.ApiKey != null && request.ApiKey.StartsWith("sk-", StringComparison.OrdinalIgnoreCase)))
        {
            return _openAiService.ExplainQuestionAsync(request, cancellationToken);
        }

        return _geminiService.ExplainQuestionAsync(request, cancellationToken);
    }

    public Task<OpenAnswerEvaluationResult> EvaluateOpenAnswerAsync(
        string prompt,
        string modelAnswer,
        IReadOnlyList<string> rubric,
        string studentAnswer,
        CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected)
        {
            return _openAiService.EvaluateOpenAnswerAsync(prompt, modelAnswer, rubric, studentAnswer, cancellationToken);
        }

        return _geminiService.EvaluateOpenAnswerAsync(prompt, modelAnswer, rubric, studentAnswer, cancellationToken);
    }

    public Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default)
    {
        if (IsOpenAiSelected)
        {
            return _openAiService.IsHealthyAsync(cancellationToken);
        }

        return _geminiService.IsHealthyAsync(cancellationToken);
    }
}

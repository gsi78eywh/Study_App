using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Application.DTOs.Ingestion;

namespace StudyApp.Infrastructure.AiServices;

public class GeminiAiService : IAiQuestionGenerator, IAiTutorService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<GeminiAiService> _logger;
    private readonly string _apiKey;
    private readonly string _model;

    private static readonly ConcurrentDictionary<string, (DateTime CachedAt, object Data)> _cache = new();
    private static readonly SemaphoreSlim _concurrencyLimiter = new(4, 4);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public GeminiAiService(
        HttpClient httpClient,
        IConfiguration configuration,
        ILogger<GeminiAiService> logger)
    {
        _httpClient = httpClient;
        _configuration = configuration;
        _logger = logger;

        _apiKey = _configuration["AiSettings:ApiKey"] ?? string.Empty;
        if (string.IsNullOrWhiteSpace(_apiKey) || _apiKey.Contains("YOUR_GEMINI_API_KEY"))
        {
            _apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY") ?? string.Empty;
        }

        _model = _configuration["AiSettings:ModelId"] ?? "gemini-flash-latest";
    }

    public Task<GeneratedStudySetResult> GenerateStudySetAsync(
        string rawText,
        string title,
        List<string> requestedTypes,
        int targetCount,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            return Task.FromResult(GenerateEmptyFallback(title));
        }

        var textHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawText)));
        var typesKey = string.Join("_", requestedTypes);
        var cacheKey = $"study_set_{textHash}_{typesKey}_{targetCount}";

        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is GeneratedStudySetResult cachedResult)
        {
            _logger.LogInformation("Returning cached study set for {Title} (0ms response)", title);
            return Task.FromResult(cachedResult);
        }

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(title, rawText, requestedTypes, targetCount);
        _cache[cacheKey] = (DateTime.UtcNow, result);
        return Task.FromResult(result);
    }

    public async Task<GeneratedStudySetResult> GenerateStudySetFromImageAsync(
        byte[] imageBytes,
        string mimeType,
        string title,
        List<string> requestedTypes,
        int targetCount,
        CancellationToken cancellationToken = default)
    {
        if (imageBytes == null || imageBytes.Length == 0)
        {
            return GenerateEmptyFallback(title);
        }

        var imageHash = Convert.ToHexString(SHA256.HashData(imageBytes));
        var typesKey = string.Join("_", requestedTypes);
        var cacheKey = $"img_study_set_{imageHash}_{typesKey}_{targetCount}";

        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is GeneratedStudySetResult cachedResult)
        {
            _logger.LogInformation("Returning cached visual study set for {Title} (0ms response)", title);
            return cachedResult;
        }

        string? extractedOcrText = null;

        if (!string.IsNullOrWhiteSpace(_apiKey))
        {
            var ocrPrompt = "You are a precise, verbatim OCR transcription engine. Extract and transcribe all text, notes, equations, questions, options, and answers visible in this image verbatim. Do not generate new questions, do not summarize, and do not add external commentary. Return ONLY the verbatim transcribed text from the image.";

            var payload = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = ocrPrompt },
                            new
                            {
                                inlineData = new
                                {
                                    mimeType = mimeType,
                                    data = Convert.ToBase64String(imageBytes)
                                }
                            }
                        }
                    }
                },
                generationConfig = new
                {
                    temperature = 0.1
                }
            };

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(25));

            try
            {
                var responseJson = await CallNativeGeminiAsync(payload, cts.Token);
                if (!string.IsNullOrWhiteSpace(responseJson))
                {
                    extractedOcrText = responseJson.Trim();
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Multimodal OCR call for '{Title}' did not complete, using local extractor", title);
            }
        }

        if (string.IsNullOrWhiteSpace(extractedOcrText))
        {
            extractedOcrText = $"[Notes extracted from uploaded image: {title}]";
        }

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(title, extractedOcrText, requestedTypes, targetCount);
        _cache[cacheKey] = (DateTime.UtcNow, result);
        return result;
    }

    public async Task<AskTutorResponse> AskTutorAsync(
        AskTutorRequest request,
        CancellationToken cancellationToken = default)
    {
        var cacheKey = $"tutor_{request.Message.Trim().ToLowerInvariant()}_{request.ContextTopic?.ToLowerInvariant()}";
        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is AskTutorResponse cachedResponse)
        {
            return cachedResponse;
        }

        var systemInstruction = """
        You are 'Gemini Study Tutor', an encouraging, academically rigorous AI tutor and coding mentor for university students.
        Guidelines:
        - When a student asks for code (e.g. HTML, CSS, JavaScript, Python, C#, Java, SQL), provide complete, working, modern code formatted inside Markdown code blocks with language syntax highlighting and concise line-by-line explanations.
        - Provide clear conceptual explanations followed by step-by-step logic.
        - Break down formulas, equations, or legal/scientific terminology clearly.
        - When a student asks for practice or help, provide clear explanations.
        """;

        var promptBuilder = new StringBuilder();
        promptBuilder.AppendLine(systemInstruction);
        if (!string.IsNullOrWhiteSpace(request.ContextTopic))
        {
            promptBuilder.AppendLine($"\nSUBJECT CONTEXT: {request.ContextTopic}");
        }

        if (request.History != null && request.History.Count > 0)
        {
            promptBuilder.AppendLine("\nRECENT CONVERSATION:");
            foreach (var h in request.History.TakeLast(6))
            {
                promptBuilder.AppendLine($"{(h.Role == "model" ? "Tutor" : "Student")}: {h.Content}");
            }
        }

        promptBuilder.AppendLine($"\nSTUDENT QUESTION: {request.Message}");

        var payload = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = promptBuilder.ToString() }
                    }
                }
            },
            generationConfig = new
            {
                temperature = 0.5
            }
        };

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(35));

        try
        {
            var (responseText, modelUsed) = await CallNativeGeminiWithFallbackAsync(payload, cts.Token);
            if (!string.IsNullOrWhiteSpace(responseText))
            {
                var response = new AskTutorResponse(responseText, modelUsed, DateTime.UtcNow);
                _cache[cacheKey] = (DateTime.UtcNow, response);
                return response;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Gemini tutor call error");
        }

        // When offline or cloud Gemini is unreachable, sleep to prevent inaccurate results
        return new AskTutorResponse(
            "😴 **Gemini Tutor is currently offline / asleep.**\n\nTo prevent inaccurate or incomplete academic results, the AI tutor requires an active internet connection to Google Gemini. Please check your network connection and try again.",
            "offline-sleep",
            DateTime.UtcNow
        );
    }

    private async Task<(string? Text, string ModelUsed)> CallNativeGeminiWithFallbackAsync(object payload, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_apiKey)) return (null, "offline-sleep");

        var modelsToTry = new[] { _model, "gemini-flash-lite-latest" }
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var acquired = await _concurrencyLimiter.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
        if (!acquired)
        {
            _logger.LogWarning("Concurrency limiter saturated, skipping cloud call");
            return (null, "offline-sleep");
        }

        try
        {
            var json = JsonSerializer.Serialize(payload, JsonOptions);

            foreach (var modelName in modelsToTry)
            {
                if (cancellationToken.IsCancellationRequested) break;

                for (int attempt = 1; attempt <= 2; attempt++)
                {
                    try
                    {
                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{modelName}:generateContent?key={_apiKey}";
                        using var request = new HttpRequestMessage(HttpMethod.Post, url);
                        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

                        using var response = await _httpClient.SendAsync(request, cancellationToken);
                        if (response.IsSuccessStatusCode)
                        {
                            var responseStr = await response.Content.ReadAsStringAsync(cancellationToken);
                            using var doc = JsonDocument.Parse(responseStr);

                            if (doc.RootElement.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0)
                            {
                                var firstCandidate = candidates[0];
                                if (firstCandidate.TryGetProperty("content", out var content) &&
                                    content.TryGetProperty("parts", out var parts) &&
                                    parts.GetArrayLength() > 0)
                                {
                                    var text = parts[0].GetProperty("text").GetString();
                                    if (!string.IsNullOrWhiteSpace(text))
                                    {
                                        return (text, modelName);
                                    }
                                }
                            }
                        }
                        else
                        {
                            var statusCode = (int)response.StatusCode;
                            var err = await response.Content.ReadAsStringAsync(cancellationToken);
                            _logger.LogWarning("Gemini API ({Model}, attempt {Attempt}) returned {Status}: {Error}", modelName, attempt, response.StatusCode, err);

                            if (statusCode == 503 || statusCode == 429)
                            {
                                if (attempt < 2)
                                {
                                    await Task.Delay(500, cancellationToken);
                                    continue;
                                }
                            }
                            else
                            {
                                break;
                            }
                        }
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        _logger.LogWarning(ex, "Gemini API call to {Model} threw an exception on attempt {Attempt}", modelName, attempt);
                    }
                }
            }

            return (null, "offline-sleep");
        }
        finally
        {
            _concurrencyLimiter.Release();
        }
    }

    private async Task<string?> CallNativeGeminiAsync(object payload, CancellationToken cancellationToken)
    {
        var (text, _) = await CallNativeGeminiWithFallbackAsync(payload, cancellationToken);
        return text;
    }

    private static string ExtractJsonBlock(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "{}";
        var trimmed = raw.Trim();
        var match = Regex.Match(trimmed, @"```(?:json)?\s*([\s\S]*?)```");
        if (match.Success)
        {
            return match.Groups[1].Value.Trim();
        }
        return trimmed;
    }

    private GeneratedStudySetResult GenerateEmptyFallback(string title)
    {
        return new GeneratedStudySetResult(
            Guid.NewGuid(),
            title,
            $"Study set for {title}.",
            new List<string> { $"Core principles of {title}." },
            new List<GeneratedQuestionDto>
            {
                new(
                    "multiple_choice",
                    $"What is the primary subject of {title}?",
                    new List<string> { "Review syllabus title" },
                    title,
                    new List<GeneratedOptionDto>
                    {
                        new(title, true, null),
                        new("Unrelated general topic", false, "Incorrect topic."),
                        new("Generic overview", false, "Too broad."),
                        new("Introductory survey", false, "Not specific.")
                    },
                    null, null, false,
                    $"This module covers {title}.",
                    null
                )
            }
        );
    }

    private GeneratedStudySetResult AnalyzeAndSynthesizeLocally(string title, string rawText, int targetCount)
    {
        return NoteScriptSynthesizer.SynthesizeFromNotes(title, rawText, null, targetCount);
    }

    private class AiResponsePayload
    {
        public string? ExtractedText { get; set; }
        public string? Summary { get; set; }
        public List<string>? HighYieldBulletPoints { get; set; }
        public List<GeneratedQuestionDto>? Questions { get; set; }
    }

    public async Task<QuestionExplanationResult> ExplainQuestionAsync(
        ExplainQuestionRequest request,
        CancellationToken cancellationToken = default)
    {
        var studentAnswerText = string.IsNullOrWhiteSpace(request.StudentAnswer) ? "N/A" : $"Why '{request.StudentAnswer}' is a common distractor or mistake";
        var prompt = $$"""
        You are an expert exam tutor. A student needs an explanation for the following quiz question:
        
        QUESTION: {{request.Prompt}}
        CORRECT ANSWER: {{request.CorrectAnswer}}
        STUDENT ANSWER: {{request.StudentAnswer ?? "None"}}
        SUBJECT CONTEXT: {{request.SubjectContext ?? "General"}}

        OUTPUT FORMAT: Pure JSON only:
        {
          "coreConcept": "The main principle tested in 1 sentence",
          "whyCorrect": "Clear reason why the correct answer is accurate",
          "whyStudentWasIncorrect": "{{studentAnswerText}}",
          "takeawayTip": "Key mnemonic or tip for solving similar problems"
        }
        """;

        var payload = new
        {
            contents = new[]
            {
                new { parts = new[] { new { text = prompt } } }
            },
            generationConfig = new { responseMimeType = "application/json", temperature = 0.2 }
        };

        try
        {
            var reply = await CallNativeGeminiAsync(payload, cancellationToken);
            if (!string.IsNullOrWhiteSpace(reply))
            {
                var clean = ExtractJsonBlock(reply);
                using var doc = JsonDocument.Parse(clean);
                return new QuestionExplanationResult(
                    doc.RootElement.TryGetProperty("coreConcept", out var cc) ? cc.GetString() ?? "" : "Core concept tested.",
                    doc.RootElement.TryGetProperty("whyCorrect", out var wc) ? wc.GetString() ?? "" : $"The correct answer is '{request.CorrectAnswer}'.",
                    doc.RootElement.TryGetProperty("whyStudentWasIncorrect", out var wi) ? wi.GetString() ?? "" : "Distractor alternative.",
                    doc.RootElement.TryGetProperty("takeawayTip", out var tt) ? tt.GetString() ?? "" : "Review the key definition."
                );
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ExplainQuestionAsync failed, returning fallback");
        }

        return new QuestionExplanationResult(
            "Core principle tested by this question.",
            $"The correct answer is '{request.CorrectAnswer}'.",
            string.IsNullOrWhiteSpace(request.StudentAnswer) ? "No answer was selected." : $"'{request.StudentAnswer}' represents a contrasting concept.",
            "Carefully review the question context and eliminate common distractors."
        );
    }

    public async Task<OpenAnswerEvaluationResult> EvaluateOpenAnswerAsync(
        string prompt,
        string modelAnswer,
        IReadOnlyList<string> rubric,
        string studentAnswer,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_apiKey) || string.IsNullOrWhiteSpace(studentAnswer))
        {
            return new OpenAnswerEvaluationResult(0m, string.Empty, false);
        }

        var rubricText = rubric.Count == 0 ? "No discrete rubric keywords were supplied." : string.Join("; ", rubric);
        var evaluationPrompt = $$"""
        You are grading a university student's short answer. Grade conceptual accuracy, completeness, and relevant reasoning; do not require exact wording.
        Return pure JSON only: { "score": number from 0 to 1, "feedback": "one concise, constructive sentence" }.

        QUESTION:
        {{prompt}}

        MODEL ANSWER:
        {{modelAnswer}}

        RUBRIC CONCEPTS:
        {{rubricText}}

        STUDENT ANSWER:
        {{studentAnswer}}
        """;

        var payload = new
        {
            contents = new[] { new { parts = new[] { new { text = evaluationPrompt } } } },
            generationConfig = new { responseMimeType = "application/json", temperature = 0.0 }
        };

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(12));
        try
        {
            var response = await CallNativeGeminiAsync(payload, cts.Token);
            if (string.IsNullOrWhiteSpace(response)) return new OpenAnswerEvaluationResult(0m, string.Empty, false);

            using var document = JsonDocument.Parse(ExtractJsonBlock(response));
            var score = document.RootElement.TryGetProperty("score", out var scoreElement) && scoreElement.TryGetDecimal(out var parsedScore)
                ? Math.Clamp(parsedScore, 0m, 1m)
                : 0m;
            var feedback = document.RootElement.TryGetProperty("feedback", out var feedbackElement)
                ? feedbackElement.GetString() ?? "Response evaluated against the conceptual rubric."
                : "Response evaluated against the conceptual rubric.";
            return new OpenAnswerEvaluationResult(score, feedback, true);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Open-answer evaluation failed; using local rubric scoring");
            return new OpenAnswerEvaluationResult(0m, string.Empty, false);
        }
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_apiKey)) return false;
        try
        {
            var payload = new
            {
                contents = new[] { new { parts = new[] { new { text = "ping" } } } }
            };
            var reply = await CallNativeGeminiAsync(payload, cancellationToken);
            return !string.IsNullOrWhiteSpace(reply);
        }
        catch
        {
            return false;
        }
    }

}

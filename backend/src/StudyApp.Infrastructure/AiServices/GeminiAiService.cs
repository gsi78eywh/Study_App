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

/// <summary>
/// Primary AI agent service integrating Google Gemini (e.g. Gemini 3.6 Flash) for active-recall
/// study set generation, OCR document synthesis, code documentation, and interactive academic tutoring.
/// </summary>
public class GeminiAiService : IAiQuestionGenerator, IAiTutorService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<GeminiAiService> _logger;
    private readonly string _apiKey;
    private readonly string _model;
    private readonly bool _cloudCallsDisabled;

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
        if (string.Equals(_apiKey, "none", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(_apiKey, "disabled", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(_apiKey, "offline", StringComparison.OrdinalIgnoreCase))
        {
            _apiKey = string.Empty;
            _cloudCallsDisabled = true;
        }
        else if (string.IsNullOrWhiteSpace(_apiKey) || _apiKey.Contains("YOUR_GEMINI_API_KEY"))
        {
            _apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY") ?? string.Empty;
            _cloudCallsDisabled = false;
        }
        else
        {
            _cloudCallsDisabled = false;
        }

        _model = _configuration["AiSettings:ModelId"] ?? "gemini-3.6-flash";
    }

    public async Task<GeneratedStudySetResult> GenerateStudySetAsync(
        string rawText,
        string title,
        List<string> requestedTypes,
        int targetCount,
        int setIndex = 0,
        string? variant = null,
        string? apiKeyOverride = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            return GenerateEmptyFallback(title);
        }

        var effectiveApiKey = !_cloudCallsDisabled && !string.IsNullOrWhiteSpace(apiKeyOverride)
            ? apiKeyOverride.Trim()
            : (!_cloudCallsDisabled && !string.IsNullOrWhiteSpace(_apiKey) ? _apiKey : null);

        var textHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawText)));
        var typesKey = string.Join("_", requestedTypes);
        var cacheKey = $"study_set_{textHash}_{typesKey}_{targetCount}_{setIndex}_{variant ?? "default"}_{(effectiveApiKey != null ? "ai" : "local")}";

        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is GeneratedStudySetResult cachedResult)
        {
            _logger.LogInformation("Returning cached study set for {Title} (0ms response)", title);
            return cachedResult;
        }

        if (!string.IsNullOrWhiteSpace(effectiveApiKey) &&
            !effectiveApiKey.Contains("YOUR_GEMINI_API_KEY") &&
            !string.Equals(effectiveApiKey, "none", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(effectiveApiKey, "disabled", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(effectiveApiKey, "offline", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var typesListStr = (requestedTypes != null && requestedTypes.Count > 0)
                    ? string.Join(", ", requestedTypes)
                    : "multiple_choice, identification, true_false, cloze, enumeration, matching, flashcard";

                var aiPrompt = $$"""
                You are an advanced academic AI exam and active-recall engine.
                Thoroughly analyze and digest the ENTIRE provided lecture notes/study material below from beginning to end.
                Do NOT just repeat the first few sentences or define words back-and-forth in a loop.
                Explore the entire text for:
                - Core concepts, mechanisms, and definitions
                - Cause and effect relationships
                - Key distinctions and comparisons
                - Processes, steps, and rules
                - Quantitative values and facts
                - Practical applications and analytical scenarios

                STUDY MATERIAL TITLE: {{title}}
                REQUESTED QUESTION/CARD TYPES: {{typesListStr}}
                TARGET ITEM COUNT: {{targetCount}}
                SET INDEX / VARIANT: {{setIndex}} / {{variant ?? "default"}}

                STUDY MATERIAL CONTENT:
                {{rawText}}

                INSTRUCTIONS FOR FLASHCARDS:
                If flashcards are requested or needed, create active-recall flashcards across distinct cognitive dimensions:
                1. Core Concept & Role (Front: What is the primary role/function of X? Back: ...)
                2. Reverse Active Recall (Front: What concept/principle operates as follows: "..."? Back: ...)
                3. Cause & Effect (Front: What is the direct consequence/outcome when X occurs? Back: ...)
                4. Key Distinction (Front: How does X differ from related concepts? Back: ...)
                5. Application Drill (Front: In a practical problem, how is X applied? Back: ...)

                Return pure valid JSON adhering to this schema:
                {
                  "summary": "2-3 sentence overview covering the full breadth of the material",
                  "highYieldBulletPoints": ["bullet 1", "bullet 2", "bullet 3", "bullet 4", "bullet 5"],
                  "questions": [
                    {
                      "type": "flashcard" | "multiple_choice" | "identification" | "true_false" | "cloze" | "enumeration" | "matching" | "scenario",
                      "prompt": "Clear, precise question or flashcard front prompt",
                      "hints": ["Helpful hint 1"],
                      "correctAnswer": "Exact correct answer or flashcard back",
                      "options": [
                        { "text": "Correct answer", "isCorrect": true, "distractorRationale": null },
                        { "text": "Authentic distractor 1 from notes", "isCorrect": false, "distractorRationale": "Why incorrect" },
                        { "text": "Authentic distractor 2 from notes", "isCorrect": false, "distractorRationale": "Why incorrect" },
                        { "text": "Authentic distractor 3 from notes", "isCorrect": false, "distractorRationale": "Why incorrect" }
                      ],
                      "explanation": "Clear explanation grounded directly in the notes",
                      "thinkingBreakdown": ["DIMENSION: CORE CONCEPT", "ANALYSIS: Reasoning step"],
                      "sourceReference": "Specific excerpt or topic from notes"
                    }
                  ]
                }
                """;

                var payload = new
                {
                    contents = new[]
                    {
                        new { parts = new[] { new { text = aiPrompt } } }
                    },
                    generationConfig = new
                    {
                        responseMimeType = "application/json",
                        temperature = 0.3
                    }
                };

                using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                cts.CancelAfter(TimeSpan.FromSeconds(35));

                var (responseText, _) = await CallNativeGeminiWithFallbackAsync(payload, effectiveApiKey, cts.Token);
                if (!string.IsNullOrWhiteSpace(responseText))
                {
                    var cleanJson = ExtractJsonBlock(responseText);
                    using var doc = JsonDocument.Parse(cleanJson);
                    var root = doc.RootElement;

                    var summary = root.TryGetProperty("summary", out var sumProp) ? sumProp.GetString() ?? $"Study set for {title}" : $"Study set for {title}";
                    var bulletPoints = new List<string>();
                    if (root.TryGetProperty("highYieldBulletPoints", out var bpProp) && bpProp.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in bpProp.EnumerateArray())
                        {
                            var s = item.GetString();
                            if (!string.IsNullOrWhiteSpace(s)) bulletPoints.Add(s);
                        }
                    }

                    var parsedQuestions = new List<GeneratedQuestionDto>();
                    if (root.TryGetProperty("questions", out var qProp) && qProp.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var qEl in qProp.EnumerateArray())
                        {
                            var type = qEl.TryGetProperty("type", out var tEl) ? tEl.GetString() ?? "multiple_choice" : "multiple_choice";
                            var prompt = qEl.TryGetProperty("prompt", out var pEl) ? pEl.GetString() ?? "" : "";
                            var correctAnswer = qEl.TryGetProperty("correctAnswer", out var caEl) ? caEl.GetString() ?? "" : "";
                            var explanation = qEl.TryGetProperty("explanation", out var exEl) ? exEl.GetString() ?? "" : "";
                            var sourceRef = qEl.TryGetProperty("sourceReference", out var srEl) ? srEl.GetString() : null;

                            var hints = new List<string>();
                            if (qEl.TryGetProperty("hints", out var hEl) && hEl.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var h in hEl.EnumerateArray())
                                {
                                    var hs = h.GetString();
                                    if (!string.IsNullOrWhiteSpace(hs)) hints.Add(hs);
                                }
                            }

                            var thinking = new List<string>();
                            if (qEl.TryGetProperty("thinkingBreakdown", out var tbEl) && tbEl.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var tb in tbEl.EnumerateArray())
                                {
                                    var tbs = tb.GetString();
                                    if (!string.IsNullOrWhiteSpace(tbs)) thinking.Add(tbs);
                                }
                            }

                            var options = new List<GeneratedOptionDto>();
                            if (qEl.TryGetProperty("options", out var optEl) && optEl.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var opt in optEl.EnumerateArray())
                                {
                                    var optText = opt.TryGetProperty("text", out var otEl) ? otEl.GetString() ?? "" : "";
                                    var isCorrect = opt.TryGetProperty("isCorrect", out var icEl) && icEl.GetBoolean();
                                    var distractor = opt.TryGetProperty("distractorRationale", out var drEl) ? drEl.GetString() : null;
                                    if (!string.IsNullOrWhiteSpace(optText))
                                    {
                                        options.Add(new GeneratedOptionDto(optText, isCorrect, distractor));
                                    }
                                }
                            }

                            if (!string.IsNullOrWhiteSpace(prompt))
                            {
                                parsedQuestions.Add(new GeneratedQuestionDto(
                                    type,
                                    prompt,
                                    hints,
                                    correctAnswer,
                                    options.Count > 0 ? options : null,
                                    null, null, false,
                                    explanation,
                                    thinking.Count > 0 ? thinking : null,
                                    sourceRef
                                ));
                            }
                        }
                    }

                    if (parsedQuestions.Count >= Math.Min(3, targetCount))
                    {
                        var geminiResult = new GeneratedStudySetResult(
                            Guid.NewGuid(),
                            title,
                            summary,
                            bulletPoints.Count > 0 ? bulletPoints : new List<string> { $"Core principles from {title}." },
                            parsedQuestions,
                            rawText
                        );
                        _cache[cacheKey] = (DateTime.UtcNow, geminiResult);
                        return geminiResult;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Gemini cloud generation for '{Title}' failed, falling back to enhanced offline synthesizer", title);
            }
        }

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(title, rawText, requestedTypes, targetCount, setIndex, variant);
        _cache[cacheKey] = (DateTime.UtcNow, result);
        return result;
    }

    public async Task<GeneratedStudySetResult> GenerateStudySetFromImageAsync(
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
        if (imageBytes == null || imageBytes.Length == 0)
        {
            return GenerateEmptyFallback(title);
        }

        var effectiveApiKey = !string.IsNullOrWhiteSpace(apiKeyOverride)
            ? apiKeyOverride.Trim()
            : (!string.IsNullOrWhiteSpace(_apiKey) ? _apiKey : null);

        var imageHash = Convert.ToHexString(SHA256.HashData(imageBytes));
        var typesKey = string.Join("_", requestedTypes);
        var cacheKey = $"img_study_set_{imageHash}_{typesKey}_{targetCount}_{setIndex}_{variant ?? "default"}";

        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is GeneratedStudySetResult cachedResult)
        {
            _logger.LogInformation("Returning cached visual study set for {Title} (0ms response)", title);
            return cachedResult;
        }

        string? extractedOcrText = null;

        if (!string.IsNullOrWhiteSpace(effectiveApiKey))
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

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(title, extractedOcrText, requestedTypes, targetCount, setIndex, variant);
        _cache[cacheKey] = (DateTime.UtcNow, result);
        return result;
    }

    public async Task<AskTutorResponse> AskTutorAsync(
        AskTutorRequest request,
        CancellationToken cancellationToken = default)
    {
        var isExplicitlyOffline = _cloudCallsDisabled ||
            string.Equals(request.ApiKey, "none", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(request.ApiKey, "disabled", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(request.ApiKey, "offline", StringComparison.OrdinalIgnoreCase);

        var effectiveApiKey = !isExplicitlyOffline
            ? (!string.IsNullOrWhiteSpace(request.ApiKey)
                ? request.ApiKey.Trim()
                : (!string.IsNullOrWhiteSpace(_apiKey)
                    ? _apiKey
                    : (Environment.GetEnvironmentVariable("GEMINI_API_KEY") ?? Environment.GetEnvironmentVariable("GOOGLE_API_KEY"))))
            : null;

        var cacheKey = $"tutor_{request.Message.Trim().ToLowerInvariant()}_{request.ContextTopic?.ToLowerInvariant()}_{(effectiveApiKey != null ? "ai" : "local")}";
        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is AskTutorResponse cachedResponse)
        {
            return cachedResponse;
        }

        // If an API key is available, attempt cloud Gemini API call
        if (!string.IsNullOrWhiteSpace(effectiveApiKey))
        {
            var systemInstruction = request.IsTeachMeMode
                ? """
                You are 'Gemini Reverse Tutor' operating in 'TEACH THE AI' MODE (Feynman Learning Technique).
                Your pedagogical mission is to let the student demonstrate mastery by teaching you:
                - Act as an intelligent, curious, and inquisitive student learning this subject for the first time.
                - Ask the user to explain the core intuition, mechanisms, and edge cases of the topic.
                - Probe for deep understanding: "Wait, why does that happen? What if the input is empty or negative?"
                - Gently spot check subtle misconceptions: If they confuse terms (e.g. Stack vs Queue), politely ask them to clarify the difference with an everyday analogy.
                - Enthusiastically validate accurate reasoning and challenge them: "That makes complete sense! Can you give me a real-world scenario where a software engineer would choose this over an alternative?"
                - Conclude by rating their conceptual clarity and offering a gold-star takeaway.
                """
                : request.IsSocraticMode
                ? """
                You are 'Gemini Study Tutor' operating in SOCRATIC PEDAGOGICAL MODE.
                Your mission is to build durable, active student understanding, following proven educational principles:
                - DO NOT give away the final answer or solution immediately.
                - Scaffold the student's thinking by providing one focused, clarifying hint at a time.
                - Ask thought-provoking follow-up questions that guide the student to discover the answer themselves.
                - Point out common traps or misconceptions if they are veering off track.
                - If the student asks "What's the answer?", give a targeted hint and ask what they think the next step is.
                - When they reach the correct answer, celebrate their insight and ask a brief reflection question to anchor retention.
                """
                : """
                You are 'Gemini Study Tutor', an encouraging, academically rigorous AI tutor and coding mentor for university students.
                Guidelines:
                - When a student asks for code (e.g. Flutter, Dart, HTML, CSS, JavaScript, Python, C#, Java, SQL), provide complete, working, modern code formatted inside Markdown code blocks with language syntax highlighting and concise line-by-line explanations.
                - When a student asks for code documentation, docstrings, or API specifications, provide comprehensive, industry-standard documentation (e.g. C# XML docs with <summary>, <param>, <returns>, Python PEP 257/Google-style docstrings, JSDoc/TSDoc for TypeScript, and Dartdoc for Flutter) along with test cases and clear architectural notes.
                - Provide clear conceptual explanations followed by step-by-step logic.
                - Break down formulas, equations, or legal/scientific terminology clearly.
                - Connect concepts to practical applications and exam questions.
                - Keep explanations focused and digestible with Markdown formatting.
                - When a student asks for practice, test cases, or debugging help, provide clear explanations with executable test cases.
                """;

            var promptBuilder = new StringBuilder();
            promptBuilder.AppendLine(systemInstruction);
            if (!string.IsNullOrWhiteSpace(request.ContextTopic))
            {
                promptBuilder.AppendLine($"\nCURRENT COURSE / SUBJECT CONTEXT: {request.ContextTopic}");
            }
            if (!string.IsNullOrWhiteSpace(request.WeakConceptsContext))
            {
                promptBuilder.AppendLine($"\nSTUDENT'S RECENT WEAK CONCEPTS: {request.WeakConceptsContext}");
            }
            if (!string.IsNullOrWhiteSpace(request.RecentMistakesContext))
            {
                promptBuilder.AppendLine($"\nSTUDENT'S RECENT MISCONCEPTION PATTERNS: {request.RecentMistakesContext}");
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
                var (responseText, modelUsed) = await CallNativeGeminiWithFallbackAsync(payload, effectiveApiKey, cts.Token);
                if (!string.IsNullOrWhiteSpace(responseText))
                {
                    var response = new AskTutorResponse(responseText, modelUsed, DateTime.UtcNow);
                    _cache[cacheKey] = (DateTime.UtcNow, response);
                    return response;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Gemini tutor cloud call error, falling back to built-in academic synthesizer");
            }
        }

        // When offline, no key provided, or cloud Gemini is unreachable, synthesize high-yield academic response
        var synthesizedReply = AcademicTutorSynthesizer.SynthesizeResponse(request.Message, request.ContextTopic, request.History);
        var fallbackResponse = new AskTutorResponse(
            synthesizedReply,
            "Built-In Academic Engine",
            DateTime.UtcNow
        );
        _cache[cacheKey] = (DateTime.UtcNow, fallbackResponse);
        return fallbackResponse;
    }

    private async Task<(string? Text, string ModelUsed)> CallNativeGeminiWithFallbackAsync(
        object payload,
        string? apiKeyOverride,
        CancellationToken cancellationToken)
    {
        var key = !string.IsNullOrWhiteSpace(apiKeyOverride) ? apiKeyOverride.Trim() : _apiKey;
        if (string.IsNullOrWhiteSpace(key) ||
            key.Contains("YOUR_GEMINI_API_KEY") ||
            string.Equals(key, "none", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(key, "disabled", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(key, "offline", StringComparison.OrdinalIgnoreCase))
        {
            return (null, "Built-In Academic Engine");
        }

        var modelsToTry = new[] { _model, "gemini-3.6-flash", "gemini-3.8-flash", "gemini-2.5-flash", "gemini-2.0-flash" }
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var acquired = await _concurrencyLimiter.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
        if (!acquired)
        {
            _logger.LogWarning("Concurrency limiter saturated, skipping cloud call");
            return (null, "Built-In Academic Engine");
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
                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{modelName}:generateContent?key={key}";
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

            return (null, "Built-In Academic Engine");
        }
        finally
        {
            _concurrencyLimiter.Release();
        }
    }

    private Task<(string? Text, string ModelUsed)> CallNativeGeminiWithFallbackAsync(object payload, CancellationToken cancellationToken)
    {
        return CallNativeGeminiWithFallbackAsync(payload, null, cancellationToken);
    }

    private async Task<string?> CallNativeGeminiAsync(object payload, string? apiKeyOverride, CancellationToken cancellationToken)
    {
        var (text, _) = await CallNativeGeminiWithFallbackAsync(payload, apiKeyOverride, cancellationToken);
        return text;
    }

    private async Task<string?> CallNativeGeminiAsync(object payload, CancellationToken cancellationToken)
    {
        var (text, _) = await CallNativeGeminiWithFallbackAsync(payload, null, cancellationToken);
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
            var effectiveKey = !string.IsNullOrWhiteSpace(request.ApiKey)
                ? request.ApiKey.Trim()
                : (!string.IsNullOrWhiteSpace(_apiKey) ? _apiKey : null);
            var reply = await CallNativeGeminiAsync(payload, effectiveKey, cancellationToken);
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

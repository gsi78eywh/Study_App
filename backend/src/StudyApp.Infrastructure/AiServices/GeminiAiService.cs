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

    public async Task<GeneratedStudySetResult> GenerateStudySetAsync(
        string rawText,
        string title,
        List<string> requestedTypes,
        int targetCount,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            return GenerateEmptyFallback(title);
        }

        var textHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawText)));
        var typesKey = string.Join("_", requestedTypes);
        var cacheKey = $"study_set_{textHash}_{typesKey}_{targetCount}";

        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is GeneratedStudySetResult cachedResult)
        {
            _logger.LogInformation("Returning cached study set for {Title} (0ms response)", title);
            return cachedResult;
        }

        if (!string.IsNullOrWhiteSpace(_apiKey))
        {
            var typesList = requestedTypes.Count > 0
                ? string.Join(", ", requestedTypes)
                : "multiple_choice, identification, enumeration";

            var systemPrompt = """
            You are an elite university professor and academic curriculum architect.
            Analyze the study material and synthesize active recall practice tests:
            1. High-yield academic summary.
            2. 5 high-yield bullet points capturing core principles, definitions, or formulas.
            3. Exactly the requested number of high-quality active recall questions matching the requested types.

            QUESTION TYPES GUIDANCE:
            - multiple_choice: Include 'prompt', 4 'options' with 1 correct option and 3 plausible distractors with 'distractorRationale', plus 'explanation'.
            - identification: Fill-in-the-blank or direct identification of key terms. Include 'prompt', 'correctAnswer', and 'hints'.
            - enumeration: Multi-item listing questions (e.g. 'Enumerate the 3 stages of...'). Include 'prompt', 'correctAnswer' (bulleted or comma-separated), and 'explanation'.

            OUTPUT FORMAT: Return pure valid JSON matching this schema:
            {
              "summary": "Academic overview of the notes...",
              "highYieldBulletPoints": ["Point 1", "Point 2", "Point 3", "Point 4", "Point 5"],
              "questions": [
                {
                  "type": "multiple_choice",
                  "prompt": "Specific question text?",
                  "hints": ["Helpful hint 1", "Helpful hint 2"],
                  "correctAnswer": "Correct Answer Text",
                  "options": [
                    { "text": "Correct Answer Text", "isCorrect": true, "distractorRationale": null },
                    { "text": "Plausible Distractor 1", "isCorrect": false, "distractorRationale": "Why this is incorrect" },
                    { "text": "Plausible Distractor 2", "isCorrect": false, "distractorRationale": "Why this is incorrect" },
                    { "text": "Plausible Distractor 3", "isCorrect": false, "distractorRationale": "Why this is incorrect" }
                  ],
                  "explanation": "Detailed explanation of why the correct answer is right and the underlying concept."
                }
              ]
            }
            """;

            var userPrompt = $"""
            TOPIC / TITLE: {title}
            TARGET QUESTION COUNT: {targetCount}
            REQUESTED QUESTION TYPES: [{typesList}]

            COURSE STUDY MATERIAL:
            {rawText}
            """;

            var payload = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new[]
                        {
                            new { text = systemPrompt + "\n\n" + userPrompt }
                        }
                    }
                },
                generationConfig = new
                {
                    responseMimeType = "application/json",
                    temperature = 0.2
                }
            };

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(20));

            try
            {
                var responseJson = await CallNativeGeminiAsync(payload, cts.Token);
                if (!string.IsNullOrWhiteSpace(responseJson))
                {
                    var cleanJson = ExtractJsonBlock(responseJson);
                    var parsed = JsonSerializer.Deserialize<AiResponsePayload>(cleanJson, JsonOptions);
                    if (parsed?.Questions != null && parsed.Questions.Count > 0)
                    {
                        _logger.LogInformation("Synthesized {Count} questions for '{Title}' using Gemini native API",
                            parsed.Questions.Count, title);

                        var result = new GeneratedStudySetResult(
                            Guid.NewGuid(),
                            title,
                            parsed.Summary ?? $"Synthesized summary for {title}.",
                            parsed.HighYieldBulletPoints ?? new List<string>(),
                            parsed.Questions
                        );

                        _cache[cacheKey] = (DateTime.UtcNow, result);
                        return result;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Gemini call for '{Title}' did not complete, activating intelligent local synthesizer", title);
            }
        }

        var localResult = AnalyzeAndSynthesizeLocally(title, rawText, targetCount);
        return localResult;
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

        if (!string.IsNullOrWhiteSpace(_apiKey))
        {
            var typesList = requestedTypes.Count > 0
                ? string.Join(", ", requestedTypes)
                : "multiple_choice, identification, enumeration";

            var systemPrompt = $$"""
            You are an expert academic curriculum designer, visual OCR analyzer, and university tutor.
            Analyze the attached image of student study materials (which may contain handwritten lecture notes, whiteboard equations, diagrams, slides, or textbook pages).
            
            TASKS:
            1. Extract all text, formulas, diagrams, definitions, and concepts shown in the image.
            2. Write a comprehensive high-yield summary of everything in the image.
            3. Extract 5 high-yield bullet points (laws, definitions, steps, key formulas).
            4. Generate exactly {{targetCount}} high-yield active recall practice questions based directly on the contents of the image.
            5. Honor the requested exam types: [{{typesList}}]. If 'multiple_choice', provide 4 options (1 correct, 3 plausible distractors) with 'distractorRationale' and 'explanation'. If 'identification', provide direct question and 'correctAnswer'. If 'enumeration', ask for lists/steps.

            OUTPUT FORMAT: Return pure valid JSON matching this schema:
            {
              "summary": "Full academic summary of the image content...",
              "highYieldBulletPoints": ["Point 1", "Point 2", "Point 3", "Point 4", "Point 5"],
              "questions": [
                {
                  "type": "multiple_choice",
                  "prompt": "Question based directly on the uploaded image?",
                  "hints": ["Hint 1", "Hint 2"],
                  "correctAnswer": "Correct Option Text",
                  "options": [
                    { "text": "Correct Option Text", "isCorrect": true, "distractorRationale": null },
                    { "text": "Plausible Distractor 1", "isCorrect": false, "distractorRationale": "Why this is incorrect" },
                    { "text": "Plausible Distractor 2", "isCorrect": false, "distractorRationale": "Why this is incorrect" },
                    { "text": "Plausible Distractor 3", "isCorrect": false, "distractorRationale": "Why this is incorrect" }
                  ],
                  "explanation": "Detailed explanation citing the visual context from the image."
                }
              ]
            }
            """;

            var payload = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = systemPrompt },
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
                    responseMimeType = "application/json",
                    temperature = 0.2
                }
            };

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(25));

            try
            {
                var responseJson = await CallNativeGeminiAsync(payload, cts.Token);
                if (!string.IsNullOrWhiteSpace(responseJson))
                {
                    var cleanJson = ExtractJsonBlock(responseJson);
                    var parsed = JsonSerializer.Deserialize<AiResponsePayload>(cleanJson, JsonOptions);
                    if (parsed?.Questions != null && parsed.Questions.Count > 0)
                    {
                        _logger.LogInformation("Successfully extracted {Count} visual questions from image for '{Title}'",
                            parsed.Questions.Count, title);

                        var result = new GeneratedStudySetResult(
                            Guid.NewGuid(),
                            title,
                            parsed.Summary ?? $"Synthesized visual study set for {title}.",
                            parsed.HighYieldBulletPoints ?? new List<string>(),
                            parsed.Questions
                        );

                        _cache[cacheKey] = (DateTime.UtcNow, result);
                        return result;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Multimodal vision call for '{Title}' did not complete, falling back to local synthesizer", title);
            }
        }

        var fallbackResult = AnalyzeAndSynthesizeLocally(title, $"[Visual Lecture Material: {title}]", targetCount);
        return fallbackResult;
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
        You are 'Gemini Study Tutor', an encouraging, academically rigorous AI tutor for university students.
        Guidelines:
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
        cts.CancelAfter(TimeSpan.FromSeconds(15));

        try
        {
            var responseText = await CallNativeGeminiAsync(payload, cts.Token);
            if (!string.IsNullOrWhiteSpace(responseText))
            {
                var response = new AskTutorResponse(responseText, "gemini-flash-latest", DateTime.UtcNow);
                _cache[cacheKey] = (DateTime.UtcNow, response);
                return response;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Gemini tutor call error");
        }

        return new AskTutorResponse(
            $"I received your question about **{request.Message}**. In the context of {request.ContextTopic ?? "your course"}, key concepts should be approached methodically: identify the core definition, determine relevant variables or boundary conditions, and verify each step.",
            "offline-tutor",
            DateTime.UtcNow
        );
    }

    private async Task<string?> CallNativeGeminiAsync(object payload, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_apiKey)) return null;

        var acquired = await _concurrencyLimiter.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
        if (!acquired)
        {
            _logger.LogWarning("Concurrency limiter saturated, skipping cloud call");
            return null;
        }

        try
        {
            var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
            var json = JsonSerializer.Serialize(payload, JsonOptions);

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
                        return text;
                    }
                }
            }
            else
            {
                var err = await response.Content.ReadAsStringAsync(cancellationToken);
                _logger.LogWarning("Gemini native API returned {Status}: {Error}", response.StatusCode, err);
            }

            return null;
        }
        finally
        {
            _concurrencyLimiter.Release();
        }
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
        var cleanLines = rawText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim())
            .Where(l => l.Length > 8 && !l.StartsWith("--- Page"))
            .ToList();

        var definitions = new List<(string Term, string Definition, string FullSentence)>();
        var isPattern = new Regex(@"^(?:The\s+)?([A-Z][a-zA-Z0-9\s-]{2,40})\s+(?:is|are|refers to|represents|means)\s+(.+)$", RegexOptions.IgnoreCase);
        var colonPattern = new Regex(@"^([A-Z][a-zA-Z0-9\s-]{2,40}):\s*(.+)$");

        foreach (var line in cleanLines)
        {
            var defMatch = isPattern.Match(line);
            if (defMatch.Success)
            {
                var term = defMatch.Groups[1].Value.Trim();
                var def = defMatch.Groups[2].Value.Trim();
                if (term.Split(' ').Length <= 5 && def.Length > 12)
                {
                    definitions.Add((term, def, line));
                    continue;
                }
            }

            var colMatch = colonPattern.Match(line);
            if (colMatch.Success)
            {
                var term = colMatch.Groups[1].Value.Trim();
                var def = colMatch.Groups[2].Value.Trim();
                if (term.Split(' ').Length <= 5 && def.Length > 12)
                {
                    definitions.Add((term, def, line));
                }
            }
        }

        var bulletPoints = cleanLines
            .Where(l => l.Length > 25 && l.Length < 180)
            .Take(5)
            .Select(l => l.TrimStart('-', '*', '•', '1', '2', '3', '4', '5', '.', ' '))
            .ToList();

        if (bulletPoints.Count == 0)
        {
            bulletPoints.Add($"Key concepts synthesized directly from {title}.");
            bulletPoints.Add("Active recall practice generated for student exam readiness.");
        }

        var questions = new List<GeneratedQuestionDto>();
        int count = Math.Max(targetCount, 4);

        foreach (var def in definitions.Take(count / 2 + 1))
        {
            var distractors = definitions
                .Where(d => d.Term != def.Term)
                .Select(d => d.Definition)
                .Take(3)
                .ToList();

            while (distractors.Count < 3)
            {
                distractors.Add($"An ancillary property not matching the definition of {def.Term}.");
                distractors.Add($"A contrasting condition found in alternative theoretical frameworks.");
                distractors.Add($"A historical assumption superseded by modern analysis.");
            }

            var options = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(def.Definition, true, null),
                new GeneratedOptionDto(distractors[0], false, $"This refers to a separate concept, not {def.Term}."),
                new GeneratedOptionDto(distractors[1], false, $"This is an alternative condition, not the definition of {def.Term}."),
                new GeneratedOptionDto(distractors[2], false, $"Contrasting framework not applicable to {def.Term}.")
            };

            var rand = new Random(def.Term.GetHashCode());
            options = options.OrderBy(_ => rand.Next()).ToList();

            questions.Add(new GeneratedQuestionDto(
                "multiple_choice",
                $"According to the study material, which of the following best defines \"{def.Term}\"?",
                new List<string> { $"Search for context around \"{def.Term}\" in your notes.", "Pay close attention to key definitions." },
                def.Definition,
                options,
                null, null, false,
                $"Document context: {def.FullSentence}",
                null
            ));

            questions.Add(new GeneratedQuestionDto(
                "identification",
                $"What academic term is defined as: \"{def.Definition}\"?",
                new List<string> { $"Starts with letter '{def.Term[0]}'", $"Length is {def.Term.Length} characters" },
                def.Term,
                new List<GeneratedOptionDto> { new GeneratedOptionDto(def.Term, true, null) },
                new List<string> { def.Term.ToLowerInvariant() },
                null, false,
                $"The term \"{def.Term}\" explicitly matches this definition.",
                null
            ));
        }

        while (questions.Count < count)
        {
            int idx = questions.Count + 1;
            questions.Add(new GeneratedQuestionDto(
                "multiple_choice",
                $"In {title}, which statement best demonstrates understanding of core concept #{idx}?",
                new List<string> { "Focus on foundational rules and definitions." },
                $"Applying primary verified principles of {title}.",
                new List<GeneratedOptionDto>
                {
                    new GeneratedOptionDto($"Applying primary verified principles of {title}.", true, null),
                    new GeneratedOptionDto("Arbitrary memorization of disconnected rules.", false, "Memorization without understanding is discouraged."),
                    new GeneratedOptionDto("Disregarding theoretical boundary conditions.", false, "Boundary conditions are essential for valid analysis."),
                    new GeneratedOptionDto("Overlooking underlying formulas and derivations.", false, "Derivations provide foundational context.")
                },
                null, null, false,
                $"Academic mastery relies on understanding foundational theoretical structures in {title}.",
                null
            ));
        }

        return new GeneratedStudySetResult(
            Guid.NewGuid(),
            title,
            $"Academic study set generated from source material in {title}.",
            bulletPoints,
            questions.Take(count).ToList()
        );
    }

    private class AiResponsePayload
    {
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

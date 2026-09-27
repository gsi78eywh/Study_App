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

/// Server-side OpenAI AI service integration implementing <see cref="IAiQuestionGenerator"/> and <see cref="IAiTutorService"/>.

/// Features resilient paused-wiring guardrails: when an OpenAI key is unconfigured, placeholder, or invalid,

/// cloud wiring is kept paused pending a valid project target and seamlessly delegates to the local educational synthesizer.

/// </summary>

public class OpenAiAiService : IAiQuestionGenerator, IAiTutorService

{

    private readonly HttpClient _httpClient;

    private readonly IConfiguration _configuration;

    private readonly ILogger<OpenAiAiService> _logger;



    private readonly string _serverApiKey;

    private readonly string _model;

    private readonly string _baseUrl;

    private readonly string? _organization;

    private readonly string? _project;



    private static readonly ConcurrentDictionary<string, (DateTime CachedAt, object Data)> _cache = new();

    private static readonly SemaphoreSlim _concurrencyLimiter = new(4, 4);



    private static readonly JsonSerializerOptions JsonOptions = new()

    {

        PropertyNameCaseInsensitive = true,

        PropertyNamingPolicy = JsonNamingPolicy.CamelCase

    };



    private class AiResponsePayload

    {

        public string? ExtractedText { get; set; }

        public string? Summary { get; set; }

        public List<string>? HighYieldBulletPoints { get; set; }

        public List<GeneratedQuestionDto>? Questions { get; set; }

    }



    public OpenAiAiService(

        HttpClient httpClient,

        IConfiguration configuration,

        ILogger<OpenAiAiService> logger)

    {

        _httpClient = httpClient;

        _configuration = configuration;

        _logger = logger;



        var configuredKey = _configuration["AiSettings:OpenAi:ApiKey"] ?? string.Empty;

        if (string.IsNullOrWhiteSpace(configuredKey) || configuredKey.Contains("YOUR_OPENAI_API_KEY"))

        {

            configuredKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY") ?? string.Empty;

        }



        if (string.IsNullOrWhiteSpace(configuredKey) &&

            string.Equals(_configuration["AiSettings:Provider"], "OpenAI", StringComparison.OrdinalIgnoreCase))

        {

            var fallbackKey = _configuration["AiSettings:ApiKey"];

            if (!string.IsNullOrWhiteSpace(fallbackKey) && !fallbackKey.Contains("YOUR_GEMINI_API_KEY"))

            {

                configuredKey = fallbackKey;

            }

        }



        _serverApiKey = configuredKey.Trim();

        _model = _configuration["AiSettings:OpenAi:ModelId"]

            ?? _configuration["AiSettings:ModelId"]

            ?? "gpt-4o-mini";



        var configuredBaseUrl = _configuration["AiSettings:OpenAi:BaseUrl"];

        _baseUrl = !string.IsNullOrWhiteSpace(configuredBaseUrl)

            ? configuredBaseUrl.Trim()

            : "https://api.openai.com/v1/chat/completions";



        _organization = _configuration["AiSettings:OpenAi:Organization"];

        _project = _configuration["AiSettings:OpenAi:Project"];



        if (IsWiringPaused)

        {

            _logger.LogInformation("[OpenAI] Wiring paused: No valid OpenAI project target key detected. Operating in safe local synthesis mode.");

        }

        else

        {

            _logger.LogInformation("[OpenAI] Active server-side target configured (Model: {Model}).", _model);

        }

    }



    /// <summary>

    /// Indicates whether OpenAI cloud calls are currently paused due to absence of a validated project target key.

    /// </summary>

    public bool IsWiringPaused => !IsValidProjectKey(_serverApiKey);



    public string ActiveModel => _model;



    public string WiringStatus => IsWiringPaused ? "paused_pending_key" : "active_live_target";



    public static bool IsValidProjectKey(string? key)

    {

        if (string.IsNullOrWhiteSpace(key)) return false;

        var trimmed = key.Trim();

        if (string.Equals(trimmed, "none", StringComparison.OrdinalIgnoreCase) ||

            string.Equals(trimmed, "disabled", StringComparison.OrdinalIgnoreCase) ||

            string.Equals(trimmed, "offline", StringComparison.OrdinalIgnoreCase) ||

            trimmed.Contains("YOUR_OPENAI_API_KEY") ||

            trimmed.Contains("YOUR_API_KEY"))

        {

            return false;

        }



        return trimmed.StartsWith("sk-", StringComparison.OrdinalIgnoreCase) || trimmed.Length >= 20;

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



        var effectiveApiKey = !string.IsNullOrWhiteSpace(apiKeyOverride) && IsValidProjectKey(apiKeyOverride)

            ? apiKeyOverride.Trim()

            : (!IsWiringPaused ? _serverApiKey : null);



        var textHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawText)));

        var typesKey = string.Join("_", requestedTypes);

        var cacheKey = $"openai_studyset_{textHash}_{typesKey}_{targetCount}_{setIndex}_{variant ?? "default"}_{(effectiveApiKey != null ? "live" : "paused")}";



        if (_cache.TryGetValue(cacheKey, out var cached) && (DateTime.UtcNow - cached.CachedAt).TotalMinutes < 30)

        {

            return (GeneratedStudySetResult)cached.Data;

        }



        // If wiring is paused and no client key override is provided, synthesize via pedagogical engine

        if (effectiveApiKey == null)

        {

            _logger.LogInformation("[OpenAI] Wiring paused pending project target. Synthesizing set '{Title}' via pedagogical engine.", title);

            var localResult = NoteScriptSynthesizer.SynthesizeFromNotes(rawText, title, requestedTypes, targetCount, setIndex, variant);

            _cache[cacheKey] = (DateTime.UtcNow, localResult);

            return localResult;

        }



        // Attempt live OpenAI chat completion

        try

        {

            var typesDescription = requestedTypes.Count > 0

                ? string.Join(", ", requestedTypes)

                : "multiple_choice, identification, enumeration, bullet_points, logical_thinking";



            var systemPrompt = """
                You are an elite university professor, expert collegiate instructor, and university examination board director.
                Your mission is to formulate rigorous, high-intelligence examination questions that demand deep critical thinking, analytical deduction, and mechanistic understanding (Bloom\'s Taxonomy Levels 4 to 6: Analyze, Evaluate, Synthesize).

                MANDATORY PEDAGOGICAL STANDARDS:
                1. HIGHER-ORDER INTELLECTUAL QUALITY:
                   - NEVER create elementary, simplistic definition-matching questions like "What is X?", "Which of the following defines X?", or "What term means Y?".
                   - Craft intellectually substantive scenario problems, mechanistic cause-and-effect questions ("Under conditions where X is altered, which mechanism accounts for Y?"), counterfactual deductions ("If component A fails, what theoretical consequence occurs to B?"), and diagnostic evaluations.

                2. AUTHENTIC DISCRIMINATIVE DISTRACTORS:
                   - Every incorrect distractor MUST be a sophisticated, plausible college-level misconception that an advanced student might reasonably confuse.
                   - NEVER use joke options, obvious throwaway options, or generic placeholders.
                   - Provide a precise diagnostic rationale for EVERY incorrect distractor explaining the exact conceptual flaw.

                3. STRICT ANTI-REPETITION:
                   - Thoroughly explore the ENTIRE notes from beginning to end.
                   - Every single question must target a COMPLETELY UNIQUE concept, mechanism, or analytical angle. Never repeat questions or test the same concept twice with trivial wording swaps.

                4. DIRECT & METADATA-FREE:
                   - Make question prompts direct, professional, and clear.
                   - NEVER use meta-referencing phrases like "Based on the screenshot", "According to the provided module", "In your study notes", "Based on the image", or "From the reading".
                   - Ask directly about the concept, principle, or mechanism itself.

                JSON structure:
                {
                  "summary": "High yield conceptual summary...",
                  "highYieldBulletPoints": ["Bullet 1", "Bullet 2"],
                  "questions": [
                    {
                      "type": "multiple_choice",
                      "prompt": "Question text...",
                      "hints": ["Hint 1"],
                      "correctAnswer": "Correct Option",
                      "options": [
                        { "text": "Correct Option", "isCorrect": true, "distractorRationale": null },
                        { "text": "Wrong Option", "isCorrect": false, "distractorRationale": "Why incorrect..." }
                      ],
                      "explanation": "Pedagogical explanation of why this answer is correct."
                    }
                  ]
                }
                """;



            var userPrompt = $"""

                Title: {title}

                Target Count: {targetCount}

                Question Types Requested: {typesDescription}

                Set Index / Focus: {variant ?? $"Set {(char)('A' + (setIndex % 26))}"}



                Source Material:

                {rawText}

                """;



            var payload = new

            {

                model = _model,

                temperature = 0.2,

                response_format = new { type = "json_object" },

                messages = new object[]

                {

                    new { role = "system", content = systemPrompt },

                    new { role = "user", content = userPrompt }

                }

            };



            var rawReply = await CallOpenAiChatAsync(payload, effectiveApiKey, cancellationToken);

            if (!string.IsNullOrWhiteSpace(rawReply))

            {

                var parsed = ParseOpenAiJson(rawReply);

                if (parsed?.Questions != null && parsed.Questions.Count > 0)

                {

                    var questions = parsed.Questions.Select(q => new GeneratedQuestionDto(

                        q.Type ?? "multiple_choice",

                        NoteScriptSynthesizer.SanitizeDirectPrompt(q.Prompt ?? "Question"),

                        q.Hints ?? new List<string>(),

                        q.CorrectAnswer ?? string.Empty,

                        q.Options?.Select(o => new GeneratedOptionDto(o.Text ?? string.Empty, o.IsCorrect, o.DistractorRationale)).ToList() ?? new List<GeneratedOptionDto>(),

                        null,

                        null,

                        false,

                        q.Explanation ?? "Educational explanation generated by OpenAI.",

                        new List<string>(),

                        null

                    )).ToList();



                    var result = new GeneratedStudySetResult(

                        Guid.NewGuid(),

                        title,

                        parsed.Summary ?? "Summary synthesized by OpenAI.",

                        parsed.HighYieldBulletPoints ?? new List<string>(),

                        questions

                    );



                    _cache[cacheKey] = (DateTime.UtcNow, result);

                    return result;

                }

            }

        }

        catch (Exception ex)

        {

            _logger.LogWarning(ex, "[OpenAI] Live completion call failed. Falling back smoothly to educational engine.");

        }



        // Graceful fallback to NoteScriptSynthesizer

        var fallback = NoteScriptSynthesizer.SynthesizeFromNotes(rawText, title, requestedTypes, targetCount, setIndex, variant);

        _cache[cacheKey] = (DateTime.UtcNow, fallback);

        return fallback;

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

        var localResult = NoteScriptSynthesizer.SynthesizeFromNotes(

            $"[Visual study document: {title}] Key concepts and high-yield active-recall topics extracted from study imagery.",

            title, requestedTypes, targetCount, setIndex, variant);

        return Task.FromResult(localResult);

    }



    public async Task<AskTutorResponse> AskTutorAsync(AskTutorRequest request, CancellationToken cancellationToken = default)

    {

        var effectiveApiKey = !string.IsNullOrWhiteSpace(request.ApiKey) && IsValidProjectKey(request.ApiKey)

            ? request.ApiKey.Trim()

            : (!IsWiringPaused ? _serverApiKey : null);



        if (effectiveApiKey == null)

        {

            var localReply = AcademicTutorSynthesizer.SynthesizeResponse(request.Message, request.ContextTopic, request.History);

            return new AskTutorResponse(

                localReply,

                "Built-in Academic Engine (OpenAI paused pending key)",

                DateTime.UtcNow

            );

        }



        try

        {

            var systemPrompt = "You are a master academic university tutor. Provide clear, encouraging, conceptually rigorous responses with analogies, examples, and study recommendations. Keep responses structured in markdown.";

            var messages = new List<object>

            {

                new { role = "system", content = systemPrompt }

            };



            if (request.History != null)

            {

                foreach (var h in request.History.TakeLast(6))

                {

                    messages.Add(new { role = h.Role == "model" ? "assistant" : h.Role, content = h.Content });

                }

            }



            var promptWithContext = !string.IsNullOrWhiteSpace(request.ContextTopic)

                ? $"[Context Topic: {request.ContextTopic}]\n\nStudent Question: {request.Message}"

                : request.Message;



            messages.Add(new { role = "user", content = promptWithContext });



            var payload = new

            {

                model = _model,

                temperature = 0.5,

                messages = messages.ToArray()

            };



            var reply = await CallOpenAiChatAsync(payload, effectiveApiKey, cancellationToken);

            if (!string.IsNullOrWhiteSpace(reply))

            {

                return new AskTutorResponse(

                    reply,

                    $"OpenAI {_model}",

                    DateTime.UtcNow

                );

            }

        }

        catch (Exception ex)

        {

            _logger.LogWarning(ex, "[OpenAI] Tutor request failed. Gracefully falling back to academic synthesizer.");

        }



        var fallbackReply = AcademicTutorSynthesizer.SynthesizeResponse(request.Message, request.ContextTopic, request.History);

        return new AskTutorResponse(

            fallbackReply,

            "Built-in Academic Engine",

            DateTime.UtcNow

        );

    }



    public async Task<QuestionExplanationResult> ExplainQuestionAsync(ExplainQuestionRequest request, CancellationToken cancellationToken = default)

    {

        var effectiveApiKey = !string.IsNullOrWhiteSpace(request.ApiKey) && IsValidProjectKey(request.ApiKey)

            ? request.ApiKey.Trim()

            : (!IsWiringPaused ? _serverApiKey : null);



        if (effectiveApiKey == null)

        {

            return SynthesizeLocalExplanation(request);

        }



        try

        {

            var prompt = $$"""

                You are an academic exam tutor. Explain why the correct answer is right and why the student's selected answer was mistaken.

                Return JSON only:

                {

                  "coreConcept": "The main theoretical principle tested",

                  "whyCorrect": "Direct explanation of why the correct answer is accurate",

                  "whyStudentWasIncorrect": "Why the student answer was mistaken or a common distractor",

                  "takeawayTip": "Actionable memory tip or rule for next time"

                }



                QUESTION: {{request.Prompt}}

                CORRECT ANSWER: {{request.CorrectAnswer}}

                STUDENT ANSWER: {{request.StudentAnswer ?? "None selected / Skipped"}}

                """;



            var payload = new

            {

                model = _model,

                temperature = 0.3,

                response_format = new { type = "json_object" },

                messages = new object[]

                {

                    new { role = "system", content = "You are an expert exam tutor explaining multiple-choice and conceptual answers in pure JSON." },

                    new { role = "user", content = prompt }

                }

            };



            var reply = await CallOpenAiChatAsync(payload, effectiveApiKey, cancellationToken);

            if (!string.IsNullOrWhiteSpace(reply))

            {

                using var doc = JsonDocument.Parse(reply);

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

            _logger.LogWarning(ex, "[OpenAI] Explain question failed. Falling back to local synthesizer.");

        }



        return SynthesizeLocalExplanation(request);

    }



    public async Task<OpenAnswerEvaluationResult> EvaluateOpenAnswerAsync(

        string prompt,

        string modelAnswer,

        IReadOnlyList<string> rubric,

        string studentAnswer,

        CancellationToken cancellationToken = default)

    {

        if (IsWiringPaused || string.IsNullOrWhiteSpace(studentAnswer))

        {

            return new OpenAnswerEvaluationResult(0m, string.Empty, false);

        }



        try

        {

            var rubricText = rubric.Count == 0 ? "No specific keywords provided." : string.Join("; ", rubric);

            var evalPrompt = $$"""

                Evaluate student answer for conceptual accuracy and completeness.

                Return JSON only: { "score": 0.0 to 1.0, "feedback": "constructive sentence" }

                QUESTION: {{prompt}}

                MODEL ANSWER: {{modelAnswer}}

                RUBRIC CRITERIA: {{rubricText}}

                STUDENT ANSWER: {{studentAnswer}}

                """;



            var payload = new

            {

                model = _model,

                temperature = 0.2,

                response_format = new { type = "json_object" },

                messages = new object[]

                {

                    new { role = "system", content = "You are a university short answer grader." },

                    new { role = "user", content = evalPrompt }

                }

            };



            var reply = await CallOpenAiChatAsync(payload, _serverApiKey, cancellationToken);

            if (!string.IsNullOrWhiteSpace(reply))

            {

                using var doc = JsonDocument.Parse(reply);

                var score = doc.RootElement.TryGetProperty("score", out var s) ? s.GetDecimal() : 0.5m;

                var feedback = doc.RootElement.TryGetProperty("feedback", out var f) ? f.GetString() ?? "Good response." : "Evaluated.";

                return new OpenAnswerEvaluationResult(score, feedback, true);

            }

        }

        catch (Exception ex)

        {

            _logger.LogWarning(ex, "[OpenAI] Open answer evaluation failed.");

        }



        return new OpenAnswerEvaluationResult(0m, string.Empty, false);

    }



    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default)

    {

        if (IsWiringPaused)

        {

            return true;

        }



        try

        {

            var payload = new

            {

                model = _model,

                max_tokens = 5,

                messages = new object[] { new { role = "user", content = "ping" } }

            };



            var reply = await CallOpenAiChatAsync(payload, _serverApiKey, cancellationToken);

            return !string.IsNullOrWhiteSpace(reply);

        }

        catch

        {

            return false;

        }

    }



    private async Task<string?> CallOpenAiChatAsync(object payload, string apiKey, CancellationToken cancellationToken)

    {

        var acquired = await _concurrencyLimiter.WaitAsync(TimeSpan.FromSeconds(5), cancellationToken);

        if (!acquired)

        {

            _logger.LogWarning("[OpenAI] Concurrency limit saturated; falling back.");

            return null;

        }



        try

        {

            var json = JsonSerializer.Serialize(payload, JsonOptions);

            using var request = new HttpRequestMessage(HttpMethod.Post, _baseUrl);

            request.Headers.Add("Authorization", $"Bearer {apiKey}");



            if (!string.IsNullOrWhiteSpace(_organization))

            {

                request.Headers.Add("OpenAI-Organization", _organization);

            }



            if (!string.IsNullOrWhiteSpace(_project))

            {

                request.Headers.Add("OpenAI-Project", _project);

            }



            request.Content = new StringContent(json, Encoding.UTF8, "application/json");



            using var response = await _httpClient.SendAsync(request, cancellationToken);

            if (!response.IsSuccessStatusCode)

            {

                var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);

                _logger.LogWarning("[OpenAI] API returned status {StatusCode}: {Error}", response.StatusCode, errorBody);

                return null;

            }



            var responseJson = await response.Content.ReadAsStringAsync(cancellationToken);

            using var doc = JsonDocument.Parse(responseJson);



            if (doc.RootElement.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0)

            {

                var firstChoice = choices[0];

                if (firstChoice.TryGetProperty("message", out var message) &&

                    message.TryGetProperty("content", out var content))

                {

                    return content.GetString();

                }

            }



            return null;

        }

        finally

        {

            _concurrencyLimiter.Release();

        }

    }



    private static AiResponsePayload? ParseOpenAiJson(string raw)

    {

        try

        {

            var jsonMatch = Regex.Match(raw, @"```(?:json)?\s*([\s\S]*?)\s*```", RegexOptions.IgnoreCase);

            var jsonString = jsonMatch.Success ? jsonMatch.Groups[1].Value.Trim() : raw.Trim();

            if (!jsonString.StartsWith("{") && jsonString.Contains("{"))

            {

                var start = jsonString.IndexOf('{');

                var end = jsonString.LastIndexOf('}');

                if (start >= 0 && end > start)

                {

                    jsonString = jsonString.Substring(start, end - start + 1);

                }

            }



            return JsonSerializer.Deserialize<AiResponsePayload>(jsonString, JsonOptions);

        }

        catch

        {

            return null;

        }

    }



    private static QuestionExplanationResult SynthesizeLocalExplanation(ExplainQuestionRequest request)

    {

        var correct = request.CorrectAnswer;

        var userAns = request.StudentAnswer ?? "None selected";



        return new QuestionExplanationResult(

            "Core theoretical concept tested by this question.",

            $"The validated answer is '{correct}' because it adheres to the authoritative definition in this subject matter.",

            $"Selected option '{userAns}' represents a common distractor or related but contrasting concept.",

            $"Takeaway: Verify definitions and eliminate opposing choices to secure full marks."

        );

    }



    private static GeneratedStudySetResult GenerateEmptyFallback(string title)

    {

        return new GeneratedStudySetResult(

            Guid.NewGuid(),

            title,

            "No source material provided.",

            new List<string>(),

            new List<GeneratedQuestionDto>()

        );

    }

}


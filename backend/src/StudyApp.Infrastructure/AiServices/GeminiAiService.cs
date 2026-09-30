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



    /// <summary>

    /// Strict Philippine DSWD / CWC child-safe harm blocking filters for lower-grade elementary and school environments.

    /// Blocks harassment, hate speech, sexually explicit, and dangerous content at BLOCK_LOW_AND_ABOVE.

    /// </summary>

    private static readonly object[] ChildSafeSafetySettings = new[]

    {

        new { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_LOW_AND_ABOVE" },

        new { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_LOW_AND_ABOVE" },

        new { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_LOW_AND_ABOVE" },

        new { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_LOW_AND_ABOVE" }

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
                You are an expert pedagogical instructor and examination specialist.
                Your mission is to formulate rigorous, accurate, high-quality study items, questions, and flashcards grounded directly in the provided material.

                DOMAIN ADAPTATION RULES:
                1. ACADEMIC / SCIENTIFIC TEXTS:
                   - Focus on deep mechanistic understanding, cause-and-effect, and analytical deduction (Bloom's Taxonomy Levels 4 to 6).
                   - Craft substantive scenario questions, operational mechanisms, and diagnostic evaluations.

                2. REAL-WORLD, COMMERCIAL, WEB, OR INFORMATIONAL TEXTS (e.g. cafes, restaurants, businesses, menus, travel guides, articles, locations, technical guides):
                   - Extract CONCRETE, REAL-WORLD FACTS stated directly in the text: specific prices, menu items, ingredients, location addresses, landmarks, directions, operating hours, policies, reviews, and distinct attributes.
                   - Examples:
                     * "Where is [Entity] located?" -> "[Exact address/barangay/city]"
                     * "What is the price of [Menu Item]?" -> "[Exact currency/price stated]"
                     * "What landmark do travelers pass on the way to [Destination]?" -> "[Landmark name]"
                     * "How can visitors travel to [Entity] from [Origin]?" -> "[Route/bus/transit directions]"

                3. STRICT ANTI-CIRCULAR & FACTUAL INTEGRITY GUARDS:
                   - NEVER create circular questions where the page title or URL is asked about itself (e.g., NEVER ask "What is the primary role of X in X?").
                   - The answer must NEVER be merely the document title or URL.
                   - NEVER output placeholder sentences like "Core academic principles and subject knowledge of...".
                   - Every single question must be grounded in an actual fact explicitly written in the provided text.

                4. AUTHENTIC DISTRACTORS:
                   - For multiple-choice questions, every distractor must be plausible and drawn from adjacent concepts, items, prices, or details in the text.
                   - NEVER use joke options, obvious throwaway options, or generic placeholders.

                5. DIRECT & METADATA-FREE:
                   - Make question prompts direct and professional.
                   - NEVER use meta-referencing phrases like "Based on the text", "According to the notes", "In the provided document", or "As seen on the website".

                STUDY MATERIAL TITLE: {{title}}
                REQUESTED QUESTION/CARD TYPES: {{typesListStr}}
                TARGET ITEM COUNT: {{targetCount}}
                SET INDEX / VARIANT: {{setIndex}} / {{variant ?? "default"}}

                STUDY MATERIAL CONTENT:
                {{rawText}}

                INSTRUCTIONS FOR FLASHCARDS:
                If flashcards are requested or needed, create active-recall flashcards testing concrete knowledge from the text (Front: clear question asking for a specific fact, mechanism, price, or location; Back: concise, accurate answer).
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

                    },

                    safetySettings = ChildSafeSafetySettings

                };



                using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

                cts.CancelAfter(TimeSpan.FromSeconds(12));



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

                            var prompt = NoteScriptSynthesizer.SanitizeDirectPrompt(qEl.TryGetProperty("prompt", out var pEl) ? pEl.GetString() ?? "" : "");

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

                },

                safetySettings = ChildSafeSafetySettings

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
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        var isExplicitlyOffline = _cloudCallsDisabled ||
            string.Equals(request.ApiKey, "none", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(request.ApiKey, "disabled", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(request.ApiKey, "offline", StringComparison.OrdinalIgnoreCase);

        var effectiveApiKey = !isExplicitlyOffline
            ? (!string.IsNullOrWhiteSpace(request.ApiKey)
                ? request.ApiKey.Trim()
                : (!string.IsNullOrWhiteSpace(_apiKey)
                    ? _apiKey
                    : (Environment.GetEnvironmentVariable("AiSettings__ApiKey")
                        ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY")
                        ?? Environment.GetEnvironmentVariable("GOOGLE_API_KEY"))))
            : null;

        var notesAttached = !string.IsNullOrWhiteSpace(request.ContextTopic) ||
                            !string.IsNullOrWhiteSpace(request.WeakConceptsContext) ||
                            !string.IsNullOrWhiteSpace(request.RecentMistakesContext);

        var cacheKey = $"tutor_{request.Message.Trim().ToLowerInvariant()}_{request.ContextTopic?.ToLowerInvariant()}_{request.IsSocraticMode}";
        if (_cache.TryGetValue(cacheKey, out var cached) && cached.Data is AskTutorResponse cachedResponse)
        {
            return cachedResponse;
        }

        if (string.IsNullOrWhiteSpace(effectiveApiKey) || effectiveApiKey.Contains("YOUR_GEMINI_API_KEY"))
        {
            _logger.LogInformation("No valid cloud Gemini API key; using local AcademicTutorSynthesizer.");
            var localReply = AcademicTutorSynthesizer.SynthesizeResponse(request.Message, request.ContextTopic, request.History);
            var localResponse = new AskTutorResponse(
                localReply,
                "Built-In Academic Engine",
                DateTime.UtcNow,
                0.0,
                null,
                notesAttached
            );
            _cache[cacheKey] = (DateTime.UtcNow, localResponse);
            return localResponse;
        }

        // Real System Instruction as specified by User Requirements
        var systemInstruction = request.IsSocraticMode
            ? """
            You are a study tutor operating in Socratic mode. Answer the student's actual request. Use the provided course notes first, and say when something isn't in the notes. If you're unsure, say so instead of guessing. If the request is unclear, ask one short clarifying question. If the student asks for a diagram, reply with a Mermaid flowchart in a mermaid code block plus two sentences of explanation. Never invent facts, formulas, or citations. Keep answers under 200 words unless asked for more. In Socratic mode, give hints and questions, not final answers.
            """
            : """
            You are a study tutor. Answer the student's actual request. Use the provided course notes first, and say when something isn't in the notes (e.g. 'That is outside your course notes, but here is a draft:'). If you're unsure, say so instead of guessing. If the request is unclear, ask one short clarifying question. If the student asks for a diagram, reply with a Mermaid flowchart in a mermaid code block plus two sentences of explanation. Never invent facts, formulas, or citations. Keep answers under 200 words unless asked for more.
            """;

        var contentsList = new List<object>();

        // Add last 6-10 turns of conversation history
        if (request.History != null && request.History.Count > 0)
        {
            foreach (var h in request.History.TakeLast(10))
            {
                var role = (string.Equals(h.Role, "assistant", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(h.Role, "model", StringComparison.OrdinalIgnoreCase))
                    ? "model"
                    : "user";
                contentsList.Add(new
                {
                    role = role,
                    parts = new[] { new { text = h.Content } }
                });
            }
        }

        // Build current student prompt with grounded notes if available
        var currentPromptBuilder = new StringBuilder();
        if (!string.IsNullOrWhiteSpace(request.ContextTopic))
        {
            currentPromptBuilder.AppendLine($"[Course Notes / Topic Context]: {request.ContextTopic}");
        }
        if (!string.IsNullOrWhiteSpace(request.WeakConceptsContext))
        {
            currentPromptBuilder.AppendLine($"[Key Course Notes / High Yield Concepts]: {request.WeakConceptsContext}");
        }
        if (!string.IsNullOrWhiteSpace(request.RecentMistakesContext))
        {
            currentPromptBuilder.AppendLine($"[Recent Missed Questions / Misconceptions]: {request.RecentMistakesContext}");
        }
        if (currentPromptBuilder.Length > 0)
        {
            currentPromptBuilder.AppendLine();
        }
        currentPromptBuilder.Append(request.Message);

        contentsList.Add(new
        {
            role = "user",
            parts = new[] { new { text = currentPromptBuilder.ToString() } }
        });

        var payload = new
        {
            system_instruction = new
            {
                parts = new[] { new { text = systemInstruction } }
            },
            contents = contentsList,
            generationConfig = new
            {
                temperature = 0.3
            },
            safetySettings = ChildSafeSafetySettings
        };

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(30));

        var (responseText, modelUsed) = await CallNativeGeminiWithFallbackAsync(payload, effectiveApiKey, cts.Token);
        stopwatch.Stop();

        if (!string.IsNullOrWhiteSpace(responseText) &&
            !string.Equals(modelUsed, "Built-In Academic Engine", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(modelUsed, "offline", StringComparison.OrdinalIgnoreCase))
        {
            var latencySec = Math.Round(stopwatch.Elapsed.TotalSeconds, 2);
            _logger.LogInformation("Gemini tutor call successful: model={Model}, latency={Latency}s, notesAttached={NotesAttached}",
                modelUsed, latencySec, notesAttached);

            var response = new AskTutorResponse(
                responseText,
                modelUsed,
                DateTime.UtcNow,
                latencySec,
                null,
                notesAttached
            );

            _cache[cacheKey] = (DateTime.UtcNow, response);
            return response;
        }

        // When offline, no key provided, or cloud Gemini is unreachable, synthesize high-yield academic response
        var synthesizedReply = AcademicTutorSynthesizer.SynthesizeResponse(request.Message, request.ContextTopic, request.History);
        var fallbackResponse = new AskTutorResponse(
            synthesizedReply,
            "Built-In Academic Engine",
            DateTime.UtcNow,
            Math.Round(stopwatch.Elapsed.TotalSeconds, 2),
            null,
            notesAttached
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

        var modelsToTry = new[] { _model, "gemini-3.1-flash-lite", "gemini-flash-lite-latest", "gemini-3.8-flash" }
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var acquired = await _concurrencyLimiter.WaitAsync(TimeSpan.FromSeconds(3), cancellationToken);
        if (!acquired)
        {
            _logger.LogWarning("Concurrency limiter saturated, skipping cloud call");
            return (null, "Built-In Academic Engine");
        }

        try
        {
            var json = JsonSerializer.Serialize(payload, JsonOptions);
            bool abortAllModels = false;

            foreach (var modelName in modelsToTry)
            {
                if (cancellationToken.IsCancellationRequested || abortAllModels) break;

                for (int attempt = 1; attempt <= 2; attempt++)
                {
                    try
                    {
                        using var attemptCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                        attemptCts.CancelAfter(TimeSpan.FromSeconds(15));

                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{modelName}:generateContent?key={key}";
                        using var request = new HttpRequestMessage(HttpMethod.Post, url);
                        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

                        using var response = await _httpClient.SendAsync(request, attemptCts.Token);
                        if (response.IsSuccessStatusCode)
                        {
                            var responseStr = await response.Content.ReadAsStringAsync(attemptCts.Token);
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
                            var err = await response.Content.ReadAsStringAsync(attemptCts.Token);
                            _logger.LogWarning("Gemini API ({Model}, attempt {Attempt}) returned {Status}: {Error}", modelName, attempt, response.StatusCode, err);

                            if (statusCode == 401 || statusCode == 403)
                            {
                                _logger.LogWarning("Gemini API key is unauthorized or forbidden ({StatusCode}), immediately aborting cloud attempts", statusCode);
                                abortAllModels = true;
                                break;
                            }

                            if (statusCode == 503 || statusCode == 429)
                            {
                                if (attempt < 2)
                                {
                                    await Task.Delay(300, cancellationToken);
                                    continue;
                                }
                            }
                            else
                            {
                                break;
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        _logger.LogWarning("Gemini API attempt {Attempt} for {Model} timed out after 15s", attempt, modelName);
                        break;
                    }
                    catch (Exception ex)
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

            generationConfig = new { responseMimeType = "application/json", temperature = 0.2 },

            safetySettings = ChildSafeSafetySettings

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

            generationConfig = new { responseMimeType = "application/json", temperature = 0.0 },

            safetySettings = ChildSafeSafetySettings

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



    public async Task<TutorStatusResponse> CheckStatusAsync(CancellationToken cancellationToken = default)

    {

        var key = !string.IsNullOrWhiteSpace(_apiKey)

            ? _apiKey

            : (Environment.GetEnvironmentVariable("AiSettings__ApiKey")

                ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY")

                ?? Environment.GetEnvironmentVariable("GOOGLE_API_KEY"));



        if (string.IsNullOrWhiteSpace(key) || key.Contains("YOUR_GEMINI_API_KEY") || _cloudCallsDisabled)

        {

            return new TutorStatusResponse(false, "None", "offline", 0, "No API key configured");

        }



        var sw = System.Diagnostics.Stopwatch.StartNew();

        try

        {

            using var pingCts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

            var url = $"https://generativelanguage.googleapis.com/v1beta/models?key={key}";

            using var resp = await _httpClient.GetAsync(url, pingCts.Token);

            sw.Stop();

            if (resp.IsSuccessStatusCode)

            {

                return new TutorStatusResponse(true, "Gemini", _model, Math.Round(sw.Elapsed.TotalMilliseconds, 1), "Online");

            }

            return new TutorStatusResponse(false, "Gemini", "offline", Math.Round(sw.Elapsed.TotalMilliseconds, 1), $"HTTP {(int)resp.StatusCode}");

        }

        catch (Exception ex)

        {

            sw.Stop();

            return new TutorStatusResponse(false, "Gemini", "offline", Math.Round(sw.Elapsed.TotalMilliseconds, 1), ex.Message);

        }

    }

}


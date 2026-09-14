using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using StudyApp.Application.DTOs.Ingestion;
using StudyApp.Infrastructure.DocumentParsers;

namespace StudyApp.Infrastructure.AiServices;

public static class NoteScriptSynthesizer
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public sealed record ListCluster(string Title, List<string> Items, bool IsOrdered);

    public static string NormalizeMarkdownLine(string rawLine)
    {
        if (string.IsNullOrWhiteSpace(rawLine)) return string.Empty;
        var s = rawLine.Trim();

        // 1. Strip markdown headings (#, ##, ###, etc.)
        s = Regex.Replace(s, @"^#{1,6}\s*", "");

        // 2. Strip bullet markers (*, -, +, •, ◦, ▪, etc.)
        s = Regex.Replace(s, @"^[\*\-\+•◦▪]\s*", "");

        // 3. Strip bold/italic wrappers (**text**, *text*, __text__, _text_)
        s = Regex.Replace(s, @"\*\*([^*]+)\*\*", "$1");
        s = Regex.Replace(s, @"__([^_]+)__", "$1");

        // 4. Clean any leftover boundary asterisks or underscores e.g. **Answer:** B -> Answer: B
        s = Regex.Replace(s, @"^\*+\s*", "");
        s = Regex.Replace(s, @"\s*\*+$", "");

        return s.Trim(' ', '*', '_', '#', '`');
    }

    public static GeneratedStudySetResult SynthesizeFromNotes(
        string title,
        string rawText,
        List<string>? requestedTypes = null,
        int targetCount = 10,
        int setIndex = 0,
        string? variant = null)
    {
        var cleanTitle = string.IsNullOrWhiteSpace(title) ? "Study Notes" : title.Trim();
        var safeText = rawText ?? string.Empty;

        var rawLines = safeText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim())
            .Where(l => l.Length > 0 && !l.StartsWith("--- Page", StringComparison.OrdinalIgnoreCase))
            .ToList();

        var cleanLines = rawLines
            .Select(NormalizeMarkdownLine)
            .Where(l => l.Length > 0)
            .ToList();

        // 1. Extract Overview & High-Yield Bullet Points directly from the notes
        var bulletPoints = cleanLines
            .Where(l => (l.StartsWith("-") || l.StartsWith("*") || l.StartsWith("•") || Regex.IsMatch(l, @"^\d+[\.\)]\s+")) &&
                        !Regex.IsMatch(l, @"^\s*[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]") &&
                        !Regex.IsMatch(l, @"^\s*(?:Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                        !Regex.IsMatch(l, @"^\s*Q(?:uestion)?\s*\d*[:.]?", RegexOptions.IgnoreCase) &&
                        l.Length > 15 && l.Length < 220)
            .Select(l => Regex.Replace(l, @"^[-*•\d\.\)\s]+", "").Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(5)
            .ToList();

        if (bulletPoints.Count == 0)
        {
            bulletPoints = cleanLines
                .Where(l => l.Length > 25 && l.Length < 180 &&
                            !Regex.IsMatch(l, @"^\s*[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]") &&
                            !Regex.IsMatch(l, @"^\s*(?:Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                            !Regex.IsMatch(l, @"^\s*Q(?:uestion)?\s*\d*[:.]?", RegexOptions.IgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(5)
                .ToList();
        }

        if (bulletPoints.Count == 0)
        {
            bulletPoints.Add($"Key principles extracted directly from {cleanTitle}.");
            bulletPoints.Add("Active recall practice material synthesized from notes.");
        }

        var summaryParagraphs = cleanLines
            .Where(l => l.Length > 30 &&
                        !Regex.IsMatch(l, @"^\s*[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]") &&
                        !Regex.IsMatch(l, @"^\s*(?:Answer|Ans|Key|Solution|Q|Question):?", RegexOptions.IgnoreCase))
            .Take(3)
            .ToList();

        var summary = summaryParagraphs.Count > 0
            ? string.Join(" ", summaryParagraphs)
            : $"Comprehensive study notes and active recall practice synthesized from source material for {cleanTitle}.";

        var questions = new List<GeneratedQuestionDto>();
        var parsedDefinitions = ExtractDefinitions(cleanLines);
        var poolOfAnswersAndTerms = new List<string>();

        // Collect terms from definitions
        foreach (var def in parsedDefinitions)
        {
            poolOfAnswersAndTerms.Add(def.Term);
            poolOfAnswersAndTerms.Add(def.Definition);
        }

        // Apply concept rotation and shuffling based on setIndex and variant to eliminate continuous repetition
        if (parsedDefinitions.Count > 0 && setIndex > 0)
        {
            int rotation = (setIndex * 3) % parsedDefinitions.Count;
            parsedDefinitions = parsedDefinitions.Skip(rotation).Concat(parsedDefinitions.Take(rotation)).ToList();
        }
        if (variant == "shuffle" || variant == "random" || setIndex >= 900)
        {
            var rng = new Random(setIndex);
            parsedDefinitions = parsedDefinitions.OrderBy(_ => rng.Next()).ToList();
        }

        // 2. Stage 1: Parse pre-formatted multiple-choice questions already present in notes
        var mcqQuestions = ParseFormattedMultipleChoice(cleanLines, cleanTitle);
        // 3. Stage 2: Parse Q&A pairs (e.g. Q: ... A: ...)
        var qaQuestions = ParseQuestionAnswerPairs(cleanLines, cleanTitle, poolOfAnswersAndTerms);

        // If user is generating subsequent sets (setIndex > 0) and the notes have rich definitions,
        // prioritize synthesizing fresh active recall questions rather than regurgitating identical pre-formatted questions!
        bool hasRichDefinitions = parsedDefinitions.Count >= Math.Min(4, targetCount / 2);
        if (setIndex == 0 || !hasRichDefinitions)
        {
            foreach (var q in mcqQuestions)
            {
                var processed = (setIndex > 0) ? VaryQuestionForSet(q, setIndex, cleanTitle, poolOfAnswersAndTerms) : q;
                questions.Add(processed);
                if (!string.IsNullOrWhiteSpace(processed.CorrectAnswer))
                {
                    poolOfAnswersAndTerms.Add(processed.CorrectAnswer);
                }
                if (processed.Options != null)
                {
                    foreach (var opt in processed.Options)
                    {
                        if (!string.IsNullOrWhiteSpace(opt.Text))
                        {
                            poolOfAnswersAndTerms.Add(opt.Text);
                        }
                    }
                }
            }

            foreach (var q in qaQuestions)
            {
                if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
                {
                    var processed = (setIndex > 0) ? VaryQuestionForSet(q, setIndex, cleanTitle, poolOfAnswersAndTerms) : q;
                    questions.Add(processed);
                    if (!string.IsNullOrWhiteSpace(processed.CorrectAnswer))
                    {
                        poolOfAnswersAndTerms.Add(processed.CorrectAnswer);
                    }
                }
            }
        }

        // 4. Extract List Clusters (headings with 2-8 bulleted or numbered items)
        var listClusters = ExtractListClusters(rawLines);
        if (listClusters.Count > 0 && setIndex > 0)
        {
            int clusterRot = setIndex % listClusters.Count;
            listClusters = listClusters.Skip(clusterRot).Concat(listClusters.Take(clusterRot)).ToList();
        }
        foreach (var cluster in listClusters)
        {
            poolOfAnswersAndTerms.Add(cluster.Title);
            foreach (var item in cluster.Items)
            {
                poolOfAnswersAndTerms.Add(item);
            }
        }

        // 5. Stage 3: Multi-Type Exam Generation based on requestedTypes
        var rawTypes = requestedTypes ?? new List<string>();
        var validTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "multiple_choice",
            "identification",
            "enumeration",
            "cloze",
            "true_false",
            "matching",
            "short_answer",
            "scenario"
        };

        var filteredRequested = rawTypes
            .Select(t => t.ToLowerInvariant().Trim())
            .Where(t => !string.IsNullOrWhiteSpace(t))
            .ToList();

        bool isSimulatedExam = filteredRequested.Count == 0 ||
                               filteredRequested.Contains("simulated_exam") ||
                               filteredRequested.Contains("all");

        List<string> targetTypes;
        if (isSimulatedExam)
        {
            // Balanced comprehensive simulated exam across all core active-recall question types
            targetTypes = new List<string>
            {
                "multiple_choice",
                "true_false",
                "identification",
                "cloze",
                "enumeration",
                "matching"
            };
        }
        else
        {
            targetTypes = filteredRequested.Where(t => validTypes.Contains(t)).Distinct().ToList();
            if (targetTypes.Count == 0)
            {
                targetTypes = new List<string> { "multiple_choice", "identification", "enumeration" };
            }
        }

        // Pre-allocate quota per active question type
        int remainingNeeded = Math.Max(0, targetCount - questions.Count);
        if (remainingNeeded > 0)
        {
            int baseQuota = Math.Max(1, remainingNeeded / targetTypes.Count);
            var quotaPerType = targetTypes.ToDictionary(t => t, _ => baseQuota);
            int allocated = baseQuota * targetTypes.Count;
            int remainder = remainingNeeded - allocated;
            for (int k = 0; k < remainder && k < targetTypes.Count; k++)
            {
                quotaPerType[targetTypes[k]]++;
            }

            // Generate for each requested type directly grounded in the notes
            foreach (var type in targetTypes)
            {
                if (questions.Count >= targetCount) break;
                int quota = quotaPerType.TryGetValue(type, out var qVal) ? qVal : 1;
                int neededNow = Math.Min(quota, targetCount - questions.Count);

                List<GeneratedQuestionDto> generatedForType = type switch
                {
                    "true_false" => GenerateTrueFalseQuestions(parsedDefinitions, cleanLines, cleanTitle, neededNow, setIndex, variant),
                    "cloze" => GenerateClozeQuestions(parsedDefinitions, cleanLines, cleanTitle, neededNow, setIndex, variant),
                    "enumeration" => GenerateEnumerationQuestions(listClusters, parsedDefinitions, cleanTitle, neededNow),
                    "matching" => GenerateMatchingQuestions(parsedDefinitions, cleanTitle, neededNow, setIndex),
                    "identification" => GenerateIdentificationQuestions(parsedDefinitions, cleanTitle, neededNow, setIndex),
                    "scenario" => GenerateScenarioQuestions(parsedDefinitions, cleanTitle, poolOfAnswersAndTerms, neededNow, setIndex, variant),
                    "short_answer" => GenerateShortAnswerQuestions(parsedDefinitions, cleanTitle, neededNow, setIndex),
                    "multiple_choice" => GenerateQuestionsFromDefinitions(parsedDefinitions, cleanTitle, poolOfAnswersAndTerms, countNeeded: neededNow, setIndex: setIndex, variant: variant),
                    _ => new List<GeneratedQuestionDto>()
                };

                foreach (var q in generatedForType)
                {
                    if (questions.Count >= targetCount) break;
                    if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
                    {
                        questions.Add(q);
                    }
                }
            }
        }

        // 6. Stage 4: Fallback to definitions & factual sentences if below targetCount
        if (questions.Count < targetCount && parsedDefinitions.Count > 0)
        {
            int needed = targetCount - questions.Count;
            var defQuestions = GenerateQuestionsFromDefinitions(parsedDefinitions, cleanTitle, poolOfAnswersAndTerms, countNeeded: needed, setIndex: setIndex, variant: variant);
            foreach (var q in defQuestions)
            {
                if (questions.Count >= targetCount) break;
                if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
                {
                    questions.Add(q);
                }
            }
        }

        if (questions.Count < targetCount)
        {
            var sentenceQuestions = GenerateFromSentences(cleanLines, cleanTitle, poolOfAnswersAndTerms, targetCount - questions.Count);
            foreach (var q in sentenceQuestions)
            {
                if (questions.Count >= targetCount) break;
                if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
                {
                    questions.Add(q);
                }
            }
        }

        // 6. Stage 5: Final Validation & Deduplication on ALL options across all multiple-choice questions
        var normalizedQuestions = new List<GeneratedQuestionDto>();
        for (int i = 0; i < questions.Count; i++)
        {
            var q = questions[i];
            if (q.Type.Equals("multiple_choice", StringComparison.OrdinalIgnoreCase) || q.Type.Equals("scenario", StringComparison.OrdinalIgnoreCase))
            {
                var normalized = EnsureFourDistinctChoices(q, i + 1, cleanTitle, poolOfAnswersAndTerms);
                normalizedQuestions.Add(normalized);
            }
            else
            {
                normalizedQuestions.Add(q);
            }
        }

        // If user input had more questions (e.g. 15 questions in note script), retain all of them!
        return new GeneratedStudySetResult(
            Guid.NewGuid(),
            cleanTitle,
            summary,
            bulletPoints,
            normalizedQuestions,
            ExtractedText: safeText
        );
    }

    private static List<GeneratedQuestionDto> ParseFormattedMultipleChoice(List<string> lines, string title)
    {
        var result = new List<GeneratedQuestionDto>();
        var promptPattern = new Regex(@"^(?:[\*#\-_•\s]*)(?:(?:Q(?:uestion)?\s*\d*[:.]?)|(?:\d+[\.\)]))\s*(.*)$", RegexOptions.IgnoreCase);
        var optionPattern = new Regex(
            @"^\s*(?:[\*\-\+•◦▪]\s*)?(?:[\*_]{1,3})?(?:(?:Option|Choice)\s+)?(?:[\(\[]([A-Fa-f])[\)\]][\.:\s\-]?|([A-Fa-f])\)[\.:\s\-]?|([A-Fa-f])[\.\:\-]\s+)(?:[\*_]{1,3})?\s*(.+)$",
            RegexOptions.IgnoreCase
        );
        var answerPattern = new Regex(
            @"^\s*(?:[\*\-\+•◦▪]\s*)?(?:[\*_]{1,3})?(?:(?:The\s+)?(?:Correct\s+)?(?:Answer(?:\s+is)?|Ans|Key|Solution|Correct(?:\s+Option)?))\s*[\.:\-]?\s*(?:[\*_]{1,3})?\s*(.+)$",
            RegexOptions.IgnoreCase
        );
        var explanationPattern = new Regex(@"^\s*(?:[\*\-\+•◦▪]\s*)?(?:[\*_]{1,3})?(?:Explanation|Rationale|Note)\s*[:\-]?\s*(?:[\*_]{1,3})?\s*(.+)$", RegexOptions.IgnoreCase);

        int i = 0;
        while (i < lines.Count)
        {
            var rawLine = lines[i];
            var line = NormalizeMarkdownLine(rawLine);
            var promptMatch = promptPattern.Match(line);
            bool isPrompt = promptMatch.Success;
            string candidatePrompt = isPrompt ? promptMatch.Groups[1].Value.Trim() : line.Trim();

            // Also detect unnumbered question if next line is Option A
            if (!isPrompt && i + 1 < lines.Count)
            {
                var nextOptMatch = optionPattern.Match(NormalizeMarkdownLine(lines[i + 1]));
                if (nextOptMatch.Success)
                {
                    var firstLetter = (nextOptMatch.Groups[1].Success ? nextOptMatch.Groups[1].Value :
                                       nextOptMatch.Groups[2].Success ? nextOptMatch.Groups[2].Value :
                                       nextOptMatch.Groups[3].Value).ToUpperInvariant();
                    if (firstLetter == "A" && candidatePrompt.Length > 3 && !candidatePrompt.StartsWith("#"))
                    {
                        isPrompt = true;
                    }
                }
            }

            if (isPrompt)
            {
                candidatePrompt = NormalizeMarkdownLine(candidatePrompt);
                candidatePrompt = Regex.Replace(candidatePrompt, @"^(?:Q(?:uestion)?\s*[:.-]?\s*)", "", RegexOptions.IgnoreCase).Trim();
                candidatePrompt = candidatePrompt.Trim(' ', '*', '_', '#', '`');
                var options = new List<(string Letter, string Text, bool IsInlineCorrect)>();
                string? answerLineValue = null;
                string? explanation = null;

                int j = i + 1;
                while (j < lines.Count)
                {
                    var subLineRaw = lines[j];
                    var subLine = NormalizeMarkdownLine(subLineRaw);

                    if (string.IsNullOrWhiteSpace(subLine))
                    {
                        j++;
                        continue;
                    }

                    // Check if a new question starts
                    bool isNextQuestion = promptPattern.IsMatch(subLine);
                    if (!isNextQuestion && j + 1 < lines.Count)
                    {
                        var checkOpt = optionPattern.Match(NormalizeMarkdownLine(lines[j + 1]));
                        if (checkOpt.Success)
                        {
                            var checkLetter = (checkOpt.Groups[1].Success ? checkOpt.Groups[1].Value :
                                               checkOpt.Groups[2].Success ? checkOpt.Groups[2].Value :
                                               checkOpt.Groups[3].Value).ToUpperInvariant();
                            if (checkLetter == "A")
                            {
                                isNextQuestion = true;
                            }
                        }
                    }

                    if (isNextQuestion && options.Count > 0)
                    {
                        break;
                    }

                    var optMatch = optionPattern.Match(subLine);
                    if (optMatch.Success)
                    {
                        var letter = (optMatch.Groups[1].Success ? optMatch.Groups[1].Value :
                                      optMatch.Groups[2].Success ? optMatch.Groups[2].Value :
                                      optMatch.Groups[3].Value).ToUpperInvariant();
                        var optText = NormalizeMarkdownLine(optMatch.Groups[4].Value).Trim(' ', '*', '_');
                        bool isInline = false;

                        if (optText.Contains("(correct)", StringComparison.OrdinalIgnoreCase) ||
                            optText.Contains("[correct]", StringComparison.OrdinalIgnoreCase) ||
                            (optText.StartsWith("*") && optText.EndsWith("*")))
                        {
                            isInline = true;
                            optText = Regex.Replace(optText, @"\s*[\(\[]correct[\)\]]|\*", "", RegexOptions.IgnoreCase).Trim();
                        }

                        options.Add((letter, optText, isInline));
                        j++;
                        continue;
                    }

                    var ansMatch = answerPattern.Match(subLine);
                    if (ansMatch.Success)
                    {
                        answerLineValue = NormalizeMarkdownLine(ansMatch.Groups[1].Value).Trim(' ', '*', '_', '`');
                        j++;
                        continue;
                    }

                    var expMatch = explanationPattern.Match(subLine);
                    if (expMatch.Success)
                    {
                        explanation = NormalizeMarkdownLine(expMatch.Groups[1].Value).Trim(' ', '*', '_');
                        j++;
                        continue;
                    }

                    // Check horizontal separator line
                    if (Regex.IsMatch(subLine, @"^[-=_*]{3,}$"))
                    {
                        j++;
                        if (options.Count >= 2) break;
                        continue;
                    }

                    // If we haven't seen any options yet, line is continuation of multi-line prompt
                    if (options.Count == 0 && candidatePrompt.Length < 300)
                    {
                        candidatePrompt = string.IsNullOrWhiteSpace(candidatePrompt) ? subLine.Trim() : candidatePrompt + " " + subLine.Trim();
                        j++;
                        continue;
                    }

                    // If we have options but no answer yet, line could be continuation of previous option
                    if (options.Count > 0 && string.IsNullOrWhiteSpace(answerLineValue))
                    {
                        var last = options[options.Count - 1];
                        options[options.Count - 1] = (last.Letter, last.Text + " " + subLine.Trim(), last.IsInlineCorrect);
                        j++;
                        continue;
                    }

                    // If we already have options and an answer, line could be explanation
                    if (!string.IsNullOrWhiteSpace(answerLineValue) && string.IsNullOrWhiteSpace(explanation))
                    {
                        explanation = subLine.Trim();
                        j++;
                        continue;
                    }

                    break;
                }

                if (options.Count >= 2)
                {
                    // Match the correct answer
                    string? correctText = null;
                    var generatedOptions = new List<GeneratedOptionDto>();

                    string? answerLetter = null;
                    if (!string.IsNullOrWhiteSpace(answerLineValue))
                    {
                        // 1. Explicit letter alone: B, B., B), (B), [B], Option B, Choice B, b
                        var explicitMatch = Regex.Match(
                            answerLineValue,
                            @"^(?:(?:Option|Choice)\s+)?[\(\[]?([A-Fa-f])[\)\]]?[\.:]?$",
                            RegexOptions.IgnoreCase
                        );

                        if (explicitMatch.Success)
                        {
                            answerLetter = explicitMatch.Groups[1].Value.ToUpperInvariant();
                        }
                        else
                        {
                            // 2. Letter with delimiter and trailing text: (B) text, B) text, B. text, B - text, B: text, Option B: text
                            var letterDelimMatch = Regex.Match(
                                answerLineValue,
                                @"^(?:(?:Option|Choice)\s+)?(?:[\(\[]([A-Fa-f])[\)\]]|([A-Fa-f])[\)\]]|([A-Fa-f])\s*[\:\-\.\)])\s*(.*)$",
                                RegexOptions.IgnoreCase
                            );

                            if (letterDelimMatch.Success)
                            {
                                answerLetter = (letterDelimMatch.Groups[1].Success ? letterDelimMatch.Groups[1].Value :
                                                letterDelimMatch.Groups[2].Success ? letterDelimMatch.Groups[2].Value :
                                                letterDelimMatch.Groups[3].Value).ToUpperInvariant();

                                var trailing = letterDelimMatch.Groups[4].Value.Trim();
                                if (!string.IsNullOrWhiteSpace(trailing) && string.IsNullOrWhiteSpace(explanation))
                                {
                                    explanation = trailing;
                                }
                            }
                            else
                            {
                                // 3. Single non-vowel letter (B, C, D, F) followed by whitespace and trailing commentary (e.g. "B for example this test...")
                                var nonVowelMatch = Regex.Match(
                                    answerLineValue,
                                    @"^([B-Fb-f])\s+(.+)$",
                                    RegexOptions.IgnoreCase
                                );

                                if (nonVowelMatch.Success)
                                {
                                    answerLetter = nonVowelMatch.Groups[1].Value.ToUpperInvariant();
                                    var trailing = nonVowelMatch.Groups[2].Value.Trim();
                                    if (!string.IsNullOrWhiteSpace(trailing) && string.IsNullOrWhiteSpace(explanation))
                                    {
                                        explanation = trailing;
                                    }
                                }
                                else
                                {
                                    // 4. Letter A followed by explanatory marker keywords (e.g. "A because...", "A for example...")
                                    var letterAMatch = Regex.Match(
                                        answerLineValue,
                                        @"^([Aa])\s+(?:for\s+example|because|since|as\s+stated|note|explanation)\b\s*(.*)$",
                                        RegexOptions.IgnoreCase
                                    );

                                    if (letterAMatch.Success)
                                    {
                                        answerLetter = "A";
                                        var trailing = letterAMatch.Groups[2].Value.Trim();
                                        if (!string.IsNullOrWhiteSpace(trailing) && string.IsNullOrWhiteSpace(explanation))
                                        {
                                            explanation = trailing;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // If answerLetter wasn't matched yet, check for direct match against option text
                    if (answerLetter == null && !string.IsNullOrWhiteSpace(answerLineValue))
                    {
                        var directOpt = options.FirstOrDefault(o =>
                            string.Equals(o.Text, answerLineValue, StringComparison.OrdinalIgnoreCase) ||
                            (answerLineValue.Length >= 5 && o.Text.StartsWith(answerLineValue, StringComparison.OrdinalIgnoreCase)) ||
                            (o.Text.Length >= 5 && answerLineValue.StartsWith(o.Text, StringComparison.OrdinalIgnoreCase)));

                        if (directOpt != default)
                        {
                            answerLetter = directOpt.Letter;
                        }
                    }

                    foreach (var opt in options)
                    {
                        bool isCorrect = false;
                        if (opt.IsInlineCorrect)
                        {
                            isCorrect = true;
                        }
                        else if (answerLetter != null && string.Equals(opt.Letter, answerLetter, StringComparison.OrdinalIgnoreCase))
                        {
                            isCorrect = true;
                        }
                        else if (!string.IsNullOrWhiteSpace(answerLineValue) &&
                                 (string.Equals(opt.Text, answerLineValue, StringComparison.OrdinalIgnoreCase) ||
                                  (answerLineValue.Length >= 5 && opt.Text.StartsWith(answerLineValue, StringComparison.OrdinalIgnoreCase)) ||
                                  (opt.Text.Length >= 5 && answerLineValue.StartsWith(opt.Text, StringComparison.OrdinalIgnoreCase))))
                        {
                            isCorrect = true;
                        }

                        if (isCorrect)
                        {
                            correctText = opt.Text;
                        }

                        generatedOptions.Add(new GeneratedOptionDto(
                            opt.Text,
                            isCorrect,
                            isCorrect ? null : "Incorrect option based on notes."
                        ));
                    }

                    // If no correct option was matched yet, default to text containing match or first option
                    if (!generatedOptions.Any(o => o.IsCorrect))
                    {
                        if (!string.IsNullOrWhiteSpace(answerLineValue))
                        {
                            var matchingOpt = generatedOptions.FirstOrDefault(o =>
                                (answerLineValue.Length >= 3 && o.Text.Contains(answerLineValue, StringComparison.OrdinalIgnoreCase)) ||
                                (o.Text.Length >= 3 && answerLineValue.Contains(o.Text, StringComparison.OrdinalIgnoreCase)));

                            if (matchingOpt != null)
                            {
                                int idx = generatedOptions.IndexOf(matchingOpt);
                                generatedOptions[idx] = new GeneratedOptionDto(matchingOpt.Text, true, null);
                                correctText = matchingOpt.Text;
                            }
                            else
                            {
                                generatedOptions[0] = new GeneratedOptionDto(generatedOptions[0].Text, true, null);
                                correctText = generatedOptions[0].Text;
                            }
                        }
                        else
                        {
                            generatedOptions[0] = new GeneratedOptionDto(generatedOptions[0].Text, true, null);
                            correctText = generatedOptions[0].Text;
                        }
                    }

                    result.Add(new GeneratedQuestionDto(
                        "multiple_choice",
                        candidatePrompt,
                        new List<string> { "Review related section in notes." },
                        correctText ?? generatedOptions.First(o => o.IsCorrect).Text,
                        generatedOptions,
                        null, null, false,
                        explanation ?? $"Source context verified from notes for {title}.",
                        null,
                        $"Extracted from note script: {candidatePrompt}"
                    ));

                    i = j;
                    continue;
                }
            }

            i++;
        }

        return result;
    }

    private static List<GeneratedQuestionDto> ParseQuestionAnswerPairs(List<string> lines, string title, List<string> pool)
    {
        var result = new List<GeneratedQuestionDto>();
        var qaPattern = new Regex(@"^(?:Q(?:uestion)?\s*\d*[:.]?|\d+[\.\)]\s*Question[:.]?)\s*(.+)$", RegexOptions.IgnoreCase);
        var answerPattern = new Regex(@"^(?:A(?:nswer)?|Ans)[:.]?\s*(.+)$", RegexOptions.IgnoreCase);

        int i = 0;
        while (i < lines.Count)
        {
            var line = lines[i];
            var qMatch = qaPattern.Match(line);
            if (qMatch.Success)
            {
                var prompt = qMatch.Groups[1].Value.Trim();
                // Ensure it ends with question mark or is a valid question
                if (!prompt.EndsWith("?")) prompt += "?";

                // Look ahead for the answer
                string? answer = null;
                int j = i + 1;
                while (j < lines.Count && j <= i + 3)
                {
                    var aMatch = answerPattern.Match(lines[j]);
                    if (aMatch.Success)
                    {
                        answer = aMatch.Groups[1].Value.Trim();
                        i = j;
                        break;
                    }
                    j++;
                }

                if (!string.IsNullOrWhiteSpace(answer) && answer.Length > 1 && !answer.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                {
                    var distractors = pool
                        .Where(p => !string.Equals(p, answer, StringComparison.OrdinalIgnoreCase) && p.Length > 2 && p.Length < 150)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .Take(3)
                        .ToList();

                    int dIdx = 1;
                    while (distractors.Count < 3)
                    {
                        distractors.Add($"Alternative concept {dIdx++} from {title}");
                    }

                    var options = new List<GeneratedOptionDto>
                    {
                        new GeneratedOptionDto(answer, true, null),
                        new GeneratedOptionDto(distractors[0], false, "Alternative term in notes."),
                        new GeneratedOptionDto(distractors[1], false, "Contrasting concept."),
                        new GeneratedOptionDto(distractors[2], false, "Unrelated property.")
                    };

                    var rand = new Random(prompt.GetHashCode());
                    options = options.OrderBy(_ => rand.Next()).ToList();

                    result.Add(new GeneratedQuestionDto(
                        "multiple_choice",
                        prompt,
                        new List<string> { "Carefully recall the answer given in your notes." },
                        answer,
                        options,
                        null, null, false,
                        $"According to your notes: '{answer}'.",
                        null,
                        $"Source note Q&A pair: {prompt}"
                    ));
                }
            }
            i++;
        }

        return result;
    }

    public static bool IsMcqOptionOrAnswerKeyLine(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) return false;
        var trimmed = line.Trim();
        var stripped = Regex.Replace(trimmed, @"^[\*\-\+•◦▪\>]+\s*", "").Trim('*', '_', ' ', '\t');

        // Option letters with optional markdown bullets: e.g. "* A)", "- B.", "• C)", "A)", "D."
        if (Regex.IsMatch(trimmed, @"^(?:[\*\-\+•◦▪\>]+\s*)?[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]") ||
            Regex.IsMatch(stripped, @"^[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]"))
            return true;

        // Answer key markers like "Answer: B", "Ans: True", "Answer Key: C", "Key: A", "Solution: ..."
        if (Regex.IsMatch(stripped, @"^(?:(?:Answer|Ans)(?:\s+Key)?|Key|Solution)\s*[:=]", RegexOptions.IgnoreCase))
            return true;

        // Inline answer/option indicators: e.g. "Answer: B", "Option A"
        if (Regex.IsMatch(trimmed, @"\b(?:Answer|Ans)\s*[:=]\s*[A-Fa-f0-9]", RegexOptions.IgnoreCase) ||
            Regex.IsMatch(trimmed, @"\b(?:Option|Choice)\s+[A-Fa-f]\b", RegexOptions.IgnoreCase))
            return true;

        return false;
    }

    private static List<(string Term, string Definition, string FullSentence)> ExtractDefinitions(List<string> cleanLines)
    {
        var definitions = new List<(string Term, string Definition, string FullSentence)>();
        var isPattern = new Regex(@"^(?:The\s+)?([A-Z][a-zA-Z0-9\s-]{2,40})\s+(?:is defined as|is a|is an|is|are|refers to|represents|means)\s+(.+)$", RegexOptions.IgnoreCase);
        var colonPattern = new Regex(@"^(?:[-*•]\s*)?([A-Z][a-zA-Z0-9\s-]{2,40}):\s*(.+)$");
        var dashPattern = new Regex(@"^(?:[-*•]\s*)?([A-Z][a-zA-Z0-9\s-]{2,40})\s+[-–—]\s+(.+)$");

        foreach (var line in cleanLines)
        {
            if (line.StartsWith("Answer", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("Ans", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("Key", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("Solution", StringComparison.OrdinalIgnoreCase) ||
                Regex.IsMatch(line, @"^(?:Q(?:uestion)?\s*\d*[:.]?|\d+[\.\)])", RegexOptions.IgnoreCase) ||
                IsMcqOptionOrAnswerKeyLine(line))
            {
                continue;
            }

            var colMatch = colonPattern.Match(line);
            if (colMatch.Success)
            {
                var term = colMatch.Groups[1].Value.Trim();
                var def = colMatch.Groups[2].Value.Trim();
                if (Regex.IsMatch(term, @"^(?:Question|Q\d|Problem|Item|Note)\b", RegexOptions.IgnoreCase))
                {
                    continue;
                }
                if (term.Split(' ').Length <= 5 && def.Length >= 8)
                {
                    definitions.Add((term, def, line));
                    continue;
                }
            }

            var isMatch = isPattern.Match(line);
            if (isMatch.Success)
            {
                var term = isMatch.Groups[1].Value.Trim();
                var def = isMatch.Groups[2].Value.Trim();
                if (term.Split(' ').Length <= 5 && def.Length >= 8)
                {
                    definitions.Add((term, def, line));
                    continue;
                }
            }

            var dashMatch = dashPattern.Match(line);
            if (dashMatch.Success)
            {
                var term = dashMatch.Groups[1].Value.Trim();
                var def = dashMatch.Groups[2].Value.Trim();
                if (term.Split(' ').Length <= 5 && def.Length >= 8)
                {
                    definitions.Add((term, def, line));
                }
            }
        }

        return definitions;
    }

    public static List<ListCluster> ExtractListClusters(List<string> rawLines)
    {
        var clusters = new List<ListCluster>();
        int i = 0;
        while (i < rawLines.Count)
        {
            var line = rawLines[i].Trim();
            bool isHeaderCandidate = line.EndsWith(":") ||
                                     Regex.IsMatch(line, @"^(?:#{1,6}\s+|[A-Z][a-zA-Z0-9\s-]{3,60}:?$)", RegexOptions.None) ||
                                     Regex.IsMatch(line, @"^(?:Types|Stages|Steps|Components|Characteristics|Features|Principles|Examples|Categories|Elements|Phases|Functions)\b", RegexOptions.IgnoreCase);

            if (isHeaderCandidate &&
                !Regex.IsMatch(line, @"^(?:Q(?:uestion)?\s*\d*[:.]?|(?:Answer|Ans|Solution)\s*[:.]?|Key\s*[:.]|(?:Option|Choice)\s+[A-Fa-f])", RegexOptions.IgnoreCase) &&
                !IsMcqOptionOrAnswerKeyLine(line))
            {
                var header = NormalizeMarkdownLine(line).TrimEnd(':');
                var items = new List<string>();
                bool isOrdered = false;
                int j = i + 1;

                while (j < rawLines.Count)
                {
                    var candidate = rawLines[j].Trim();
                    if (string.IsNullOrWhiteSpace(candidate))
                    {
                        j++;
                        continue;
                    }

                    if (IsMcqOptionOrAnswerKeyLine(candidate))
                    {
                        break;
                    }

                    var numMatch = Regex.Match(candidate, @"^\s*(\d+)[\.\)]\s+(.+)$");
                    var bulletMatch = Regex.Match(candidate, @"^\s*[\*\-\+•◦▪]\s+(.+)$");

                    if (numMatch.Success)
                    {
                        isOrdered = true;
                        var itemText = NormalizeMarkdownLine(numMatch.Groups[2].Value).Trim();
                        if (itemText.Length > 2 && itemText.Length < 120)
                        {
                            items.Add(itemText);
                        }
                    }
                    else if (bulletMatch.Success)
                    {
                        var itemText = NormalizeMarkdownLine(bulletMatch.Groups[1].Value).Trim();
                        if (itemText.Length > 2 && itemText.Length < 120)
                        {
                            items.Add(itemText);
                        }
                    }
                    else
                    {
                        break;
                    }
                    j++;
                }

                if (items.Count >= 2 && items.Count <= 8 && header.Length >= 4)
                {
                    clusters.Add(new ListCluster(header, items, isOrdered));
                    i = j;
                    continue;
                }
            }
            i++;
        }

        return clusters;
    }

    private static GeneratedQuestionDto VaryQuestionForSet(GeneratedQuestionDto original, int setIndex, string title, List<string> pool)
    {
        var rand = new Random(setIndex * 31 + original.Prompt.GetHashCode());
        var prompt = original.Prompt;

        // Dynamic prompt framing variation across sets
        if (setIndex % 3 == 1)
        {
            prompt = $"Regarding {title}, which core concept directly corresponds to: \"{original.Prompt.TrimEnd('?')}\"?";
        }
        else if (setIndex % 3 == 2)
        {
            prompt = $"In an analytical problem regarding {title}, consider: \"{original.Prompt.TrimEnd('?')}\". Identify the correct answer:";
        }

        // Shuffle options and swap fresh distractors
        List<GeneratedOptionDto>? variedOptions = null;
        if (original.Options != null && original.Options.Count > 1)
        {
            var correct = original.Options.FirstOrDefault(o => o.IsCorrect) ?? original.Options[0];
            var newDistractors = pool
                .Where(p => !string.Equals(p, correct.Text, StringComparison.OrdinalIgnoreCase) && p.Length > 2 && p.Length < 120)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(_ => rand.Next())
                .Take(3)
                .ToList();

            int dCount = 1;
            while (newDistractors.Count < 3)
            {
                newDistractors.Add($"Alternative concept {dCount++} for Set {setIndex + 1}");
            }

            variedOptions = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(correct.Text, true, null),
                new GeneratedOptionDto(newDistractors[0], false, "Alternative concept from other sections."),
                new GeneratedOptionDto(newDistractors[1], false, "Contrasting option."),
                new GeneratedOptionDto(newDistractors[2], false, "Unrelated term.")
            };
            variedOptions = variedOptions.OrderBy(_ => rand.Next()).ToList();
        }

        return new GeneratedQuestionDto(
            original.Type,
            prompt,
            original.Hints,
            original.CorrectAnswer,
            variedOptions ?? original.Options,
            original.ValidSynonyms,
            original.EnumerationItems,
            original.IsOrdered,
            original.Explanation,
            original.ThinkingBreakdown,
            original.SourceReference
        );
    }

    private static List<GeneratedQuestionDto> GenerateTrueFalseQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        List<string> cleanLines,
        string title,
        int countNeeded,
        int setIndex = 0,
        string? variant = null)
    {
        var result = new List<GeneratedQuestionDto>();
        int defIndex = 0;
        bool nextIsTrue = (setIndex % 2 == 0);

        while (defIndex < definitions.Count && result.Count < countNeeded)
        {
            var current = definitions[defIndex];

            if (nextIsTrue || definitions.Count < 2)
            {
                int tfStyle = (defIndex + setIndex) % 2;
                var prompt = tfStyle == 0
                    ? $"True or False: According to the study notes, {current.Term} refers to: \"{current.Definition}\"."
                    : $"True or False: In {title}, the principle of \"{current.Term}\" encompasses: \"{current.Definition}\".";

                var options = new List<GeneratedOptionDto>
                {
                    new GeneratedOptionDto("True", true, null),
                    new GeneratedOptionDto("False", false, "This statement is directly confirmed in your notes.")
                };

                result.Add(new GeneratedQuestionDto(
                    "true_false",
                    prompt,
                    new List<string> { "Carefully verify the definition against your notes." },
                    "True",
                    options,
                    null, null, false,
                    $"True. According to your study notes: \"{current.FullSentence}\"",
                    null,
                    $"Source excerpt: {current.FullSentence}"
                ));
                nextIsTrue = false;
            }
            else
            {
                int altIndex = (defIndex + 1) % definitions.Count;
                var alt = definitions[altIndex];

                var prompt = $"True or False: In your study notes, {current.Term} is defined as: \"{alt.Definition}\".";
                var options = new List<GeneratedOptionDto>
                {
                    new GeneratedOptionDto("True", false, $"Contradicts notes. That definition applies to {alt.Term}, not {current.Term}."),
                    new GeneratedOptionDto("False", true, null)
                };

                result.Add(new GeneratedQuestionDto(
                    "true_false",
                    prompt,
                    new List<string> { $"Check whether this definition actually describes '{current.Term}' or another concept." },
                    "False",
                    options,
                    null, null, false,
                    $"False. In your notes, \"{alt.Definition}\" actually defines {alt.Term}. Meanwhile, {current.Term} is defined as: \"{current.Definition}\".",
                    null,
                    $"Source excerpt: {current.FullSentence}"
                ));
                nextIsTrue = true;
            }

            defIndex++;
        }

        if (result.Count < countNeeded)
        {
            var factualSentences = cleanLines
                .Where(l => l.Length >= 30 && l.Length <= 160 && !l.Contains("?") &&
                            !Regex.IsMatch(l, @"^(?:[\*\-\+•◦▪\>]+\s*)?(?:Q(?:uestion)?\s*\d*|\d+[\.\)]|Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                            !IsMcqOptionOrAnswerKeyLine(l))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            for (int i = 0; i < factualSentences.Count && result.Count < countNeeded; i++)
            {
                var s = factualSentences[i];
                if (result.Any(q => q.Prompt.Contains(s[..Math.Min(20, s.Length)]))) continue;

                var prompt = $"True or False: According to your study material: \"{s}\"";
                var options = new List<GeneratedOptionDto>
                {
                    new GeneratedOptionDto("True", true, null),
                    new GeneratedOptionDto("False", false, "This factual statement is directly stated in your notes.")
                };

                result.Add(new GeneratedQuestionDto(
                    "true_false",
                    prompt,
                    new List<string> { "Recall the factual statements in your notes." },
                    "True",
                    options,
                    null, null, false,
                    $"True. Factual statement confirmed from notes: \"{s}\"",
                    null,
                    $"Notes excerpt: {s}"
                ));
            }
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateClozeQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        List<string> cleanLines,
        string title,
        int countNeeded,
        int setIndex = 0,
        string? variant = null)
    {
        var result = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count && result.Count < countNeeded; i++)
        {
            var def = definitions[i];
            int clozeStyle = (i + setIndex) % 3;
            string prompt;

            if (clozeStyle == 0 || !def.FullSentence.Contains(def.Term, StringComparison.OrdinalIgnoreCase))
            {
                prompt = $"Fill in the missing key term: \"________ is {def.Definition}\"";
            }
            else if (clozeStyle == 1)
            {
                prompt = $"Fill in the missing key concept from {title}: \"{Regex.Replace(def.FullSentence, Regex.Escape(def.Term), "________", RegexOptions.IgnoreCase)}\"";
            }
            else
            {
                prompt = $"Complete the definition: \"In your notes, ________ is defined as: {def.Definition}\"";
            }

            var hints = new List<string>
            {
                $"Term starts with '{def.Term[0]}'",
                $"{def.Term.Length} characters"
            };
            var synonyms = new List<string>
            {
                def.Term.ToLowerInvariant(),
                def.Term.Trim()
            };

            var options = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(def.Term, true, null)
            };

            result.Add(new GeneratedQuestionDto(
                "cloze",
                prompt,
                hints,
                def.Term,
                options,
                synonyms,
                null,
                false,
                $"Full passage from notes: \"{def.FullSentence}\"",
                null,
                $"Notes excerpt: {def.FullSentence}"
            ));
        }

        if (result.Count < countNeeded)
        {
            var factualSentences = cleanLines
                .Where(l => l.Length >= 25 && l.Length <= 160 && !l.Contains("?") &&
                            !Regex.IsMatch(l, @"^(?:[\*\-\+•◦▪\>]+\s*)?(?:Q(?:uestion)?\s*\d*|\d+[\.\)]|Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                            !IsMcqOptionOrAnswerKeyLine(l))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            for (int i = 0; i < factualSentences.Count && result.Count < countNeeded; i++)
            {
                var sentence = factualSentences[i];
                var words = sentence.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (words.Length < 5) continue;

                var candidateWord = words.FirstOrDefault(w => w.Length >= 5 && char.IsLetter(w[0]) &&
                    !Regex.IsMatch(w, @"^(which|their|about|these|those|where|there|would|could|should|being|after|before)$", RegexOptions.IgnoreCase))
                    ?? words[words.Length / 2];

                candidateWord = candidateWord.TrimEnd('.', ',', ';', ':', '!', '?');
                if (candidateWord.Length < 3) continue;

                var blanked = Regex.Replace(sentence, Regex.Escape(candidateWord), "________", RegexOptions.IgnoreCase);
                var prompt = $"Fill in the missing word from your study notes: \"{blanked}\"";

                result.Add(new GeneratedQuestionDto(
                    "cloze",
                    prompt,
                    new List<string> { $"Begins with letter '{candidateWord[0]}'", $"{candidateWord.Length} letters" },
                    candidateWord,
                    new List<GeneratedOptionDto> { new GeneratedOptionDto(candidateWord, true, null) },
                    new List<string> { candidateWord.ToLowerInvariant(), candidateWord },
                    null,
                    false,
                    $"Full text from your study notes: \"{sentence}\"",
                    null,
                    $"Notes passage: {sentence}"
                ));
            }
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateEnumerationQuestions(
        List<ListCluster> clusters,
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        int countNeeded)
    {
        var result = new List<GeneratedQuestionDto>();

        foreach (var cluster in clusters)
        {
            if (result.Count >= countNeeded) break;

            var prompt = $"Enumerate the {cluster.Items.Count} items/components of: \"{cluster.Title}\"";
            var correctAnswer = string.Join(", ", cluster.Items);
            var hints = new List<string>
            {
                $"{cluster.Items.Count} items total",
                $"First item begins with '{cluster.Items[0][0]}'"
            };

            result.Add(new GeneratedQuestionDto(
                "enumeration",
                prompt,
                hints,
                correctAnswer,
                null,
                null,
                cluster.Items,
                cluster.IsOrdered,
                $"From your study notes under '{cluster.Title}': {correctAnswer}",
                null,
                $"Notes section: {cluster.Title}"
            ));
        }

        if (result.Count < countNeeded && definitions.Count >= 3)
        {
            var groupedTerms = definitions.Select(d => d.Term).Distinct().Take(4).ToList();
            if (groupedTerms.Count >= 3)
            {
                var prompt = $"List {groupedTerms.Count} core academic terms and concepts covered in {title}:";
                var correctAnswer = string.Join(", ", groupedTerms);
                result.Add(new GeneratedQuestionDto(
                    "enumeration",
                    prompt,
                    new List<string> { $"{groupedTerms.Count} terms", $"First term: '{groupedTerms[0]}'" },
                    correctAnswer,
                    null,
                    null,
                    groupedTerms,
                    false,
                    $"Key terms from notes: {correctAnswer}",
                    null,
                    $"Study material for {title}"
                ));
            }
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateMatchingQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        int countNeeded,
        int setIndex = 0)
    {
        var result = new List<GeneratedQuestionDto>();
        if (definitions.Count < 2) return result;

        int offset = (setIndex * 2) % Math.Max(1, definitions.Count);
        while (offset < definitions.Count && result.Count < countNeeded)
        {
            var slice = definitions.Skip(offset).Take(4).ToList();
            if (slice.Count < 2)
            {
                if (definitions.Count >= 3)
                {
                    slice = definitions.Take(4).ToList();
                }
                else
                {
                    break;
                }
            }

            var matchingPairs = slice.Select(d => new { term = d.Term, definition = d.Definition }).ToList();
            var serializedPairs = JsonSerializer.Serialize(matchingPairs, JsonOptions);

            var prompt = $"Match each key term to its correct definition from your study notes on {title}:";
            var hints = new List<string>
            {
                $"{matchingPairs.Count} matching pairs",
                "Review key terminology directly from notes"
            };

            var explanation = "Correct matches:\n" + string.Join("\n", matchingPairs.Select(p => $"• {p.term} ➔ {p.definition}"));

            result.Add(new GeneratedQuestionDto(
                "matching",
                prompt,
                hints,
                serializedPairs,
                null,
                null,
                null,
                false,
                explanation,
                null,
                $"Extracted definitions from {title}"
            ));

            offset += slice.Count;
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateIdentificationQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        int countNeeded,
        int setIndex = 0)
    {
        var result = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count && result.Count < countNeeded; i++)
        {
            var def = definitions[i];
            int idStyle = (i + setIndex) % 3;
            string prompt = idStyle switch
            {
                1 => $"In {title}, what term or concept is defined as: \"{def.Definition}\"?",
                2 => $"Name the core concept matching: \"{def.Definition}\"",
                _ => $"Identify the term or concept: \"{def.Definition}\""
            };

            result.Add(new GeneratedQuestionDto(
                "identification",
                prompt,
                new List<string> { $"First letter: '{def.Term[0]}'", $"{def.Term.Length} characters" },
                def.Term,
                new List<GeneratedOptionDto> { new GeneratedOptionDto(def.Term, true, null) },
                new List<string> { def.Term.ToLowerInvariant(), def.Term.Trim() },
                null,
                false,
                $"Defined in notes: \"{def.FullSentence}\"",
                null,
                $"Source passage: {def.FullSentence}"
            ));
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateScenarioQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        List<string> pool,
        int countNeeded,
        int setIndex = 0,
        string? variant = null)
    {
        var result = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count && result.Count < countNeeded; i++)
        {
            var def = definitions[i];
            var rand = new Random(setIndex * 997 + (def.Term + i + "scenario").GetHashCode());

            var otherTerms = definitions
                .Where(d => !string.Equals(d.Term, def.Term, StringComparison.OrdinalIgnoreCase))
                .Select(d => d.Term)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(_ => rand.Next())
                .Take(3)
                .ToList();

            int tCount = 1;
            while (otherTerms.Count < 3)
            {
                otherTerms.Add($"Alternative concept {tCount++} from {title}");
            }

            var options = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(def.Term, true, null),
                new GeneratedOptionDto(otherTerms[0], false, "Applies to a different condition in the notes."),
                new GeneratedOptionDto(otherTerms[1], false, "Not applicable to this specific case."),
                new GeneratedOptionDto(otherTerms[2], false, "Contrasting concept from another section.")
            };

            options = options.OrderBy(_ => rand.Next()).ToList();

            int scenarioStyle = (i + setIndex) % 4;
            string prompt = scenarioStyle switch
            {
                1 => $"During an analytical review of {title}, the following operational condition is observed: \"{def.Definition}\". What is this condition called?",
                2 => $"Suppose you are evaluating a real-world case study on {title} and need to apply the principle of: \"{def.Definition}\". Which concept should you utilize?",
                3 => $"In an applied problem regarding {title}, which core concept explains why {def.Definition.ToLowerInvariant().TrimEnd('.')}?",
                _ => $"In a practical problem scenario regarding {title}, which core concept directly addresses the following condition: \"{def.Definition}\"?"
            };

            result.Add(new GeneratedQuestionDto(
                "scenario",
                prompt,
                new List<string> { $"Starts with '{def.Term[0]}'", "Evaluate the key definitions from your notes." },
                def.Term,
                options,
                null, null, false,
                $"Correct concept: \"{def.Term}\". Reference from notes: \"{def.FullSentence}\"",
                null,
                $"Source passage: {def.FullSentence}"
            ));
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateShortAnswerQuestions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        int countNeeded,
        int setIndex = 0)
    {
        var result = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count && result.Count < countNeeded; i++)
        {
            var def = definitions[i];
            int saStyle = (i + setIndex) % 3;
            string prompt = saStyle switch
            {
                1 => $"Analyze the core function and key attributes of \"{def.Term}\" in {title}.",
                2 => $"Summarize what defines \"{def.Term}\" according to your study material.",
                _ => $"In your own words, explain the concept and significance of \"{def.Term}\" based on your study notes."
            };

            var keywords = def.Definition
                .Split(new[] { ' ', ',', '.', ';', ':', '(', ')' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(w => w.Length >= 4 && char.IsLetter(w[0]) &&
                            !Regex.IsMatch(w, @"^(that|with|from|which|this|these|those|have|been|were|their)$", RegexOptions.IgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(5)
                .ToList();

            if (keywords.Count == 0) keywords.Add(def.Term);

            result.Add(new GeneratedQuestionDto(
                "short_answer",
                prompt,
                keywords,
                def.Definition,
                null,
                null,
                null,
                false,
                $"Key explanation from your notes: \"{def.FullSentence}\"",
                null,
                $"Source passage: {def.FullSentence}"
            ));
        }

        return result;
    }

    private static List<GeneratedQuestionDto> GenerateQuestionsFromDefinitions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        List<string> pool,
        bool wantsOnlyMcq = false,
        bool wantsIdentification = false,
        int countNeeded = int.MaxValue,
        int setIndex = 0,
        string? variant = null)
    {
        var questions = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count; i++)
        {
            if (questions.Count >= countNeeded) break;
            var def = definitions[i];
            var rand = new Random(setIndex * 7919 + (def.Term + i).GetHashCode());

            // 1. Definition Multiple Choice Question
            var otherDefs = definitions
                .Where(d => !string.Equals(d.Term, def.Term, StringComparison.OrdinalIgnoreCase))
                .Select(d => d.Definition)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(_ => rand.Next())
                .Take(3)
                .ToList();

            int dCount = 1;
            while (otherDefs.Count < 3)
            {
                otherDefs.Add($"Contrasting definition {dCount++} related to {title}.");
            }

            var options = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(def.Definition, true, null),
                new GeneratedOptionDto(otherDefs[0], false, "Refers to a different concept in the notes."),
                new GeneratedOptionDto(otherDefs[1], false, "Alternative condition not matching this term."),
                new GeneratedOptionDto(otherDefs[2], false, "Contrasting definition from other material.")
            };

            options = options.OrderBy(_ => rand.Next()).ToList();

            int promptStyle = (i + setIndex) % 4;
            string mcqPrompt = promptStyle switch
            {
                1 => $"Which core concept from {title} is characterized by the following: \"{def.Definition}\"?",
                2 => $"In the study of {title}, what is the primary role or definition associated with \"{def.Term}\"?",
                3 => $"Identify the key principle corresponding directly to: \"{def.Definition}\"",
                _ => $"According to the study material on {title}, which of the following best defines \"{def.Term}\"?"
            };

            questions.Add(new GeneratedQuestionDto(
                "multiple_choice",
                mcqPrompt,
                new List<string> { $"Review notes on \"{def.Term}\".", "Check key definitions." },
                def.Definition,
                options,
                null, null, false,
                $"Document context: {def.FullSentence}",
                null,
                $"Source passage: {def.FullSentence}"
            ));

            if (questions.Count >= countNeeded) break;

            // 2. Reverse Term Multiple Choice Question
            var otherTerms = definitions
                .Where(d => !string.Equals(d.Term, def.Term, StringComparison.OrdinalIgnoreCase))
                .Select(d => d.Term)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(3)
                .ToList();

            int tCount = 1;
            while (otherTerms.Count < 3)
            {
                otherTerms.Add($"Concept {tCount++}");
            }

            var termOptions = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(def.Term, true, null),
                new GeneratedOptionDto(otherTerms[0], false, "Separate concept from the study notes."),
                new GeneratedOptionDto(otherTerms[1], false, "Contrasting topic."),
                new GeneratedOptionDto(otherTerms[2], false, "Alternative term.")
            };
            termOptions = termOptions.OrderBy(_ => rand.Next()).ToList();

            questions.Add(new GeneratedQuestionDto(
                "multiple_choice",
                $"What academic term is described as: \"{def.Definition}\"?",
                new List<string> { $"Starts with letter '{def.Term[0]}'", $"Length is {def.Term.Length} characters" },
                def.Term,
                termOptions,
                null, null, false,
                $"The term \"{def.Term}\" explicitly matches this definition.",
                null,
                $"Source passage: {def.FullSentence}"
            ));

            if (wantsIdentification && questions.Count < countNeeded)
            {
                questions.Add(new GeneratedQuestionDto(
                    "identification",
                    $"Identify the term: \"{def.Definition}\"",
                    new List<string> { $"First letter: '{def.Term[0]}'" },
                    def.Term,
                    new List<GeneratedOptionDto> { new GeneratedOptionDto(def.Term, true, null) },
                    new List<string> { def.Term.ToLowerInvariant() },
                    null, false,
                    $"Defined in notes: {def.FullSentence}",
                    null,
                    $"Source passage: {def.FullSentence}"
                ));
            }
        }

        return questions;
    }

    private static List<GeneratedQuestionDto> GenerateFromSentences(
        List<string> cleanLines,
        string title,
        List<string> pool,
        int countNeeded)
    {
        var result = new List<GeneratedQuestionDto>();
        var factualSentences = cleanLines
            .Where(l => l.Length >= 25 && l.Length <= 240 && !l.Contains("?") &&
                        !Regex.IsMatch(l, @"^(?:[\*\-\+•◦▪\>]+\s*)?(?:Q(?:uestion)?\s*\d*|\d+[\.\)]|Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                        !IsMcqOptionOrAnswerKeyLine(l) &&
                        !Regex.IsMatch(l.TrimEnd(), @"\b(on|to|for|with|in|at|by|from|of|into|onto|and|or|but|as|that|than|via|after|before|during|under|over|between|about)$", RegexOptions.IgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        for (int i = 0; i < factualSentences.Count && result.Count < countNeeded; i++)
        {
            var sentence = factualSentences[i];
            var words = sentence.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (words.Length < 5) continue;

            // Pick a significant key word or noun phrase from the sentence, avoiding generic status/UI words
            var candidateWord = words
                .Select(w => w.Trim().TrimEnd('.', ',', ';', ':', '!', '?', '"', '\'').TrimStart('"', '\''))
                .FirstOrDefault(w => w.Length >= 5 && char.IsLetter(w[0]) &&
                                     !Regex.IsMatch(w, @"^(which|their|about|these|those|where|there|would|could|should|unable|access|visit|using|being|having|getting|stated|given|takes|makes|comes|looks|needs|please|check|click|refer|terms|follow|below|above|start|every|other|first|second|third|issue|repository)$", RegexOptions.IgnoreCase))
                ?? words.Select(w => w.Trim().TrimEnd('.', ',', ';', ':', '!', '?')).FirstOrDefault(w => w.Length >= 5 && char.IsLetter(w[0]))
                ?? words[words.Length / 2].TrimEnd('.', ',', ';', ':', '!', '?');

            candidateWord = candidateWord.TrimEnd('.', ',', ';', ':', '!', '?');
            if (candidateWord.Length < 3) continue;

            var blankedSentence = Regex.Replace(sentence, Regex.Escape(candidateWord), "________", RegexOptions.IgnoreCase);

            var distractors = pool
                .Where(p => !string.Equals(p, candidateWord, StringComparison.OrdinalIgnoreCase) && p.Length > 2 && p.Length < 40)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(3)
                .ToList();

            if (distractors.Count < 3)
            {
                // Pull additional vocabulary words from other clean lines in the document
                var docWords = cleanLines
                    .SelectMany(l => l.Split(new[] { ' ', ',', '.', ';', ':', '!', '?' }, StringSplitOptions.RemoveEmptyEntries))
                    .Where(w => w.Length >= 5 && char.IsLetter(w[0]) &&
                                !string.Equals(w, candidateWord, StringComparison.OrdinalIgnoreCase) &&
                                !Regex.IsMatch(w, @"^(which|their|about|these|those|where|there|would|could|should|unable|access|visit|using|being|having|getting|stated)$", RegexOptions.IgnoreCase))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();

                foreach (var dw in docWords)
                {
                    if (distractors.Count >= 3) break;
                    if (!distractors.Contains(dw, StringComparer.OrdinalIgnoreCase))
                    {
                        distractors.Add(dw);
                    }
                }
            }

            var genericDistractors = new[] { "Mechanism", "Structure", "Pathway", "Component", "Principle", "System", "Function" };
            int gIdx = 0;
            while (distractors.Count < 3 && gIdx < genericDistractors.Length)
            {
                var candidate = genericDistractors[gIdx++];
                if (!distractors.Contains(candidate, StringComparer.OrdinalIgnoreCase))
                {
                    distractors.Add(candidate);
                }
            }

            var options = new List<GeneratedOptionDto>
            {
                new GeneratedOptionDto(candidateWord, true, null),
                new GeneratedOptionDto(distractors[0], false, "Not the word stated in the notes."),
                new GeneratedOptionDto(distractors[1], false, "Incorrect term for this statement."),
                new GeneratedOptionDto(distractors[2], false, "Alternative term from another topic.")
            };

            var rand = new Random((sentence + i).GetHashCode());
            options = options.OrderBy(_ => rand.Next()).ToList();

            result.Add(new GeneratedQuestionDto(
                "multiple_choice",
                $"Fill in the blank from your study notes: \"{blankedSentence}\"",
                new List<string> { $"Word begins with '{candidateWord[0]}'" },
                candidateWord,
                options,
                null, null, false,
                $"Full text from your notes: \"{sentence}\"",
                null,
                $"Notes passage: {sentence}"
            ));
        }

        return result;
    }

    private static GeneratedQuestionDto EnsureFourDistinctChoices(
        GeneratedQuestionDto q,
        int questionIndex,
        string title,
        List<string> pool)
    {
        var seenTexts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var uniqueOptions = new List<GeneratedOptionDto>();

        if (q.Options != null)
        {
            foreach (var opt in q.Options)
            {
                var trimmed = opt.Text?.Trim() ?? string.Empty;
                if (trimmed.Length > 0 && seenTexts.Add(trimmed))
                {
                    uniqueOptions.Add(new GeneratedOptionDto(trimmed, opt.IsCorrect, opt.DistractorRationale));
                }
            }
        }

        // Guarantee exactly 1 correct option
        int correctCount = uniqueOptions.Count(o => o.IsCorrect);
        if (correctCount == 0)
        {
            if (!string.IsNullOrWhiteSpace(q.CorrectAnswer))
            {
                var match = uniqueOptions.FirstOrDefault(o => string.Equals(o.Text, q.CorrectAnswer.Trim(), StringComparison.OrdinalIgnoreCase));
                if (match != null)
                {
                    int mIdx = uniqueOptions.IndexOf(match);
                    uniqueOptions[mIdx] = new GeneratedOptionDto(match.Text, true, null);
                }
                else if (seenTexts.Add(q.CorrectAnswer.Trim()))
                {
                    uniqueOptions.Insert(0, new GeneratedOptionDto(q.CorrectAnswer.Trim(), true, null));
                }
                else if (uniqueOptions.Count > 0)
                {
                    uniqueOptions[0] = new GeneratedOptionDto(uniqueOptions[0].Text, true, null);
                }
            }
            else if (uniqueOptions.Count > 0)
            {
                uniqueOptions[0] = new GeneratedOptionDto(uniqueOptions[0].Text, true, null);
            }
        }
        else if (correctCount > 1)
        {
            // Keep only the first correct one
            bool keptFirst = false;
            for (int k = 0; k < uniqueOptions.Count; k++)
            {
                if (uniqueOptions[k].IsCorrect)
                {
                    if (!keptFirst)
                    {
                        keptFirst = true;
                    }
                    else
                    {
                        uniqueOptions[k] = new GeneratedOptionDto(uniqueOptions[k].Text, false, "Alternative distractor.");
                    }
                }
            }
        }

        // Guarantee 4 distinct options
        var poolCandidates = pool
            .Where(p => p.Length > 1 && p.Length < 120 && !seenTexts.Contains(p.Trim()))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        int candidateIdx = 0;
        while (uniqueOptions.Count < 4 && candidateIdx < poolCandidates.Count)
        {
            var candidate = poolCandidates[candidateIdx++].Trim();
            if (seenTexts.Add(candidate))
            {
                uniqueOptions.Add(new GeneratedOptionDto(candidate, false, "Alternative option from notes."));
            }
        }

        // If pool is exhausted, supplement with distinct, non-repeating academic distractors
        int fallbackNum = 1;
        while (uniqueOptions.Count < 4)
        {
            var fallbackText = fallbackNum switch
            {
                1 => $"Contrasting condition not matching item #{questionIndex}",
                2 => $"Alternative property from external syllabus topic",
                3 => $"Historical assumption superseded in {title}",
                _ => $"Theoretical exception #{questionIndex}-{fallbackNum}"
            };
            fallbackNum++;

            if (seenTexts.Add(fallbackText))
            {
                uniqueOptions.Add(new GeneratedOptionDto(fallbackText, false, "Contextual distractor."));
            }
        }

        var correctOpt = uniqueOptions.FirstOrDefault(o => o.IsCorrect) ?? uniqueOptions.First();

        return new GeneratedQuestionDto(
            q.Type,
            q.Prompt,
            q.Hints,
            correctOpt.Text,
            uniqueOptions.Take(4).ToList(),
            q.ValidSynonyms,
            q.EnumerationItems,
            q.IsOrdered,
            q.Explanation ?? $"Correct solution: {correctOpt.Text}",
            q.ThinkingBreakdown,
            q.SourceReference
        );
    }
}

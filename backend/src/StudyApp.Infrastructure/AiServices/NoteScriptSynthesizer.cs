using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using StudyApp.Application.DTOs.Ingestion;

namespace StudyApp.Infrastructure.AiServices;

public static class NoteScriptSynthesizer
{
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
        int targetCount = 10)
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

        // 2. Stage 1: Parse pre-formatted multiple-choice questions already present in notes
        var mcqQuestions = ParseFormattedMultipleChoice(cleanLines, cleanTitle);
        foreach (var q in mcqQuestions)
        {
            questions.Add(q);
            if (!string.IsNullOrWhiteSpace(q.CorrectAnswer))
            {
                poolOfAnswersAndTerms.Add(q.CorrectAnswer);
            }
            if (q.Options != null)
            {
                foreach (var opt in q.Options)
                {
                    if (!string.IsNullOrWhiteSpace(opt.Text))
                    {
                        poolOfAnswersAndTerms.Add(opt.Text);
                    }
                }
            }
        }

        // 3. Stage 2: Parse Q&A pairs (e.g. Q: ... A: ...)
        var qaQuestions = ParseQuestionAnswerPairs(cleanLines, cleanTitle, poolOfAnswersAndTerms);
        foreach (var q in qaQuestions)
        {
            // Avoid duplicate prompts
            if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
            {
                questions.Add(q);
                if (!string.IsNullOrWhiteSpace(q.CorrectAnswer))
                {
                    poolOfAnswersAndTerms.Add(q.CorrectAnswer);
                }
            }
        }

        // 4. Stage 3: Generate multiple-choice questions from definitions & concepts if below targetCount
        var types = requestedTypes ?? new List<string>();
        bool wantsOnlyMcq = types.Count == 0 || types.Any(t => t.Equals("multiple_choice", StringComparison.OrdinalIgnoreCase));
        bool wantsIdentification = types.Any(t => t.Equals("identification", StringComparison.OrdinalIgnoreCase));

        if (questions.Count < targetCount && parsedDefinitions.Count > 0)
        {
            int needed = targetCount - questions.Count;
            var defQuestions = GenerateQuestionsFromDefinitions(parsedDefinitions.Take(needed).ToList(), cleanTitle, poolOfAnswersAndTerms, wantsOnlyMcq, wantsIdentification);
            foreach (var q in defQuestions)
            {
                if (questions.Count >= targetCount) break;
                if (!questions.Any(existing => string.Equals(existing.Prompt, q.Prompt, StringComparison.OrdinalIgnoreCase)))
                {
                    questions.Add(q);
                }
            }
        }

        // 5. Stage 4: Generate from key factual sentences if we still have fewer questions than targetCount
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
                Regex.IsMatch(line, @"^\s*[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]"))
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

    private static List<GeneratedQuestionDto> GenerateQuestionsFromDefinitions(
        List<(string Term, string Definition, string FullSentence)> definitions,
        string title,
        List<string> pool,
        bool wantsOnlyMcq,
        bool wantsIdentification)
    {
        var questions = new List<GeneratedQuestionDto>();

        for (int i = 0; i < definitions.Count; i++)
        {
            var def = definitions[i];

            // 1. Definition Multiple Choice Question
            var otherDefs = definitions
                .Where(d => !string.Equals(d.Term, def.Term, StringComparison.OrdinalIgnoreCase))
                .Select(d => d.Definition)
                .Distinct(StringComparer.OrdinalIgnoreCase)
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

            var rand = new Random((def.Term + i).GetHashCode());
            options = options.OrderBy(_ => rand.Next()).ToList();

            questions.Add(new GeneratedQuestionDto(
                "multiple_choice",
                $"According to the study material, which of the following best defines \"{def.Term}\"?",
                new List<string> { $"Review notes on \"{def.Term}\".", "Check key definitions." },
                def.Definition,
                options,
                null, null, false,
                $"Document context: {def.FullSentence}",
                null,
                $"Source passage: {def.FullSentence}"
            ));

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

            if (wantsIdentification)
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
            .Where(l => l.Length >= 25 && l.Length <= 160 &&
                        !l.Contains("?") &&
                        !Regex.IsMatch(l, @"^(?:Q(?:uestion)?\s*\d*|\d+[\.\)]|Answer|Ans|Key|Solution)\b", RegexOptions.IgnoreCase) &&
                        !Regex.IsMatch(l, @"^\s*[\(\[]?[A-Fa-f][\)\]]?[\.:\s\-]"))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        for (int i = 0; i < factualSentences.Count && result.Count < countNeeded; i++)
        {
            var sentence = factualSentences[i];
            var words = sentence.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (words.Length < 5) continue;

            // Pick a significant key word or noun phrase from the sentence
            var candidateWord = words.FirstOrDefault(w => w.Length >= 5 && char.IsLetter(w[0]) && !Regex.IsMatch(w, @"^(which|their|about|these|those|where|there|would|could|should)$", RegexOptions.IgnoreCase))
                ?? words[words.Length / 2];

            candidateWord = candidateWord.TrimEnd('.', ',', ';', ':', '!', '?');

            var blankedSentence = Regex.Replace(sentence, Regex.Escape(candidateWord), "________", RegexOptions.IgnoreCase);

            var distractors = pool
                .Where(p => !string.Equals(p, candidateWord, StringComparison.OrdinalIgnoreCase) && p.Length > 2 && p.Length < 40)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(3)
                .ToList();

            var genericDistractors = new[] { "Condition", "Standard", "Variable", "Factor", "Principle", "Element" };
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

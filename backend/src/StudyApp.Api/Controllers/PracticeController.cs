using System.Globalization;
using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Practice;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

/// <summary>
/// Grades every assessment mode on the server.  The mobile client may cache a
/// deck for offline use, but scores that are synced here are always recalculated
/// from the original question rather than trusting a client supplied score.
/// </summary>
[ApiController]
[Route("api/v1/practice")]
[Authorize]
public sealed class PracticeController : ControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly IApplicationDbContext _context;
    private readonly IAiTutorService _aiTutorService;

    public PracticeController(IApplicationDbContext context, IAiTutorService aiTutorService)
    {
        _context = context;
        _aiTutorService = aiTutorService;
    }

    [HttpGet("studysets/{studySetId:guid}/questions")]
    public async Task<IActionResult> GetAdaptiveQuestions(
        Guid studySetId,
        [FromQuery] StudyMode mode = StudyMode.SimulatedExam,
        [FromQuery] int count = 15,
        CancellationToken cancellationToken = default)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();
        count = Math.Clamp(count, 1, 50);

        var studySet = await _context.StudySets
            .Where(set => set.Id == studySetId && set.Course != null && set.Course.UserId == userId.Value)
            .Include(set => set.Questions)
                .ThenInclude(question => question.Options)
            .Include(set => set.Questions)
                .ThenInclude(question => question.Rubrics)
            .SingleOrDefaultAsync(cancellationToken);
        if (studySet is null) return NotFound(new { message = "Study set not found." });

        var submittedScores = await _context.SessionAnswers
            .Where(answer => answer.Question != null && answer.Question.StudySetId == studySetId)
            .Select(answer => new { answer.QuestionId, answer.PartialScore })
            .ToListAsync(cancellationToken);
        var performance = submittedScores
            .GroupBy(answer => answer.QuestionId)
            .ToDictionary(group => group.Key, group => (Accuracy: group.Average(answer => answer.PartialScore), Attempts: group.Count()));

        var averageAccuracy = performance.Count == 0 ? 0m : performance.Values.Average(value => value.Accuracy);
        var targetDifficulty = averageAccuracy < 0.6m ? 1 : averageAccuracy < 0.85m ? 2 : 3;
        var candidates = studySet.Questions
            .Where(question => IsEligibleForMode(question.Type, mode))
            .Select(question => new
            {
                Question = question,
                Accuracy = performance.TryGetValue(question.Id, out var result) ? result.Accuracy : -1m,
                Attempts = performance.TryGetValue(question.Id, out var attempt) ? attempt.Attempts : 0
            })
            .OrderBy(item => mode == StudyMode.WeakSpotMastery ? item.Accuracy : Math.Abs(item.Question.Difficulty - targetDifficulty))
            .ThenBy(item => item.Attempts == 0 ? 0 : 1)
            .ThenBy(_ => Guid.NewGuid())
            .Take(count)
            .ToList();

        // Server sessions deliberately omit answer keys. This permits online modes
        // to be graded authoritatively while cached offline decks can retain their
        // existing /studysets/{id}/questions representation.
        return Ok(candidates.Select(item => new
        {
            item.Question.Id,
            item.Question.StudySetId,
            Type = item.Question.Type.ToString(),
            item.Question.Prompt,
            Hints = ReadHints(item.Question.HintsJson),
            item.Question.Difficulty,
            item.Question.SortOrder,
            Options = item.Question.Options.Select(option => new { option.Id, option.OptionText }).OrderBy(_ => Guid.NewGuid()),
            MatchingTerms = item.Question.Type == QuestionType.Matching ? ReadMatchingTerms(item.Question.Rubrics) : null,
            MatchingDefinitions = item.Question.Type == QuestionType.Matching ? ReadMatchingDefinitions(item.Question.Rubrics) : null,
            SourceReference = ReadSourceReference(item.Question.ThinkingBreakdownJson)
        }));
    }

    [HttpPost("sessions")]
    public async Task<ActionResult<CompletePracticeSessionResponse>> CompleteSession(
        [FromBody] CompletePracticeSessionRequest request,
        CancellationToken cancellationToken)
    {
        if (request.StudySetId == Guid.Empty || request.Answers is null || request.Answers.Count == 0)
        {
            return BadRequest(new { message = "A study set and at least one answer are required." });
        }

        if (request.TimeSpentSeconds is < 0 or > 86_400)
        {
            return BadRequest(new { message = "Time spent must be between 0 and 86,400 seconds." });
        }

        if (request.Answers.Any(a => a.QuestionId == Guid.Empty) || request.Answers.Select(a => a.QuestionId).Distinct().Count() != request.Answers.Count)
        {
            return BadRequest(new { message = "Each submitted answer must reference one distinct question." });
        }

        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var studySet = await _context.StudySets
            .Where(s => s.Id == request.StudySetId && s.Course != null && s.Course.UserId == userId.Value)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Rubrics)
            .SingleOrDefaultAsync(cancellationToken);

        if (studySet is null) return NotFound(new { message = "Study set not found." });

        var questions = studySet.Questions.ToDictionary(q => q.Id);
        if (request.Answers.Any(a => !questions.ContainsKey(a.QuestionId)))
        {
            return BadRequest(new { message = "One or more questions do not belong to this study set." });
        }

        var now = DateTime.UtcNow;
        var grades = new List<AnswerGradeDto>(request.Answers.Count);
        foreach (var answer in request.Answers)
        {
            grades.Add(await GradeAsync(questions[answer.QuestionId], answer, request.Mode, now, cancellationToken));
        }

        var session = new TestSession
        {
            Id = Guid.NewGuid(),
            StudySetId = studySet.Id,
            Mode = request.Mode,
            Score = grades.Count(g => g.IsCorrect),
            TotalQuestions = grades.Count,
            TimeSpentSeconds = request.TimeSpentSeconds,
            CompletedAt = now
        };

        foreach (var answer in request.Answers)
        {
            var grade = grades.Single(g => g.QuestionId == answer.QuestionId);
            session.Answers.Add(new SessionAnswer
            {
                Id = Guid.NewGuid(),
                QuestionId = answer.QuestionId,
                UserSubmittedAnswer = answer.Answer?.Trim() ?? string.Empty,
                IsCorrect = grade.IsCorrect,
                PartialScore = grade.PartialScore,
                AiFeedback = grade.Feedback
            });
        }

        _context.TestSessions.Add(session);
        await _context.SaveChangesAsync(cancellationToken);

        var percent = grades.Count == 0 ? 0m : Math.Round(grades.Sum(g => g.PartialScore) / grades.Count * 100m, 1);
        return Ok(new CompletePracticeSessionResponse(session.Id, session.Score, session.TotalQuestions, percent, grades));
    }

    [HttpGet("mastery")]
    public async Task<ActionResult<List<MasteryTopicDto>>> GetMastery(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var attempts = await _context.SessionAnswers
            .Include(a => a.Question)
                .ThenInclude(q => q!.StudySet)
                    .ThenInclude(s => s!.Course)
            .Where(a => a.Question != null && a.Question.StudySet != null && a.Question.StudySet.Course != null && a.Question.StudySet.Course.UserId == userId.Value)
            .Select(a => new { a.Question!.StudySetId, a.Question.StudySet!.Title, a.IsCorrect, a.PartialScore })
            .ToListAsync(cancellationToken);

        var result = attempts
            .GroupBy(a => new { a.StudySetId, a.Title })
            .Select(g =>
            {
                var accuracy = Math.Round(g.Average(a => a.PartialScore) * 100m, 1);
                return new MasteryTopicDto(g.Key.StudySetId, g.Key.Title, g.Count(), g.Count(a => a.IsCorrect), accuracy,
                    accuracy >= 85m ? "Mastered" : accuracy >= 60m ? "Review Needed" : "High Risk");
            })
            .OrderBy(x => x.AccuracyPercent)
            .ToList();

        return Ok(result);
    }

    [HttpGet("weak-spots")]
    public async Task<ActionResult<List<WeakSpotDto>>> GetWeakSpots([FromQuery] int take = 20, CancellationToken cancellationToken = default)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();
        take = Math.Clamp(take, 1, 100);

        var attempts = await _context.SessionAnswers
            .Include(a => a.Question)
                .ThenInclude(q => q!.StudySet)
                    .ThenInclude(s => s!.Course)
            .Where(a => a.Question != null && a.Question.StudySet != null && a.Question.StudySet.Course != null && a.Question.StudySet.Course.UserId == userId.Value)
            .Select(a => new { a.QuestionId, a.IsCorrect, a.PartialScore, Prompt = a.Question!.Prompt, Type = a.Question.Type, a.Question.StudySetId })
            .ToListAsync(cancellationToken);

        var result = attempts
            .GroupBy(a => new { a.QuestionId, a.StudySetId, a.Prompt, a.Type })
            .Select(g => new WeakSpotDto(
                g.Key.QuestionId,
                g.Key.StudySetId,
                g.Key.Prompt,
                g.Key.Type,
                g.Count(),
                g.Count(a => !a.IsCorrect),
                Math.Round(g.Average(a => a.PartialScore) * 100m, 1)))
            .Where(x => x.Misses > 0)
            .OrderBy(x => x.AccuracyPercent)
            .ThenByDescending(x => x.Attempts)
            .Take(take)
            .ToList();

        return Ok(result);
    }

    private async Task<AnswerGradeDto> GradeAsync(
        Question question,
        PracticeAnswerRequest submitted,
        StudyMode mode,
        DateTime now,
        CancellationToken cancellationToken)
    {
        var answer = submitted.Answer?.Trim() ?? string.Empty;
        if (mode == StudyMode.Flashcards && submitted.RecallRating is >= 1 and <= 4)
        {
            var isCorrect = submitted.RecallRating >= 3;
            var historyCount = await _context.SessionAnswers.CountAsync(
                a => a.QuestionId == question.Id && a.TestSession != null && a.TestSession.Mode == StudyMode.Flashcards,
                cancellationToken);
            var delay = GetReviewDelay(submitted.RecallRating.Value, historyCount);
            var label = submitted.RecallRating.Value switch { 1 => "Again", 2 => "Hard", 3 => "Good", _ => "Easy" };
            return new AnswerGradeDto(question.Id, isCorrect, submitted.RecallRating == 2 ? 0.5m : isCorrect ? 1m : 0m,
                $"Marked {label}. Your next review is scheduled from this rating.", GetCorrectAnswer(question), now.Add(delay));
        }

        return question.Type switch
        {
            QuestionType.MultipleChoice => GradeChoice(question, answer),
            QuestionType.TrueFalse => GradeChoice(question, answer),
            QuestionType.Identification or QuestionType.Cloze => GradeTypedAnswer(question, answer),
            QuestionType.Enumeration or QuestionType.BulletPoints => GradeEnumeration(question, answer),
            QuestionType.Matching => GradeMatching(question, answer),
            QuestionType.ShortAnswer or QuestionType.LogicalThinking => await GradeConceptAnswerAsync(question, answer, cancellationToken),
            QuestionType.Scenario => question.Options.Any() ? GradeChoice(question, answer) : await GradeConceptAnswerAsync(question, answer, cancellationToken),
            _ => GradeTypedAnswer(question, answer)
        };
    }

    private static AnswerGradeDto GradeChoice(Question question, string answer)
    {
        var selected = question.Options.FirstOrDefault(o =>
            Guid.TryParse(answer, out var id) && o.Id == id || NormalizedEquals(o.OptionText, answer));
        var correct = selected?.IsCorrect == true;
        return new AnswerGradeDto(question.Id, correct, correct ? 1m : 0m,
            correct ? "Correct." : "Not quite. Review the explanation and try this concept again.", GetCorrectAnswer(question));
    }

    private static AnswerGradeDto GradeTypedAnswer(Question question, string answer)
    {
        var accepted = question.Options.Where(o => o.IsCorrect).Select(o => o.OptionText).Distinct().ToList();
        var correct = accepted.Any(expected => IsFuzzyMatch(answer, expected));
        return new AnswerGradeDto(question.Id, correct, correct ? 1m : 0m,
            correct ? "Correct recall." : "That does not match the expected term closely enough.", GetCorrectAnswer(question));
    }

    private static AnswerGradeDto GradeEnumeration(Question question, string answer)
    {
        var expected = question.Rubrics.OrderBy(r => r.SortOrder).Select(r => r.ItemText).ToList();
        if (expected.Count == 0) expected = SplitItems(GetCorrectAnswer(question));
        var given = SplitItems(answer);
        var ordered = IsOrderedEnumeration(question.ThinkingBreakdownJson);
        var matched = 0;

        if (ordered)
        {
            for (var i = 0; i < Math.Min(expected.Count, given.Count); i++)
            {
                if (IsFuzzyMatch(given[i], expected[i])) matched++;
            }
        }
        else
        {
            var remaining = new List<string>(given);
            foreach (var item in expected)
            {
                var index = remaining.FindIndex(givenItem => IsFuzzyMatch(givenItem, item));
                if (index < 0) continue;
                matched++;
                remaining.RemoveAt(index);
            }
        }

        var partial = expected.Count == 0 ? 0m : Math.Round((decimal)matched / expected.Count, 2);
        var correct = expected.Count > 0 && partial >= 0.999m;
        return new AnswerGradeDto(question.Id, correct, partial,
            $"Matched {matched} of {expected.Count} expected items{(ordered ? " in order" : string.Empty)}.", GetCorrectAnswer(question));
    }

    private static AnswerGradeDto GradeMatching(Question question, string answer)
    {
        var expected = question.Rubrics
            .Select(r => TryReadPair(r.ItemText))
            .Where(pair => pair is not null)
            .Cast<(string Term, string Definition)>()
            .ToList();
        var actual = ReadPairs(answer);

        if (expected.Count == 0)
        {
            return new AnswerGradeDto(question.Id, false, 0m, "This matching question has no valid answer key.", GetCorrectAnswer(question));
        }

        var matched = expected.Count(pair => actual.Any(a => NormalizedEquals(a.Term, pair.Term) && IsFuzzyMatch(a.Definition, pair.Definition)));
        var partial = Math.Round((decimal)matched / expected.Count, 2);
        return new AnswerGradeDto(question.Id, matched == expected.Count, partial,
            $"Matched {matched} of {expected.Count} pairs.", GetCorrectAnswer(question));
    }

    private async Task<AnswerGradeDto> GradeConceptAnswerAsync(Question question, string answer, CancellationToken cancellationToken)
    {
        var rubric = question.Rubrics.OrderBy(r => r.SortOrder).Select(r => r.ItemText).ToList();
        if (rubric.Count == 0) rubric = ReadHints(question.HintsJson);
        var matches = rubric.Count(keyword => ContainsNormalized(answer, keyword));
        var partial = rubric.Count == 0
            ? (answer.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 12 ? 0.6m : 0m)
            : Math.Round((decimal)matches / rubric.Count, 2);
        var correct = partial >= 0.7m;
        var feedback = rubric.Count == 0
            ? "Your response was recorded for review. Add specific concepts and supporting reasoning."
            : $"Your answer covered {matches} of {rubric.Count} rubric concepts.";

        var modelAnswer = GetCorrectAnswer(question);
        if (!string.IsNullOrWhiteSpace(answer) && !string.IsNullOrWhiteSpace(modelAnswer))
        {
            var aiGrade = await _aiTutorService.EvaluateOpenAnswerAsync(question.Prompt, modelAnswer, rubric, answer, cancellationToken);
            if (aiGrade.IsAiEvaluation)
            {
                partial = aiGrade.Score;
                correct = partial >= 0.7m;
                feedback = aiGrade.Feedback;
            }
        }

        return new AnswerGradeDto(question.Id, correct, partial,
            feedback,
            GetCorrectAnswer(question));
    }

    private Guid? GetUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    private static TimeSpan GetReviewDelay(int rating, int historyCount)
    {
        if (rating == 1) return TimeSpan.FromMinutes(10);
        var baseDays = rating == 2 ? 1 : rating == 3 ? 3 : 7;
        var multiplier = Math.Pow(1.7, Math.Min(historyCount, 8));
        return TimeSpan.FromDays(Math.Min(180, Math.Round(baseDays * multiplier)));
    }

    private static string GetCorrectAnswer(Question question) => string.Join("; ", question.Options.Where(o => o.IsCorrect).Select(o => o.OptionText));

    private static List<string> SplitItems(string input) => Regex.Split(input ?? string.Empty, @"(?:\r?\n|,|;|\||\s+\d+[.)]\s*)")
        .Select(x => Regex.Replace(x, @"^\s*(?:[-*â€¢]|\d+[.)])\s*", string.Empty).Trim())
        .Where(x => x.Length > 0)
        .ToList();

    private static List<string> ReadHints(string hintsJson)
    {
        try { return JsonSerializer.Deserialize<List<string>>(hintsJson, JsonOptions) ?? new List<string>(); }
        catch (JsonException) { return new List<string>(); }
    }

    private static bool IsEligibleForMode(QuestionType type, StudyMode mode) => mode switch
    {
        StudyMode.MultipleChoice => type == QuestionType.MultipleChoice,
        StudyMode.Identification => type == QuestionType.Identification,
        StudyMode.Enumeration => type is QuestionType.Enumeration or QuestionType.BulletPoints,
        StudyMode.ClozeTest => type == QuestionType.Cloze,
        StudyMode.TrueFalse => type == QuestionType.TrueFalse,
        StudyMode.MatchingType => type == QuestionType.Matching,
        StudyMode.ShortAnswer => type is QuestionType.ShortAnswer or QuestionType.LogicalThinking,
        StudyMode.ScenarioDrills => type == QuestionType.Scenario,
        StudyMode.RapidFireBlitz => type is QuestionType.Identification or QuestionType.TrueFalse or QuestionType.MultipleChoice,
        _ => true
    };

    private static List<string> ReadMatchingTerms(IEnumerable<QuestionRubric> rubrics) => rubrics
        .Select(rubric => TryReadPair(rubric.ItemText))
        .Where(pair => pair is not null)
        .Select(pair => pair!.Value.Term)
        .ToList();

    private static List<string> ReadMatchingDefinitions(IEnumerable<QuestionRubric> rubrics) => rubrics
        .Select(rubric => TryReadPair(rubric.ItemText))
        .Where(pair => pair is not null)
        .Select(pair => pair!.Value.Definition)
        .OrderBy(_ => Guid.NewGuid())
        .ToList();

    private static string? ReadSourceReference(string? metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata)) return null;
        try
        {
            using var document = JsonDocument.Parse(metadata);
            return document.RootElement.ValueKind == JsonValueKind.Object && document.RootElement.TryGetProperty("sourceReference", out var sourceReference)
                ? sourceReference.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static bool IsOrderedEnumeration(string? metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata)) return false;
        try
        {
            using var document = JsonDocument.Parse(metadata);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("isOrdered", out var isOrdered) &&
                   isOrdered.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static List<(string Term, string Definition)> ReadPairs(string answer)
    {
        try
        {
            using var document = JsonDocument.Parse(answer);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                return document.RootElement.EnumerateObject().Select(p => (p.Name, p.Value.GetString() ?? string.Empty)).ToList();
            }
            if (document.RootElement.ValueKind == JsonValueKind.Array)
            {
                return document.RootElement.EnumerateArray()
                    .Where(x => x.ValueKind == JsonValueKind.Object)
                    .Select(x => (x.TryGetProperty("term", out var term) ? term.GetString() ?? string.Empty : string.Empty,
                        x.TryGetProperty("definition", out var definition) ? definition.GetString() ?? string.Empty : string.Empty))
                    .ToList();
            }
        }
        catch (JsonException) { }
        return new List<(string Term, string Definition)>();
    }

    private static (string Term, string Definition)? TryReadPair(string serialized)
    {
        try
        {
            using var document = JsonDocument.Parse(serialized);
            var root = document.RootElement;
            if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("term", out var term) && root.TryGetProperty("definition", out var definition))
            {
                return (term.GetString() ?? string.Empty, definition.GetString() ?? string.Empty);
            }
        }
        catch (JsonException) { }
        return null;
    }

    private static bool NormalizedEquals(string first, string second) => Normalize(first) == Normalize(second);
    private static bool ContainsNormalized(string text, string phrase) => Normalize(text).Contains(Normalize(phrase), StringComparison.Ordinal);

    private static bool IsFuzzyMatch(string submitted, string expected)
    {
        var a = Normalize(submitted);
        var b = Normalize(expected);
        if (a.Length == 0 || b.Length == 0) return false;
        if (a == b) return true;
        var tolerance = b.Length <= 5 ? 1 : Math.Max(2, (int)Math.Floor(b.Length * 0.18));
        return LevenshteinDistance(a, b) <= tolerance;
    }

    private static string Normalize(string value) => Regex.Replace((value ?? string.Empty).ToLower(CultureInfo.InvariantCulture), @"[^\p{L}\p{N}]+", " ").Trim();

    private static int LevenshteinDistance(string first, string second)
    {
        var previous = Enumerable.Range(0, second.Length + 1).ToArray();
        for (var i = 1; i <= first.Length; i++)
        {
            var current = new int[second.Length + 1];
            current[0] = i;
            for (var j = 1; j <= second.Length; j++)
            {
                current[j] = Math.Min(Math.Min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + (first[i - 1] == second[j - 1] ? 0 : 1));
            }
            previous = current;
        }
        return previous[second.Length];
    }
}

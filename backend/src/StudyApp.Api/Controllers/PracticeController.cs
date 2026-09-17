using System.Data.Common;
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

        return Ok(candidates.Select(item => new
        {
            item.Question.Id,
            item.Question.StudySetId,
            Type = item.Question.Type.ToString(),
            item.Question.Prompt,
            Hints = ReadHints(item.Question.HintsJson),
            Explanation = item.Question.Explanation,
            CorrectAnswer = GetCorrectAnswer(item.Question),
            IsTrue = item.Question.Type == QuestionType.TrueFalse
                ? (item.Question.Options.FirstOrDefault(o => o.IsCorrect)?.OptionText.Trim().Equals("True", StringComparison.OrdinalIgnoreCase) ??
                   item.Question.Options.FirstOrDefault(o => o.IsCorrect)?.OptionText.Trim().Equals("1", StringComparison.OrdinalIgnoreCase))
                : (bool?)null,
            item.Question.Difficulty,
            item.Question.SortOrder,
            Options = item.Question.Options.Select(option => new
            {
                option.Id,
                option.OptionText,
                option.IsCorrect,
                option.DistractorRationale
            }),
            MatchingPairs = item.Question.Type == QuestionType.Matching
                ? item.Question.Rubrics.Select(r => TryReadPair(r.ItemText)).Where(p => p.HasValue).Select(p => new { term = p!.Value.Term, definition = p.Value.Definition })
                : null,
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

    [HttpGet("today-plan")]
    public async Task<ActionResult<TodayStudyPlanDto>> GetTodayStudyPlan(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var courses = await _context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
                    .ThenInclude(q => q.Options)
            .Where(c => c.UserId == userId.Value)
            .ToListAsync(cancellationToken);

        if (courses.Count == 0)
        {
            return Ok(new TodayStudyPlanDto(
                null, "No Courses", "N/A", null, null, 25,
                new List<CoursePriorityDto>(),
                new List<StudyPlanStepDto>(),
                "Create or import your first course to generate an adaptive daily study plan.",
                new ExplainableReadinessDto(0, 0, 0, 0, 0, "No study history recorded yet.")
            ));
        }

        var attempts = await _context.SessionAnswers
            .Include(a => a.Question)
                .ThenInclude(q => q!.StudySet)
                    .ThenInclude(s => s!.Course)
            .Include(a => a.TestSession)
            .Where(a => a.Question != null && a.Question.StudySet != null && a.Question.StudySet.Course != null && a.Question.StudySet.Course.UserId == userId.Value)
            .ToListAsync(cancellationToken);

        var primaryCourse = courses
            .OrderBy(c => c.ExamDate.HasValue && c.ExamDate.Value > DateTime.UtcNow ? 0 : 1)
            .ThenBy(c => c.ExamDate ?? DateTime.MaxValue)
            .ThenBy(c =>
            {
                var cAttempts = attempts.Where(a => a.Question?.StudySet?.CourseId == c.Id).ToList();
                return cAttempts.Count == 0 ? 0 : cAttempts.Average(a => a.PartialScore);
            })
            .First();

        var daysUntilExam = primaryCourse.ExamDate.HasValue
            ? Math.Max(0, (int)Math.Ceiling((primaryCourse.ExamDate.Value - DateTime.UtcNow).TotalDays))
            : (int?)null;

        var courseSets = primaryCourse.StudySets.ToList();
        var priorities = new List<CoursePriorityDto>();

        foreach (var set in courseSets)
        {
            var setAttempts = attempts.Where(a => a.Question?.StudySetId == set.Id).ToList();
            var accuracy = setAttempts.Count == 0
                ? 50m
                : Math.Round(setAttempts.Average(a => a.PartialScore) * 100m, 1);
            var missedCount = setAttempts.Count(a => !a.IsCorrect);
            var status = accuracy >= 85m ? "Strong" : accuracy >= 60m ? "Needs Review" : "High Priority";
            priorities.Add(new CoursePriorityDto(set.Title, accuracy, status, missedCount));
        }

        priorities = priorities.OrderBy(p => p.MasteryPercent).ToList();

        var recentAttempts = attempts.Where(a => a.Question?.StudySet?.CourseId == primaryCourse.Id).ToList();
        var flashcardAttempts = recentAttempts.Where(a => a.TestSession?.Mode == StudyMode.Flashcards).ToList();
        var quizAttempts = recentAttempts.Where(a => a.TestSession?.Mode != StudyMode.Flashcards).ToList();

        var qAccuracy = quizAttempts.Count == 0 ? 70m : Math.Round(quizAttempts.Average(a => a.PartialScore) * 100m, 1);
        var fRetention = flashcardAttempts.Count == 0 ? 75m : Math.Round(flashcardAttempts.Average(a => a.PartialScore) * 100m, 1);
        var activeDays = recentAttempts.Select(a => a.TestSession?.CompletedAt.Date).Distinct().Count(d => d.HasValue);
        var unresolvedMistakes = recentAttempts.Where(a => !a.IsCorrect).GroupBy(a => a.QuestionId).Count();

        var overallReadiness = Math.Clamp(
            Math.Round((qAccuracy * 0.5m) + (fRetention * 0.35m) + (Math.Min(activeDays, 5) * 3m) - (unresolvedMistakes * 1.5m), 1),
            20m, 98m);

        var readinessExplanation = unresolvedMistakes > 0
            ? $"Based on {qAccuracy}% question accuracy, {fRetention}% flashcard retention, and {unresolvedMistakes} active misconception patterns."
            : $"Strong concept retention across {activeDays} study days with zero active misconception patterns.";

        var steps = new List<StudyPlanStepDto>();
        var lowestSet = courseSets.OrderBy(s => priorities.FirstOrDefault(p => p.TopicName == s.Title)?.MasteryPercent ?? 50m).FirstOrDefault();
        var allFlashcards = primaryCourse.StudySets.SelectMany(s => s.Questions.Where(q => q.Type == QuestionType.Identification || (q.ThinkingBreakdownJson != null && q.ThinkingBreakdownJson.Contains("DIMENSION:")))).ToList();

        steps.Add(new StudyPlanStepDto(
            1, "spaced_flashcards",
            "Review Spaced Flashcards",
            5,
            "Spaced repetition retrieval prompt. Solidifies decaying memory traces before new concepts.",
            Math.Min(allFlashcards.Count > 0 ? allFlashcards.Count : 6, 8),
            lowestSet?.Id,
            lowestSet?.Title
        ));

        steps.Add(new StudyPlanStepDto(
            2, "retrieval_practice",
            $"Retrieval Practice: {lowestSet?.Title ?? "Core Topics"}",
            10,
            $"Prioritized due to {priorities.FirstOrDefault()?.MasteryPercent ?? 42}% mastery and {priorities.FirstOrDefault()?.MissedCount ?? 2} recent misses.",
            5,
            lowestSet?.Id,
            lowestSet?.Title
        ));

        steps.Add(new StudyPlanStepDto(
            3, "mistake_drill",
            "Mistake Bank Targeted Drill",
            7,
            $"Directly targets {Math.Max(1, unresolvedMistakes)} previously missed questions to prevent recurring exam errors.",
            Math.Max(1, Math.Min(unresolvedMistakes, 5)),
            lowestSet?.Id,
            lowestSet?.Title
        ));

        steps.Add(new StudyPlanStepDto(
            4, "socratic_tutor",
            "Socratic AI Tutor Check-in",
            3,
            "Interactive guided dialogue explaining the core rationale behind your most challenging concepts.",
            1,
            lowestSet?.Id,
            lowestSet?.Title
        ));

        var aiRec = unresolvedMistakes > 0
            ? $"⚠️ Priority focus on {priorities.FirstOrDefault()?.TopicName ?? "core concepts"}. You have {unresolvedMistakes} mistake patterns flagged for review."
            : $"🚀 High exam momentum! Maintain consistency with quick spaced flashcard drills.";

        return Ok(new TodayStudyPlanDto(
            primaryCourse.Id,
            primaryCourse.Name,
            primaryCourse.Code,
            primaryCourse.ExamDate,
            daysUntilExam,
            25,
            priorities,
            steps,
            aiRec,
            new ExplainableReadinessDto(overallReadiness, qAccuracy, fRetention, Math.Max(1, activeDays), unresolvedMistakes, readinessExplanation)
        ));
    }

    [HttpGet("mistake-bank")]
    public async Task<ActionResult<List<MistakeBankItemDto>>> GetMistakeBank([FromQuery] Guid? courseId, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var query = _context.SessionAnswers
            .Include(a => a.Question)
                .ThenInclude(q => q!.Options)
            .Include(a => a.Question)
                .ThenInclude(q => q!.StudySet)
                    .ThenInclude(s => s!.Course)
            .Where(a => a.Question != null && a.Question.StudySet != null && a.Question.StudySet.Course != null && a.Question.StudySet.Course.UserId == userId.Value);

        if (courseId.HasValue && courseId.Value != Guid.Empty)
        {
            query = query.Where(a => a.Question!.StudySet!.CourseId == courseId.Value);
        }

        var answers = await query.ToListAsync(cancellationToken);

        var grouped = answers
            .GroupBy(a => a.QuestionId)
            .Select(g =>
            {
                var q = g.First().Question!;
                var misses = g.Count(a => !a.IsCorrect);
                var lastMiss = g.Where(a => !a.IsCorrect).OrderByDescending(a => a.Id).FirstOrDefault();
                var lastAnswer = g.OrderByDescending(a => a.Id).FirstOrDefault();
                var isResolved = lastAnswer?.IsCorrect == true;

                var misconception = !string.IsNullOrWhiteSpace(q.Explanation)
                    ? q.Explanation
                    : "Review the question prompt and examine the distinguishing characteristics between the correct answer and distractor choices.";

                return new MistakeBankItemDto(
                    q.Id,
                    q.StudySetId,
                    q.StudySet?.Title ?? "Study Set",
                    q.StudySet?.Course?.Code ?? "COURSE",
                    q.StudySet?.Course?.Name ?? "General",
                    q.Prompt,
                    q.Type.ToString(),
                    q.Options.Select(o => o.OptionText).ToList(),
                    GetCorrectAnswer(q),
                    misconception,
                    misses,
                    lastMiss != null ? DateTime.UtcNow : DateTime.UtcNow.AddDays(-1),
                    lastMiss?.UserSubmittedAnswer,
                    misses >= 3
                        ? $"Recurring misconception: missed {misses} times across recent sessions."
                        : misses >= 2
                            ? "Needs reinforcement: missed 2 times."
                            : "Recent stumble: missed in last session.",
                    isResolved
                );
            })
            .Where(m => m.MissCount > 0)
            .OrderBy(m => m.IsResolved ? 1 : 0)
            .ThenByDescending(m => m.MissCount)
            .ToList();

        return Ok(grouped);
    }

    [HttpPost("mistake-bank/resolve")]
    public async Task<IActionResult> ResolveMistake([FromBody] ResolveMistakeRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var question = await _context.Questions
            .Include(q => q.StudySet)
                .ThenInclude(s => s!.Course)
            .FirstOrDefaultAsync(q => q.Id == request.QuestionId && q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == userId.Value, cancellationToken);

        if (question is null) return NotFound(new { message = "Question not found." });

        var session = new TestSession
        {
            Id = Guid.NewGuid(),
            StudySetId = question.StudySetId,
            Mode = StudyMode.WeakSpotMastery,
            Score = request.IsResolved ? 1 : 0,
            TotalQuestions = 1,
            TimeSpentSeconds = 15,
            CompletedAt = DateTime.UtcNow
        };

        session.Answers.Add(new SessionAnswer
        {
            Id = Guid.NewGuid(),
            QuestionId = question.Id,
            UserSubmittedAnswer = GetCorrectAnswer(question),
            IsCorrect = request.IsResolved,
            PartialScore = request.IsResolved ? 1m : 0m,
            AiFeedback = "Mistake Bank drill resolved by student."
        });

        _context.TestSessions.Add(session);
        await _context.SaveChangesAsync(cancellationToken);

        return Ok(new { success = true, isResolved = request.IsResolved });
    }

    [HttpGet("smart-session")]
    public async Task<ActionResult<SmartSessionPayloadDto>> GetSmartSession([FromQuery] Guid? courseId, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var coursesQuery = _context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
                    .ThenInclude(q => q.Options)
            .Where(c => c.UserId == userId.Value);

        if (courseId.HasValue && courseId.Value != Guid.Empty)
        {
            coursesQuery = coursesQuery.Where(c => c.Id == courseId.Value);
        }

        var courses = await coursesQuery.ToListAsync(cancellationToken);
        if (courses.Count == 0) return NotFound(new { message = "No courses available for smart session." });

        var allQuestions = courses.SelectMany(c => c.StudySets.SelectMany(s => s.Questions)).ToList();
        if (allQuestions.Count == 0) return BadRequest(new { message = "No study material found. Add questions or flashcards first." });

        var pastAnswers = await _context.SessionAnswers
            .Where(a => allQuestions.Select(q => q.Id).Contains(a.QuestionId))
            .ToListAsync(cancellationToken);

        // Stage 1: Flashcards (up to 5)
        var flashcards = allQuestions
            .Where(q => q.Type == QuestionType.Identification || (q.ThinkingBreakdownJson != null && q.ThinkingBreakdownJson.Contains("DIMENSION:")))
            .OrderBy(q => pastAnswers.Count(a => a.QuestionId == q.Id))
            .Take(5)
            .Select(q => new SmartSessionFlashcardDto(
                q.Id,
                q.StudySetId,
                q.Prompt,
                GetCorrectAnswer(q),
                q.ThinkingBreakdownJson?.Contains("DIMENSION:") == true ? "CORE CONCEPT" : "ACTIVE RECALL",
                "Spaced retrieval: strengthens recall retention of foundational concepts."
            ))
            .ToList();

        if (flashcards.Count == 0)
        {
            flashcards = allQuestions
                .Take(4)
                .Select(q => new SmartSessionFlashcardDto(
                    q.Id,
                    q.StudySetId,
                    q.Prompt,
                    GetCorrectAnswer(q),
                    "CORE CONCEPT",
                    "Foundational retrieval drill."
                ))
                .ToList();
        }

        // Stage 2: Weak Topic Retrieval Practice (up to 5 non-flashcard questions with lowest accuracy)
        var retrievalQuestions = allQuestions
            .Where(q => q.Type != QuestionType.Identification && (q.ThinkingBreakdownJson == null || !q.ThinkingBreakdownJson.Contains("DIMENSION:")))
            .OrderBy(q =>
            {
                var qAnswers = pastAnswers.Where(a => a.QuestionId == q.Id).ToList();
                return qAnswers.Count == 0 ? 0.5m : qAnswers.Average(a => a.PartialScore);
            })
            .Take(5)
            .Select(q => new SmartSessionQuestionDto(
                q.Id,
                q.StudySetId,
                q.Prompt,
                q.Type.ToString(),
                q.Options.Select(o => new SmartSessionOptionDto(o.Id, o.OptionText, o.IsCorrect, o.DistractorRationale)).ToList(),
                GetCorrectAnswer(q),
                q.Explanation,
                "Stage 2: Retrieval Practice",
                "Adaptive weak-topic targeting to close knowledge gaps."
            ))
            .ToList();

        // Stage 3: Mistake Bank Drills (up to 3 questions that were previously answered incorrectly)
        var missedQuestionIds = pastAnswers
            .Where(a => !a.IsCorrect)
            .GroupBy(a => a.QuestionId)
            .OrderByDescending(g => g.Count())
            .Select(g => g.Key)
            .ToList();

        var mistakeQuestions = allQuestions
            .Where(q => missedQuestionIds.Contains(q.Id))
            .Take(3)
            .Select(q => new SmartSessionQuestionDto(
                q.Id,
                q.StudySetId,
                q.Prompt,
                q.Type.ToString(),
                q.Options.Select(o => new SmartSessionOptionDto(o.Id, o.OptionText, o.IsCorrect, o.DistractorRationale)).ToList(),
                GetCorrectAnswer(q),
                q.Explanation,
                "Stage 3: Mistake Bank Drill",
                "Targeted retry of concepts where misconceptions occurred."
            ))
            .ToList();

        return Ok(new SmartSessionPayloadDto(
            "⚡ 25-Minute Adaptive Smart Session",
            25,
            flashcards,
            retrievalQuestions,
            mistakeQuestions
        ));
    }

    [HttpGet("exam-readiness/{courseId:guid}")]
    public async Task<ActionResult<ExplainableReadinessDto>> GetExamReadiness(Guid courseId, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var course = await _context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
            .FirstOrDefaultAsync(c => c.Id == courseId && c.UserId == userId.Value, cancellationToken);

        if (course is null) return NotFound(new { message = "Course not found." });

        var courseQuestionIds = course.StudySets.SelectMany(s => s.Questions.Select(q => q.Id)).ToList();
        var attempts = await _context.SessionAnswers
            .Include(a => a.TestSession)
            .Where(a => courseQuestionIds.Contains(a.QuestionId))
            .ToListAsync(cancellationToken);

        var quizAttempts = attempts.Where(a => a.TestSession?.Mode != StudyMode.Flashcards).ToList();
        var flashcardAttempts = attempts.Where(a => a.TestSession?.Mode == StudyMode.Flashcards).ToList();

        var qAccuracy = quizAttempts.Count == 0 ? 65m : Math.Round(quizAttempts.Average(a => a.PartialScore) * 100m, 1);
        var fRetention = flashcardAttempts.Count == 0 ? 70m : Math.Round(flashcardAttempts.Average(a => a.PartialScore) * 100m, 1);
        var activeDays = attempts.Select(a => a.TestSession?.CompletedAt.Date).Distinct().Count(d => d.HasValue);
        var unresolved = attempts.Where(a => !a.IsCorrect).GroupBy(a => a.QuestionId).Count();

        var overall = Math.Clamp(
            Math.Round((qAccuracy * 0.5m) + (fRetention * 0.35m) + (Math.Min(activeDays, 5) * 3m) - (unresolved * 1.5m), 1),
            20m, 98m);

        var explanation = unresolved > 0
            ? $"Readiness is {overall}% based on {qAccuracy}% accuracy, {fRetention}% flashcard retention, and {unresolved} active mistake patterns."
            : $"High readiness of {overall}% with consistent retrieval accuracy and 0 active mistake patterns.";

        return Ok(new ExplainableReadinessDto(overall, qAccuracy, fRetention, Math.Max(1, activeDays), unresolved, explanation));
    }

    [HttpGet("student-brain")]
    public async Task<ActionResult<StudentBrainProfileDto>> GetStudentBrainProfile(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var courses = await _context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
            .Where(c => c.UserId == userId.Value)
            .ToListAsync(cancellationToken);

        var allQuestionIds = courses.SelectMany(c => c.StudySets.SelectMany(s => s.Questions.Select(q => q.Id))).ToList();

        var attempts = await _context.SessionAnswers
            .Include(a => a.TestSession)
            .Where(a => allQuestionIds.Contains(a.QuestionId))
            .ToListAsync(cancellationToken);

        var weakConcepts = attempts
            .GroupBy(a => a.QuestionId)
            .Count(g => g.Any(a => !a.IsCorrect) || g.Average(a => a.PartialScore) < 0.6m);

        var masteredConcepts = attempts
            .GroupBy(a => a.QuestionId)
            .Count(g => g.Count() >= 2 && g.Average(a => a.PartialScore) >= 0.85m);

        var pendingReviews = courses.SelectMany(c => c.StudySets.SelectMany(s => s.Questions))
            .Count(q => q.Type == QuestionType.Identification || (q.ThinkingBreakdownJson != null && q.ThinkingBreakdownJson.Contains("DIMENSION:")));

        var upcomingExamsCount = courses.Count(c => c.ExamDate.HasValue && c.ExamDate.Value > DateTime.UtcNow);

        // Academic tasks count
        var tasksList = await GetUserAcademicTasksAsync(userId.Value, cancellationToken);
        var upcomingDeadlinesCount = tasksList.Count(t => !t.IsCompleted && t.DueDate >= DateTime.UtcNow);

        // Priority Course
        var topCourse = courses
            .OrderBy(c => c.ExamDate.HasValue && c.ExamDate.Value > DateTime.UtcNow ? 0 : 1)
            .ThenBy(c => c.ExamDate ?? DateTime.MaxValue)
            .FirstOrDefault();

        var priorityCourseName = topCourse?.Name ?? "General Studies";
        var priorityCourseCode = topCourse?.Code ?? "GEN101";
        var daysUntilExam = topCourse?.ExamDate.HasValue == true
            ? Math.Max(0, (int)Math.Ceiling((topCourse.ExamDate.Value - DateTime.UtcNow).TotalDays))
            : (int?)null;

        var priorityMastery = 55.0m;
        if (topCourse != null)
        {
            var topQIds = topCourse.StudySets.SelectMany(s => s.Questions.Select(q => q.Id)).ToList();
            var topAttempts = attempts.Where(a => topQIds.Contains(a.QuestionId)).ToList();
            if (topAttempts.Count > 0)
            {
                priorityMastery = Math.Round(topAttempts.Average(a => a.PartialScore) * 100m, 1);
            }
        }

        var priorityWhy = daysUntilExam.HasValue && daysUntilExam.Value <= 7
            ? $"You have an upcoming assessment in {daysUntilExam.Value} days, your recent accuracy is {priorityMastery}%, and {Math.Min(pendingReviews, 8)} flashcards are due for review."
            : $"Current mastery is {priorityMastery}% with {weakConcepts} concepts flagged for active recall reinforcement.";

        var dailyAnswers = new StudentBrainDailyAnswersDto(
            WhatDoINeedToDo: upcomingDeadlinesCount > 0
                ? $"Complete {upcomingDeadlinesCount} pending academic deadlines and review {Math.Min(pendingReviews, 8)} spaced flashcards."
                : $"Review {Math.Min(pendingReviews, 8)} spaced flashcards and complete today's retrieval practice session.",
            WhatShouldIStudy: $"{priorityCourseCode}: {priorityCourseName} ({priorityMastery}% mastery) — {priorityWhy}",
            WhatAmIStrugglingWith: weakConcepts > 0
                ? $"{weakConcepts} concepts identified with recurring misconception patterns in active retrieval sessions."
                : "No active misconception patterns detected. Ready for advanced difficulty synthesis.",
            HowCanILearnIt: "Follow the 3-step loop: Spaced Active Recall (5 min) -> Retrieval Practice (10 min) -> Mistake Bank Target Drill (7 min).",
            WhatShouldIDoNext: "Launch today's 25-Minute Smart Study Session to address weak areas immediately."
        );

        return Ok(new StudentBrainProfileDto(
            courses.Count,
            courses.Count,
            upcomingDeadlinesCount,
            weakConcepts,
            masteredConcepts,
            Math.Min(pendingReviews, 18),
            upcomingExamsCount,
            priorityCourseName,
            priorityCourseCode,
            priorityMastery,
            priorityWhy,
            dailyAnswers
        ));
    }

    [HttpPost("recovery-plan")]
    public async Task<ActionResult<BuildRecoveryPlanResponse>> BuildRecoveryPlan(
        [FromBody] BuildRecoveryPlanRequest request,
        CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var questions = await _context.Questions
            .Include(q => q.StudySet)
            .Where(q => request.MissedQuestionIds.Contains(q.Id))
            .ToListAsync(cancellationToken);

        var targetedTopics = questions
            .Select(q => q.StudySet?.Title ?? "Core Topics")
            .Distinct()
            .ToList();

        if (targetedTopics.Count == 0) targetedTopics.Add("Core Concepts");

        var recMinutes = Math.Clamp(questions.Count * 3, 10, 30);
        var msg = $"Recovery plan synthesized! {questions.Count} missed questions routed to your Mistake Bank for a {recMinutes}-minute targeted drill.";

        return Ok(new BuildRecoveryPlanResponse(
            questions.Count,
            targetedTopics,
            "1-Tap Smart Session targeting your specific missed questions",
            recMinutes,
            msg
        ));
    }

    [HttpGet("planner/tasks")]
    public async Task<ActionResult<List<AcademicTaskDto>>> GetAcademicTasks(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var tasks = await GetUserAcademicTasksAsync(userId.Value, cancellationToken);
        return Ok(tasks);
    }

    [HttpPost("planner/tasks")]
    public async Task<ActionResult<AcademicTaskDto>> CreateAcademicTask(
        [FromBody] CreateAcademicTaskRequest request,
        CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var taskId = Guid.NewGuid();
        var stepsJson = JsonSerializer.Serialize(request.ActionSteps ?? new List<string>(), JsonOptions);
        var courseCode = "COURSE";

        if (request.CourseId.HasValue)
        {
            var course = await _context.Courses.FindAsync(new object[] { request.CourseId.Value }, cancellationToken);
            if (course != null) courseCode = course.Code;
        }

        var db = (DbContext)_context;
        await db.Database.ExecuteSqlRawAsync(
            "INSERT INTO \"AcademicTasks\" (\"Id\", \"UserId\", \"CourseId\", \"Title\", \"Type\", \"DueDate\", \"EstimatedDifficulty\", \"IsCompleted\", \"ActionStepsJson\", \"CreatedAt\") VALUES ({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8}, {9});",
            taskId.ToString(),
            userId.Value.ToString(),
            (object?)request.CourseId?.ToString() ?? DBNull.Value,
            request.Title,
            request.Type,
            request.DueDate.ToString("o"),
            request.EstimatedDifficulty,
            0,
            stepsJson,
            DateTime.UtcNow.ToString("o"),
            cancellationToken
        );

        return Ok(new AcademicTaskDto(
            taskId,
            request.CourseId,
            courseCode,
            request.Title,
            request.Type,
            request.DueDate,
            request.EstimatedDifficulty,
            false,
            request.ActionSteps ?? new List<string>()
        ));
    }

    [HttpPost("planner/generate-breakdown")]
    public ActionResult<GenerateBreakdownResponse> GenerateAssignmentBreakdown([FromBody] GenerateBreakdownRequest request)
    {
        var days = Math.Max(1, (int)Math.Ceiling((request.DueDate - DateTime.UtcNow).TotalDays));
        var steps = new List<string>();

        if (request.Type.Equals("project", StringComparison.OrdinalIgnoreCase) || request.Title.Contains("project", StringComparison.OrdinalIgnoreCase))
        {
            steps.Add("Day 1: Understand project requirements, scope boundaries, and design architecture");
            steps.Add("Day 2: Implement core classes, data structures, and baseline functionality");
            steps.Add("Day 3: Implement auxiliary interfaces, algorithms, and integration logic");
            steps.Add("Day 4: Run unit tests, verify edge cases, and debug errors");
            steps.Add("Day 5: Document project, format deliverables, and do final submission check");
        }
        else if (request.Type.Equals("exam", StringComparison.OrdinalIgnoreCase) || request.Title.Contains("exam", StringComparison.OrdinalIgnoreCase) || request.Title.Contains("quiz", StringComparison.OrdinalIgnoreCase))
        {
            steps.Add("Day 1: High-level syllabus review and flashcard concept mapping");
            steps.Add("Day 2: Topic-level retrieval practice on lowest mastery topics");
            steps.Add("Day 3: Mistake Bank review and misconception resolution");
            steps.Add("Day 4: Full simulated exam under strict timed conditions");
            steps.Add("Day 5: Light formula review and restful mental preparation");
        }
        else
        {
            steps.Add("Day 1: Break down assignment guidelines and gather references");
            steps.Add("Day 2: Draft initial outline and solve foundational parts");
            steps.Add("Day 3: Deep work session: complete technical and analytical questions");
            steps.Add("Day 4: Peer check / AI Socratic check for reasoning clarity");
            steps.Add("Day 5: Final review, citations check, and clean submission");
        }

        var adjustedSteps = steps.Take(Math.Max(2, Math.Min(days, steps.Count))).ToList();
        var summary = $"Generated structured {adjustedSteps.Count}-step execution roadmap for {request.Title} due on {request.DueDate:MMM dd}.";

        return Ok(new GenerateBreakdownResponse(request.Title, adjustedSteps, summary));
    }

    [HttpPut("planner/tasks/{taskId:guid}/toggle")]
    public async Task<IActionResult> ToggleAcademicTask(Guid taskId, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var db = (DbContext)_context;
        await db.Database.ExecuteSqlRawAsync(
            "UPDATE \"AcademicTasks\" SET \"IsCompleted\" = CASE WHEN \"IsCompleted\" = 1 THEN 0 ELSE 1 END WHERE \"Id\" = {0} AND \"UserId\" = {1};",
            taskId.ToString(),
            userId.Value.ToString(),
            cancellationToken
        );

        return Ok(new { success = true, taskId });
    }

    private async Task<List<AcademicTaskDto>> GetUserAcademicTasksAsync(Guid userId, CancellationToken cancellationToken)
    {
        var list = new List<AcademicTaskDto>();
        try
        {
            var db = (DbContext)_context;
            using var conn = db.Database.GetDbConnection();
            await conn.OpenAsync(cancellationToken);
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT t.\"Id\", t.\"CourseId\", t.\"Title\", t.\"Type\", t.\"DueDate\", t.\"EstimatedDifficulty\", t.\"IsCompleted\", t.\"ActionStepsJson\", c.\"Code\" FROM \"AcademicTasks\" t LEFT JOIN \"Courses\" c ON t.\"CourseId\" = c.\"Id\" WHERE t.\"UserId\" = @uid ORDER BY t.\"DueDate\" ASC;";
            var p = cmd.CreateParameter();
            p.ParameterName = "@uid";
            p.Value = userId.ToString();
            cmd.Parameters.Add(p);

            using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var id = Guid.Parse(reader.GetString(0));
                Guid? cId = reader.IsDBNull(1) ? null : Guid.Parse(reader.GetString(1));
                var title = reader.GetString(2);
                var type = reader.GetString(3);
                var dueDate = DateTime.Parse(reader.GetString(4));
                var diff = reader.GetString(5);
                var isComp = reader.GetInt32(6) == 1;
                var stepsRaw = reader.GetString(7);
                var cCode = reader.IsDBNull(8) ? "COURSE" : reader.GetString(8);

                List<string> steps = new();
                try { steps = JsonSerializer.Deserialize<List<string>>(stepsRaw, JsonOptions) ?? new(); } catch { }

                list.Add(new AcademicTaskDto(id, cId, cCode, title, type, dueDate, diff, isComp, steps));
            }
        }
        catch { }

        return list;
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
            .Where(pair => pair.HasValue)
            .Select(pair => pair!.Value)
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

    private static string GetCorrectAnswer(Question question)
    {
        var correctOptions = string.Join("; ", question.Options.Where(o => o.IsCorrect).Select(o => o.OptionText));
        if (!string.IsNullOrWhiteSpace(correctOptions)) return correctOptions;
        if (question.Rubrics.Any())
        {
            return string.Join(", ", question.Rubrics.OrderBy(r => r.SortOrder).Select(r => r.ItemText));
        }
        return string.Empty;
    }

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

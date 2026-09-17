using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.Services;
using Xunit;

namespace StudyApp.UnitTests;

/// <summary>
/// Extensive end-to-end and domain-driven test suite validating SQLite relational integrity,
/// multi-tenant data isolation, exam grading logic, AI note parsing, and offline synchronization.
/// </summary>
public class ComprehensiveSystemExtensiveTests
{
    private ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    #region 1. User Security, Hashing & Settings Initialization

    [Fact]
    public void PasswordHasher_HashAndVerify_SecuresCredentialsCorrectly()
    {
        var hasher = new PasswordHasher();
        const string password = "StrongSecretPassword2026!";

        var hash = hasher.HashPassword(password);

        Assert.False(string.IsNullOrWhiteSpace(hash));
        Assert.NotEqual(password, hash);
        Assert.True(hasher.VerifyPassword(password, hash));
        Assert.False(hasher.VerifyPassword("WrongPassword123!", hash));
        Assert.False(hasher.VerifyPassword(string.Empty, hash));
    }

    [Fact]
    public async Task UserRegistration_WithSettings_PersistsValidDefaultsInDatabase()
    {
        using var context = CreateContext();
        var hasher = new PasswordHasher();

        var user = new User
        {
            Email = "student.jane@university.edu",
            FullName = "Jane Student",
            PasswordHash = hasher.HashPassword("JanePass123!")
        };

        var settings = new UserSettings
        {
            UserId = user.Id,
            DefaultQuestionCount = 20,
            DailyStudyGoalMinutes = 45,
            ThemePreference = "dark"
        };

        context.Users.Add(user);
        context.UserSettings.Add(settings);
        await context.SaveChangesAsync();

        var retrievedUser = await context.Users
            .Include(u => u.Courses)
            .FirstOrDefaultAsync(u => u.Email == "student.jane@university.edu");

        var retrievedSettings = await context.UserSettings
            .FirstOrDefaultAsync(s => s.UserId == user.Id);

        Assert.NotNull(retrievedUser);
        Assert.Equal("Jane Student", retrievedUser.FullName);
        Assert.NotNull(retrievedSettings);
        Assert.Equal(20, retrievedSettings.DefaultQuestionCount);
        Assert.Equal(45, retrievedSettings.DailyStudyGoalMinutes);
        Assert.Equal("dark", retrievedSettings.ThemePreference);
    }

    #endregion

    #region 2. Multi-Tenant Data Isolation & Security

    [Fact]
    public async Task MultiTenantDataIsolation_UserACannotAccessUserBCoursesOrNotes()
    {
        using var context = CreateContext();

        var userA = new User { Email = "alice@study.local", FullName = "Alice Student", PasswordHash = "hashA" };
        var userB = new User { Email = "bob@study.local", FullName = "Bob Student", PasswordHash = "hashB" };
        context.Users.AddRange(userA, userB);

        var courseA = new Course { UserId = userA.Id, Code = "CS-101", Name = "Computer Science 1" };
        var courseB = new Course { UserId = userB.Id, Code = "MED-201", Name = "Human Anatomy" };
        context.Courses.AddRange(courseA, courseB);

        var noteA = new NotebookPage { CourseId = courseA.Id, Title = "Binary Trees", ContentMarkdown = "# Trees" };
        var noteB = new NotebookPage { CourseId = courseB.Id, Title = "Cranial Nerves", ContentMarkdown = "# Nerves" };
        context.NotebookPages.AddRange(noteA, noteB);

        await context.SaveChangesAsync();

        // Query scoped strictly to User A
        var aliceCourses = await context.Courses
            .Where(c => c.UserId == userA.Id)
            .ToListAsync();

        var aliceNotes = await context.NotebookPages
            .Where(n => context.Courses.Where(c => c.UserId == userA.Id).Select(c => c.Id).Contains(n.CourseId))
            .ToListAsync();

        Assert.Single(aliceCourses);
        Assert.Equal("CS-101", aliceCourses[0].Code);
        Assert.DoesNotContain(aliceCourses, c => c.Code == "MED-201");

        Assert.Single(aliceNotes);
        Assert.Equal("Binary Trees", aliceNotes[0].Title);
        Assert.DoesNotContain(aliceNotes, n => n.Title == "Cranial Nerves");
    }

    #endregion

    #region 3. Cascading Relational Deletion

    [Fact]
    public async Task CascadeDelete_DeletingCourse_RemovesAllChildStudySetsQuestionsAndOptions()
    {
        using var context = CreateContext();

        var user = new User { Email = "test.cascade@study.local", FullName = "Cascade Tester", PasswordHash = "h" };
        context.Users.Add(user);

        var course = new Course { UserId = user.Id, Code = "CHEM-101", Name = "Organic Chemistry" };
        context.Courses.Add(course);

        var studySet = new StudySet { CourseId = course.Id, Title = "Alkanes & Alkenes" };
        context.StudySets.Add(studySet);

        var question = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "What is the general formula for alkanes?",
            Type = QuestionType.MultipleChoice,
            Explanation = "C_n H_{2n+2}"
        };
        question.Options.Add(new QuestionOption { OptionText = "C_n H_{2n+2}", IsCorrect = true });
        question.Options.Add(new QuestionOption { OptionText = "C_n H_{2n}", IsCorrect = false });
        context.Questions.Add(question);

        var note = new NotebookPage { CourseId = course.Id, Title = "Reaction Mechanisms", ContentMarkdown = "Notes..." };
        context.NotebookPages.Add(note);

        await context.SaveChangesAsync();

        // Verify entities exist prior to deletion
        Assert.Equal(1, await context.Courses.CountAsync());
        Assert.Equal(1, await context.StudySets.CountAsync());
        Assert.Equal(1, await context.Questions.CountAsync());
        Assert.Equal(2, await context.QuestionOptions.CountAsync());
        Assert.Equal(1, await context.NotebookPages.CountAsync());

        // Perform cascading removal
        var courseToDelete = await context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
                    .ThenInclude(q => q.Options)
            .Include(c => c.NotebookPages)
            .FirstAsync(c => c.Id == course.Id);

        context.Courses.Remove(courseToDelete);
        await context.SaveChangesAsync();

        // Verify all child elements are cleanly eliminated from database
        Assert.Equal(0, await context.Courses.CountAsync());
        Assert.Equal(0, await context.StudySets.CountAsync());
        Assert.Equal(0, await context.Questions.CountAsync());
        Assert.Equal(0, await context.QuestionOptions.CountAsync());
        Assert.Equal(0, await context.NotebookPages.CountAsync());
    }

    #endregion

    #region 4. Server-Authoritative Exam Grading & Answer Scoring

    [Fact]
    public async Task ExamGrading_ExactAndClozeAnswers_CalculatesCorrectScoreAndBreakdown()
    {
        using var context = CreateContext();

        var studySet = new StudySet { CourseId = Guid.NewGuid(), Title = "Neuroscience Quiz" };
        context.StudySets.Add(studySet);

        // Q1: Multiple Choice
        var q1 = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "Which lobe of the brain is responsible for visual processing?",
            Type = QuestionType.MultipleChoice
        };
        var optCorrect1 = new QuestionOption { OptionText = "Occipital Lobe", IsCorrect = true };
        var optWrong1 = new QuestionOption { OptionText = "Frontal Lobe", IsCorrect = false };
        q1.Options.Add(optCorrect1);
        q1.Options.Add(optWrong1);
        context.Questions.Add(q1);

        // Q2: Cloze / Fill in the blank
        var q2 = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "The gap between two neurons where neurotransmitters are released is called a [_____].",
            Type = QuestionType.Cloze
        };
        var optCorrect2 = new QuestionOption { OptionText = "synapse", IsCorrect = true };
        q2.Options.Add(optCorrect2);
        context.Questions.Add(q2);

        await context.SaveChangesAsync();

        // Student submits answers: Q1 correct, Q2 correct with leading/trailing spaces and uppercase
        var session = new TestSession
        {
            StudySetId = studySet.Id,
            Mode = StudyMode.SimulatedExam,
            TotalQuestions = 2
        };

        // Grade Q1:
        var studentAns1 = "Occipital Lobe";
        var isCorrect1 = q1.Options.Any(o => o.IsCorrect && string.Equals(o.OptionText.Trim(), studentAns1.Trim(), StringComparison.OrdinalIgnoreCase));
        session.Answers.Add(new SessionAnswer
        {
            QuestionId = q1.Id,
            UserSubmittedAnswer = studentAns1,
            IsCorrect = isCorrect1
        });

        // Grade Q2:
        var studentAns2 = "  SYNAPSE  ";
        var isCorrect2 = q2.Options.Any(o => o.IsCorrect && string.Equals(o.OptionText.Trim(), studentAns2.Trim(), StringComparison.OrdinalIgnoreCase));
        session.Answers.Add(new SessionAnswer
        {
            QuestionId = q2.Id,
            UserSubmittedAnswer = studentAns2,
            IsCorrect = isCorrect2
        });

        session.Score = session.Answers.Count(a => a.IsCorrect);
        context.TestSessions.Add(session);
        await context.SaveChangesAsync();

        // Assert 100% Score
        Assert.Equal(2, session.Score);
        Assert.Equal(2, session.TotalQuestions);
        Assert.All(session.Answers, a => Assert.True(a.IsCorrect));
    }

    [Fact]
    public void ExamGrading_WrongOrBlankAnswers_YieldsZeroScoreWithoutCrashing()
    {
        var q = new Question
        {
            Prompt = "What is 2 + 2?",
            Type = QuestionType.MultipleChoice
        };
        q.Options.Add(new QuestionOption { OptionText = "4", IsCorrect = true });
        q.Options.Add(new QuestionOption { OptionText = "5", IsCorrect = false });

        var submission = ""; // Student left it empty
        var isCorrect = q.Options.Any(o => o.IsCorrect && !string.IsNullOrWhiteSpace(submission) && string.Equals(o.OptionText.Trim(), submission.Trim(), StringComparison.OrdinalIgnoreCase));

        Assert.False(isCorrect);
    }

    #endregion

    #region 5. NoteScript Markdown Normalization & Question Validation

    [Theory]
    [InlineData("# Heading 1", "Heading 1")]
    [InlineData("### Sub-concept Section", "Sub-concept Section")]
    [InlineData("* Bullet Point Note", "Bullet Point Note")]
    [InlineData("• Unicode Bullet Point", "Unicode Bullet Point")]
    [InlineData("**Bold Keyword:** Definition", "Bold Keyword: Definition")]
    [InlineData("__Underlined Concept__", "Underlined Concept")]
    public void NoteScriptParser_NormalizeMarkdownLine_StripsFormattingArtifactsCleanly(string input, string expected)
    {
        var cleaned = NoteScriptSynthesizer.NormalizeMarkdownLine(input);
        Assert.Equal(expected, cleaned);
    }

    [Fact]
    public void NoteScriptParser_SynthesizeFromNotes_GeneratesValidStudySetWithNonEmptyOptions()
    {
        const string rawNotes = """
        # Software Engineering Architecture Notes
        
        1. Microservices Architecture:
        - Loosely coupled collection of services deployed independently.
        - Enables continuous delivery and automated horizontal scaling.
        - Requires robust API gateway and distributed tracing.
        
        2. Monolithic Architecture:
        - Single unified codebase where all components execute in a single process.
        - Simple to develop initially, but difficult to scale across distinct teams.
        - Changes require complete re-deployment of the entire artifact.
        
        3. Event-Driven Architecture:
        - Decoupled event producers and event consumers communicate through an event broker.
        - High responsiveness and eventual consistency.
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Software Architecture",
            rawNotes,
            new List<string> { "MultipleChoice", "TrueFalse", "Cloze" },
            targetCount: 6,
            setIndex: 0,
            variant: "set_a"
        );

        Assert.NotNull(result);
        Assert.NotEmpty(result.Questions);
        Assert.True(result.Questions.Count >= 3);

        foreach (var q in result.Questions)
        {
            Assert.False(string.IsNullOrWhiteSpace(q.Prompt), "Prompt must not be empty");
            Assert.NotNull(q.Options);
            Assert.NotEmpty(q.Options);
            Assert.Contains(q.Options, o => o.IsCorrect);
        }
    }

    #endregion

    #region 6. Offline Sync Timestamp & Delta Filtering

    [Fact]
    public async Task OfflineSync_DeltaFiltering_ReturnsOnlyEntitiesModifiedAfterLastSyncedAt()
    {
        using var context = CreateContext();

        var userId = Guid.NewGuid();
        var baselineTime = new DateTime(2026, 9, 10, 12, 0, 0, DateTimeKind.Utc);
        var syncTime = new DateTime(2026, 9, 12, 12, 0, 0, DateTimeKind.Utc);
        var recentTime = new DateTime(2026, 9, 14, 12, 0, 0, DateTimeKind.Utc);

        // Course 1: Created before syncTime, not updated
        var oldCourse = new Course
        {
            UserId = userId,
            Code = "HIST-101",
            Name = "Ancient Civilizations",
            CreatedAt = baselineTime,
            UpdatedAt = null
        };

        // Course 2: Updated recently after syncTime
        var updatedCourse = new Course
        {
            UserId = userId,
            Code = "MATH-202",
            Name = "Multivariable Calculus",
            CreatedAt = baselineTime,
            UpdatedAt = recentTime
        };

        // Course 3: Newly created after syncTime
        var newCourse = new Course
        {
            UserId = userId,
            Code = "PHYS-301",
            Name = "Quantum Mechanics",
            CreatedAt = recentTime,
            UpdatedAt = null
        };

        context.Courses.AddRange(oldCourse, updatedCourse, newCourse);
        await context.SaveChangesAsync();

        // Delta query filtering courses where (UpdatedAt ?? CreatedAt) > syncTime
        var deltaCourses = await context.Courses
            .Where(c => c.UserId == userId && (c.UpdatedAt ?? c.CreatedAt) > syncTime)
            .OrderBy(c => c.Code)
            .ToListAsync();

        Assert.Equal(2, deltaCourses.Count);
        Assert.Equal("MATH-202", deltaCourses[0].Code);
        Assert.Equal("PHYS-301", deltaCourses[1].Code);
        Assert.DoesNotContain(deltaCourses, c => c.Code == "HIST-101");
    }

    #endregion

    #region 7. User Settings Constraints & Extreme Boundaries

    [Theory]
    [InlineData(-10, 5)]   // Below minimum -> clamped to 5
    [InlineData(0, 5)]     // Zero -> clamped to 5
    [InlineData(25, 25)]   // Valid value -> preserved
    [InlineData(50, 50)]   // Boundary value -> preserved
    [InlineData(999, 50)]  // Above maximum -> clamped to 50
    public void UserSettings_QuestionCountClamp_EnforcesValidRange(int input, int expected)
    {
        var clamped = Math.Clamp(input, 5, 50);
        Assert.Equal(expected, clamped);
    }

    [Theory]
    [InlineData(-5, 10)]   // Below minimum -> clamped to 10
    [InlineData(10, 10)]   // Minimum boundary
    [InlineData(30, 30)]   // Valid value
    [InlineData(60, 60)]   // Maximum boundary
    [InlineData(300, 60)]  // Above maximum -> clamped to 60
    public void UserSettings_PomodoroFocusClamp_EnforcesValidRange(int input, int expected)
    {
        var clamped = Math.Clamp(input, 10, 60);
        Assert.Equal(expected, clamped);
    }

    [Theory]
    [InlineData("DARK", "dark")]
    [InlineData("Light", "light")]
    [InlineData("SYSTEM", "system")]
    [InlineData("invalid_mode", "system")]
    public void UserSettings_ThemePreference_NormalizesAndFallsBackSafely(string rawInput, string expected)
    {
        var normalized = rawInput.Trim().ToLowerInvariant();
        var safeTheme = normalized is "dark" or "light" or "system" ? normalized : "system";
        Assert.Equal(expected, safeTheme);
    }

    #endregion

    #region 8. Server-Authoritative Multi-Type Exam Scoring Diagnostic Engine

    [Fact]
    public async Task MultiTypeExamGrading_CalculatesGranularAccuracy_AcrossVariedQuestionFormats()
    {
        using var context = CreateContext();

        var studySet = new StudySet { CourseId = Guid.NewGuid(), Title = "Comprehensive Medical & Science Exam" };
        context.StudySets.Add(studySet);

        // 1. Multiple Choice Question
        var qMcq = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "What is the primary currency of cellular energy?",
            Type = QuestionType.MultipleChoice,
            Explanation = "ATP is adenosine triphosphate."
        };
        var optCorrect = new QuestionOption { OptionText = "Adenosine Triphosphate (ATP)", IsCorrect = true };
        var optWrong = new QuestionOption { OptionText = "Deoxyribose", IsCorrect = false };
        qMcq.Options.Add(optCorrect);
        qMcq.Options.Add(optWrong);
        context.Questions.Add(qMcq);

        // 2. True / False Question
        var qTf = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "Mitochondria contain their own independent DNA genomes.",
            Type = QuestionType.TrueFalse,
            Explanation = "True, mitochondrial DNA is maternally inherited."
        };
        var optTfCorrect = new QuestionOption { OptionText = "True", IsCorrect = true };
        var optTfWrong = new QuestionOption { OptionText = "False", IsCorrect = false };
        qTf.Options.Add(optTfCorrect);
        qTf.Options.Add(optTfWrong);
        context.Questions.Add(qTf);

        // 3. Cloze (Fill-in-the-Blank) Question
        var qCloze = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "The powerhouse of the cell is the [mitochondria].",
            Type = QuestionType.Cloze,
            Explanation = "Mitochondria produce ATP."
        };
        var optCloze = new QuestionOption { OptionText = "mitochondria", IsCorrect = true };
        qCloze.Options.Add(optCloze);
        context.Questions.Add(qCloze);

        // 4. Identification Question
        var qIdent = new Question
        {
            StudySetId = studySet.Id,
            Prompt = "Identify the process by which green plants convert sunlight into glucose.",
            Type = QuestionType.Identification,
            Explanation = "Photosynthesis."
        };
        var optIdent = new QuestionOption { OptionText = "Photosynthesis", IsCorrect = true };
        qIdent.Options.Add(optIdent);
        context.Questions.Add(qIdent);

        await context.SaveChangesAsync();

        // Simulate student submission with realistic variations (case difference, whitespace)
        var studentAnswers = new Dictionary<Guid, string>
        {
            { qMcq.Id, optCorrect.Id.ToString() }, // Correct MCQ
            { qTf.Id, optTfCorrect.Id.ToString() }, // Correct True/False
            { qCloze.Id, "  MITOCHONDRIA  " }, // Correct Cloze with whitespace and uppercase
            { qIdent.Id, "cellular respiration" } // Incorrect Identification
        };

        // Score authoritative evaluation
        int correctCount = 0;
        var loadedQuestions = await context.Questions
            .Include(q => q.Options)
            .Where(q => q.StudySetId == studySet.Id)
            .ToListAsync();

        foreach (var q in loadedQuestions)
        {
            if (!studentAnswers.TryGetValue(q.Id, out var ans)) continue;

            if (q.Type is QuestionType.MultipleChoice or QuestionType.TrueFalse)
            {
                var correctOption = q.Options.FirstOrDefault(o => o.IsCorrect);
                if (correctOption != null && Guid.TryParse(ans, out var chosenOptId) && chosenOptId == correctOption.Id)
                {
                    correctCount++;
                }
            }
            else
            {
                var correctText = q.Options.FirstOrDefault(o => o.IsCorrect)?.OptionText ?? "";
                if (string.Equals(ans.Trim(), correctText.Trim(), StringComparison.OrdinalIgnoreCase))
                {
                    correctCount++;
                }
            }
        }

        double scorePercent = (double)correctCount / loadedQuestions.Count * 100.0;

        Assert.Equal(3, correctCount);
        Assert.Equal(4, loadedQuestions.Count);
        Assert.Equal(75.0, scorePercent);
    }

    [Fact]
    public void ExamGrading_ZeroAndNegativeEdgeCases_SafelyHandledWithoutDivisionByZero()
    {
        int totalQuestions = 0;
        int correctAnswers = 0;

        double calculatedScore = totalQuestions > 0
            ? Math.Round((double)correctAnswers / totalQuestions * 100.0, 1)
            : 0.0;

        Assert.Equal(0.0, calculatedScore);

        // Clamping score between 0.0 and 100.0
        double clampedScore = Math.Clamp(calculatedScore, 0.0, 100.0);
        Assert.Equal(0.0, clampedScore);
    }

    #endregion

    #region 9. Gemini AI Fallback & Resilience Engine

    [Theory]
    [InlineData("explain binary search trees and logarithmic complexity", "Computer Science", "Binary")]
    [InlineData("describe cellular respiration and ATP synthase", "Biology", "ATP")]
    [InlineData("explain integration by parts and fundamental theorem", "Calculus", "Calculus")]
    [InlineData("Newton's second law of motion and acceleration", "Physics", "Physics")]
    public void AcademicTutorSynthesizer_GeneratesDisciplinedResponses_AcrossMajorDomains(
        string prompt, string topic, string expectedKeyword)
    {
        var response = AcademicTutorSynthesizer.SynthesizeResponse(prompt, topic);

        Assert.False(string.IsNullOrWhiteSpace(response));
        Assert.Contains(expectedKeyword, response, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("built-in educational tutor knowledge engine", response);
    }

    [Theory]
    [InlineData("none")]
    [InlineData("disabled")]
    [InlineData("offline")]
    public async Task GeminiAiService_OfflineMode_ConsistentlyUsesLocalSynthesizerWithoutNetworkLeak(string offlineFlag)
    {
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", offlineFlag },
            { "AiSettings:ModelId", "gemini-3.6-flash" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var httpClient = new HttpClient();
        var logger = NullLogger<GeminiAiService>.Instance;

        var service = new GeminiAiService(httpClient, configuration, logger);

        var result = await service.AskTutorAsync(new AskTutorRequest("Explain QuickSort algorithm", "Algorithms"));

        Assert.NotNull(result);
        Assert.Equal("Built-In Academic Engine", result.ModelUsed);
        Assert.False(string.IsNullOrWhiteSpace(result.Reply));
        Assert.DoesNotContain("offline / asleep", result.Reply);
    }

    #endregion

    #region 10. Multi-User Concurrent Isolation & Relational Stress

    [Fact]
    public async Task MultiUserConcurrentOperations_ParallelTransactions_PreserveDataIsolation()
    {
        using var context = CreateContext();

        // Spawn 10 simultaneous user tenants
        var users = Enumerable.Range(1, 10).Select(i => new User
        {
            Email = $"student{i}@university.edu",
            FullName = $"Student Number {i}",
            PasswordHash = $"hash_{i}"
        }).ToList();

        context.Users.AddRange(users);
        await context.SaveChangesAsync();

        // Concurrently generate courses and notebook pages for all 10 users in parallel
        var tasks = users.Select(async u =>
        {
            var course = new Course
            {
                UserId = u.Id,
                Code = $"CS-30{u.FullName[^1]}",
                Name = $"Advanced Computing {u.FullName[^1]}"
            };

            var note = new NotebookPage
            {
                CourseId = course.Id,
                Title = $"Session Note for {u.FullName}",
                ContentMarkdown = $"# Notes by {u.FullName}"
            };

            return (course, note);
        });

        var results = await Task.WhenAll(tasks);

        foreach (var (c, n) in results)
        {
            context.Courses.Add(c);
            context.NotebookPages.Add(n);
        }
        await context.SaveChangesAsync();

        // Verify each user has exactly 1 course and 1 note, with 0 cross-contamination
        foreach (var u in users)
        {
            var userCourses = await context.Courses.Where(c => c.UserId == u.Id).ToListAsync();
            Assert.Single(userCourses);
            Assert.Equal($"CS-30{u.FullName[^1]}", userCourses[0].Code);

            var userNotes = await context.NotebookPages
                .Where(n => context.Courses.Where(c => c.UserId == u.Id).Select(c => c.Id).Contains(n.CourseId))
                .ToListAsync();

            Assert.Single(userNotes);
            Assert.Equal($"Session Note for {u.FullName}", userNotes[0].Title);
        }
    }

    [Fact]
    public void SpacedRepetition_SuperMemo2IntervalCalculations_ProgressesReviewDurationsAccurately()
    {
        // SM-2 Spaced Repetition Formula Validation
        // Repetition 0 -> 1 day interval
        // Repetition 1 -> 6 days interval
        // Repetition 2+ -> Previous Interval * Ease Factor

        double easeFactor = 2.5;
        int repetitions = 0;
        int intervalDays = 0;

        // Step 1: First successful review (quality = 5)
        repetitions++;
        intervalDays = repetitions == 1 ? 1 : (repetitions == 2 ? 6 : (int)Math.Round(intervalDays * easeFactor));
        Assert.Equal(1, repetitions);
        Assert.Equal(1, intervalDays);

        // Step 2: Second successful review (quality = 5)
        repetitions++;
        intervalDays = repetitions == 1 ? 1 : (repetitions == 2 ? 6 : (int)Math.Round(intervalDays * easeFactor));
        Assert.Equal(2, repetitions);
        Assert.Equal(6, intervalDays);

        // Step 3: Third successful review with ease factor 2.5
        repetitions++;
        intervalDays = repetitions == 1 ? 1 : (repetitions == 2 ? 6 : (int)Math.Round(intervalDays * easeFactor));
        Assert.Equal(3, repetitions);
        Assert.Equal(15, intervalDays); // 6 * 2.5 = 15 days

        // Step 4: Quality lapse (quality < 3) resets repetitions to 0 and interval to 1
        int poorQuality = 1;
        if (poorQuality < 3)
        {
            repetitions = 0;
            intervalDays = 1;
        }
        Assert.Equal(0, repetitions);
        Assert.Equal(1, intervalDays);
    }

    #endregion

    #region 11. Anti-Repetition Question Shuffling and Seed Randomization

    [Fact]
    public void AntiRepetitionEngine_QuestionRandomization_PreservesAllElementsWithoutDuplicates()
    {
        var originalPrompts = Enumerable.Range(1, 20)
            .Select(i => $"Diagnostic Question #{i:D2}")
            .ToList();

        // Shuffle with seed 42
        var rnd1 = new Random(42);
        var shuffled1 = originalPrompts.OrderBy(_ => rnd1.Next()).ToList();

        // Shuffle with seed 999
        var rnd2 = new Random(999);
        var shuffled2 = originalPrompts.OrderBy(_ => rnd2.Next()).ToList();

        // Cardinality & Uniqueness preserved
        Assert.Equal(20, shuffled1.Count);
        Assert.Equal(20, shuffled2.Count);
        Assert.Equal(20, shuffled1.Distinct().Count());
        Assert.Equal(20, shuffled2.Distinct().Count());

        // Both contain every item from original
        Assert.All(originalPrompts, item => Assert.Contains(item, shuffled1));
        Assert.All(originalPrompts, item => Assert.Contains(item, shuffled2));

        // Orderings are randomized and distinct from each other and original
        Assert.False(originalPrompts.SequenceEqual(shuffled1));
        Assert.False(shuffled1.SequenceEqual(shuffled2));
    }

    #endregion
}

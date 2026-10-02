using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/dev")]
[ApiExplorerSettings(IgnoreApi = true)]
[Microsoft.AspNetCore.Authorization.AllowAnonymous]
public class DevController : ControllerBase
{
    private readonly IApplicationDbContext _context;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;

    public DevController(
        IApplicationDbContext context,
        IPasswordHasher passwordHasher,
        IJwtTokenGenerator jwtTokenGenerator,
        IConfiguration configuration,
        IHostEnvironment environment)
    {
        _context = context;
        _passwordHasher = passwordHasher;
        _jwtTokenGenerator = jwtTokenGenerator;
        _configuration = configuration;
        _environment = environment;
    }

    [HttpGet("diagnostics")]
    public async Task<IActionResult> GetDiagnostics()
    {
        if (!_environment.IsDevelopment())
        {
            return NotFound();
        }

        var dbProvider = _context is DbContext dbContext ? dbContext.Database.ProviderName ?? "Unknown" : "Unknown";
        var isSqlite = dbProvider.Contains("Sqlite", StringComparison.OrdinalIgnoreCase);

        var userCount = await _context.Users.CountAsync();
        var courseCount = await _context.Courses.CountAsync();
        var studySetCount = await _context.StudySets.CountAsync();
        var questionCount = await _context.Questions.CountAsync();

        var geminiKey = _configuration["AiSettings:ApiKey"]
            ?? Environment.GetEnvironmentVariable("AiSettings__ApiKey")
            ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY");
        var hasGeminiKey = !string.IsNullOrWhiteSpace(geminiKey) && !geminiKey.Contains("YOUR_GEMINI_API_KEY");
        var openAiKey = _configuration["AiSettings:OpenAi:ApiKey"] ?? Environment.GetEnvironmentVariable("OPENAI_API_KEY");
        var hasOpenAiKey = StudyApp.Infrastructure.AiServices.OpenAiAiService.IsValidProjectKey(openAiKey);
        var activeProvider = _configuration["AiSettings:Provider"] ?? "GoogleGemini";
        var isOpenAi = string.Equals(activeProvider, "OpenAI", StringComparison.OrdinalIgnoreCase);

        // Check authenticated user if token present
        User? authUser = null;
        var authHeader = Request?.Headers?.Authorization.FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader.Substring("Bearer ".Length).Trim();
            var claimsPrincipal = _jwtTokenGenerator.ValidateToken(token);
            if (claimsPrincipal != null)
            {
                var subClaim = claimsPrincipal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                    ?? claimsPrincipal.FindFirst("sub")?.Value;
                if (Guid.TryParse(subClaim, out var userId))
                {
                    authUser = await _context.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId);
                }
            }
        }

        var appVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "1.0.0-prod";

        return Ok(new
        {
            status = "online",
            serverReachable = true,
            version = appVersion,
            environment = _environment.EnvironmentName,
            runtime = Environment.Version.ToString(),
            os = Environment.OSVersion.ToString(),
            serverTimeUtc = DateTime.UtcNow,
            database = new
            {
                provider = isSqlite ? "SQLite" : "PostgreSQL",
                rawProvider = dbProvider,
                userCount,
                courseCount,
                studySetCount,
                questionCount
            },
            aiService = new
            {
                provider = activeProvider,
                model = isOpenAi
                    ? (_configuration["AiSettings:OpenAi:ModelId"] ?? "gpt-4o-mini")
                    : (_configuration["AiSettings:ModelId"] ?? "gemini-3.1-flash-lite"),
                hasApiKey = isOpenAi ? hasOpenAiKey : hasGeminiKey,
                openAiWiringStatus = hasOpenAiKey ? "active_live_target" : "paused_pending_key",
                geminiAvailable = hasGeminiKey,
                openAiAvailable = hasOpenAiKey,
                reachable = hasGeminiKey || hasOpenAiKey
            },
            auth = new
            {
                accepted = authUser != null,
                userId = authUser?.Id,
                email = authUser?.Email,
                name = authUser?.FullName,
                role = authUser != null ? "Student" : null
            },
            supportedQuestionSets = new[]
            {
                new { id = "set_a", name = "Set A: Core Concepts", focus = "Primary definitions & terminology" },
                new { id = "set_b", name = "Set B: Reverse & Cloze", focus = "Inverted recall & fill-in-the-blank" },
                new { id = "set_c", name = "Set C: Scenarios & Applied", focus = "Application scenarios & T/F contrast" },
                new { id = "set_d", name = "Set D: Simulated Exam", focus = "Balanced active-recall spread" },
                new { id = "shuffle", name = "🎲 Fresh Shuffled Set", focus = "Timestamp-seeded random permutation" }
            },
            activeFeatures = new[]
            {
                "Question Sets Anti-Repetition Engine",
                "Vision OCR & Document Parser",
                "Instant Fast Mode (<100ms)",
                "Flashcard Deck with Cascading Deletion",
                "Server-Authoritative Practice Session Grading",
                "Bi-directional Offline Sync"
            }
        });
    }

    [HttpPost("seed-test-user")]
    public async Task<IActionResult> SeedTestUser()
    {
        if (!_environment.IsDevelopment())
        {
            return NotFound();
        }

        const string testEmail = "dev@studyapp.local";
        const string testPass = "DevPass123!";

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == testEmail);
        if (user == null)
        {
            user = new User
            {
                Email = testEmail,
                FullName = "Developer Test Account",
                PasswordHash = _passwordHasher.HashPassword(testPass)
            };
            _context.Users.Add(user);
            await _context.SaveChangesAsync();
        }

        // Provision Starter Pack Courses if user has none
        var hasCourses = await _context.Courses.AnyAsync(c => c.UserId == user.Id);
        if (!hasCourses)
        {
            var biologyCourse = new Course
            {
                UserId = user.Id,
                Code = "BIO-101",
                Name = "General Biology & Respiration",
                ColorHex = "#6366F1"
            };
            _context.Courses.Add(biologyCourse);
            await _context.SaveChangesAsync();

            var studySet = new StudySet
            {
                CourseId = biologyCourse.Id,
                Title = "Cellular Respiration & Krebs Cycle - Set A (Core)",
                Description = "Foundational concepts covering glycolysis, Krebs cycle, and oxidative phosphorylation."
            };
            _context.StudySets.Add(studySet);
            await _context.SaveChangesAsync();

            var q1 = new Question
            {
                StudySetId = studySet.Id,
                Prompt = "Where does the Krebs cycle take place in eukaryotic cells?",
                Type = QuestionType.MultipleChoice,
                Explanation = "The Krebs cycle occurs inside the inner mitochondrial matrix.",
                Difficulty = 2
            };
            q1.Options.Add(new QuestionOption { OptionText = "Mitochondrial matrix", IsCorrect = true });
            q1.Options.Add(new QuestionOption { OptionText = "Cytoplasm", IsCorrect = false });
            q1.Options.Add(new QuestionOption { OptionText = "Endoplasmic reticulum", IsCorrect = false });
            q1.Options.Add(new QuestionOption { OptionText = "Outer membrane", IsCorrect = false });
            _context.Questions.Add(q1);

            var q2 = new Question
            {
                StudySetId = studySet.Id,
                Prompt = "Which enzyme is primarily responsible for synthesizing ATP during oxidative phosphorylation?",
                Type = QuestionType.Cloze,
                Explanation = "ATP Synthase utilizes the proton motive force.",
                Difficulty = 2
            };
            q2.Options.Add(new QuestionOption { OptionText = "ATP Synthase", IsCorrect = true });
            _context.Questions.Add(q2);

            await _context.SaveChangesAsync();
        }

        var (token, expiresAt) = _jwtTokenGenerator.GenerateToken(user);

        return Ok(new
        {
            message = "Developer test user ready.",
            user = new
            {
                id = user.Id,
                email = user.Email,
                fullName = user.FullName
            },
            token,
            expiresAt
        });
    }

    [HttpGet("endpoints")]
    public IActionResult GetEndpoints()
    {
        if (!_environment.IsDevelopment())
        {
            return NotFound();
        }

        return Ok(new
        {
            auth = new[]
            {
                "POST /api/v1/auth/register",
                "POST /api/v1/auth/login",
                "GET /api/v1/auth/me"
            },
            courses = new[]
            {
                "GET /api/v1/courses",
                "POST /api/v1/courses",
                "GET /api/v1/courses/{id}",
                "PUT /api/v1/courses/{id}",
                "DELETE /api/v1/courses/{id}",
                "POST /api/v1/courses/demo-pack"
            },
            ingestion = new[]
            {
                "POST /api/v1/ingestion/text",
                "POST /api/v1/ingestion/file",
                "POST /api/v1/ingestion/url",
                "POST /api/v1/ingestion/scan"
            },
            practice = new[]
            {
                "GET /api/v1/practice/studysets/{id}/questions",
                "POST /api/v1/practice/sessions",
                "GET /api/v1/practice/mastery",
                "DELETE /api/v1/questions/{id}"
            },
            ai = new[]
            {
                "POST /api/v1/ai/tutor",
                "POST /api/v1/ai/explain",
                "GET /api/v1/ai/status"
            },
            sync = new[]
            {
                "POST /api/v1/sync"
            },
            settings = new[]
            {
                "GET /api/v1/settings",
                "PUT /api/v1/settings"
            }
        });
    }
}

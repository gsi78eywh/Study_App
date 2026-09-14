using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Sync;
using StudyApp.Domain.Entities;
using StudyApp.Infrastructure.Data;
using Xunit;

namespace StudyApp.UnitTests;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _dbName = Guid.NewGuid().ToString();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            var descriptor = services.SingleOrDefault(d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));
            if (descriptor != null)
            {
                services.Remove(descriptor);
            }

            services.AddDbContext<ApplicationDbContext>(options =>
            {
                options.UseInMemoryDatabase(_dbName);
            });
        });
    }
}

public class UatEndToEndIntegrationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly CustomWebApplicationFactory _factory;

    public UatEndToEndIntegrationTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task UAT_01_HealthAndWelcomePortal_ReturnSuccessAndHealthy()
    {
        // 1. Health check
        var healthResp = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, healthResp.StatusCode);
        var healthJson = await healthResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("healthy", healthJson.GetProperty("status").GetString());

        // 2. Web portal root
        var portalResp = await _client.GetAsync("/");
        Assert.Equal(HttpStatusCode.OK, portalResp.StatusCode);
        var portalHtml = await portalResp.Content.ReadAsStringAsync();
        Assert.Contains("StudyApp C# Backend API", portalHtml);
        Assert.Contains("REST API Online", portalHtml);
    }

    [Fact]
    public async Task UAT_02_StudentAuthLifecycle_RegistrationLoginAndMe_EnforcesSecurityAndJWT()
    {
        var uniqueEmail = $"student_{Guid.NewGuid():N}@studyapp.test";
        var password = "SecurePassword123!";

        // 1. Register new student
        var regResp = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            fullName = "Alex Mercer",
            email = uniqueEmail,
            password = password
        });
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regJson = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(regJson.TryGetProperty("token", out var regToken));
        Assert.False(string.IsNullOrWhiteSpace(regToken.GetString()));

        // 2. Duplicate registration rejection
        var dupResp = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            fullName = "Alex Mercer",
            email = uniqueEmail,
            password = password
        });
        Assert.True(dupResp.StatusCode == HttpStatusCode.BadRequest || dupResp.StatusCode == HttpStatusCode.Conflict);

        // 3. Login with credentials
        var loginResp = await _client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = uniqueEmail,
            password = password
        });
        Assert.Equal(HttpStatusCode.OK, loginResp.StatusCode);
        var loginJson = await loginResp.Content.ReadFromJsonAsync<JsonElement>();
        var token = loginJson.GetProperty("token").GetString();
        Assert.NotNull(token);

        // 4. Authenticated profile check (GET /api/v1/auth/me)
        using var authReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        authReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var meResp = await _client.SendAsync(authReq);
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
        var meJson = await meResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Alex Mercer", meJson.GetProperty("fullName").GetString());
        Assert.Equal(uniqueEmail, meJson.GetProperty("email").GetString());

        // 5. Negative test: Tampered / unauthenticated token
        using var invalidReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        invalidReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "invalid.jwt.token");
        var unauthResp = await _client.SendAsync(invalidReq);
        Assert.Equal(HttpStatusCode.Unauthorized, unauthResp.StatusCode);
    }

    [Fact]
    public async Task UAT_03_CoursesAndDemoPack_ProvisionsStarterCurriculumSuccessfully()
    {
        var token = await AuthenticateTestUserAsync("demostudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Seed demo pack
        var demoResp = await client.PostAsync("/api/v1/courses/demo-pack", null);
        Assert.Equal(HttpStatusCode.OK, demoResp.StatusCode);
        var demoJson = await demoResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(demoJson.GetProperty("success").GetBoolean());

        // 2. Query courses
        var coursesResp = await client.GetAsync("/api/v1/courses");
        Assert.Equal(HttpStatusCode.OK, coursesResp.StatusCode);
        var courses = await coursesResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(courses.GetArrayLength() > 0);
        var firstCourse = courses[0];
        Assert.Equal("BIO-101", firstCourse.GetProperty("code").GetString());
    }

    [Fact]
    public async Task UAT_04_TextIngestion_SynthesizesActiveRecallStudySets()
    {
        var token = await AuthenticateTestUserAsync("ingeststudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Create a course first
        var createCourseResp = await client.PostAsJsonAsync("/api/v1/courses", new
        {
            code = "NEURO-301",
            name = "Cellular Neuroscience",
            colorHex = "#3B82F6"
        });
        Assert.Equal(HttpStatusCode.Created, createCourseResp.StatusCode);
        var course = await createCourseResp.Content.ReadFromJsonAsync<JsonElement>();
        var courseId = course.GetProperty("id").GetGuid();

        // 2. Ingest structured study notes
        var lectureNotes = """
            # Action Potentials in Neurons
            - The resting membrane potential of a typical neuron is approximately -70 mV.
            - Depolarization occurs when voltage-gated sodium channels open, allowing Na+ to rush into the cell.
            - Repolarization is driven by voltage-gated potassium channels opening and K+ exiting the cell.
            - The refractory period prevents backward propagation of the electrical impulse.
            """;

        var ingestResp = await client.PostAsJsonAsync("/api/v1/ingestion/text", new
        {
            courseId = courseId,
            title = "Action Potentials Mastery",
            content = lectureNotes,
            questionTypes = new List<string> { "multiple_choice", "cloze", "identification" },
            targetCount = 5
        });

        Assert.Equal(HttpStatusCode.OK, ingestResp.StatusCode);
        var ingestResult = await ingestResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(ingestResult.GetProperty("questionCount").GetInt32() > 0);
        Assert.Equal("Action Potentials Mastery", ingestResult.GetProperty("title").GetString());
    }

    [Fact]
    public async Task UAT_05_PracticeSession_FullServerAuthoritativeQuizLifecycle()
    {
        var token = await AuthenticateTestUserAsync("quizstudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Load starter pack to guarantee questions exist
        await client.PostAsync("/api/v1/courses/demo-pack", null);

        var coursesResp = await client.GetAsync("/api/v1/courses");
        var courses = await coursesResp.Content.ReadFromJsonAsync<JsonElement>();
        var courseId = courses[0].GetProperty("id").GetGuid();

        // Query course details to obtain studySetId
        var detailResp = await client.GetAsync($"/api/v1/courses/{courseId}");
        Assert.Equal(HttpStatusCode.OK, detailResp.StatusCode);
        var courseDetail = await detailResp.Content.ReadFromJsonAsync<JsonElement>();
        var studySets = courseDetail.GetProperty("studySets");
        Assert.True(studySets.GetArrayLength() > 0);
        var studySet = studySets[0];
        var studySetId = studySet.GetProperty("id").GetGuid();

        // Query adaptive questions via practice endpoint
        var questionsResp = await client.GetAsync($"/api/v1/practice/studysets/{studySetId}/questions");
        Assert.Equal(HttpStatusCode.OK, questionsResp.StatusCode);
        var questions = await questionsResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(questions.GetArrayLength() > 0);
        var q1 = questions[0];
        var q1Id = q1.GetProperty("id").GetGuid();

        // 2. Submit server-authoritative test session for grading
        var sessionResp = await client.PostAsJsonAsync("/api/v1/practice/sessions", new
        {
            studySetId = studySetId,
            mode = 1, // Standard Quiz
            timeSpentSeconds = 42,
            answers = new[]
            {
                new
                {
                    questionId = q1Id,
                    answer = "Replenish electrons in photo-excited chlorophyll"
                }
            }
        });
        Assert.Equal(HttpStatusCode.OK, sessionResp.StatusCode);
        var sessionResult = await sessionResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(sessionResult.TryGetProperty("sessionId", out var sessionId) || sessionResult.TryGetProperty("SessionId", out sessionId));
        Assert.True(sessionResult.TryGetProperty("score", out var score) || sessionResult.TryGetProperty("Score", out score));
        Assert.True(sessionResult.TryGetProperty("scorePercent", out _) || sessionResult.TryGetProperty("ScorePercent", out _));
        Assert.True(sessionResult.TryGetProperty("answers", out var grades) || sessionResult.TryGetProperty("Answers", out grades));
        Assert.True(grades.GetArrayLength() > 0);

        // 3. Query mastery topics
        var masteryResp = await client.GetAsync("/api/v1/practice/mastery");
        Assert.Equal(HttpStatusCode.OK, masteryResp.StatusCode);
        var mastery = await masteryResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(mastery.GetArrayLength() > 0);
    }

    [Fact]
    public async Task UAT_06_BiDirectionalSync_MergesClientCoursesAndPreservesState()
    {
        var token = await AuthenticateTestUserAsync("syncstudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Prepare client offline state to synchronize using SyncPushRequest schema
        var offlineCourseId = Guid.NewGuid();
        var syncPayload = new SyncPushRequest(
            LastSyncedAt: DateTime.UtcNow.AddHours(-1),
            Courses: new List<SyncCourseDto>
            {
                new SyncCourseDto(offlineCourseId, "PHYS-202", "Electromagnetism & Optics", "#8B5CF6", DateTime.UtcNow, false)
            },
            StudySets: new List<SyncStudySetDto>
            {
                new SyncStudySetDto(Guid.NewGuid(), offlineCourseId, "Maxwell's Equations", "Gauss, Faraday, and Ampere laws.", DateTime.UtcNow, false, 10)
            },
            Questions: new List<SyncQuestionDto>(),
            TestSessions: new List<SyncTestSessionDto>()
        );

        var syncResp = await client.PostAsJsonAsync("/api/v1/sync", syncPayload);
        Assert.Equal(HttpStatusCode.OK, syncResp.StatusCode);
        var syncResult = await syncResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(syncResult.TryGetProperty("serverTimestamp", out _));
        Assert.True(syncResult.TryGetProperty("updatedCourses", out var updatedCourses));
        Assert.True(updatedCourses.GetArrayLength() > 0);
    }

    [Fact]
    public async Task UAT_07_UserSettings_AcademicDefaultsAndUpdatesPersist()
    {
        var token = await AuthenticateTestUserAsync("settingsstudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Fetch default settings
        var getResp = await client.GetAsync("/api/v1/settings");
        Assert.Equal(HttpStatusCode.OK, getResp.StatusCode);
        var settings = await getResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(15, settings.GetProperty("defaultQuestionCount").GetInt32());
        Assert.Equal(25, settings.GetProperty("pomodoroFocusMinutes").GetInt32());

        // 2. Update settings with rigorous college study preferences
        var updateResp = await client.PutAsJsonAsync("/api/v1/settings", new
        {
            defaultQuestionCount = 25,
            preferredStudyMode = 8, // Simulated Exam
            instantFeedback = false,
            shuffleOptions = true,
            dailyStudyGoalMinutes = 60,
            dailyQuestionTarget = 40,
            blitzSecondsPerQuestion = 12,
            pomodoroFocusMinutes = 50,
            pomodoroShortBreakMinutes = 10,
            pomodoroLongBreakMinutes = 20,
            defaultAiDifficulty = 3,
            preferredQuestionTypes = "multiple_choice,cloze",
            soundEffectsEnabled = false,
            hapticFeedbackEnabled = true,
            themePreference = "dark"
        });
        Assert.Equal(HttpStatusCode.OK, updateResp.StatusCode);

        // 3. Verify updated preferences persisted
        var verifyResp = await client.GetAsync("/api/v1/settings");
        Assert.Equal(HttpStatusCode.OK, verifyResp.StatusCode);
        var updated = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(25, updated.GetProperty("defaultQuestionCount").GetInt32());
        Assert.Equal(50, updated.GetProperty("pomodoroFocusMinutes").GetInt32());
        Assert.Equal(60, updated.GetProperty("dailyStudyGoalMinutes").GetInt32());
        Assert.Equal("dark", updated.GetProperty("themePreference").GetString());
    }

    [Fact]
    public async Task UAT_08_AiTutor_ReturnsStatusAndInteractiveGuidance()
    {
        var token = await AuthenticateTestUserAsync("aistudent@studyapp.test");

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Status endpoint
        var statusResp = await client.GetAsync("/api/v1/ai/status");
        Assert.Equal(HttpStatusCode.OK, statusResp.StatusCode);
        var statusJson = await statusResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(statusJson.TryGetProperty("provider", out _));

        // 2. AI Tutor question
        var tutorResp = await client.PostAsJsonAsync("/api/v1/ai/tutor", new
        {
            message = "Can you explain how active transport differs from passive diffusion in cell biology?",
            contextTopic = "Cell Biology"
        });
        Assert.Equal(HttpStatusCode.OK, tutorResp.StatusCode);
        var tutorJson = await tutorResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(tutorJson.TryGetProperty("reply", out var tutorResponse));
        Assert.False(string.IsNullOrWhiteSpace(tutorResponse.GetString()));
    }

    private async Task<string> AuthenticateTestUserAsync(string email)
    {
        var resp = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            fullName = "StudyApp Student",
            email = email,
            password = "SecurePassword123!"
        });

        if (resp.IsSuccessStatusCode)
        {
            var json = await resp.Content.ReadFromJsonAsync<JsonElement>();
            return json.GetProperty("token").GetString()!;
        }

        var loginResp = await _client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = email,
            password = "SecurePassword123!"
        });
        var loginJson = await loginResp.Content.ReadFromJsonAsync<JsonElement>();
        return loginJson.GetProperty("token").GetString()!;
    }

    [Fact]
    public async Task UAT_09_ScanDocumentContent_ExtractsTextAndReturnsStructuredMetadata()
    {
        var email = $"scanner_user_{Guid.NewGuid():N}@studyapp.test";
        var token = await AuthenticateTestUserAsync(email);

        using var authedClient = _factory.CreateClient();
        authedClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Upload and scan user screenshot or test image
        var screenshotPath = @"C:\Users\SethAndreyJabagat\.gemini\antigravity-ide\brain\bf666538-0260-4588-a691-dfc70581fbd4\.user_uploaded\media_1789349862791.png";
        byte[] fileBytes;
        string fileName;
        if (File.Exists(screenshotPath))
        {
            fileBytes = await File.ReadAllBytesAsync(screenshotPath);
            fileName = "quiz_screenshot.png";
        }
        else
        {
            fileBytes = System.Text.Encoding.UTF8.GetBytes("Question 1: What is exploration in reinforcement learning?\nA. Taking new actions to discover better long term rewards.\nAnswer: A");
            fileName = "notes.txt";
        }

        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(fileBytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(fileName.EndsWith(".png") ? "image/png" : "text/plain");
        content.Add(fileContent, "file", fileName);

        var response = await authedClient.PostAsync("/api/v1/ingestion/scan", content);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(json.GetProperty("hasContent").GetBoolean());
        Assert.True(json.GetProperty("charCount").GetInt32() > 0);
        Assert.True(json.GetProperty("wordCount").GetInt32() > 0);
        var extractedText = json.GetProperty("extractedText").GetString();
        Assert.False(string.IsNullOrWhiteSpace(extractedText));
    }

    [Fact]
    public async Task UAT_07_DeleteFlashcardQuestion_RemovesFromDatabaseAndCleansDependencies()
    {
        var email = $"delete_card_user_{Guid.NewGuid():N}@studyapp.test";
        var token = await AuthenticateTestUserAsync(email);

        using var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // 1. Initialize Starter Pack
        var packResp = await client.PostAsync("/api/v1/courses/demo-pack", null);
        Assert.Equal(HttpStatusCode.OK, packResp.StatusCode);

        // 2. Query Courses & StudySets
        var coursesResp = await client.GetAsync("/api/v1/courses");
        var courses = await coursesResp.Content.ReadFromJsonAsync<List<JsonElement>>();
        Assert.NotNull(courses);
        Assert.True(courses.Count > 0);
        var courseId = courses[0].GetProperty("id").GetGuid();

        var detailResp = await client.GetAsync($"/api/v1/courses/{courseId}");
        var courseDetail = await detailResp.Content.ReadFromJsonAsync<JsonElement>();
        var studySets = courseDetail.GetProperty("studySets");
        Assert.True(studySets.GetArrayLength() > 0);
        var studySetId = studySets[0].GetProperty("id").GetGuid();

        // 3. Query questions for this study set
        var questionsResp = await client.GetAsync($"/api/v1/studysets/{studySetId}/questions");
        Assert.Equal(HttpStatusCode.OK, questionsResp.StatusCode);
        var questions = await questionsResp.Content.ReadFromJsonAsync<List<JsonElement>>();
        Assert.NotNull(questions);
        Assert.True(questions.Count > 0);

        var originalCount = questions.Count;
        var targetQuestionId = Guid.Parse(questions[0].GetProperty("id").GetString()!);

        // 4. Delete the question
        var deleteResp = await client.DeleteAsync($"/api/v1/questions/{targetQuestionId}");
        Assert.Equal(HttpStatusCode.OK, deleteResp.StatusCode);

        // 5. Query questions again and verify count decremented and question absent
        var refreshedResp = await client.GetAsync($"/api/v1/studysets/{studySetId}/questions");
        var refreshedQuestions = await refreshedResp.Content.ReadFromJsonAsync<List<JsonElement>>();
        Assert.NotNull(refreshedQuestions);
        Assert.Equal(originalCount - 1, refreshedQuestions.Count);
        Assert.DoesNotContain(refreshedQuestions, q => Guid.Parse(q.GetProperty("id").GetString()!) == targetQuestionId);

        // 6. Attempting to delete again returns 404
        var repeatDeleteResp = await client.DeleteAsync($"/api/v1/questions/{targetQuestionId}");
        Assert.Equal(HttpStatusCode.NotFound, repeatDeleteResp.StatusCode);
    }

    [Fact]
    public async Task UAT_10_DevDiagnosticsAndSeedTestUser_ReturnsOperationalStatus()
    {
        // 1. Diagnostics endpoint
        var diagResp = await _client.GetAsync("/api/v1/dev/diagnostics");
        Assert.Equal(HttpStatusCode.OK, diagResp.StatusCode);
        var diagJson = await diagResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("online", diagJson.GetProperty("status").GetString());
        Assert.True(diagJson.TryGetProperty("database", out var dbInfo));
        Assert.True(dbInfo.TryGetProperty("provider", out _));

        // 2. Seed test user
        var seedResp = await _client.PostAsync("/api/v1/dev/seed-test-user", null);
        Assert.Equal(HttpStatusCode.OK, seedResp.StatusCode);
        var seedJson = await seedResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(seedJson.TryGetProperty("token", out var tokenProp));
        var devToken = tokenProp.GetString();
        Assert.False(string.IsNullOrWhiteSpace(devToken));

        // 3. Authenticate with seeded user to verify immediate usability
        using var authedClient = _factory.CreateClient();
        authedClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", devToken);
        var coursesResp = await authedClient.GetAsync("/api/v1/courses");
        Assert.Equal(HttpStatusCode.OK, coursesResp.StatusCode);

        // 4. Endpoints directory
        var endpointsResp = await _client.GetAsync("/api/v1/dev/endpoints");
        Assert.Equal(HttpStatusCode.OK, endpointsResp.StatusCode);
    }
}


using System.Net;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using StudyApp.Api.Controllers;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ingestion;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.DocumentParsers;
using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

public class UatSecurityAndLoadBalancingTests
{
    private class DummyAiGenerator : IAiQuestionGenerator
    {
        public Task<GeneratedStudySetResult> GenerateStudySetAsync(
            string rawText,
            string title,
            List<string> requestedTypes,
            int targetCount,
            int setIndex = 0,
            string? variant = null,
            string? apiKeyOverride = null,
            CancellationToken cancellationToken = default)
        {
            var result = new GeneratedStudySetResult(
                StudySetId: Guid.NewGuid(),
                Title: title,
                Summary: "This is a verified academic summary of the lecture material for college students.",
                HighYieldBulletPoints: new List<string>
                {
                    "Mitochondria generate adenosine triphosphate (ATP)",
                    "Cellular respiration involves glycolysis, Krebs cycle, and oxidative phosphorylation"
                },
                Questions: new List<GeneratedQuestionDto>
                {
                    new GeneratedQuestionDto(
                        Type: "Identification",
                        Prompt: "What is the primary power house of the cell?",
                        Hints: new List<string> { "Begins with M" },
                        CorrectAnswer: "Mitochondria",
                        Options: null,
                        ValidSynonyms: new List<string> { "Mitochondrion" },
                        EnumerationItems: null,
                        IsOrdered: false,
                        Explanation: "Mitochondria produce ATP via cellular respiration.",
                        ThinkingBreakdown: new List<string> { "Step 1: Cell biology fundamentals" },
                        SourceReference: "Mitochondria generate adenosine triphosphate through oxidative phosphorylation."
                    )
                }
            );
            return Task.FromResult(result);
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
            return GenerateStudySetAsync("Sample image transcription", title, requestedTypes, targetCount, setIndex, variant, apiKeyOverride, cancellationToken);
        }
    }

    private class DummyDocumentExtractor : IDocumentExtractor
    {
        public Task<string> ExtractPdfTextAsync(Stream pdfStream, CancellationToken cancellationToken = default)
            => Task.FromResult("Extracted PDF content with substantive academic data.");

        public Task<string> ExtractDocxTextAsync(Stream docxStream, CancellationToken cancellationToken = default)
            => Task.FromResult("Extracted DOCX content with substantive academic data.");

        public Task<string> ExtractUrlContentAsync(string url, CancellationToken cancellationToken = default)
        {
            if (url.Contains("invalid") || url.Contains("169.254"))
            {
                throw new InvalidOperationException("Blocked by SSRF or security filter.");
            }
            return Task.FromResult("Extracted legitimate web article content covering academic concepts and lecture highlights.");
        }

        public Task<string> ExtractImageTextAsync(Stream imageStream, string mimeType, string? apiKeyOverride = null, CancellationToken cancellationToken = default)
            => Task.FromResult("Extracted OCR text from whiteboard photo.");
    }

    private ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;
        return new ApplicationDbContext(options);
    }

    private ControllerContext CreateControllerContext(Guid userId)
    {
        var identity = new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
            new Claim(ClaimTypes.Email, "student@usjr.edu.ph")
        }, "TestAuth");

        var principal = new ClaimsPrincipal(identity);
        return new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = principal }
        };
    }

    // =========================================================================
    // 1. SECURITY & INPUT SANITIZATION UAT
    // =========================================================================

    [Fact]
    public async Task Security_TranscriptToNotes_RejectsPayloadExceedingMaximumLength_ReturnsBadRequest()
    {
        using var context = CreateContext();
        var userId = Guid.NewGuid();
        var controller = new IngestionController(new DummyAiGenerator(), new DummyDocumentExtractor(), context)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        // Attack: 200,001 character payload designed to consume server memory
        var hugePayload = new string('A', 200_001);
        var request = new TranscriptToNotesRequest(
            Content: hugePayload,
            Title: "DoS Attempt"
        );

        var result = await controller.TranscriptToNotes(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.NotNull(badRequest.Value);
        Assert.Contains("200,000", badRequest.Value.ToString()!);
    }

    [Fact]
    public async Task Security_TranscriptToNotes_RejectsUrlExceedingMaximumLength_ReturnsBadRequest()
    {
        using var context = CreateContext();
        var userId = Guid.NewGuid();
        var controller = new IngestionController(new DummyAiGenerator(), new DummyDocumentExtractor(), context)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        // Attack: URL with > 2,048 chars
        var longUrl = "https://example.com/" + new string('x', 2050);
        var request = new TranscriptToNotesRequest(
            Url: longUrl,
            Title: "Long URL Test"
        );

        var result = await controller.TranscriptToNotes(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.NotNull(badRequest.Value);
        Assert.Contains("2,048", badRequest.Value.ToString()!);
    }

    [Fact]
    public async Task Security_TranscriptToNotes_RejectsEmptyContentAndUrl_ReturnsBadRequest()
    {
        using var context = CreateContext();
        var userId = Guid.NewGuid();
        var controller = new IngestionController(new DummyAiGenerator(), new DummyDocumentExtractor(), context)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        var request = new TranscriptToNotesRequest(Content: "", Url: "");

        var result = await controller.TranscriptToNotes(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.NotNull(badRequest.Value);
        Assert.Contains("Please provide either a lecture transcript", badRequest.Value.ToString()!);
    }

    [Theory]
    [InlineData("ftp://internal-server.local/confidential.txt")]
    [InlineData("file:///etc/passwd")]
    [InlineData("gopher://127.0.0.1:70/")]
    public async Task Security_TranscriptToNotes_RejectsNonHttpOrHttpsSchemes_ReturnsBadRequest(string invalidUrl)
    {
        using var context = CreateContext();
        var userId = Guid.NewGuid();
        var controller = new IngestionController(new DummyAiGenerator(), new DummyDocumentExtractor(), context)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        var request = new TranscriptToNotesRequest(
            Url: invalidUrl,
            Title: "Protocol Smuggling Attempt"
        );

        var result = await controller.TranscriptToNotes(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.NotNull(badRequest.Value);
        Assert.Contains("Only valid HTTP(S) URLs can be processed", badRequest.Value.ToString()!);
    }

    [Theory]
    [InlineData("169.254.169.254", true)] // AWS / GCP / Azure IMDS
    [InlineData("127.0.0.1", true)]       // Loopback
    [InlineData("10.0.0.50", true)]       // Private LAN
    [InlineData("192.168.1.1", true)]     // Private LAN
    [InlineData("172.16.0.1", true)]      // Private LAN
    [InlineData("8.8.8.8", false)]        // Public DNS
    [InlineData("142.250.190.46", false)] // Public Google IP
    public void Security_DocumentExtractor_IsPrivateOrLocal_BlocksCloudMetadataAndInternalIps(string ipStr, bool isPrivate)
    {
        var ip = IPAddress.Parse(ipStr);
        var detected = DocumentExtractor.IsPrivateOrLocal(ip);
        Assert.Equal(isPrivate, detected);
    }

    // =========================================================================
    // 2. SYSTEM LOAD BALANCING & MEMORY CACHE UAT
    // =========================================================================

    [Fact]
    public async Task LoadBalancing_GradesController_GetGradeSummary_CachesResultInIMemoryCache()
    {
        using var context = CreateContext();
        var memoryCache = new MemoryCache(new MemoryCacheOptions());
        var userId = Guid.NewGuid();

        // Seed a sample course with grades
        var course = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Code = "CS-301",
            Name = "Operating Systems",
            Units = 3.0,
            PrelimGrade = 88.0,
            MidtermGrade = 90.0,
            SemiFinalGrade = 85.0,
            FinalGrade = 92.0,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        context.Courses.Add(course);
        await context.SaveChangesAsync();

        var controller = new GradesController(context, memoryCache)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        // 1. First invocation: Computes from database and stores in memory cache
        var initialResult = await controller.GetGradeSummary(CancellationToken.None);
        var initialOk = Assert.IsType<OkObjectResult>(initialResult);
        Assert.NotNull(initialOk.Value);

        // Verify cache now contains the key
        var cacheKey = $"grades_summary_{userId}";
        Assert.True(memoryCache.TryGetValue(cacheKey, out object? cachedValue));
        Assert.NotNull(cachedValue);

        // 2. Direct modification of DB entity to simulate external change without cache eviction
        course.PrelimGrade = 50.0;
        await context.SaveChangesAsync();

        // 3. Second invocation: Should immediately hit IMemoryCache (load-balancing, 0 database overhead)
        var secondResult = await controller.GetGradeSummary(CancellationToken.None);
        var secondOk = Assert.IsType<OkObjectResult>(secondResult);
        Assert.Same(cachedValue, secondOk.Value);
    }

    [Fact]
    public async Task LoadBalancing_GradesController_UpdateCourseGrade_InvalidatesCache()
    {
        using var context = CreateContext();
        var memoryCache = new MemoryCache(new MemoryCacheOptions());
        var userId = Guid.NewGuid();

        var courseId = Guid.NewGuid();
        var course = new Course
        {
            Id = courseId,
            UserId = userId,
            Code = "MATH-201",
            Name = "Discrete Mathematics",
            Units = 3.0,
            PrelimGrade = 80.0,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        context.Courses.Add(course);
        await context.SaveChangesAsync();

        var controller = new GradesController(context, memoryCache)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        // Step 1: Pre-populate cache via GetGradeSummary
        await controller.GetGradeSummary(CancellationToken.None);
        var cacheKey = $"grades_summary_{userId}";
        Assert.True(memoryCache.TryGetValue(cacheKey, out _));

        // Step 2: Update grade via controller
        var updateRequest = new UpdateCourseGradeRequest(
            Units: 3.0,
            TargetGrade: 95.0,
            PrelimGrade: 92.0,
            MidtermGrade: 94.0,
            SemiFinalGrade: null,
            FinalGrade: null,
            PrelimWeight: null,
            MidtermWeight: null,
            SemiFinalWeight: null,
            FinalWeight: null
        );

        var updateResult = await controller.UpdateCourseGrades(courseId, updateRequest, CancellationToken.None);
        Assert.IsType<OkObjectResult>(updateResult);

        // Step 3: Cache must be invalidated immediately
        Assert.False(memoryCache.TryGetValue(cacheKey, out _));

        // Step 4: Next GetGradeSummary computes fresh data with updated 92.0 Prelim
        var freshResult = await controller.GetGradeSummary(CancellationToken.None);
        var freshOk = Assert.IsType<OkObjectResult>(freshResult);
        Assert.NotNull(freshOk.Value);
    }

    // =========================================================================
    // 3. NOTES ACCURACY & CORNELL STRUCTURE UAT
    // =========================================================================

    [Fact]
    public async Task NotesAccuracy_TranscriptToNotes_GeneratesStructuredCornellSections()
    {
        using var context = CreateContext();
        var userId = Guid.NewGuid();
        var controller = new IngestionController(new DummyAiGenerator(), new DummyDocumentExtractor(), context)
        {
            ControllerContext = CreateControllerContext(userId)
        };

        var lectureText = @"
Today we examine the role of Mitochondria in cellular metabolism.
Mitochondria generate adenosine triphosphate through oxidative phosphorylation.
The inner mitochondrial membrane contains the electron transport chain complexes.
Glucose undergoes glycolysis in the cytoplasm before entering the citric acid cycle.
This process provides the primary energy currency for eukaryotic organisms.";

        var request = new TranscriptToNotesRequest(
            Content: lectureText,
            Title: "Cellular Biology Lecture 4",
            GenerateFlashcards: true
        );

        var result = await controller.TranscriptToNotes(request, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(okResult.Value);

        // Inspect the saved NotebookPage in database
        var savedPage = await context.NotebookPages.FirstOrDefaultAsync();
        Assert.NotNull(savedPage);
        Assert.Equal("Cellular Biology Lecture 4", savedPage.Title);

        var markdown = savedPage.ContentMarkdown;

        // Verify Cornell Note Structure keeps generated flashcards out of note body
        Assert.Contains("# Cellular Biology Lecture 4", markdown);
        Assert.Contains("## Executive Lecture Summary", markdown);
        Assert.Contains("## Core Academic Concepts & Cornell Cues", markdown);
        Assert.Contains("## Mechanistic Breakdown & Detailed Notes", markdown);
        Assert.DoesNotContain("## Active Recall Flashcard Prompts", markdown);

        // Verify Content Accuracy
        Assert.Contains("Mitochondria", markdown);
        Assert.DoesNotContain("Active Recall Flashcard Prompts", markdown);
    }

    [Fact]
    public void NotesAccuracy_NoteScriptSynthesizer_NormalizesMarkdownAccurately()
    {
        // 1. Heading stripping
        var headingLine = "### 1. The Second Law of Thermodynamics";
        Assert.Equal("1. The Second Law of Thermodynamics", NoteScriptSynthesizer.NormalizeMarkdownLine(headingLine));

        // 2. Bullet point stripping
        var bulletLine = "- **Entropy**: The measure of molecular disorder in a closed system.";
        Assert.Equal("Entropy: The measure of molecular disorder in a closed system.", NoteScriptSynthesizer.NormalizeMarkdownLine(bulletLine));

        // 3. Bold/italic stripping
        var formattedLine = "The *Carnot cycle* defines the maximum theoretical efficiency.";
        Assert.Equal("The Carnot cycle defines the maximum theoretical efficiency.", NoteScriptSynthesizer.NormalizeMarkdownLine(formattedLine));
    }
}

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using StudyApp.Api.Controllers;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

public class AcademicTutorTests
{
    [Fact]
    public void SynthesizeResponse_WithFlutterSetup_ReturnsComprehensiveGuideAndCode()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("generate flutter setup", null);

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("flutter doctor -v", reply);
        Assert.Contains("flutter create", reply);
        Assert.Contains("main.dart", reply);
        Assert.Contains("StatelessWidget", reply);
        Assert.Contains("built-in educational tutor knowledge engine", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithMathCalculus_ReturnsMathematicalPrinciples()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("explain derivatives and tangent slope", "Calculus");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Rate of Change", reply);
        Assert.Contains("derivative", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithBarangayGovernance_ReturnsComprehensivePhilippineGovernanceGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "what is the actual process of barangay when publishing or implementing projects that needs a volunteer like projects for clean up and so on",
            "Barangay Project Implementation");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Republic Act No. 7160", reply);
        Assert.Contains("Republic Act No. 9003", reply);
        Assert.Contains("Sangguniang Barangay", reply);
        Assert.Contains("Punong Barangay", reply);
        Assert.Contains("Barangay Assembly", reply);
        Assert.Contains("Volunteer", reply);
        Assert.Contains("Materials Recovery Facility", reply);
        Assert.True(reply.Length > 2000, $"Expected response length > 2000 but got {reply.Length}");
    }

    [Fact]
    public void SynthesizeResponse_WithLawAndJurisprudence_ReturnsConstitutionalLawGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("explain due process and equal protection of the laws", "Constitutional Law");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Police Power", reply);
        Assert.Contains("Substantive vs. Procedural Due Process", reply);
        Assert.Contains("Ang Tibay v. CIR", reply);
        Assert.True(reply.Length > 1500);
    }

    [Fact]
    public void SynthesizeResponse_WithEconomicsAndAccounting_ReturnsAccountingAndEconomicsGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("how do debits and credits affect the balance sheet equation", "Accounting");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Assets", reply);
        Assert.Contains("Liabilities", reply);
        Assert.Contains("Owner's Equity", reply);
        Assert.Contains("Debit", reply);
        Assert.Contains("Credit", reply);
        Assert.True(reply.Length > 1500);
    }

    [Fact]
    public void SynthesizeResponse_WithHealthSciences_ReturnsNursingProcessAndPharmacologyGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("explain the nursing process ADPIE and vital signs", "Nursing");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("ADPIE", reply);
        Assert.Contains("Blood Pressure", reply);
        Assert.Contains("Pharmacokinetics", reply);
        Assert.True(reply.Length > 1500);
    }

    [Fact]
    public void SynthesizeResponse_WithSystemsAndNetworking_ReturnsOperatingSystemsAndNetworkingGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("explain process vs thread, coffman deadlock conditions and TCP 3-way handshake", "Operating Systems");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Process vs. Thread", reply);
        Assert.Contains("Coffman Conditions", reply);
        Assert.Contains("OSI Layer", reply);
        Assert.Contains("SYN", reply);
        Assert.True(reply.Length > 1500);
    }

    [Fact]
    public void SynthesizeResponse_WithGeneralSubject_ReturnsSubstantialMultiSectionGuide()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse("what are the core principles of cognitive load theory in educational psychology", "Cognitive Psychology");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Executive Overview", reply);
        Assert.Contains("Theoretical Mechanics", reply);
        Assert.Contains("Real-World Applied Case Study", reply);
        Assert.Contains("Active Recall", reply);
        Assert.True(reply.Length > 2000, $"Expected general guide length > 2000 but got {reply.Length}");
    }

    [Fact]
    public void IngestionController_TryExtractSearchEngineQuery_WithGoogleSearchUrl_ExtractsQuery()
    {
        // Arrange
        var testUrl = "https://www.google.com/search?q=what+is+the+actual+process+of+barangay+when+publishing+or+implementing+projects+that+needs+a+volunteer+like+projects+for+clean+up+and+so+on&sourceid=chrome&ie=UTF-8";

        // Act
        var success = IngestionController.TryExtractSearchEngineQuery(testUrl, out var query, out var engineName);

        // Assert
        Assert.True(success);
        Assert.Equal("Google Search", engineName);
        Assert.Contains("process of barangay", query);
        Assert.Contains("volunteer", query);
    }

    [Fact]
    public async Task GeminiAiService_AskTutorAsync_WithoutCloudApiKeyReturnsResearchUnavailableInsteadOfGuessing()
    {
        // Arrange: Configuration explicitly without cloud API key
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "none" },
            { "AiSettings:ModelId", "gemini-3.1-flash-lite" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var httpClient = new HttpClient();
        var logger = NullLogger<GeminiAiService>.Instance;

        var service = new GeminiAiService(httpClient, configuration, logger);

        // Act
        var response = await service.AskTutorAsync(new AskTutorRequest("generate flutter setup"));

        // Assert
        Assert.NotNull(response);
        Assert.Equal("Google Search unavailable", response.ModelUsed);
        Assert.Contains("couldn't verify", response.Reply, StringComparison.OrdinalIgnoreCase);
        Assert.Empty(response.Sources ?? []);
    }

    [Fact]
    public async Task AiController_AskTutor_WithHeaderKey_PassesKeyToService()
    {
        // Arrange
        var fakeTutor = new FakeAiTutorService();
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ModelId", "gemini-3.1-flash-lite" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();

        var controller = new AiController(fakeTutor, configuration)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
        controller.Request.Headers["X-Gemini-ApiKey"] = "AIzaSyUserKey123";

        // Act
        var result = await controller.AskTutor(new AskTutorRequest("generate flutter setup"), CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<AskTutorResponse>(okResult.Value);
        Assert.Equal("AIzaSyUserKey123", fakeTutor.LastReceivedApiKey);
        Assert.Contains("AIzaSyUserKey123", response.Reply);
    }

    [Fact]
    public async Task AiController_GetTutorStatus_ReturnsStatusFromService()
    {
        // Arrange
        var fakeTutor = new FakeAiTutorService();
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ModelId", "gemini-3.1-flash-lite" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var controller = new AiController(fakeTutor, configuration);

        // Act
        var result = await controller.GetTutorStatus(CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var status = Assert.IsType<TutorStatusResponse>(okResult.Value);
        Assert.True(status.Reachable);
        Assert.Equal("gemini-3.1-flash-lite", status.Model);
    }

    private class FakeAiTutorService : IAiTutorService
    {
        public string? LastReceivedApiKey { get; private set; }

        public Task<AskTutorResponse> AskTutorAsync(AskTutorRequest request, CancellationToken cancellationToken = default)
        {
            LastReceivedApiKey = request.ApiKey;
            return Task.FromResult(new AskTutorResponse(
                $"Replied to: {request.Message} with key: {request.ApiKey}",
                "gemini-3.1-flash-lite",
                DateTime.UtcNow
            ));
        }

        public Task<QuestionExplanationResult> ExplainQuestionAsync(ExplainQuestionRequest request, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new QuestionExplanationResult("Concept", "Why", "Distractor", "Tip"));
        }

        public Task<OpenAnswerEvaluationResult> EvaluateOpenAnswerAsync(string prompt, string modelAnswer, IReadOnlyList<string> rubric, string studentAnswer, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new OpenAnswerEvaluationResult(1m, "Good", true));
        }

        public Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(true);
        }

        public Task<TutorStatusResponse> CheckStatusAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new TutorStatusResponse(true, "AI Tutor Online", "gemini-3.1-flash-lite", 20));
        }
    }
}

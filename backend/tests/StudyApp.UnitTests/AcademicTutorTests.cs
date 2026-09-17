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
    public async Task GeminiAiService_AskTutorAsync_WithoutCloudApiKey_ReturnsSynthesizedResponseInsteadOfSleep()
    {
        // Arrange: Configuration explicitly without cloud API key
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "none" },
            { "AiSettings:ModelId", "gemini-3.6-flash" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var httpClient = new HttpClient();
        var logger = NullLogger<GeminiAiService>.Instance;

        var service = new GeminiAiService(httpClient, configuration, logger);

        // Act
        var response = await service.AskTutorAsync(new AskTutorRequest("generate flutter setup"));

        // Assert
        Assert.NotNull(response);
        Assert.Equal("Built-In Academic Engine", response.ModelUsed);
        Assert.DoesNotContain("offline / asleep", response.Reply);
        Assert.Contains("flutter doctor", response.Reply);
        Assert.Contains("flutter create", response.Reply);
    }

    [Fact]
    public async Task AiController_AskTutor_WithHeaderKey_PassesKeyToService()
    {
        // Arrange
        var fakeTutor = new FakeAiTutorService();
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ModelId", "gemini-3.6-flash" }
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

    private class FakeAiTutorService : IAiTutorService
    {
        public string? LastReceivedApiKey { get; private set; }

        public Task<AskTutorResponse> AskTutorAsync(AskTutorRequest request, CancellationToken cancellationToken = default)
        {
            LastReceivedApiKey = request.ApiKey;
            return Task.FromResult(new AskTutorResponse(
                $"Replied to: {request.Message} with key: {request.ApiKey}",
                "gemini-3.6-flash",
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
    }
}

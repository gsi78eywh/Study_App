using System.Reflection;
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

/// <summary>
/// Comprehensive test suite verifying AI Agent behaviors, code documentation generation,
/// docstring standards synthesis, and offline-resilient question generation.
/// </summary>
public class CodeDocumentationAndAiAgentTests
{
    [Fact]
    public void SynthesizeResponse_WithXmlCodeDocumentation_ReturnsSummaryParamReturnsAndBestPractices()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "explain C# XML code documentation standards for our backend",
            "Software Architecture");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Code Documentation & Technical Specification Standards", reply);
        Assert.Contains("<summary>", reply);
        Assert.Contains("<param", reply);
        Assert.Contains("<returns>", reply);
        Assert.Contains("<exception", reply);
        Assert.Contains("Document Intent", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithPythonDocstrings_ReturnsPep257StandardArgsReturnsAndExample()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "generate python docstring formatting for our ML functions",
            "Python Development");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Python Docstrings (PEP 257 / Google Style)", reply);
        Assert.Contains("Args:", reply);
        Assert.Contains("Returns:", reply);
        Assert.Contains("Raises:", reply);
        Assert.Contains("\"\"\"", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithTypeScriptJsDoc_ReturnsValidTsDocAnnotations()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "how to write JSDoc and TSDoc code documentation for frontend components",
            "TypeScript");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("TypeScript / JavaScript (JSDoc / TSDoc)", reply);
        Assert.Contains("@template", reply);
        Assert.Contains("@param", reply);
        Assert.Contains("@returns", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithDartdocFlutter_ReturnsTripleSlashMarkdownDocumentation()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "how to write dartdoc code documentation in flutter widgets",
            "Flutter");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Dart / Flutter (Dartdoc `///`)", reply);
        Assert.Contains("///", reply);
        Assert.Contains("StatelessWidget", reply);
    }

    [Fact]
    public void SynthesizeResponse_WithApiDocumentation_ReturnsOpenApiAndRestBestPractices()
    {
        // Act
        var reply = AcademicTutorSynthesizer.SynthesizeResponse(
            "best practices for API documentation and openapi doc specifications",
            "Web APIs");

        // Assert
        Assert.False(string.IsNullOrWhiteSpace(reply));
        Assert.Contains("Code Documentation Best Practices Checklist", reply);
        Assert.Contains("Specify Contracts", reply);
        Assert.Contains("Keep Synchronized", reply);
    }

    [Fact]
    public async Task GeminiAiService_AskTutorAsync_WithCodeDocumentationPrompt_ReturnsRichDocumentationGuide()
    {
        // Arrange
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "PLACEHOLDER_LOCAL_TEST_KEY" },
            { "AiSettings:ModelId", "gemini-3.6-flash" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var httpClient = new HttpClient();
        var logger = NullLogger<GeminiAiService>.Instance;
        var service = new GeminiAiService(httpClient, configuration, logger);

        // Act
        var response = await service.AskTutorAsync(new AskTutorRequest(
            "show me code documentation examples with XML docs and docstrings",
            "Software Engineering"));

        // Assert
        Assert.NotNull(response);
        Assert.Equal("Built-In Academic Engine", response.ModelUsed);
        Assert.Contains("<summary>", response.Reply);
        Assert.Contains("PEP 257", response.Reply);
    }

    [Fact]
    public async Task SemanticKernelQuestionGenerator_WithCodeDocumentationNotes_SynthesizesActiveRecallDeck()
    {
        // Arrange
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "PLACEHOLDER_KEY" },
            { "AiSettings:ModelId", "gemini-3.6-flash" },
            { "AiSettings:BaseUrl", "https://generativelanguage.googleapis.com/v1beta/openai/" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var generator = new SemanticKernelQuestionGenerator(configuration);

        var lectureNotes = """
            # Code Documentation in Modern Software Engineering
            - XML documentation comments in C# begin with three forward slashes (///) and support compiler validation.
            - Python PEP 257 defines conventions for docstrings, recommending concise one-line summaries followed by Args and Returns blocks.
            - JSDoc enables static type inference in JavaScript and TypeScript without transpilation.
            - Documentation should always explain the *Why* behind architectural decisions, not just repeating the syntax.
            - Outdated code documentation is worse than no documentation because it misleads maintainers.
            """;

        // Act
        var result = await generator.GenerateStudySetAsync(
            lectureNotes,
            "Code Documentation Standards",
            new List<string> { "multiple_choice", "cloze", "identification" },
            targetCount: 5);

        // Assert
        Assert.NotNull(result);
        Assert.Equal("Code Documentation Standards", result.Title);
        Assert.NotEmpty(result.Summary);
        Assert.NotEmpty(result.HighYieldBulletPoints);
        Assert.True(result.Questions.Count > 0, "Should generate active recall questions from notes");
        Assert.All(result.Questions, q =>
        {
            Assert.False(string.IsNullOrWhiteSpace(q.Prompt));
            Assert.True((q.Options != null && q.Options.Count > 0) || (q.EnumerationItems != null && q.EnumerationItems.Count > 0) || !string.IsNullOrWhiteSpace(q.CorrectAnswer));
        });
    }

    [Fact]
    public async Task SemanticKernelQuestionGenerator_EmptyContent_ReturnsCleanFallbackWithoutThrowing()
    {
        // Arrange
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "KEY" },
            { "AiSettings:ModelId", "gemini-3.6-flash" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var generator = new SemanticKernelQuestionGenerator(configuration);

        // Act
        var result = await generator.GenerateStudySetAsync(
            string.Empty,
            "Empty Doc",
            new List<string>(),
            targetCount: 5);

        // Assert
        Assert.NotNull(result);
        Assert.Equal("Empty Doc", result.Title);
        Assert.Empty(result.Questions);
        Assert.Contains("No readable text", result.Summary);
    }

    [Fact]
    public async Task AiController_AskTutor_WithCodeDocumentationContext_ReturnsOkWithTutorResponse()
    {
        // Arrange
        var inMemoryConfig = new Dictionary<string, string?>
        {
            { "AiSettings:ApiKey", "PLACEHOLDER_KEY" },
            { "AiSettings:ModelId", "gemini-3.6-flash" }
        };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(inMemoryConfig).Build();
        var httpClient = new HttpClient();
        var logger = NullLogger<GeminiAiService>.Instance;
        var service = new GeminiAiService(httpClient, configuration, logger);

        var controller = new AiController(service, configuration)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };

        // Act
        var actionResult = await controller.AskTutor(new AskTutorRequest(
            "explain XML code documentation tags",
            "C# Architecture"), CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(actionResult);
        var response = Assert.IsType<AskTutorResponse>(okResult.Value);
        Assert.Contains("<summary>", response.Reply);
    }

    [Fact]
    public void NoteScriptSynthesizer_WithCodeDocumentationNotes_ProducesVariedQuestionTypes()
    {
        // Arrange
        var docNotes = """
            # Code Documentation Patterns
            - C# XML documentation comments: Uses triple-slash /// syntax for IDE IntelliSense and automated OpenAPI generation.
            - Python PEP 257: Prescribes standard docstring format with triple double-quotes.
            - TSDoc: Standardizes doc comments for TypeScript codebases.
            - API Contracts: Define preconditions, postconditions, and exception types.
            """;

        // Act
        var studySet = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Documentation Module",
            docNotes,
            new List<string> { "multiple_choice", "cloze", "identification" },
            targetCount: 4);

        // Assert
        Assert.NotNull(studySet);
        Assert.True(studySet.Questions.Count >= 3);
        Assert.Contains(studySet.Questions, q => q.Type == "multiple_choice" || q.Type == "cloze" || q.Type == "identification");
    }

    [Fact]
    public void AiAgents_PublicContractsAndTypes_AreImplementedAndExposedProperly()
    {
        // Verify IAiQuestionGenerator contract
        Assert.True(typeof(IAiQuestionGenerator).IsAssignableFrom(typeof(GeminiAiService)));
        Assert.True(typeof(IAiQuestionGenerator).IsAssignableFrom(typeof(SemanticKernelQuestionGenerator)));

        // Verify IAiTutorService contract
        Assert.True(typeof(IAiTutorService).IsAssignableFrom(typeof(GeminiAiService)));

        // Verify public reflection properties
        var geminiMethods = typeof(GeminiAiService).GetMethods(BindingFlags.Public | BindingFlags.Instance);
        Assert.Contains(geminiMethods, m => m.Name == nameof(GeminiAiService.AskTutorAsync));
        Assert.Contains(geminiMethods, m => m.Name == nameof(GeminiAiService.GenerateStudySetAsync));
        Assert.Contains(geminiMethods, m => m.Name == nameof(GeminiAiService.GenerateStudySetFromImageAsync));

        var skMethods = typeof(SemanticKernelQuestionGenerator).GetMethods(BindingFlags.Public | BindingFlags.Instance);
        Assert.Contains(skMethods, m => m.Name == nameof(SemanticKernelQuestionGenerator.GenerateStudySetAsync));
        Assert.Contains(skMethods, m => m.Name == nameof(SemanticKernelQuestionGenerator.GenerateStudySetFromImageAsync));
    }
}

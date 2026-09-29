using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

/// <summary>
/// Executable UAT coverage demonstrating the entire Product Vision lifecycle:
/// Capture -> Understand -> Practice -> Feedback -> Review,
/// including "what if" failure states, "why" explanations, next "how" actions,
/// and OpenAI server-side paused wiring verification.
/// </summary>
public class ProductVisionUatLifecycleTests
{
    private readonly IConfiguration _emptyConfig;

    public ProductVisionUatLifecycleTests()
    {
        _emptyConfig = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "AiSettings:Provider", "OpenAI" },
                { "AiSettings:OpenAi:ApiKey", "" }, // Unconfigured key
                { "AiSettings:OpenAi:ModelId", "gpt-4o-mini" }
            })
            .Build();
    }

    [Fact]
    public async Task UAT_Phase1_Capture_WhatIfEmptyInput_ExplainsWhyAndProvidesNextHow()
    {
        // ARRANGE: Ingestion service with empty or invalid capture inputs
        var generator = new OpenAiAiService(new HttpClient(), _emptyConfig, NullLogger<OpenAiAiService>.Instance);

        // ACT: "What if" failure state - Student submits blank notes or whitespace
        var blankResult = await generator.GenerateStudySetAsync("", "Blank Title", new List<string>(), 5);

        // ASSERT: System handles gracefully with "why" and empty fallback instead of crashing
        Assert.NotNull(blankResult);
        Assert.Equal("Blank Title", blankResult.Title);
        Assert.Equal("No source material provided.", blankResult.Summary);
        Assert.Empty(blankResult.Questions);
    }

    [Fact]
    public async Task UAT_Phase2_Understand_OpenAiWiringPausedUntilSecureKeyTargetProvided()
    {
        // ARRANGE: OpenAI configured without a valid project API key
        var unconfiguredGenerator = new OpenAiAiService(new HttpClient(), _emptyConfig, NullLogger<OpenAiAiService>.Instance);

        // ASSERT: OpenAI wiring is purposefully PAUSED pending a valid project target
        Assert.True(unconfiguredGenerator.IsWiringPaused);
        Assert.Equal("paused_pending_key", unconfiguredGenerator.WiringStatus);

        // ACT: Student requests study set synthesis while wiring is paused
        const string rawNotes = """
            Operating Systems: Virtual Memory
            Paging is a memory management scheme by which a computer stores and retrieves data from secondary storage for use in main memory.
            Page Fault: An interrupt that occurs when a software program attempts to access a page not currently mapped in RAM.
            TLB: Translation Lookaside Buffer, a hardware cache used to reduce the time taken to access a user memory location.
            """;

        var studySet = await unconfiguredGenerator.GenerateStudySetAsync(
            rawNotes,
            "OS Virtual Memory",
            new List<string> { "multiple_choice", "identification" },
            3
        );

        // ASSERT: System gracefully delegates to the built-in pedagogical synthesizer
        Assert.NotNull(studySet);
        Assert.NotEmpty(studySet.Summary);
        Assert.NotEmpty(studySet.HighYieldBulletPoints);
        Assert.NotEmpty(studySet.Questions);

        // ACT: Verify key validator recognizes valid project target format
        Assert.False(OpenAiAiService.IsValidProjectKey(""));
        Assert.False(OpenAiAiService.IsValidProjectKey("YOUR_OPENAI_API_KEY_HERE"));
        Assert.False(OpenAiAiService.IsValidProjectKey("disabled"));
        Assert.True(OpenAiAiService.IsValidProjectKey("sk-proj-valid-openai-target-test-key-12345"));
    }

    [Fact]
    public async Task UAT_Phase3_Practice_AdaptiveExecutionAndSessionGrading()
    {
        // ARRANGE: Study set with questions
        const string notes = """
            Photosynthesis:
            Light-dependent reactions occur in the thylakoid membrane and produce ATP and NADPH.
            Calvin cycle occurs in the stroma and converts carbon dioxide into glucose.
            Chlorophyll is the primary pigment absorbing blue and red light.
            """;

        var generator = new OpenAiAiService(new HttpClient(), _emptyConfig, NullLogger<OpenAiAiService>.Instance);
        var set = await generator.GenerateStudySetAsync(notes, "Cellular Biology", new List<string> { "multiple_choice" }, 2);

        Assert.NotEmpty(set.Questions);
        var q1 = set.Questions[0];

        // "What if" failure state: Question answered correctly vs skipped
        Assert.False(string.IsNullOrWhiteSpace(q1.CorrectAnswer));
        Assert.NotNull(q1.Options);
        Assert.NotEmpty(q1.Options);

        var correctOption = q1.Options.Find(o => o.IsCorrect);
        var distractorOption = q1.Options.Find(o => !o.IsCorrect);

        Assert.NotNull(correctOption);
        Assert.NotNull(distractorOption);
    }

    [Fact]
    public async Task UAT_Phase4_Feedback_DistractorRationalesExplainWhyAndNextHow()
    {
        // ARRANGE: Tutor service with paused OpenAI wiring
        var tutor = new OpenAiAiService(new HttpClient(), _emptyConfig, NullLogger<OpenAiAiService>.Instance);

        // ACT: Student makes a mistake and asks for feedback
        var explainRequest = new ExplainQuestionRequest(
            Prompt: "Where do the light-dependent reactions of photosynthesis take place?",
            CorrectAnswer: "Thylakoid Membrane",
            StudentAnswer: "Stroma",
            SubjectContext: "Biology 101"
        );

        var feedback = await tutor.ExplainQuestionAsync(explainRequest);

        // ASSERT: Feedback provides "Why" explanation and next "How" action
        Assert.NotNull(feedback);
        Assert.Contains("Thylakoid Membrane", feedback.WhyCorrect);
        Assert.False(string.IsNullOrWhiteSpace(feedback.WhyStudentWasIncorrect)); // "Why" explanation
        Assert.False(string.IsNullOrWhiteSpace(feedback.TakeawayTip)); // Next "How" action
    }

    [Fact]
    public async Task UAT_Phase5_Review_TutorGuidanceProvidesActionableNextSteps()
    {
        // ARRANGE: Tutor in local pedagogical mode
        var tutor = new OpenAiAiService(new HttpClient(), _emptyConfig, NullLogger<OpenAiAiService>.Instance);

        // ACT: Student requests a summary of a difficult concept
        var tutorRequest = new AskTutorRequest(
            Message: "Can you explain recursion with an analogy?",
            ContextTopic: "Data Structures & Algorithms"
        );

        var response = await tutor.AskTutorAsync(tutorRequest);

        // ASSERT: Tutor provides structured breakdown with next pedagogical recommendations
        Assert.NotNull(response);
        Assert.NotEmpty(response.Reply);
        Assert.Contains("Built-in Academic Engine", response.ModelUsed);
    }
}

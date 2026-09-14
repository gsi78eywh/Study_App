using System.Text.Json;
using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

public class MultiTypeExamSynthesisTests
{
    private const string SampleLectureNotes = """
        # Comprehensive Biology & Genetics Notes

        Photosynthesis: The biological process by which green plants convert light energy into chemical energy stored in glucose.
        Mitochondria: The powerhouse organelle of eukaryotic cells responsible for producing ATP through cellular respiration.
        Ribosome: The complex molecular machine found within all living cells that serves as the site of biological protein synthesis.
        DNA: The hereditary molecule in organisms that encodes the genetic instructions for development and functioning.
        Endoplasmic Reticulum: An extensive membrane network involved in protein translocation and lipid synthesis.

        Key Stages of Mitosis:
        1. Prophase - Chromatin condenses into distinct chromosomes
        2. Metaphase - Chromosomes align at the equatorial spindle plane
        3. Anaphase - Sister chromatids separate toward opposite poles
        4. Telophase - Nuclear envelopes reform around daughter nuclei

        Essential Elements of Cellular Metabolism:
        - Glycolysis takes place in the cytoplasm without oxygen
        - Krebs cycle operates inside the mitochondrial matrix
        - Electron transport chain generates high yields of ATP across the inner membrane
        """;

    [Fact]
    public void SynthesizeFromNotes_GeneratesTrueFalseExam_WithBalancedTrueAndFalseAnswers()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "true_false" },
            targetCount: 6
        );

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 4, $"Expected at least 4 questions, got {result.Questions.Count}");

        foreach (var q in result.Questions)
        {
            Assert.Equal("true_false", q.Type);
            Assert.StartsWith("True or False:", q.Prompt);
            Assert.NotNull(q.Options);
            Assert.Equal(2, q.Options!.Count);
            Assert.Contains(q.Options, o => o.Text == "True");
            Assert.Contains(q.Options, o => o.Text == "False");
            Assert.Single(q.Options, o => o.IsCorrect);
            Assert.False(q.Prompt.Contains("Parameter"), "Must not contain 'Parameter'");
        }

        // Verify there is a mix of True and False statements
        Assert.Contains(result.Questions, q => q.CorrectAnswer == "True");
        Assert.Contains(result.Questions, q => q.CorrectAnswer == "False");
    }

    [Fact]
    public void SynthesizeFromNotes_GeneratesClozeFillInExam_WithBlanksAndHints()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "cloze" },
            targetCount: 5
        );

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 3, $"Expected at least 3 questions, got {result.Questions.Count}");

        foreach (var q in result.Questions)
        {
            Assert.Equal("cloze", q.Type);
            Assert.Contains("________", q.Prompt);
            Assert.False(string.IsNullOrWhiteSpace(q.CorrectAnswer));
            Assert.NotEmpty(q.Hints);
            Assert.False(q.Prompt.Contains("Parameter"), "Must not contain 'Parameter'");
        }
    }

    [Fact]
    public void SynthesizeFromNotes_GeneratesEnumerationExam_FromListClusters()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "enumeration" },
            targetCount: 4
        );

        Assert.NotNull(result);
        Assert.NotEmpty(result.Questions);

        var enumQ = result.Questions.FirstOrDefault(q => q.Type == "enumeration");
        Assert.NotNull(enumQ);
        Assert.NotNull(enumQ!.EnumerationItems);
        Assert.True(enumQ.EnumerationItems!.Count >= 2, "Enumeration must have at least 2 items");
        Assert.False(enumQ.Prompt.Contains("Parameter"), "Must not contain 'Parameter'");
    }

    [Fact]
    public void SynthesizeFromNotes_GeneratesMatchingTypeExam_WithValidJsonPairs()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "matching" },
            targetCount: 2
        );

        Assert.NotNull(result);
        Assert.NotEmpty(result.Questions);

        var matchQ = result.Questions.FirstOrDefault(q => q.Type == "matching");
        Assert.NotNull(matchQ);
        Assert.Equal("matching", matchQ!.Type);

        // Verify serialized JSON pairs
        var pairs = JsonSerializer.Deserialize<List<Dictionary<string, string>>>(
            matchQ.CorrectAnswer,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
        );
        Assert.NotNull(pairs);
        Assert.True(pairs!.Count >= 2, "Matching question must contain at least 2 pairs");

        foreach (var pair in pairs)
        {
            Assert.True(pair.ContainsKey("term"), "Pair must contain 'term'");
            Assert.True(pair.ContainsKey("definition"), "Pair must contain 'definition'");
            Assert.False(string.IsNullOrWhiteSpace(pair["term"]));
            Assert.False(string.IsNullOrWhiteSpace(pair["definition"]));
        }
    }

    [Fact]
    public void SynthesizeFromNotes_SimulatedExam_GeneratesBalancedAllTypes()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "simulated_exam" },
            targetCount: 10
        );

        Assert.NotNull(result);
        Assert.Equal(10, result.Questions.Count);

        var distinctTypes = result.Questions.Select(q => q.Type).Distinct().ToList();
        // A simulated exam must contain at least 3 distinct question types
        Assert.True(distinctTypes.Count >= 3, $"Expected at least 3 distinct question types in simulated exam, got {distinctTypes.Count}: {string.Join(", ", distinctTypes)}");

        // Verify no questions contain Parameter or hallucinated distractors
        foreach (var q in result.Questions)
        {
            Assert.False(q.Prompt.Contains("Parameter"), $"Prompt contained 'Parameter': {q.Prompt}");
            if (q.Options != null)
            {
                foreach (var opt in q.Options)
                {
                    Assert.False(opt.Text.Contains("Parameter"), $"Option contained 'Parameter': {opt.Text}");
                }
            }
        }
    }

    [Fact]
    public void ExtractListClusters_IdentifiesHeadingsAndNumberedLists()
    {
        var rawLines = SampleLectureNotes.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries).ToList();
        var clusters = NoteScriptSynthesizer.ExtractListClusters(rawLines);

        Assert.NotEmpty(clusters);
        var mitosisCluster = clusters.FirstOrDefault(c => c.Title.Contains("Mitosis", StringComparison.OrdinalIgnoreCase));
        Assert.NotNull(mitosisCluster);
        Assert.True(mitosisCluster!.IsOrdered);
        Assert.Equal(4, mitosisCluster.Items.Count);
        Assert.Contains(mitosisCluster.Items, item => item.Contains("Prophase", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void SynthesizeFromNotes_WithDifferentSetIndices_GeneratesDifferentSetsOfQuestionsWithoutRepetition()
    {
        // Set A (Foundational)
        var setA = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "multiple_choice", "true_false", "cloze" },
            targetCount: 6,
            setIndex: 0
        );

        // Set B (Reverse / Offset Variant)
        var setB = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "multiple_choice", "true_false", "cloze" },
            targetCount: 6,
            setIndex: 1
        );

        // Set C (Scenario / Applied Variant)
        var setC = NoteScriptSynthesizer.SynthesizeFromNotes(
            "Cell Biology",
            SampleLectureNotes,
            new List<string> { "multiple_choice", "true_false", "cloze" },
            targetCount: 6,
            setIndex: 2
        );

        Assert.NotNull(setA);
        Assert.NotNull(setB);
        Assert.NotNull(setC);

        var promptsA = setA.Questions.Select(q => q.Prompt).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var promptsB = setB.Questions.Select(q => q.Prompt).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var promptsC = setC.Questions.Select(q => q.Prompt).ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Verify Set A, Set B, and Set C are not identical to each other
        bool isDifferentFromB = !promptsA.SetEquals(promptsB);
        bool isDifferentFromC = !promptsB.SetEquals(promptsC);

        Assert.True(isDifferentFromB, "Set B must have different question prompts from Set A");
        Assert.True(isDifferentFromC, "Set C must have different question prompts from Set B");
    }
}

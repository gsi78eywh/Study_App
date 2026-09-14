using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.DocumentParsers;
using Xunit;

namespace StudyApp.UnitTests;

public class OcrTextCleanerTests
{
    [Fact]
    public void CleanAndReconstructText_StripsUiNoiseAndReassemblesSentences()
    {
        var rawScreenshotOcr = @"
Free
ID srv-
gsi78eywh /
upgrade your Instance
Blueprrt managed
Deploy Error
e) Auto-De
We are unable to access to your GitHub repository. For tips on
troubleshooting this issue, please visit our docs-
D Your free
Cancel
h a specific commit
ore.
";

        var cleaned = OcrTextCleaner.CleanAndReconstructText(rawScreenshotOcr);

        Assert.False(string.IsNullOrWhiteSpace(cleaned));
        // UI artifacts should be removed
        Assert.DoesNotContain("ID srv-", cleaned, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Cancel", cleaned, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("upgrade your Instance", cleaned, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Blueprrt managed", cleaned, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("e) Auto-De", cleaned, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("ore.", cleaned, StringComparison.OrdinalIgnoreCase);

        // Core text should be reassembled into a coherent sentence without broken trailing line breaks
        Assert.Contains("We are unable to access to your GitHub repository. For tips on troubleshooting this issue, please visit our docs", cleaned, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SynthesizeFromNotes_WithCleanedOcrText_DoesNotGeneratePrepositionEndedBlankQuestion()
    {
        var rawScreenshotOcr = @"
Free
ID srv-
gsi78eywh /
upgrade your Instance
Blueprrt managed
Deploy Error
e) Auto-De
We are unable to access to your GitHub repository. For tips on
troubleshooting this issue, please visit our docs-
D Your free
Cancel
h a specific commit
ore.
";

        var cleaned = OcrTextCleaner.CleanAndReconstructText(rawScreenshotOcr);
        var result = NoteScriptSynthesizer.SynthesizeFromNotes("Git Repository Troubleshooting", cleaned, new List<string> { "multiple_choice" }, 2);

        Assert.NotNull(result);
        Assert.NotNull(result.Questions);

        foreach (var q in result.Questions)
        {
            // Must not end with incomplete preposition fragments like "For tips on"
            Assert.False(q.Prompt.Contains("For tips on\"", StringComparison.OrdinalIgnoreCase), $"Prompt contained broken fragment: {q.Prompt}");
            // Must not use generic distractors like Condition
            if (q.Options != null)
            {
                Assert.DoesNotContain(q.Options, opt => opt.Text.Equals("Condition", StringComparison.OrdinalIgnoreCase));
            }
        }
    }
}

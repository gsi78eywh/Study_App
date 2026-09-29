using System.Text.RegularExpressions;
using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

public class WebIngestionAndFlashcardSynthesisTests
{
    private const string SampleCafeContent = """
        # JMT Cafe Tabon

        Overview: A highland coffee shop and cafe located in the scenic mountain barangay of Tabon in Dalaguete, Cebu.

        JMT Cafe is located at Purok 5 Tabon, Dalaguete, Cebu.
        Operating hours are from 7:00 AM to 8:00 PM daily.

        Hikers frequently pass JMT Cafe on the way to Osmeña Peak.
        To get there from Cebu City, take a south-bound bus to Dalaguete proper, then ride a habal-habal or tricycle to Purok 5 Tabon.

        Menu & Pricing:
        - Vietnamese Egg Coffee: ₱65
        - Native Hot Chocolate: ₱50
        - Spanish Latte: ₱75
        - Dalaguete Mountain Brew: ₱60
        - Pork Tocino with Garlic Rice: ₱120
        - Beef Tapa Silog: ₱130

        Specialties: Freshly brewed mountain coffee, local highland breakfast meals, and panoramic views of Dalaguete hills.
        The cafe features outdoor balcony seating overlooking the southern Cebu mountain ranges.
        """;

    [Fact]
    public void WebPageFlashcardGeneration_ExtractsRealFactsAndPrices_NotCircularPlaceholders()
    {
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "JMT Cafe Tabon",
            SampleCafeContent,
            new List<string> { "flashcard", "identification" },
            targetCount: 8
        );

        Assert.NotNull(result);
        Assert.NotEmpty(result.Questions);

        // Verify no circular questions or placeholders exist
        foreach (var q in result.Questions)
        {
            Assert.False(q.Prompt.Contains("in JMT Cafe Tabon in JMT Cafe Tabon", StringComparison.OrdinalIgnoreCase),
                $"Question must not circularly repeat the title twice: {q.Prompt}");
            Assert.False(string.Equals(q.CorrectAnswer.Trim(), "JMT Cafe Tabon", StringComparison.OrdinalIgnoreCase),
                $"Answer must not merely repeat the title: {q.CorrectAnswer}");
            Assert.DoesNotContain("Core academic principles", q.CorrectAnswer, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Core academic principles", q.Prompt, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Foundational study material", q.Explanation ?? "", StringComparison.OrdinalIgnoreCase);
        }

        // Verify factual content from the text is actually tested (prices, locations, menu items)
        bool hasPriceOrMenuFact = result.Questions.Any(q =>
            q.Prompt.Contains("₱") || q.CorrectAnswer.Contains("₱") ||
            q.Prompt.Contains("Vietnamese Egg Coffee", StringComparison.OrdinalIgnoreCase) ||
            q.CorrectAnswer.Contains("Vietnamese Egg Coffee", StringComparison.OrdinalIgnoreCase) ||
            q.Prompt.Contains("Dalaguete", StringComparison.OrdinalIgnoreCase) ||
            q.CorrectAnswer.Contains("Dalaguete", StringComparison.OrdinalIgnoreCase) ||
            q.CorrectAnswer.Contains("Purok 5", StringComparison.OrdinalIgnoreCase) ||
            q.Prompt.Contains("Osmeña Peak", StringComparison.OrdinalIgnoreCase) ||
            q.CorrectAnswer.Contains("Osmeña Peak", StringComparison.OrdinalIgnoreCase)
        );

        Assert.True(hasPriceOrMenuFact, "Generated questions must test concrete facts, prices, or locations from the web page.");
    }

    [Fact]
    public void SynthesizeFromNotes_WithRawUrlAsTitle_CleansAndGeneratesFactualItems()
    {
        // When title passed was literally "jmt-cafe-tabon.up.railway.app"
        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "jmt-cafe-tabon.up.railway.app",
            SampleCafeContent,
            new List<string> { "flashcard" },
            targetCount: 6
        );

        Assert.NotNull(result);
        Assert.NotEmpty(result.Questions);

        foreach (var q in result.Questions)
        {
            Assert.DoesNotContain("Core academic principles", q.CorrectAnswer);
            Assert.False(string.Equals(q.CorrectAnswer.Trim(), "jmt-cafe-tabon.up.railway.app", StringComparison.OrdinalIgnoreCase),
                "Correct answer must not be the raw URL hostname.");
            Assert.False(q.Prompt.Contains("jmt-cafe-tabon.up.railway.app in jmt-cafe-tabon.up.railway.app"),
                "Prompt must not contain circular URL in URL phrasing.");
        }
    }

    [Fact]
    public void ParagraphHeavyWebText_WithNoLineBreaks_DecomposesIntoSentences()
    {
        // Simulate collapsed paragraph with no newlines
        string singleLongParagraph = "JMT Cafe is located at Purok 5 Tabon, Dalaguete, Cebu. " +
            "The popular Vietnamese Egg Coffee costs ₱65 and is freshly prepared. " +
            "Hikers frequently pass JMT Cafe on the way to Osmeña Peak. " +
            "Native Hot Chocolate is priced at ₱50 per serving. " +
            "Operating hours are from 7:00 AM to 8:00 PM daily. " +
            "The cafe features outdoor balcony seating overlooking the southern Cebu mountain ranges.";

        var result = NoteScriptSynthesizer.SynthesizeFromNotes(
            "JMT Cafe",
            singleLongParagraph,
            new List<string> { "flashcard", "identification" },
            targetCount: 4
        );

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 2, $"Expected at least 2 questions from decomposed sentences, got {result.Questions.Count}");

        foreach (var q in result.Questions)
        {
            Assert.DoesNotContain("Core academic principles", q.CorrectAnswer);
            Assert.False(string.Equals(q.CorrectAnswer.Trim(), "JMT Cafe", StringComparison.OrdinalIgnoreCase));
        }
    }
}

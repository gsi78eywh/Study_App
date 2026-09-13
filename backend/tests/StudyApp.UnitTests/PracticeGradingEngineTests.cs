using System.Text.RegularExpressions;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using Xunit;

namespace StudyApp.UnitTests;

public class PracticeGradingEngineTests
{
    [Fact]
    public void McqGrading_CorrectOption_YieldsFullCredit()
    {
        var questionId = Guid.NewGuid();
        var correctOptionId = Guid.NewGuid();
        var wrongOptionId = Guid.NewGuid();

        var question = new Question
        {
            Id = questionId,
            Type = QuestionType.MultipleChoice,
            Prompt = "What is the powerhouse of the cell?",
            Options = new List<QuestionOption>
            {
                new() { Id = correctOptionId, OptionText = "Mitochondria", IsCorrect = true },
                new() { Id = wrongOptionId, OptionText = "Nucleus", IsCorrect = false }
            }
        };

        // Simulate choosing correct option
        var selectedOpt = question.Options.FirstOrDefault(o => o.Id == correctOptionId);
        var isCorrect = selectedOpt?.IsCorrect == true;
        var score = isCorrect ? 1.0m : 0.0m;

        Assert.True(isCorrect);
        Assert.Equal(1.0m, score);
    }

    [Fact]
    public void McqGrading_WrongOption_YieldsZeroCredit()
    {
        var questionId = Guid.NewGuid();
        var correctOptionId = Guid.NewGuid();
        var wrongOptionId = Guid.NewGuid();

        var question = new Question
        {
            Id = questionId,
            Type = QuestionType.MultipleChoice,
            Prompt = "What is the powerhouse of the cell?",
            Options = new List<QuestionOption>
            {
                new() { Id = correctOptionId, OptionText = "Mitochondria", IsCorrect = true },
                new() { Id = wrongOptionId, OptionText = "Nucleus", IsCorrect = false }
            }
        };

        var selectedOpt = question.Options.FirstOrDefault(o => o.Id == wrongOptionId);
        var isCorrect = selectedOpt?.IsCorrect == true;
        var score = isCorrect ? 1.0m : 0.0m;

        Assert.False(isCorrect);
        Assert.Equal(0.0m, score);
    }

    [Theory]
    [InlineData("Photosynthesis", "Photosynthesis", true)]
    [InlineData("photosynthesis", "Photosynthesis", true)] // case insensitive
    [InlineData("Photosyntheis", "Photosynthesis", true)] // minor typo within Levenshtein tolerance
    [InlineData("Respiration", "Photosynthesis", false)] // wrong answer
    public void Identification_FuzzyMatching_ValidatesStudentAnswers(string studentAnswer, string expected, bool expectedOutcome)
    {
        var isMatch = IsFuzzyMatch(studentAnswer, expected);
        Assert.Equal(expectedOutcome, isMatch);
    }

    [Fact]
    public void EnumerationGrading_UnorderedItems_GradesCorrectly()
    {
        var expected = new List<string> { "Protons", "Neutrons", "Electrons" };
        var studentInput = "Electrons, Protons, Neutrons"; // Different order

        var given = SplitItems(studentInput);
        var remaining = new List<string>(given);
        var matched = 0;

        foreach (var item in expected)
        {
            var index = remaining.FindIndex(g => IsFuzzyMatch(g, item));
            if (index >= 0)
            {
                matched++;
                remaining.RemoveAt(index);
            }
        }

        var partial = (decimal)matched / expected.Count;
        Assert.Equal(3, matched);
        Assert.Equal(1.0m, partial);
    }

    [Fact]
    public void EnumerationGrading_PartialItems_CalculatesPartialScore()
    {
        var expected = new List<string> { "Protons", "Neutrons", "Electrons" };
        var studentInput = "Protons, Electrons"; // 2 of 3

        var given = SplitItems(studentInput);
        var remaining = new List<string>(given);
        var matched = 0;

        foreach (var item in expected)
        {
            var index = remaining.FindIndex(g => IsFuzzyMatch(g, item));
            if (index >= 0)
            {
                matched++;
                remaining.RemoveAt(index);
            }
        }

        var partial = Math.Round((decimal)matched / expected.Count, 2);
        Assert.Equal(2, matched);
        Assert.Equal(0.67m, partial);
    }

    // Levenshtein helper matching PracticeController implementation
    private static bool IsFuzzyMatch(string submitted, string expected)
    {
        var a = Normalize(submitted);
        var b = Normalize(expected);
        if (a.Length == 0 || b.Length == 0) return false;
        if (a == b) return true;
        var tolerance = b.Length <= 5 ? 1 : Math.Max(2, (int)Math.Floor(b.Length * 0.18));
        return LevenshteinDistance(a, b) <= tolerance;
    }

    private static string Normalize(string value) => Regex.Replace((value ?? string.Empty).ToLowerInvariant(), @"[^\p{L}\p{N}]+", " ").Trim();

    private static List<string> SplitItems(string input) => Regex.Split(input ?? string.Empty, @"(?:\r?\n|,|;|\||\s+\d+[.)]\s*)")
        .Select(x => Regex.Replace(x, @"^\s*(?:[-*â€¢]|\d+[.)])\s*", string.Empty).Trim())
        .Where(x => x.Length > 0)
        .ToList();

    private static int LevenshteinDistance(string first, string second)
    {
        var previous = Enumerable.Range(0, second.Length + 1).ToArray();
        for (var i = 1; i <= first.Length; i++)
        {
            var current = new int[second.Length + 1];
            current[0] = i;
            for (var j = 1; j <= second.Length; j++)
            {
                current[j] = Math.Min(Math.Min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + (first[i - 1] == second[j - 1] ? 0 : 1));
            }
            previous = current;
        }
        return previous[second.Length];
    }
}

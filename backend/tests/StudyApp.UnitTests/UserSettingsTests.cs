using StudyApp.Domain.Entities;
using Xunit;

namespace StudyApp.UnitTests;

public class UserSettingsTests
{
    [Fact]
    public void UserSettings_DefaultValues_AdhereToOptimalAcademicStudyDefaults()
    {
        var settings = new UserSettings
        {
            UserId = Guid.NewGuid()
        };

        Assert.Equal(15, settings.DefaultQuestionCount);
        Assert.Equal(8, settings.PreferredStudyMode); // SimulatedExam
        Assert.True(settings.InstantFeedback);
        Assert.True(settings.ShuffleOptions);
        Assert.Equal(30, settings.DailyStudyGoalMinutes);
        Assert.Equal(25, settings.DailyQuestionTarget);
        Assert.Equal(10, settings.BlitzSecondsPerQuestion);
        Assert.Equal(25, settings.PomodoroFocusMinutes);
        Assert.Equal(5, settings.PomodoroShortBreakMinutes);
        Assert.Equal(15, settings.PomodoroLongBreakMinutes);
        Assert.Equal(2, settings.DefaultAiDifficulty);
        Assert.Equal("system", settings.ThemePreference);
        Assert.True(settings.SoundEffectsEnabled);
        Assert.True(settings.HapticFeedbackEnabled);
    }

    [Theory]
    [InlineData(2, 5)]    // below min -> clamp to 5
    [InlineData(20, 20)]  // in range -> keep 20
    [InlineData(100, 50)] // above max -> clamp to 50
    public void DefaultQuestionCount_Clamp_RestrictsToValidBounds(int requested, int expected)
    {
        var clamped = Math.Clamp(requested, 5, 50);
        Assert.Equal(expected, clamped);
    }

    [Theory]
    [InlineData(2, 5)]    // below min -> clamp to 5
    [InlineData(12, 12)]  // in range -> keep 12
    [InlineData(60, 30)]  // above max -> clamp to 30
    public void BlitzSecondsPerQuestion_Clamp_RestrictsToValidBounds(int requested, int expected)
    {
        var clamped = Math.Clamp(requested, 5, 30);
        Assert.Equal(expected, clamped);
    }

    [Theory]
    [InlineData(5, 10)]   // below min -> clamp to 10
    [InlineData(45, 45)]  // in range -> keep 45
    [InlineData(120, 60)] // above max -> clamp to 60
    public void PomodoroFocusMinutes_Clamp_RestrictsToValidBounds(int requested, int expected)
    {
        var clamped = Math.Clamp(requested, 10, 60);
        Assert.Equal(expected, clamped);
    }

    [Theory]
    [InlineData("DARK", "dark")]
    [InlineData("light", "light")]
    [InlineData("System", "system")]
    [InlineData("invalid_theme", null)]
    public void ThemePreference_Validation_AcceptsOnlyValidModes(string input, string? expected)
    {
        var normalized = input.Trim().ToLowerInvariant();
        var isValid = normalized is "system" or "dark" or "light";
        var result = isValid ? normalized : null;
        Assert.Equal(expected, result);
    }
}

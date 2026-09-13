using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Settings;
using StudyApp.Domain.Entities;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/settings")]
[Authorize]
public class SettingsController : ControllerBase
{
    private readonly IApplicationDbContext _context;

    public SettingsController(IApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<IActionResult> GetSettings(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var settings = await GetOrCreateSettingsAsync(userId.Value, cancellationToken);
        return Ok(ToDto(settings));
    }

    [HttpPut]
    public async Task<IActionResult> UpdateSettings([FromBody] UpdateUserSettingsRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var settings = await GetOrCreateSettingsAsync(userId.Value, cancellationToken);

        if (request.DefaultQuestionCount.HasValue)
        {
            settings.DefaultQuestionCount = Math.Clamp(request.DefaultQuestionCount.Value, 5, 50);
        }

        if (request.PreferredStudyMode.HasValue)
        {
            settings.PreferredStudyMode = request.PreferredStudyMode.Value;
        }

        if (request.InstantFeedback.HasValue)
        {
            settings.InstantFeedback = request.InstantFeedback.Value;
        }

        if (request.ShuffleOptions.HasValue)
        {
            settings.ShuffleOptions = request.ShuffleOptions.Value;
        }

        if (request.DailyStudyGoalMinutes.HasValue)
        {
            settings.DailyStudyGoalMinutes = Math.Clamp(request.DailyStudyGoalMinutes.Value, 5, 300);
        }

        if (request.DailyQuestionTarget.HasValue)
        {
            settings.DailyQuestionTarget = Math.Clamp(request.DailyQuestionTarget.Value, 5, 200);
        }

        if (request.BlitzSecondsPerQuestion.HasValue)
        {
            settings.BlitzSecondsPerQuestion = Math.Clamp(request.BlitzSecondsPerQuestion.Value, 5, 30);
        }

        if (request.PomodoroFocusMinutes.HasValue)
        {
            settings.PomodoroFocusMinutes = Math.Clamp(request.PomodoroFocusMinutes.Value, 10, 60);
        }

        if (request.PomodoroShortBreakMinutes.HasValue)
        {
            settings.PomodoroShortBreakMinutes = Math.Clamp(request.PomodoroShortBreakMinutes.Value, 1, 15);
        }

        if (request.PomodoroLongBreakMinutes.HasValue)
        {
            settings.PomodoroLongBreakMinutes = Math.Clamp(request.PomodoroLongBreakMinutes.Value, 5, 30);
        }

        if (request.DefaultAiDifficulty.HasValue)
        {
            settings.DefaultAiDifficulty = Math.Clamp(request.DefaultAiDifficulty.Value, 1, 3);
        }

        if (!string.IsNullOrWhiteSpace(request.PreferredQuestionTypes))
        {
            settings.PreferredQuestionTypes = request.PreferredQuestionTypes.Trim()[..Math.Min(request.PreferredQuestionTypes.Trim().Length, 200)];
        }

        if (request.SoundEffectsEnabled.HasValue)
        {
            settings.SoundEffectsEnabled = request.SoundEffectsEnabled.Value;
        }

        if (request.HapticFeedbackEnabled.HasValue)
        {
            settings.HapticFeedbackEnabled = request.HapticFeedbackEnabled.Value;
        }

        if (!string.IsNullOrWhiteSpace(request.ThemePreference))
        {
            var theme = request.ThemePreference.Trim().ToLowerInvariant();
            if (theme is "system" or "dark" or "light")
            {
                settings.ThemePreference = theme;
            }
        }

        settings.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync(cancellationToken);

        return Ok(ToDto(settings));
    }

    [HttpPost("reset")]
    public async Task<IActionResult> ResetSettings(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var settings = await GetOrCreateSettingsAsync(userId.Value, cancellationToken);

        settings.DefaultQuestionCount = 15;
        settings.PreferredStudyMode = 8;
        settings.InstantFeedback = true;
        settings.ShuffleOptions = true;
        settings.DailyStudyGoalMinutes = 30;
        settings.DailyQuestionTarget = 25;
        settings.BlitzSecondsPerQuestion = 10;
        settings.PomodoroFocusMinutes = 25;
        settings.PomodoroShortBreakMinutes = 5;
        settings.PomodoroLongBreakMinutes = 15;
        settings.DefaultAiDifficulty = 2;
        settings.PreferredQuestionTypes = "multiple_choice,identification,enumeration,cloze,true_false";
        settings.SoundEffectsEnabled = true;
        settings.HapticFeedbackEnabled = true;
        settings.ThemePreference = "system";
        settings.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(cancellationToken);
        return Ok(ToDto(settings));
    }

    private async Task<UserSettings> GetOrCreateSettingsAsync(Guid userId, CancellationToken cancellationToken)
    {
        var settings = await _context.UserSettings.FirstOrDefaultAsync(s => s.UserId == userId, cancellationToken);
        if (settings is null)
        {
            settings = new UserSettings
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                UpdatedAt = DateTime.UtcNow
            };
            _context.UserSettings.Add(settings);
            await _context.SaveChangesAsync(cancellationToken);
        }
        return settings;
    }

    private static UserSettingsDto ToDto(UserSettings s) => new(
        s.DefaultQuestionCount,
        s.PreferredStudyMode,
        s.InstantFeedback,
        s.ShuffleOptions,
        s.DailyStudyGoalMinutes,
        s.DailyQuestionTarget,
        s.BlitzSecondsPerQuestion,
        s.PomodoroFocusMinutes,
        s.PomodoroShortBreakMinutes,
        s.PomodoroLongBreakMinutes,
        s.DefaultAiDifficulty,
        s.PreferredQuestionTypes,
        s.SoundEffectsEnabled,
        s.HapticFeedbackEnabled,
        s.ThemePreference,
        s.UpdatedAt
    );

    private Guid? GetUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;
}

namespace StudyApp.Application.DTOs.Settings;

public record UserSettingsDto(
    int DefaultQuestionCount,
    int PreferredStudyMode,
    bool InstantFeedback,
    bool ShuffleOptions,
    int DailyStudyGoalMinutes,
    int DailyQuestionTarget,
    int BlitzSecondsPerQuestion,
    int PomodoroFocusMinutes,
    int PomodoroShortBreakMinutes,
    int PomodoroLongBreakMinutes,
    int DefaultAiDifficulty,
    string PreferredQuestionTypes,
    bool SoundEffectsEnabled,
    bool HapticFeedbackEnabled,
    string ThemePreference,
    DateTime UpdatedAt
);

public record UpdateUserSettingsRequest(
    int? DefaultQuestionCount,
    int? PreferredStudyMode,
    bool? InstantFeedback,
    bool? ShuffleOptions,
    int? DailyStudyGoalMinutes,
    int? DailyQuestionTarget,
    int? BlitzSecondsPerQuestion,
    int? PomodoroFocusMinutes,
    int? PomodoroShortBreakMinutes,
    int? PomodoroLongBreakMinutes,
    int? DefaultAiDifficulty,
    string? PreferredQuestionTypes,
    bool? SoundEffectsEnabled,
    bool? HapticFeedbackEnabled,
    string? ThemePreference
);

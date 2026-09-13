namespace StudyApp.Domain.Entities;

public class UserSettings
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User? User { get; set; }

    // Study & Quiz Configurations
    public int DefaultQuestionCount { get; set; } = 15;
    public int PreferredStudyMode { get; set; } = 8; // 8: SimulatedExam, 2: MultipleChoice, 1: Flashcards, 13: RapidFire
    public bool InstantFeedback { get; set; } = true;
    public bool ShuffleOptions { get; set; } = true;
    public int DailyStudyGoalMinutes { get; set; } = 30;
    public int DailyQuestionTarget { get; set; } = 25;

    // Timer & Focus Configurations
    public int BlitzSecondsPerQuestion { get; set; } = 10; // 5 to 30s
    public int PomodoroFocusMinutes { get; set; } = 25;
    public int PomodoroShortBreakMinutes { get; set; } = 5;
    public int PomodoroLongBreakMinutes { get; set; } = 15;

    // AI Curriculum Defaults
    public int DefaultAiDifficulty { get; set; } = 2; // 1: Easy, 2: Medium, 3: Hard
    public string PreferredQuestionTypes { get; set; } = "multiple_choice,identification,enumeration,cloze,true_false";

    // UX & Accessibility
    public bool SoundEffectsEnabled { get; set; } = true;
    public bool HapticFeedbackEnabled { get; set; } = true;
    public string ThemePreference { get; set; } = "system"; // "system", "dark", "light"

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

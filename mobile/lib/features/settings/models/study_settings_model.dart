class StudySettingsModel {
  final int defaultQuestionCount;
  final int preferredStudyMode;
  final bool instantFeedback;
  final bool shuffleOptions;
  final int dailyStudyGoalMinutes;
  final int dailyQuestionTarget;
  final int blitzSecondsPerQuestion;
  final int pomodoroFocusMinutes;
  final int pomodoroShortBreakMinutes;
  final int pomodoroLongBreakMinutes;
  final int defaultAiDifficulty;
  final String preferredQuestionTypes;
  final bool soundEffectsEnabled;
  final bool hapticFeedbackEnabled;
  final String themePreference;

  const StudySettingsModel({
    this.defaultQuestionCount = 15,
    this.preferredStudyMode = 8, // StudyModeValue.simulatedExam
    this.instantFeedback = true,
    this.shuffleOptions = true,
    this.dailyStudyGoalMinutes = 30,
    this.dailyQuestionTarget = 25,
    this.blitzSecondsPerQuestion = 10,
    this.pomodoroFocusMinutes = 25,
    this.pomodoroShortBreakMinutes = 5,
    this.pomodoroLongBreakMinutes = 15,
    this.defaultAiDifficulty = 2,
    this.preferredQuestionTypes = "multiple_choice,identification,enumeration,cloze,true_false",
    this.soundEffectsEnabled = true,
    this.hapticFeedbackEnabled = true,
    this.themePreference = "system",
  });

  factory StudySettingsModel.defaultSettings() => const StudySettingsModel();

  factory StudySettingsModel.fromJson(Map<String, dynamic> json) {
    return StudySettingsModel(
      defaultQuestionCount: json["defaultQuestionCount"] as int? ?? 15,
      preferredStudyMode: json["preferredStudyMode"] as int? ?? 8,
      instantFeedback: json["instantFeedback"] as bool? ?? true,
      shuffleOptions: json["shuffleOptions"] as bool? ?? true,
      dailyStudyGoalMinutes: json["dailyStudyGoalMinutes"] as int? ?? 30,
      dailyQuestionTarget: json["dailyQuestionTarget"] as int? ?? 25,
      blitzSecondsPerQuestion: json["blitzSecondsPerQuestion"] as int? ?? 10,
      pomodoroFocusMinutes: json["pomodoroFocusMinutes"] as int? ?? 25,
      pomodoroShortBreakMinutes: json["pomodoroShortBreakMinutes"] as int? ?? 5,
      pomodoroLongBreakMinutes: json["pomodoroLongBreakMinutes"] as int? ?? 15,
      defaultAiDifficulty: json["defaultAiDifficulty"] as int? ?? 2,
      preferredQuestionTypes: json["preferredQuestionTypes"] as String? ?? "multiple_choice,identification,enumeration,cloze,true_false",
      soundEffectsEnabled: json["soundEffectsEnabled"] as bool? ?? true,
      hapticFeedbackEnabled: json["hapticFeedbackEnabled"] as bool? ?? true,
      themePreference: json["themePreference"] as String? ?? "system",
    );
  }

  Map<String, dynamic> toJson() => {
    "defaultQuestionCount": defaultQuestionCount,
    "preferredStudyMode": preferredStudyMode,
    "instantFeedback": instantFeedback,
    "shuffleOptions": shuffleOptions,
    "dailyStudyGoalMinutes": dailyStudyGoalMinutes,
    "dailyQuestionTarget": dailyQuestionTarget,
    "blitzSecondsPerQuestion": blitzSecondsPerQuestion,
    "pomodoroFocusMinutes": pomodoroFocusMinutes,
    "pomodoroShortBreakMinutes": pomodoroShortBreakMinutes,
    "pomodoroLongBreakMinutes": pomodoroLongBreakMinutes,
    "defaultAiDifficulty": defaultAiDifficulty,
    "preferredQuestionTypes": preferredQuestionTypes,
    "soundEffectsEnabled": soundEffectsEnabled,
    "hapticFeedbackEnabled": hapticFeedbackEnabled,
    "themePreference": themePreference,
  };

  StudySettingsModel copyWith({
    int? defaultQuestionCount,
    int? preferredStudyMode,
    bool? instantFeedback,
    bool? shuffleOptions,
    int? dailyStudyGoalMinutes,
    int? dailyQuestionTarget,
    int? blitzSecondsPerQuestion,
    int? pomodoroFocusMinutes,
    int? pomodoroShortBreakMinutes,
    int? pomodoroLongBreakMinutes,
    int? defaultAiDifficulty,
    String? preferredQuestionTypes,
    bool? soundEffectsEnabled,
    bool? hapticFeedbackEnabled,
    String? themePreference,
  }) {
    return StudySettingsModel(
      defaultQuestionCount: defaultQuestionCount ?? this.defaultQuestionCount,
      preferredStudyMode: preferredStudyMode ?? this.preferredStudyMode,
      instantFeedback: instantFeedback ?? this.instantFeedback,
      shuffleOptions: shuffleOptions ?? this.shuffleOptions,
      dailyStudyGoalMinutes: dailyStudyGoalMinutes ?? this.dailyStudyGoalMinutes,
      dailyQuestionTarget: dailyQuestionTarget ?? this.dailyQuestionTarget,
      blitzSecondsPerQuestion: blitzSecondsPerQuestion ?? this.blitzSecondsPerQuestion,
      pomodoroFocusMinutes: pomodoroFocusMinutes ?? this.pomodoroFocusMinutes,
      pomodoroShortBreakMinutes: pomodoroShortBreakMinutes ?? this.pomodoroShortBreakMinutes,
      pomodoroLongBreakMinutes: pomodoroLongBreakMinutes ?? this.pomodoroLongBreakMinutes,
      defaultAiDifficulty: defaultAiDifficulty ?? this.defaultAiDifficulty,
      preferredQuestionTypes: preferredQuestionTypes ?? this.preferredQuestionTypes,
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      hapticFeedbackEnabled: hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
      themePreference: themePreference ?? this.themePreference,
    );
  }
}

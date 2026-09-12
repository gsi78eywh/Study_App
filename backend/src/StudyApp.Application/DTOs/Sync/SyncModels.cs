namespace StudyApp.Application.DTOs.Sync;

public record SyncPushRequest(
    DateTime LastSyncedAt,
    List<SyncCourseDto> Courses,
    List<SyncStudySetDto> StudySets,
    List<SyncQuestionDto> Questions,
    List<SyncTestSessionDto> TestSessions
);

public record SyncCourseDto(Guid Id, string Code, string Name, string ColorHex, DateTime UpdatedAt, bool IsDeleted);
public record SyncStudySetDto(Guid Id, Guid CourseId, string Title, string Description, DateTime UpdatedAt, bool IsDeleted);
public record SyncQuestionDto(Guid Id, Guid StudySetId, int Type, string Prompt, string HintsJson, string Explanation, int Difficulty, int SortOrder);
public record SyncTestSessionDto(Guid Id, Guid StudySetId, int Mode, int Score, int TotalQuestions, int TimeSpentSeconds, DateTime CompletedAt);

public record SyncPullResponse(
    DateTime ServerTimestamp,
    List<SyncCourseDto> UpdatedCourses,
    List<SyncStudySetDto> UpdatedStudySets,
    List<SyncQuestionDto> UpdatedQuestions
);

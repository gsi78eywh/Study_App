using StudyApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace StudyApp.Application.Common.Interfaces;

public interface IApplicationDbContext
{
    DbSet<User> Users { get; }
    DbSet<Course> Courses { get; }
    DbSet<StudySet> StudySets { get; }
    DbSet<Question> Questions { get; }
    DbSet<QuestionOption> QuestionOptions { get; }
    DbSet<QuestionRubric> QuestionRubrics { get; }
    DbSet<SourceDocument> SourceDocuments { get; }
    DbSet<NotebookPage> NotebookPages { get; }
    DbSet<TestSession> TestSessions { get; }
    DbSet<SessionAnswer> SessionAnswers { get; }
    DbSet<UserSettings> UserSettings { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

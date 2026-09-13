using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;

namespace StudyApp.Infrastructure.Data;

public class ApplicationDbContext : DbContext, IApplicationDbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Course> Courses => Set<Course>();
    public DbSet<StudySet> StudySets => Set<StudySet>();
    public DbSet<Question> Questions => Set<Question>();
    public DbSet<QuestionOption> QuestionOptions => Set<QuestionOption>();
    public DbSet<QuestionRubric> QuestionRubrics => Set<QuestionRubric>();
    public DbSet<SourceDocument> SourceDocuments => Set<SourceDocument>();
    public DbSet<NotebookPage> NotebookPages => Set<NotebookPage>();
    public DbSet<TestSession> TestSessions => Set<TestSession>();
    public DbSet<SessionAnswer> SessionAnswers => Set<SessionAnswer>();
    public DbSet<UserSettings> UserSettings => Set<UserSettings>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User unique email index
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(u => u.Email).IsUnique();
            entity.Property(u => u.Email).HasMaxLength(255).IsRequired();
            entity.Property(u => u.FullName).HasMaxLength(150).IsRequired();
        });

        // UserSettings configurations (1-to-1 with User)
        modelBuilder.Entity<UserSettings>(entity =>
        {
            entity.HasIndex(s => s.UserId).IsUnique();
            entity.HasOne(s => s.User)
                  .WithOne()
                  .HasForeignKey<UserSettings>(s => s.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Course configurations & indexes
        modelBuilder.Entity<Course>(entity =>
        {
            entity.HasIndex(c => c.UserId);
            entity.HasOne(c => c.User)
                  .WithMany(u => u.Courses)
                  .HasForeignKey(c => c.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // StudySet configurations & indexes
        modelBuilder.Entity<StudySet>(entity =>
        {
            entity.HasIndex(s => s.CourseId);
            entity.HasIndex(s => s.CreatedAt);
            entity.HasOne(s => s.Course)
                  .WithMany(c => c.StudySets)
                  .HasForeignKey(s => s.CourseId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Question configurations & composite indexes for fast sorting
        modelBuilder.Entity<Question>(entity =>
        {
            entity.HasIndex(q => q.StudySetId);
            entity.HasIndex(q => new { q.StudySetId, q.SortOrder });
            entity.HasOne(q => q.StudySet)
                  .WithMany(s => s.Questions)
                  .HasForeignKey(q => q.StudySetId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Question -> Options cascade & index
        modelBuilder.Entity<QuestionOption>(entity =>
        {
            entity.HasIndex(o => o.QuestionId);
            entity.HasOne(o => o.Question)
                  .WithMany(q => q.Options)
                  .HasForeignKey(o => o.QuestionId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Question -> Rubrics cascade & index
        modelBuilder.Entity<QuestionRubric>(entity =>
        {
            entity.HasIndex(r => r.QuestionId);
            entity.HasOne(r => r.Question)
                  .WithMany(q => q.Rubrics)
                  .HasForeignKey(r => r.QuestionId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // NotebookPage indexes
        modelBuilder.Entity<NotebookPage>(entity =>
        {
            entity.HasIndex(p => p.CourseId);
            entity.HasIndex(p => p.UpdatedAt);
            entity.HasIndex(p => new { p.CourseId, p.UpdatedAt });
        });

        // SourceDocument indexes
        modelBuilder.Entity<SourceDocument>(entity =>
        {
            entity.HasIndex(d => d.StudySetId);
        });

        // TestSession indexes
        modelBuilder.Entity<TestSession>(entity =>
        {
            entity.HasIndex(t => t.StudySetId);
            entity.HasIndex(t => t.CompletedAt);
            entity.HasIndex(t => new { t.StudySetId, t.CompletedAt });
            entity.HasIndex(t => new { t.StudySetId, t.Mode });
        });

        // SessionAnswer indexes
        modelBuilder.Entity<SessionAnswer>(entity =>
        {
            entity.HasIndex(a => a.TestSessionId);
            entity.HasIndex(a => a.QuestionId);
        });
    }
}

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

        // Course configurations
        modelBuilder.Entity<Course>(entity =>
        {
            entity.HasOne(c => c.User)
                  .WithMany(u => u.Courses)
                  .HasForeignKey(c => c.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Question -> Options cascade
        modelBuilder.Entity<QuestionOption>(entity =>
        {
            entity.HasOne(o => o.Question)
                  .WithMany(q => q.Options)
                  .HasForeignKey(o => o.QuestionId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // Question -> Rubrics cascade
        modelBuilder.Entity<QuestionRubric>(entity =>
        {
            entity.HasOne(r => r.Question)
                  .WithMany(q => q.Rubrics)
                  .HasForeignKey(r => r.QuestionId)
                  .OnDelete(DeleteBehavior.Cascade);
        });
    }
}

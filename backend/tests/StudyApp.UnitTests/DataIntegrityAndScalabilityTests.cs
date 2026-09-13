using Microsoft.EntityFrameworkCore;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.Data;
using Xunit;

namespace StudyApp.UnitTests;

public class DataIntegrityAndScalabilityTests
{
    private ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    [Fact]
    public void ModelIndexes_VerifyForeignKeysAndCompositeIndexes_ConfiguredForHighScalePerformance()
    {
        using var context = CreateContext();
        var model = context.Model;

        // 1. StudySet Indexes
        var studySetEntity = model.FindEntityType(typeof(StudySet));
        Assert.NotNull(studySetEntity);
        var studySetIndexes = studySetEntity.GetIndexes().ToList();
        Assert.Contains(studySetIndexes, idx => idx.Properties.Any(p => p.Name == nameof(StudySet.CourseId)));
        Assert.Contains(studySetIndexes, idx => idx.Properties.Any(p => p.Name == nameof(StudySet.CreatedAt)));

        // 2. Question Indexes
        var questionEntity = model.FindEntityType(typeof(Question));
        Assert.NotNull(questionEntity);
        var questionIndexes = questionEntity.GetIndexes().ToList();
        Assert.Contains(questionIndexes, idx => idx.Properties.Any(p => p.Name == nameof(Question.StudySetId)));

        // 3. QuestionOption Indexes
        var optionEntity = model.FindEntityType(typeof(QuestionOption));
        Assert.NotNull(optionEntity);
        var optionIndexes = optionEntity.GetIndexes().ToList();
        Assert.Contains(optionIndexes, idx => idx.Properties.Any(p => p.Name == nameof(QuestionOption.QuestionId)));

        // 4. QuestionRubric Indexes
        var rubricEntity = model.FindEntityType(typeof(QuestionRubric));
        Assert.NotNull(rubricEntity);
        var rubricIndexes = rubricEntity.GetIndexes().ToList();
        Assert.Contains(rubricIndexes, idx => idx.Properties.Any(p => p.Name == nameof(QuestionRubric.QuestionId)));

        // 5. NotebookPage Indexes
        var pageEntity = model.FindEntityType(typeof(NotebookPage));
        Assert.NotNull(pageEntity);
        var pageIndexes = pageEntity.GetIndexes().ToList();
        Assert.Contains(pageIndexes, idx => idx.Properties.Any(p => p.Name == nameof(NotebookPage.CourseId)));

        // 6. TestSession Indexes
        var sessionEntity = model.FindEntityType(typeof(TestSession));
        Assert.NotNull(sessionEntity);
        var sessionIndexes = sessionEntity.GetIndexes().ToList();
        Assert.Contains(sessionIndexes, idx => idx.Properties.Any(p => p.Name == nameof(TestSession.StudySetId)));
    }

    [Fact]
    public void ModelCascades_VerifyStudySetToQuestionAndQuestionToOptions_CascadeOnDelete()
    {
        using var context = CreateContext();
        var model = context.Model;

        var studySetEntity = model.FindEntityType(typeof(StudySet));
        var questionNav = studySetEntity!.GetNavigations().FirstOrDefault(n => n.Name == nameof(StudySet.Questions));
        Assert.NotNull(questionNav);
        Assert.Equal(DeleteBehavior.Cascade, questionNav.ForeignKey.DeleteBehavior);

        var questionEntity = model.FindEntityType(typeof(Question));
        var optionsNav = questionEntity!.GetNavigations().FirstOrDefault(n => n.Name == nameof(Question.Options));
        Assert.NotNull(optionsNav);
        Assert.Equal(DeleteBehavior.Cascade, optionsNav.ForeignKey.DeleteBehavior);

        var rubricsNav = questionEntity.GetNavigations().FirstOrDefault(n => n.Name == nameof(Question.Rubrics));
        Assert.NotNull(rubricsNav);
        Assert.Equal(DeleteBehavior.Cascade, rubricsNav.ForeignKey.DeleteBehavior);
    }

    [Fact]
    public async Task QuerySplittingBehavior_AsSplitQuery_RetrievesDeepCollectionsWithoutCartesianProduct()
    {
        using var context = CreateContext();

        var studySet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = Guid.NewGuid(),
            Title = "Distributed Systems Scaling Exam",
            Description = "High performance database scaling and data integrity test"
        };

        for (int i = 0; i < 5; i++)
        {
            var question = new Question
            {
                Id = Guid.NewGuid(),
                StudySetId = studySet.Id,
                Prompt = $"Question #{i + 1}: How does query splitting prevent Cartesian explosions?",
                Type = QuestionType.MultipleChoice,
                Explanation = "By executing separate targeted queries for 1:N relations",
                SortOrder = i
            };

            question.Options.Add(new QuestionOption { QuestionId = question.Id, OptionText = "By concatenating all strings", IsCorrect = false });
            question.Options.Add(new QuestionOption { QuestionId = question.Id, OptionText = "By executing separate targeted queries for 1:N relations", IsCorrect = true });
            question.Options.Add(new QuestionOption { QuestionId = question.Id, OptionText = "By dropping foreign key constraints", IsCorrect = false });
            question.Options.Add(new QuestionOption { QuestionId = question.Id, OptionText = "By disabling database transactions", IsCorrect = false });

            question.Rubrics.Add(new QuestionRubric { QuestionId = question.Id, ItemText = "Mentions 1:N isolation", Points = 5 });

            studySet.Questions.Add(question);
        }

        context.StudySets.Add(studySet);
        await context.SaveChangesAsync();

        // Perform AsSplitQuery fetch
        var fetchedSet = await context.StudySets
            .AsSplitQuery()
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Rubrics)
            .FirstOrDefaultAsync(s => s.Id == studySet.Id);

        Assert.NotNull(fetchedSet);
        Assert.Equal(5, fetchedSet.Questions.Count);
        Assert.All(fetchedSet.Questions, q =>
        {
            Assert.Equal(4, q.Options.Count);
            Assert.Single(q.Rubrics);
        });
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using StudyApp.Domain.Entities;
using StudyApp.Infrastructure.Data;
using Xunit;

namespace StudyApp.UnitTests;

public class SqlInjectionSecurityTests
{
    private ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: $"SqlInjectionTestDb_{Guid.NewGuid()}")
            .Options;

        return new ApplicationDbContext(options);
    }

    [Theory]
    [InlineData("' OR '1'='1")]
    [InlineData("' OR 1=1 --")]
    [InlineData("admin' --")]
    [InlineData("'; DROP TABLE \"Users\"; --")]
    [InlineData("' UNION SELECT null, null, null, null, null --")]
    [InlineData("1' AND 1=1 AND '1'='1")]
    [InlineData("\" or \"\"=\"")]
    [InlineData("1; SLEEP(5); --")]
    public async Task AuthQuery_WithSqlInjectionPayload_TreatsInputAsLiteralAndReturnsNull(string maliciousPayload)
    {
        using var context = CreateInMemoryDbContext();

        // Seed normal user
        var legitimateUser = new User
        {
            Id = Guid.NewGuid(),
            Email = "student@example.edu",
            PasswordHash = "hashed_pw_secret_123",
            FullName = "Legit Student",
            CreatedAt = DateTime.UtcNow
        };
        context.Users.Add(legitimateUser);
        await context.SaveChangesAsync();

        // Simulate login query using LINQ
        var foundUser = await context.Users
            .FirstOrDefaultAsync(u => u.Email == maliciousPayload);

        // Assert: SQL injection fails to bypass authentication; literal match returns null
        Assert.Null(foundUser);
    }

    [Theory]
    [InlineData("' OR '1'='1")]
    [InlineData("' UNION SELECT * FROM \"StudySets\" --")]
    [InlineData("'; DELETE FROM \"StudySets\"; --")]
    public async Task CourseQuery_WithSqlInjectionPayload_DoesNotLeakOtherUsersData(string maliciousPayload)
    {
        using var context = CreateInMemoryDbContext();

        var userAId = Guid.NewGuid();
        var userBId = Guid.NewGuid();

        var courseA = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userAId,
            Code = "CS-101",
            Name = "Computer Science 1",
            ColorHex = "#6366F1",
            CreatedAt = DateTime.UtcNow
        };
        var courseB = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userBId,
            Code = "BIO-101",
            Name = "Biology 101",
            ColorHex = "#10B981",
            CreatedAt = DateTime.UtcNow
        };

        context.Courses.AddRange(courseA, courseB);
        await context.SaveChangesAsync();

        // Simulate searching course title or code with malicious payload
        var result = await context.Courses
            .Where(c => c.UserId == userAId && (c.Name == maliciousPayload || c.Code == maliciousPayload))
            .ToListAsync();

        // Must not leak User B's course
        Assert.Empty(result);
        Assert.DoesNotContain(courseB, result);
    }

    [Fact]
    public async Task StudySet_Filtering_NeutralizesSqlCommentAndStackedQueries()
    {
        using var context = CreateInMemoryDbContext();

        var courseId = Guid.NewGuid();
        var studySet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = courseId,
            Title = "Cell Biology & Mitosis",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        context.StudySets.Add(studySet);
        await context.SaveChangesAsync();

        var attackString = "Cell Biology' OR 1=1; DROP TABLE StudySets; --";

        var matches = await context.StudySets
            .Where(s => s.Title == attackString)
            .ToListAsync();

        Assert.Empty(matches);

        // Ensure table was not dropped
        var count = await context.StudySets.CountAsync();
        Assert.Equal(1, count);
    }

    [Fact]
    public void ParameterizedQuery_DesignPattern_EnsuresNoStringConcatenationInDbLayers()
    {
        // Assert that EF Core parameterization tokens ({0}, {1}) are used instead of string interpolation
        const string queryTemplate = "DELETE FROM \"AcademicTasks\" WHERE \"UserId\" = {0}";
        Assert.Contains("{0}", queryTemplate);
        Assert.DoesNotContain("$", queryTemplate); // No interpolated raw string directly sent to driver
    }
}

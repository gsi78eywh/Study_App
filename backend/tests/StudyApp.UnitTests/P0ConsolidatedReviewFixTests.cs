using System.Net;
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using StudyApp.Api.Controllers;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Auth;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.Data;
using Xunit;

namespace StudyApp.UnitTests;

public class P0ConsolidatedReviewFixTests
{
    private class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Production";
        public string ApplicationName { get; set; } = "StudyApp";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private class TestPasswordHasher : IPasswordHasher
    {
        public string HashPassword(string password) => $"hashed_{password}";
        public bool VerifyPassword(string password, string hash) => hash == $"hashed_{password}";
    }

    private class TestJwtTokenGenerator : IJwtTokenGenerator
    {
        public (string Token, DateTime ExpiresAt) GenerateToken(User user) => ($"test_token_{user.Id}", DateTime.UtcNow.AddHours(1));
        public ClaimsPrincipal? ValidateToken(string token) => null;
    }

    private static ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: $"P0TestDb_{Guid.NewGuid():N}")
            .Options;
        return new ApplicationDbContext(options);
    }

    [Theory]
    [InlineData("https://www.youtube.com/watch?v=dQw4w9WgXcQ", true)]
    [InlineData("https://youtu.be/dQw4w9WgXcQ", true)]
    [InlineData("http://youtube.com/v/dQw4w9WgXcQ", true)]
    [InlineData("https://m.youtube.com/watch?v=123", true)]
    [InlineData("http://attacker.com/?youtube.com", false)]
    [InlineData("http://notyoutube.com/watch?v=123", false)]
    [InlineData("http://attacker.com/fake?youtu.be", false)]
    [InlineData("https://evil-youtube.com", false)]
    [InlineData("", false)]
    [InlineData("not-a-url", false)]
    public void IsYouTubeUrl_RejectsSubdomainAndParamSpoofing(string url, bool expected)
    {
        var method = typeof(IngestionController).GetMethod("IsYouTubeUrl", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        Assert.NotNull(method);
        var result = (bool)method.Invoke(null, new object[] { url })!;
        Assert.Equal(expected, result);
    }

    [Fact]
    public async Task DevController_Returns404InProduction()
    {
        using var context = CreateInMemoryDbContext();
        var hasher = new TestPasswordHasher();
        var jwt = new TestJwtTokenGenerator();
        var config = new ConfigurationBuilder().Build();
        var env = new TestHostEnvironment { EnvironmentName = "Production" };

        var controller = new DevController(context, hasher, jwt, config, env);

        var diagResult = await controller.GetDiagnostics();
        Assert.IsType<NotFoundResult>(diagResult);

        var seedResult = await controller.SeedTestUser();
        Assert.IsType<NotFoundResult>(seedResult);

        var endpointsResult = controller.GetEndpoints();
        Assert.IsType<NotFoundResult>(endpointsResult);
    }

    [Fact]
    public async Task AuthController_ForgotPassword_DoesNotReturnResetTokenInProduction()
    {
        using var context = CreateInMemoryDbContext();
        var user = new User
        {
            Email = "student@studyapp.test",
            FullName = "Jane Doe",
            PasswordHash = "hash123"
        };
        context.Users.Add(user);
        await context.SaveChangesAsync();

        var hasher = new TestPasswordHasher();
        var jwt = new TestJwtTokenGenerator();
        var config = new ConfigurationBuilder().Build();
        var env = new TestHostEnvironment { EnvironmentName = "Production" };

        var controller = new AuthController(context, hasher, jwt, config, env);

        var result = await controller.ForgotPassword(new ForgotPasswordRequest("student@studyapp.test"));
        var okResult = Assert.IsType<OkObjectResult>(result);

        // Verify resetToken property is null in production
        var json = System.Text.Json.JsonSerializer.Serialize(okResult.Value);
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        Assert.True(doc.RootElement.TryGetProperty("resetToken", out var resetTokenProp));
        Assert.Equal(System.Text.Json.JsonValueKind.Null, resetTokenProp.ValueKind);
    }

    [Fact]
    public async Task AuthController_OAuthLogin_RejectsAppleProviderWithDisabledMessage()
    {
        using var context = CreateInMemoryDbContext();
        var hasher = new TestPasswordHasher();
        var jwt = new TestJwtTokenGenerator();
        var config = new ConfigurationBuilder().Build();
        var env = new TestHostEnvironment { EnvironmentName = "Development" };

        var controller = new AuthController(context, hasher, jwt, config, env);

        var result = await controller.OAuthLogin(new OAuthLoginRequest("apple", "apple_token", "student@apple.com", "Apple User"));
        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        var json = System.Text.Json.JsonSerializer.Serialize(badRequest.Value);
        Assert.Contains("not enabled", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void IngestionController_ScanAndScanUrl_DoNotAllowAnonymous()
    {
        var scanMethod = typeof(IngestionController).GetMethod("ScanDocumentContent");
        Assert.NotNull(scanMethod);
        var scanAnonAttr = scanMethod.GetCustomAttribute<AllowAnonymousAttribute>();
        Assert.Null(scanAnonAttr); // Must not allow anonymous access

        var scanUrlMethod = typeof(IngestionController).GetMethod("ScanUrl");
        Assert.NotNull(scanUrlMethod);
        var scanUrlAnonAttr = scanUrlMethod.GetCustomAttribute<AllowAnonymousAttribute>();
        Assert.Null(scanUrlAnonAttr); // Must not allow anonymous access
    }

    [Fact]
    public async Task ExportStudySet_RejectsStudySetOwnedByAnotherUser()
    {
        using var context = CreateInMemoryDbContext();
        var userA = new User { Email = "userA@test.com", FullName = "User A" };
        var userB = new User { Email = "userB@test.com", FullName = "User B" };
        context.Users.AddRange(userA, userB);

        var courseA = new Course { UserId = userA.Id, Code = "CS101", Name = "Intro CS" };
        context.Courses.Add(courseA);

        var studySetA = new StudySet { CourseId = courseA.Id, Course = courseA, Title = "Algorithms" };
        context.StudySets.Add(studySetA);
        await context.SaveChangesAsync();

        var controller = new IngestionController(null!, null!, context);

        // Authenticate controller as User B
        var claims = new[] { new Claim(ClaimTypes.NameIdentifier, userB.Id.ToString()) };
        var identity = new ClaimsIdentity(claims, "TestAuth");
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };

        var result = await controller.ExportStudySet(studySetA.Id);
        Assert.IsType<NotFoundObjectResult>(result);
    }
}

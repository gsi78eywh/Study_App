using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using StudyApp.Api.Controllers;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Auth;
using StudyApp.Domain.Entities;
using StudyApp.Infrastructure.Data;
using Xunit;

namespace StudyApp.UnitTests;

/// <summary>
/// Guards against account takeover through the Google sign-in endpoint.
/// Background: an unfinished change accepted "google-direct:anyone@mail.com" and
/// "dev-google:anyone@mail.com" in every environment, letting anyone log in as any
/// student by typing their email. These tests keep that hole closed.
/// </summary>
public class GoogleAuthBypassSecurityTests
{
    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Production;
        public string ApplicationName { get; set; } = "StudyApp";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class TestPasswordHasher : IPasswordHasher
    {
        public string HashPassword(string password) => $"hashed_{password}";
        public bool VerifyPassword(string password, string hash) => hash == $"hashed_{password}";
    }

    private sealed class TestJwtTokenGenerator : IJwtTokenGenerator
    {
        public (string Token, DateTime ExpiresAt) GenerateToken(User user) => ($"token_{user.Id}", DateTime.UtcNow.AddHours(1));
        public ClaimsPrincipal? ValidateToken(string token) => null;
    }

    private static ApplicationDbContext NewDb() =>
        new(new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"GoogleAuthSec_{Guid.NewGuid():N}")
            .Options);

    private static AuthController NewController(ApplicationDbContext db, string environment, string? clientId = null)
    {
        var configValues = new Dictionary<string, string?>();
        if (clientId != null)
        {
            configValues["Authentication:Google:ClientId"] = clientId;
        }

        var config = new ConfigurationBuilder().AddInMemoryCollection(configValues).Build();
        return new AuthController(db, new TestPasswordHasher(), new TestJwtTokenGenerator(), config,
            new TestHostEnvironment { EnvironmentName = environment });
    }

    private static async Task<User> SeedVictim(ApplicationDbContext db)
    {
        var victim = new User { Email = "victim@school.edu", FullName = "Victim Student", PasswordHash = "hashed_Secret123!" };
        db.Users.Add(victim);
        await db.SaveChangesAsync();
        return victim;
    }

    [Theory]
    [InlineData("dev-google:victim@school.edu|Attacker")]
    [InlineData("DEV-GOOGLE:victim@school.edu")]
    [InlineData("google-direct:victim@school.edu")]
    [InlineData("victim@school.edu")]
    public async Task Production_RejectsEmailOnlyGoogleTokens(string forgedToken)
    {
        using var db = NewDb();
        await SeedVictim(db);
        var controller = NewController(db, Environments.Production, clientId: "real-client-id.apps.googleusercontent.com");

        var result = await controller.GoogleLogin(new GoogleLoginRequest(forgedToken));

        Assert.IsNotType<OkObjectResult>(result);
        Assert.IsType<UnauthorizedObjectResult>(result);
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public async Task NonDevelopment_DevTokenNeverCreatesAccounts(string environment)
    {
        using var db = NewDb();
        var controller = NewController(db, environment, clientId: "real-client-id.apps.googleusercontent.com");

        var result = await controller.GoogleLogin(new GoogleLoginRequest("dev-google:newperson@gmail.com|New"));

        Assert.IsNotType<OkObjectResult>(result);
        Assert.Equal(0, await db.Users.CountAsync());
    }

    [Fact]
    public async Task Production_WithoutClientId_RefusesInsteadOfAcceptingAnyToken()
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Production);

        var result = await controller.GoogleLogin(new GoogleLoginRequest("eyJhbGciOi.fake.jwt"));

        var status = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, status.StatusCode);
        Assert.Equal(0, await db.Users.CountAsync());
    }

    [Fact]
    public async Task Production_GarbageJwt_IsUnauthorized()
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Production, clientId: "real-client-id.apps.googleusercontent.com");

        var result = await controller.GoogleLogin(new GoogleLoginRequest("not.a.realjwt"));

        Assert.IsType<UnauthorizedObjectResult>(result);
    }

    [Fact]
    public async Task Development_DevToken_SignsInWithoutWritingFakeGoogleSubject()
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Development);

        var result = await controller.GoogleLogin(new GoogleLoginRequest("dev-google:Local.Dev@Gmail.com|Local Dev"));

        var ok = Assert.IsType<OkObjectResult>(result);
        var auth = Assert.IsType<AuthResponse>(ok.Value);
        Assert.Equal("local.dev@gmail.com", auth.Email);

        var stored = await db.Users.SingleAsync();
        Assert.Null(stored.GoogleSubject);
    }

    [Theory]
    [InlineData("dev-google:not-an-email")]
    [InlineData("dev-google:")]
    [InlineData("dev-google:|Name Only")]
    public async Task Development_DevToken_ValidatesEmail(string token)
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Development);

        var result = await controller.GoogleLogin(new GoogleLoginRequest(token));

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task Development_DevToken_TruncatesOversizedName()
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Development);

        var result = await controller.GoogleLogin(new GoogleLoginRequest($"dev-google:a@b.com|{new string('x', 500)}"));

        Assert.IsType<OkObjectResult>(result);
        var stored = await db.Users.SingleAsync();
        Assert.True(stored.FullName.Length <= 150);
    }

    [Theory]
    [InlineData("mock_token")]
    [InlineData("oauth_verified_token_123")]
    public async Task Production_OAuthMockTokens_AreNotAccepted(string mockToken)
    {
        using var db = NewDb();
        await SeedVictim(db);
        var controller = NewController(db, Environments.Production, clientId: "real-client-id.apps.googleusercontent.com");

        var result = await controller.OAuthLogin(new OAuthLoginRequest("google", mockToken, "victim@school.edu", "Attacker"));

        Assert.IsNotType<OkObjectResult>(result);
    }

    [Fact]
    public async Task Login_WrongPassword_ReturnsGenericUnauthorized()
    {
        using var db = NewDb();
        await SeedVictim(db);
        var controller = NewController(db, Environments.Production);

        var wrongPassword = await controller.Login(new LoginRequest("victim@school.edu", "WrongPass1!"));
        var unknownUser = await controller.Login(new LoginRequest("nobody@school.edu", "WrongPass1!"));

        // Same response type and message for both, so attackers cannot enumerate accounts.
        var a = Assert.IsType<UnauthorizedObjectResult>(wrongPassword);
        var b = Assert.IsType<UnauthorizedObjectResult>(unknownUser);
        Assert.Equal(System.Text.Json.JsonSerializer.Serialize(a.Value), System.Text.Json.JsonSerializer.Serialize(b.Value));
    }

    [Theory]
    [InlineData("short")]
    [InlineData("")]
    public async Task Register_RejectsWeakPasswords(string password)
    {
        using var db = NewDb();
        var controller = NewController(db, Environments.Production);

        var result = await controller.Register(new RegisterRequest("new@school.edu", password, "New Student"));

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, await db.Users.CountAsync());
    }
}

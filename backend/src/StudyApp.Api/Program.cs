using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.DocumentParsers;
using StudyApp.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

// Configure port: default to http://localhost:5000
builder.WebHost.UseUrls("http://localhost:5000");

// 1. Add DbContext with SQLite local fallback support
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=studyapp.db";

builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    if (connectionString.Contains("Data Source=", StringComparison.OrdinalIgnoreCase) || connectionString.EndsWith(".db", StringComparison.OrdinalIgnoreCase))
    {
        options.UseSqlite(connectionString);
    }
    else
    {
        // Try PostgreSQL, or fallback to SQLite if PostgreSQL server is not running
        try
        {
            using var tcpClient = new System.Net.Sockets.TcpClient();
            var connectTask = tcpClient.ConnectAsync("127.0.0.1", 5432);
            if (connectTask.Wait(1000) && tcpClient.Connected)
            {
                options.UseNpgsql(connectionString);
                return;
            }
        }
        catch { }

        Console.WriteLine("[Database] PostgreSQL server on 127.0.0.1:5432 not reachable. Using local SQLite studyapp.db database.");
        options.UseSqlite("Data Source=studyapp.db");
    }
});

builder.Services.AddScoped<IApplicationDbContext>(provider =>
    provider.GetRequiredService<ApplicationDbContext>());

// 2. Add Auth Services
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();

// 3. Add AI & Ingestion Services
builder.Services.AddScoped<IDocumentExtractor, DocumentExtractor>();
builder.Services.AddScoped<IAiQuestionGenerator, SemanticKernelQuestionGenerator>();

// 4. Configure JWT Authentication
var jwtSecret = builder.Configuration["JwtSettings:Secret"] ?? "SuperSecretKeyForStudyAppDevelopmentEnvironment2026!LongEnoughForHmac256";
var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret))
{
    KeyId = "studyapp-jwt-key"
};

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["JwtSettings:Issuer"] ?? "StudyApp",
            ValidAudience = builder.Configuration["JwtSettings:Audience"] ?? "StudyAppMobileClient",
            IssuerSigningKey = signingKey
        };
    });

// 5. Configure CORS for Flutter Mobile App
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowMobileClient", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddControllers();

var app = builder.Build();

// Auto-migrate schema & seed demo account if needed
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher>();

    db.Database.EnsureCreated();

    if (!db.Users.Any())
    {
        var demoUser = new User
        {
            Id = Guid.Parse("11111111-1111-1111-1111-111111111111"),
            Email = "alex@example.com",
            FullName = "Alex Scholar",
            PasswordHash = hasher.HashPassword("Password123!"),
            CreatedAt = DateTime.UtcNow
        };
        db.Users.Add(demoUser);
        db.SaveChanges();
        Console.WriteLine("[Database] Seeded demo user: alex@example.com / Password123!");
    }
}

app.UseCors("AllowMobileClient");
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

Console.WriteLine("=================================================");
Console.WriteLine("  StudyApp Backend API is running!");
Console.WriteLine("  Listening on: http://localhost:5000");
Console.WriteLine("  Demo user: alex@example.com / Password123!");
Console.WriteLine("=================================================");

app.Run();

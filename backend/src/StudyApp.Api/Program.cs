using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Diagnostics;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.DocumentParsers;
using StudyApp.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true);

// Keep Data Protection state outside the source tree. It is runtime state, not
// application source, and should not be accidentally committed with the project.
var dataProtectionDirectory = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "StudyApp",
    "data-protection-keys");
Directory.CreateDirectory(dataProtectionDirectory);
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(dataProtectionDirectory))
    .SetApplicationName("StudyApp");

// A stable development default that remains overrideable through ASPNETCORE_URLS or PORT (Railway/Render).
var port = Environment.GetEnvironmentVariable("PORT");
if (!string.IsNullOrWhiteSpace(port))
{
    builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
}
else if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_URLS")))
{
    builder.WebHost.UseUrls(builder.Configuration["Server:Urls"] ?? "http://localhost:5000");
}

// 1. Add DbContext with SQLite local fallback support
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=studyapp.db";

builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    if (connectionString.Contains("Data Source=", StringComparison.OrdinalIgnoreCase) || connectionString.EndsWith(".db", StringComparison.OrdinalIgnoreCase))
    {
        options.UseSqlite(connectionString, sqliteOptions =>
        {
            sqliteOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
        });
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
                options.UseNpgsql(connectionString, npgsqlOptions =>
                {
                    npgsqlOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
                });
                return;
            }
        }
        catch { }

        Console.WriteLine("[Database] PostgreSQL server on 127.0.0.1:5432 not reachable. Using local SQLite studyapp.db database.");
        options.UseSqlite("Data Source=studyapp.db", sqliteOptions =>
        {
            sqliteOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
        });
    }
});

builder.Services.AddScoped<IApplicationDbContext>(provider =>
    provider.GetRequiredService<ApplicationDbContext>());

// 2. Add Auth Services
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();

// 3. Add AI & Ingestion Services (Google Gemini AI Engine)
builder.Services.AddMemoryCache();
builder.Services.AddHttpClient<GeminiAiService>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(90);
});
builder.Services.AddScoped<IDocumentExtractor, DocumentExtractor>();
builder.Services.AddScoped<GeminiAiService>();
builder.Services.AddScoped<IAiQuestionGenerator>(sp => sp.GetRequiredService<GeminiAiService>());
builder.Services.AddScoped<IAiTutorService>(sp => sp.GetRequiredService<GeminiAiService>());

// 4. Configure JWT Authentication. Production must provide a stable secret
// through configuration. Development can use an ephemeral key so a known key
// is never silently deployed.
var jwtSecret = builder.Configuration["JwtSettings:Secret"];
if (string.IsNullOrWhiteSpace(jwtSecret) || jwtSecret.Length < 32)
{
    if (!builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException("JwtSettings:Secret must be configured with at least 32 characters.");
    }

    jwtSecret = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    builder.Configuration["JwtSettings:Secret"] = jwtSecret;
    Console.WriteLine("[Authentication] Using an ephemeral development JWT key. Configure JwtSettings:Secret to retain sessions across restarts.");
}
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

// 5. Configure CORS for Flutter Mobile & Web Client
var corsOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowMobileClient", policy =>
    {
        if (corsOrigins.Length == 0 || corsOrigins.Contains("*"))
        {
            policy.AllowAnyOrigin()
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        }
        else
        {
            policy.WithOrigins(corsOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        }
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "global",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 150,
                QueueLimit = 20,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("auth", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = builder.Environment.IsDevelopment() ? 500 : 10,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
            AutoReplenishment = true
        }));

    options.AddPolicy("ingestion", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = builder.Environment.IsDevelopment() ? 500 : 30,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 5,
            AutoReplenishment = true
        }));
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
    });
builder.Services.AddProblemDetails();

var app = builder.Build();

// Auto-migrate schema
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    db.Database.EnsureCreated();
    if (db.Database.IsSqlite())
    {
        db.Database.ExecuteSqlRaw("""
            CREATE TABLE IF NOT EXISTS "UserSettings" (
                "Id" TEXT NOT NULL PRIMARY KEY,
                "UserId" TEXT NOT NULL,
                "DefaultQuestionCount" INTEGER NOT NULL,
                "PreferredStudyMode" INTEGER NOT NULL,
                "InstantFeedback" INTEGER NOT NULL,
                "ShuffleOptions" INTEGER NOT NULL,
                "DailyStudyGoalMinutes" INTEGER NOT NULL,
                "DailyQuestionTarget" INTEGER NOT NULL,
                "BlitzSecondsPerQuestion" INTEGER NOT NULL,
                "PomodoroFocusMinutes" INTEGER NOT NULL,
                "PomodoroShortBreakMinutes" INTEGER NOT NULL,
                "PomodoroLongBreakMinutes" INTEGER NOT NULL,
                "DefaultAiDifficulty" INTEGER NOT NULL,
                "PreferredQuestionTypes" TEXT NOT NULL,
                "SoundEffectsEnabled" INTEGER NOT NULL,
                "HapticFeedbackEnabled" INTEGER NOT NULL,
                "ThemePreference" TEXT NOT NULL,
                "UpdatedAt" TEXT NOT NULL,
                CONSTRAINT "FK_UserSettings_Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
            );
            CREATE UNIQUE INDEX IF NOT EXISTS "IX_UserSettings_UserId" ON "UserSettings" ("UserId");
        """);

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Courses\" ADD COLUMN \"ExamDate\" TEXT NULL;");
        }
        catch { }
        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Courses\" ADD COLUMN \"ExamTitle\" TEXT NULL;");
        }
        catch { }
    }
    Console.WriteLine("[Database] Database schema verified and ready for student records.");
}

app.UseExceptionHandler(exceptionApp => exceptionApp.Run(async context =>
{
    var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var logger = context.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("UnhandledException");
    logger.LogError(exception, "Unhandled exception for {Method} {Path}", context.Request.Method, context.Request.Path);
    await Results.Problem(
        statusCode: StatusCodes.Status500InternalServerError,
        title: "An unexpected server error occurred.",
        detail: app.Environment.IsDevelopment() ? exception?.Message : null)
        .ExecuteAsync(context);
}));

app.UseCors("AllowMobileClient");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", async (ApplicationDbContext db, CancellationToken cancellationToken) =>
{
    var canConnect = await db.Database.CanConnectAsync(cancellationToken);
    return canConnect
        ? Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow })
        : Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Database unavailable.");
}).AllowAnonymous();

// Root Welcome & Health Page (so browser visits never 404)
app.MapGet("/", () => Results.Content("""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>StudyApp API - Online</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Inter', sans-serif;
            background-color: #0b1120;
            color: #f8fafc;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
        }
        .container {
            max-width: 680px;
            width: 100%;
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 24px;
            padding: 40px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }
        .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(16, 185, 129, 0.15);
            color: #10b981;
            padding: 6px 14px;
            border-radius: 9999px;
            font-size: 13px;
            font-weight: 600;
            border: 1px solid rgba(16, 185, 129, 0.4);
            margin-bottom: 20px;
        }
        .pulse {
            width: 8px;
            height: 8px;
            background: #10b981;
            border-radius: 50%;
            box-shadow: 0 0 0 rgba(16, 185, 129, 0.7);
            animation: pulse 1.8s infinite;
        }
        @keyframes pulse {
            0% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
            70% { transform: scale(1); box-shadow: 0 0 0 10px rgba(16, 185, 129, 0); }
            100% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
        }
        h1 {
            font-family: 'Outfit', sans-serif;
            font-size: 32px;
            font-weight: 700;
            color: #ffffff;
            margin-bottom: 8px;
        }
        p.subtitle {
            color: #94a3b8;
            font-size: 15px;
            line-height: 1.6;
            margin-bottom: 28px;
        }
        .btn-launch {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            background: #6366f1;
            color: #ffffff;
            text-decoration: none;
            padding: 14px 28px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 16px;
            transition: all 0.2s;
            margin-bottom: 32px;
            box-shadow: 0 4px 14px rgba(99, 102, 241, 0.4);
        }
        .btn-launch:hover {
            background: #4f46e5;
            transform: translateY(-2px);
        }
        .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
            margin-bottom: 28px;
        }
        .card {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 14px;
            padding: 18px;
        }
        .card-title {
            font-size: 12px;
            color: #94a3b8;
            text-transform: uppercase;
            font-weight: 600;
            letter-spacing: 0.05em;
            margin-bottom: 6px;
        }
        .card-value {
            font-size: 15px;
            font-weight: 600;
            color: #f8fafc;
        }
        .endpoints {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 14px;
            padding: 20px;
        }
        .endpoint-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #1e293b;
            font-size: 13px;
        }
        .endpoint-item:last-child { border-bottom: none; }
        .method {
            padding: 2px 8px;
            border-radius: 6px;
            font-weight: 700;
            font-size: 11px;
            font-family: monospace;
        }
        .post { background: rgba(99, 102, 241, 0.2); color: #818cf8; }
        .get { background: rgba(16, 185, 129, 0.2); color: #34d399; }
        .path { font-family: monospace; color: #cbd5e1; }
    </style>
</head>
<body>
    <div class="container">
        <div class="badge">
            <span class="pulse"></span>
            <span>REST API Online &amp; Healthy</span>
        </div>
        <h1>StudyApp C# Backend API</h1>
        <p class="subtitle">ASP.NET Core 10 Clean Architecture engine powering AI document ingestion, active recall quiz sessions, and cross-platform synchronization.</p>
        
        <div class="btn-launch" role="status">
            Flutter client runs separately — API base URL: http://localhost:5000
        </div>

        <div class="grid">
            <div class="card">
                <div class="card-title">Database</div>
                <div class="card-value">SQLite (studyapp.db)</div>
            </div>
            <div class="card">
                <div class="card-title">Authentication</div>
                <div class="card-value">Multi-User JWT Auth</div>
            </div>
        </div>

        <div class="endpoints">
            <div class="card-title" style="margin-bottom: 12px;">Active API Endpoints</div>
            <div class="endpoint-item">
                <span class="path">/api/v1/auth/login</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/auth/register</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/notebooks</span>
                <span class="method get">GET</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/ingestion/file</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/ingestion/text</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/sync</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/ai/tutor</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/ai/explain</span>
                <span class="method post">POST</span>
            </div>
            <div class="endpoint-item">
                <span class="path">/api/v1/ai/status</span>
                <span class="method get">GET</span>
            </div>
        </div>
    </div>
</body>
</html>
""", "text/html"));

app.MapControllers();

app.Run();

public partial class Program { }

using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Diagnostics;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Authorization;
using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.DocumentParsers;
using StudyApp.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true);

// Keep the server-side multipart contract explicit. The mobile app validates the
// same 30 MB limit before it reads a file into memory, but this is the boundary
// that protects the API when it is called directly.
builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = 30L * 1024 * 1024;
    options.ValueLengthLimit = 150_000;
});

static bool IsLocalPortAvailable(int port)
{
    try
    {
        using var listener = new System.Net.Sockets.TcpListener(IPAddress.Parse("127.0.0.1"), port);
        listener.Start();
        return true;
    }
    catch
    {
        return false;
    }
}

static string ResolvePreferredUrl(string? configuredUrl)
{
    var preferred = configuredUrl;
    if (string.IsNullOrWhiteSpace(preferred))
    {
        preferred = "http://localhost:5000";
    }

    var candidates = preferred
        .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    foreach (var candidate in candidates)
    {
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var uri) || uri.Port <= 0)
        {
            continue;
        }

        if (IsLocalPortAvailable(uri.Port))
        {
            return candidate;
        }
    }

    for (var port = 5000; port <= 5010; port++)
    {
        if (IsLocalPortAvailable(port))
        {
            return $"http://localhost:{port}";
        }
    }

    return preferred.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "http://localhost:5000";
}

static string ResolveDatabaseConnectionString(IConfiguration configuration, IHostEnvironment environment)
{
    var envDatabaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL")
        ?? Environment.GetEnvironmentVariable("POSTGRESQL_URL");

    if (!string.IsNullOrWhiteSpace(envDatabaseUrl))
    {
        if (envDatabaseUrl.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) ||
            envDatabaseUrl.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var uri = new Uri(envDatabaseUrl);
                var userInfo = uri.UserInfo.Split(':', 2);
                var username = userInfo.Length > 0 ? Uri.UnescapeDataString(userInfo[0]) : "";
                var password = userInfo.Length > 1 ? Uri.UnescapeDataString(userInfo[1]) : "";
                var host = uri.Host;
                var port = uri.Port > 0 ? uri.Port : 5432;
                var database = uri.AbsolutePath.TrimStart('/');

                return $"Host={host};Port={port};Database={database};Username={username};Password={password};SSL Mode=Require;Trust Server Certificate=true;";
            }
            catch
            {
                return envDatabaseUrl;
            }
        }
        return envDatabaseUrl;
    }

    if (!environment.IsDevelopment())
    {
        throw new InvalidOperationException("Production deployment requires DATABASE_URL or POSTGRESQL_URL PostgreSQL connection string.");
    }

    return configuration.GetConnectionString("DefaultConnection") ?? "Data Source=studyapp.db";
}

static (string Host, int Port) ExtractHostAndPort(string npgsqlConnStr)
{
    var host = "127.0.0.1";
    var port = 5432;
    var parts = npgsqlConnStr.Split(';', StringSplitOptions.RemoveEmptyEntries);
    foreach (var part in parts)
    {
        var kv = part.Split('=', 2);
        if (kv.Length == 2)
        {
            var key = kv[0].Trim().ToLowerInvariant();
            var val = kv[1].Trim();
            if (key == "host" || key == "server") host = val;
            else if (key == "port" && int.TryParse(val, out var p)) port = p;
        }
    }
    return (host, port);
}

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
    builder.WebHost.UseUrls(ResolvePreferredUrl(builder.Configuration["Server:Urls"]));
}

// 1. Add DbContext with production PostgreSQL and SQLite local fallback support
var connectionString = ResolveDatabaseConnectionString(builder.Configuration, builder.Environment);

builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    var isSqlite = connectionString.Contains("Data Source=", StringComparison.OrdinalIgnoreCase) ||
                   connectionString.EndsWith(".db", StringComparison.OrdinalIgnoreCase);

    if (isSqlite)
    {
        options.UseSqlite(connectionString, sqliteOptions =>
        {
            sqliteOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
        });
    }
    else
    {
        if (builder.Environment.IsDevelopment())
        {
            var (host, pgPort) = ExtractHostAndPort(connectionString);
            bool canConnect = false;
            try
            {
                using var tcpClient = new System.Net.Sockets.TcpClient();
                var connectTask = tcpClient.ConnectAsync(host, pgPort);
                if (connectTask.Wait(1200) && tcpClient.Connected)
                {
                    canConnect = true;
                }
            }
            catch { }

            if (canConnect)
            {
                Console.WriteLine($"[Database] Connected to PostgreSQL on {host}:{pgPort}.");
                options.UseNpgsql(connectionString, npgsqlOptions =>
                {
                    npgsqlOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
                    npgsqlOptions.EnableRetryOnFailure(3);
                });
                return;
            }

            Console.WriteLine($"[Database] PostgreSQL server on {host}:{pgPort} not reachable in dev. Using local SQLite studyapp.db.");
            options.UseSqlite("Data Source=studyapp.db", sqliteOptions =>
            {
                sqliteOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
            });
        }
        else
        {
            Console.WriteLine("[Database] Production PostgreSQL configured.");
            options.UseNpgsql(connectionString, npgsqlOptions =>
            {
                npgsqlOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
                npgsqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null);
            });
        }
    }
});

builder.Services.AddScoped<IApplicationDbContext>(provider =>
    provider.GetRequiredService<ApplicationDbContext>());

// 2. Add Auth Services
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();

// 3. Add AI & Ingestion Services (Google Gemini & OpenAI with safe paused wiring)
builder.Services.AddMemoryCache();
builder.Services.AddHttpClient<GeminiAiService>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(90);
});
builder.Services.AddHttpClient<OpenAiAiService>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(90);
});
builder.Services.AddScoped<IDocumentExtractor, DocumentExtractor>();
builder.Services.AddScoped<GeminiAiService>();
builder.Services.AddScoped<OpenAiAiService>();
builder.Services.AddScoped<AdaptiveAiService>();
builder.Services.AddScoped<IAiQuestionGenerator>(sp => sp.GetRequiredService<AdaptiveAiService>());
builder.Services.AddScoped<IAiTutorService>(sp => sp.GetRequiredService<AdaptiveAiService>());

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

// Configure Forwarded Headers for reverse proxies (Railway, Render, K8s)
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
});

// Configure Fallback Authorization Policy (all endpoints require auth unless [AllowAnonymous])
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

// 5. Configure Production CORS for Flutter Mobile & Web Clients
var configCors = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();
var envCors = Environment.GetEnvironmentVariable("CORS_ALLOWED_ORIGINS");
var envCorsList = !string.IsNullOrWhiteSpace(envCors)
    ? envCors.Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    : Array.Empty<string>();

var allCorsOrigins = configCors.Concat(envCorsList).Distinct().ToArray();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowMobileClient", policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            policy.SetIsOriginAllowed(_ => true)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        }
        else if (allCorsOrigins.Length > 0 && !allCorsOrigins.Contains("*"))
        {
            policy.WithOrigins(allCorsOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        }
        else
        {
            policy.WithOrigins("https://localhost");
        }
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
                ?? httpContext.User?.Identity?.Name
                ?? httpContext.Connection.RemoteIpAddress?.ToString()
                ?? "global",
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
        httpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? httpContext.User?.Identity?.Name
            ?? httpContext.Connection.RemoteIpAddress?.ToString()
            ?? "unknown",
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

        string[] sqliteCourseGradeCols =
        [
            "ALTER TABLE \"Courses\" ADD COLUMN \"ExamDate\" TEXT NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"ExamTitle\" TEXT NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"Units\" REAL NOT NULL DEFAULT 3.0;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"TargetGrade\" REAL NOT NULL DEFAULT 1.5;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"PrelimGrade\" REAL NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"MidtermGrade\" REAL NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"SemiFinalGrade\" REAL NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"FinalGrade\" REAL NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"PrelimWeight\" REAL NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"MidtermWeight\" REAL NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"SemiFinalWeight\" REAL NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"FinalWeight\" REAL NOT NULL DEFAULT 0.40;",
            "ALTER TABLE \"Courses\" ADD COLUMN \"GradingScale\" TEXT NOT NULL DEFAULT 'USJ-R';"
        ];
        foreach (var sql in sqliteCourseGradeCols)
        {
            try { db.Database.ExecuteSqlRaw(sql); } catch { }
        }

        try
        {
            db.Database.ExecuteSqlRaw("""
                CREATE TABLE IF NOT EXISTS "AcademicTasks" (
                    "Id" TEXT PRIMARY KEY,
                    "UserId" TEXT NOT NULL,
                    "CourseId" TEXT NULL,
                    "Title" TEXT NOT NULL,
                    "Type" TEXT NOT NULL,
                    "DueDate" TEXT NOT NULL,
                    "EstimatedDifficulty" TEXT NOT NULL,
                    "IsCompleted" INTEGER NOT NULL,
                    "ActionStepsJson" TEXT NOT NULL,
                    "CreatedAt" TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS "IX_AcademicTasks_UserId" ON "AcademicTasks" ("UserId");
            """);
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN \"GoogleSubject\" TEXT NULL;");
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN \"EmailVerified\" INTEGER NOT NULL DEFAULT 0;");
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN \"SecurityStamp\" TEXT NULL;");
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"UserSettings\" ADD COLUMN \"LowDataMode\" INTEGER DEFAULT 0;");
        }
        catch { }
    }
    else
    {
        try
        {
            db.Database.ExecuteSqlRaw("""
                CREATE TABLE IF NOT EXISTS "AcademicTasks" (
                    "Id" TEXT PRIMARY KEY,
                    "UserId" TEXT NOT NULL,
                    "CourseId" TEXT NULL,
                    "Title" TEXT NOT NULL,
                    "Type" TEXT NOT NULL,
                    "DueDate" TEXT NOT NULL,
                    "EstimatedDifficulty" TEXT NOT NULL,
                    "IsCompleted" INTEGER NOT NULL,
                    "ActionStepsJson" TEXT NOT NULL,
                    "CreatedAt" TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS "IX_AcademicTasks_UserId" ON "AcademicTasks" ("UserId");
            """);
        }
        catch { }
        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"GoogleSubject\" TEXT NULL;");
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"EmailVerified\" BOOLEAN NOT NULL DEFAULT FALSE;");
        }
        catch { }

        try
        {
            db.Database.ExecuteSqlRaw("ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"SecurityStamp\" TEXT NULL;");
        }
        catch { }

        string[] pgCourseGradeCols =
        [
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"ExamDate\" TIMESTAMPTZ NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"ExamTitle\" TEXT NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"Units\" DOUBLE PRECISION NOT NULL DEFAULT 3.0;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"TargetGrade\" DOUBLE PRECISION NOT NULL DEFAULT 1.5;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"PrelimGrade\" DOUBLE PRECISION NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"MidtermGrade\" DOUBLE PRECISION NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"SemiFinalGrade\" DOUBLE PRECISION NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"FinalGrade\" DOUBLE PRECISION NULL;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"PrelimWeight\" DOUBLE PRECISION NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"MidtermWeight\" DOUBLE PRECISION NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"SemiFinalWeight\" DOUBLE PRECISION NOT NULL DEFAULT 0.20;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"FinalWeight\" DOUBLE PRECISION NOT NULL DEFAULT 0.40;",
            "ALTER TABLE \"Courses\" ADD COLUMN IF NOT EXISTS \"GradingScale\" TEXT NOT NULL DEFAULT 'USJ-R';",
            "ALTER TABLE \"UserSettings\" ADD COLUMN IF NOT EXISTS \"LowDataMode\" BOOLEAN DEFAULT FALSE;"
        ];
        foreach (var sql in pgCourseGradeCols)
        {
            try { db.Database.ExecuteSqlRaw(sql); } catch { }
        }
    }

    Console.WriteLine("[Database] Database schema verified and ready for student records.");
}

app.UseForwardedHeaders();

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

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}

app.UseCors("AllowMobileClient");
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

// A safe health check (no stack or database details leaked)
app.MapGet("/health", async (ApplicationDbContext db, IConfiguration config, CancellationToken cancellationToken) =>
{
    var canConnect = await db.Database.CanConnectAsync(cancellationToken);
    var geminiKey = config["AiSettings:ApiKey"] ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY");
    var hasGemini = !string.IsNullOrWhiteSpace(geminiKey) && !geminiKey.Contains("YOUR_GEMINI_API_KEY") && geminiKey != "disabled" && geminiKey != "offline";
    var version = typeof(Program).Assembly.GetName().Version?.ToString() ?? "1.0.0";

    return canConnect
        ? Results.Ok(new { ok = true, status = "healthy", version = version, gemini = hasGemini, timestamp = DateTime.UtcNow })
        : Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Database unavailable.");
}).AllowAnonymous();

app.MapGet("/health/live", () => Results.Ok(new { status = "alive", timestamp = DateTime.UtcNow })).AllowAnonymous();

app.MapGet("/health/ready", async (ApplicationDbContext db, IConfiguration config, CancellationToken cancellationToken) =>
{
    var canConnect = await db.Database.CanConnectAsync(cancellationToken);
    var geminiKey = config["AiSettings:ApiKey"] ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY");
    var hasGemini = !string.IsNullOrWhiteSpace(geminiKey) && !geminiKey.Contains("YOUR_GEMINI_API_KEY") && geminiKey != "disabled" && geminiKey != "offline";

    return canConnect
        ? Results.Ok(new { ready = true, db = true, gemini = hasGemini, timestamp = DateTime.UtcNow })
        : Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Database unavailable.");
}).AllowAnonymous();

// Minimal, secure root route
app.MapGet("/", () => Results.Ok(new { status = "healthy", service = "StudyApp API" })).AllowAnonymous();

app.MapControllers();

app.Run();

public partial class Program { }

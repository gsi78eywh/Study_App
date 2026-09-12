using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
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

// 3. Add AI & Ingestion Services (Google Gemini AI Engine)
builder.Services.AddHttpClient<GeminiAiService>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(90);
});
builder.Services.AddScoped<IDocumentExtractor, DocumentExtractor>();
builder.Services.AddScoped<GeminiAiService>();
builder.Services.AddScoped<IAiQuestionGenerator>(sp => sp.GetRequiredService<GeminiAiService>());
builder.Services.AddScoped<IAiTutorService>(sp => sp.GetRequiredService<GeminiAiService>());

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

// Auto-migrate schema
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    db.Database.EnsureCreated();
    Console.WriteLine("[Database] Database schema verified and ready for student records.");
}

app.UseCors("AllowMobileClient");
app.UseAuthentication();
app.UseAuthorization();

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
        
        <a href="http://localhost:3000" class="btn-launch">
            Open Flutter Web App (Port 3000) &rarr;
        </a>

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

// Student Notebooks API
app.MapGet("/api/v1/notebooks", async (Guid? courseId, ApplicationDbContext db, ClaimsPrincipal user) =>
{
    var query = db.NotebookPages.AsQueryable();
    if (courseId.HasValue && courseId.Value != Guid.Empty)
    {
        query = query.Where(n => n.CourseId == courseId.Value);
    }
    var notes = await query.OrderByDescending(n => n.CreatedAt).ToListAsync();
    return Results.Ok(notes);
}).RequireAuthorization();

app.MapPost("/api/v1/notebooks", async (NotebookPage note, ApplicationDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(note.Title)) return Results.BadRequest(new { message = "Note title cannot be empty." });
    note.Id = Guid.NewGuid();
    note.CreatedAt = DateTime.UtcNow;
    db.NotebookPages.Add(note);
    await db.SaveChangesAsync();
    return Results.Ok(note);
}).RequireAuthorization();

app.MapControllers();

Console.WriteLine("=================================================");
Console.WriteLine("  StudyApp Backend API is running!");
Console.WriteLine("  Listening on: http://localhost:5000");
Console.WriteLine("  Ready for student authentication & sync.");
Console.WriteLine("=================================================");

app.Run();

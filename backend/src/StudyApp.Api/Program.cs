using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Infrastructure.AiServices;
using StudyApp.Infrastructure.Data;
using StudyApp.Infrastructure.DocumentParsers;
using StudyApp.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

// 1. Add PostgreSQL DbContext
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

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
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret))
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

app.UseCors("AllowMobileClient");
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

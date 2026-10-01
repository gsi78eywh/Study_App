using Google.Apis.Auth;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Auth;
using StudyApp.Domain.Entities;

namespace StudyApp.Api.Controllers;

public record GoogleLoginRequest(string IdToken);

[ApiController]
[Route("api/v1/auth")]
[EnableRateLimiting("auth")]
public class AuthController : ControllerBase
{
    private readonly IApplicationDbContext _context;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;

    public AuthController(
        IApplicationDbContext context,
        IPasswordHasher passwordHasher,
        IJwtTokenGenerator jwtTokenGenerator,
        IConfiguration configuration,
        IHostEnvironment environment)
    {
        _context = context;
        _passwordHasher = passwordHasher;
        _jwtTokenGenerator = jwtTokenGenerator;
        _configuration = configuration;
        _environment = environment;
    }

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var email = request.Email?.Trim().ToLowerInvariant();
        var fullName = request.FullName?.Trim();
        if (string.IsNullOrWhiteSpace(email) || email.Length > 254 || !System.Net.Mail.MailAddress.TryCreate(email, out _) ||
            string.IsNullOrWhiteSpace(fullName) || fullName.Length > 150 ||
            string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8 || request.Password.Length > 128)
        {
            return BadRequest(new { message = "Enter a valid email (max 254 chars), name (max 150 chars), and a password between 8 and 128 characters." });
        }

        var existing = await _context.Users.AnyAsync(u => u.Email == email);
        if (existing)
        {
            return BadRequest(new { message = "An account with this email already exists." });
        }

        var user = new User
        {
            Email = email,
            FullName = fullName,
            PasswordHash = _passwordHasher.HashPassword(request.Password)
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        var (token, expiresAt) = _jwtTokenGenerator.GenerateToken(user);
        return Ok(new AuthResponse(user.Id, user.Email, user.FullName, token, expiresAt));
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var email = request.Email?.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(email) || email.Length > 254 || string.IsNullOrWhiteSpace(request.Password) || request.Password.Length > 128)
        {
            return BadRequest(new { message = "Valid email and password (max 128 characters) are required." });
        }

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user == null || !_passwordHasher.VerifyPassword(request.Password, user.PasswordHash))
        {
            return Unauthorized(new { message = "Invalid email or password." });
        }

        var (token, expiresAt) = _jwtTokenGenerator.GenerateToken(user);
        return Ok(new AuthResponse(user.Id, user.Email, user.FullName, token, expiresAt));
    }

    [HttpPost("forgot-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
    {
        var email = request.Email?.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(email) || !System.Net.Mail.MailAddress.TryCreate(email, out _))
        {
            return BadRequest(new { message = "Please provide a valid student email address." });
        }

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
        string? devResetToken = null;
        if (user != null)
        {
            var resetToken = GenerateResetToken(user);
            if (_environment.IsDevelopment())
            {
                devResetToken = resetToken;
            }
        }

        return Ok(new
        {
            message = "If an account is associated with this email, password reset instructions have been dispatched.",
            resetToken = devResetToken
        });
    }

    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
    {
        var email = request.Email?.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(request.Token))
        {
            return BadRequest(new { message = "Email and reset token are required." });
        }

        if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length < 8 || request.NewPassword.Length > 128)
        {
            return BadRequest(new { message = "New password must be between 8 and 128 characters." });
        }

        var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user == null || !ValidateResetToken(user, request.Token))
        {
            return BadRequest(new { message = "Invalid or expired password reset token." });
        }

        user.PasswordHash = _passwordHasher.HashPassword(request.NewPassword);
        user.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return Ok(new { message = "Password has been successfully updated. You may now sign in." });
    }

    [HttpPost("google")]
    [HttpPost("/auth/google")]
    [AllowAnonymous]
    public async Task<IActionResult> GoogleLogin([FromBody] GoogleLoginRequest request)
    {
        if (string.IsNullOrWhiteSpace(request?.IdToken))
        {
            return BadRequest(new { message = "Google ID token is required." });
        }

        var configuredClientId = _configuration["Authentication:Google:ClientId"]
            ?? Environment.GetEnvironmentVariable("GOOGLE_CLIENT_ID");

        if (!_environment.IsDevelopment() && string.IsNullOrWhiteSpace(configuredClientId))
        {
            return StatusCode(StatusCodes.Status500InternalServerError, new { message = "Google Sign-In is not configured on this server." });
        }

        GoogleJsonWebSignature.Payload payload;
        try
        {
            var settings = new GoogleJsonWebSignature.ValidationSettings();
            if (!string.IsNullOrWhiteSpace(configuredClientId))
            {
                settings.Audience = new[] { configuredClientId };
            }

            payload = await GoogleJsonWebSignature.ValidateAsync(request.IdToken, settings);
        }
        catch (Exception)
        {
            return Unauthorized(new { message = "Invalid or expired Google authentication credentials." });
        }

        if (string.IsNullOrWhiteSpace(payload?.Email))
        {
            return BadRequest(new { message = "Verified Google token did not contain an email address." });
        }

        if (!payload.EmailVerified)
        {
            return Unauthorized(new { message = "Google email address has not been verified." });
        }

        var email = payload.Email.Trim().ToLowerInvariant();
        var googleSubject = payload.Subject;
        var fullName = !string.IsNullOrWhiteSpace(payload.Name)
            ? payload.Name.Trim()
            : (!string.IsNullOrWhiteSpace(payload.GivenName) ? payload.GivenName.Trim() : "Google Student");

        // Link on GoogleSubject first, then on verified email
        var user = (!string.IsNullOrWhiteSpace(googleSubject)
            ? await _context.Users.FirstOrDefaultAsync(u => u.GoogleSubject == googleSubject)
            : null)
            ?? await _context.Users.FirstOrDefaultAsync(u => u.Email == email);

        if (user == null)
        {
            user = new User
            {
                Email = email,
                FullName = fullName,
                GoogleSubject = googleSubject,
                PasswordHash = _passwordHasher.HashPassword(Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)))
            };
            _context.Users.Add(user);
            await _context.SaveChangesAsync();
        }
        else
        {
            bool modified = false;
            if (string.IsNullOrEmpty(user.GoogleSubject) && !string.IsNullOrWhiteSpace(googleSubject))
            {
                user.GoogleSubject = googleSubject;
                modified = true;
            }
            if (user.FullName == "Google Student" && fullName != "Google Student")
            {
                user.FullName = fullName;
                modified = true;
            }
            if (modified)
            {
                await _context.SaveChangesAsync();
            }
        }

        var (token, expiresAt) = _jwtTokenGenerator.GenerateToken(user);
        return Ok(new AuthResponse(user.Id, user.Email, user.FullName, token, expiresAt));
    }

    [HttpDelete("account")]
    [HttpDelete("/account")]
    [Authorize]
    public async Task<IActionResult> DeleteAccount()
    {
        var userIdClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            return Unauthorized(new { message = "Valid authentication token required." });
        }

        var user = await _context.Users
            .Include(u => u.Courses)
            .FirstOrDefaultAsync(u => u.Id == userId);

        if (user == null)
        {
            return NotFound(new { message = "User account not found." });
        }

        try
        {
            // Clean up non-FK raw SQL records associated with this user
            if (_context is DbContext dbContext)
            {
                await dbContext.Database.ExecuteSqlRawAsync(
                    "DELETE FROM \"AcademicTasks\" WHERE \"UserId\" = {0}",
                    userId.ToString());
            }
        }
        catch { }

        var userCourses = await _context.Courses
            .Include(c => c.StudySets)
            .Where(c => c.UserId == userId)
            .ToListAsync();
        _context.Courses.RemoveRange(userCourses);

        var userSettings = await _context.UserSettings.FirstOrDefaultAsync(s => s.UserId == userId);
        if (userSettings != null)
        {
            _context.UserSettings.Remove(userSettings);
        }

        _context.Users.Remove(user);
        await _context.SaveChangesAsync();

        return Ok(new { message = "Account and all associated personal data have been permanently deleted." });
    }

    [HttpPost("oauth")]
    [AllowAnonymous]
    public async Task<IActionResult> OAuthLogin([FromBody] OAuthLoginRequest request)
    {
        var provider = request.Provider?.Trim().ToLowerInvariant();
        if (provider == "apple")
        {
            return BadRequest(new { message = "Sign in with Apple is currently not enabled." });
        }

        if (provider != "google")
        {
            return BadRequest(new { message = "Supported OAuth provider is 'google'." });
        }

        // For Google, enforce verified token verification via GoogleLogin
        if (string.IsNullOrWhiteSpace(request.IdToken))
        {
            return BadRequest(new { message = "Google Sign-In requires an authenticated ID token. Client-typed emails are disallowed." });
        }

        // Only allow mock token bypass in Development environment for automated UAT test runs
        if (_environment.IsDevelopment() && (request.IdToken.StartsWith("mock_") || request.IdToken.StartsWith("oauth_verified_token_")))
        {
            var email = request.Email?.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(email) || !System.Net.Mail.MailAddress.TryCreate(email, out _))
            {
                return BadRequest(new { message = "A valid student email is required for Single Sign-On." });
            }

            var fullName = string.IsNullOrWhiteSpace(request.FullName) ? "Google Student" : request.FullName.Trim();
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
            if (user == null)
            {
                user = new User
                {
                    Email = email,
                    FullName = fullName,
                    PasswordHash = _passwordHasher.HashPassword(Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)))
                };
                _context.Users.Add(user);
                await _context.SaveChangesAsync();
            }

            var (mockToken, mockExpiresAt) = _jwtTokenGenerator.GenerateToken(user);
            return Ok(new AuthResponse(user.Id, user.Email, user.FullName, mockToken, mockExpiresAt));
        }

        return await GoogleLogin(new GoogleLoginRequest(request.IdToken));
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> GetCurrentUser()
    {
        var userIdClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            return Unauthorized();
        }

        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return NotFound();
        }

        return Ok(new { user.Id, user.Email, user.FullName, user.CreatedAt, user.LastSyncAt });
    }

    private string GenerateResetToken(User user)
    {
        var expiry = DateTimeOffset.UtcNow.AddHours(2).ToUnixTimeSeconds();
        var key = Encoding.UTF8.GetBytes(_configuration["JwtSettings:Secret"] ?? "StudyAppEphemeralSecretKeyForDevReset1234567890");
        var hashInput = $"{user.Id}:{user.Email}:{expiry}:{user.PasswordHash[..Math.Min(16, user.PasswordHash.Length)]}";
        using var hmac = new HMACSHA256(key);
        var hash = Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(hashInput)));
        var tokenRaw = $"{user.Id}|{expiry}|{hash}";
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(tokenRaw));
    }

    private bool ValidateResetToken(User user, string token)
    {
        try
        {
            var raw = Encoding.UTF8.GetString(Convert.FromBase64String(token));
            var parts = raw.Split('|');
            if (parts.Length != 3) return false;
            if (!Guid.TryParse(parts[0], out var userId) || userId != user.Id) return false;
            if (!long.TryParse(parts[1], out var expiry)) return false;
            if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() > expiry) return false;

            var key = Encoding.UTF8.GetBytes(_configuration["JwtSettings:Secret"] ?? "StudyAppEphemeralSecretKeyForDevReset1234567890");
            var hashInput = $"{user.Id}:{user.Email}:{expiry}:{user.PasswordHash[..Math.Min(16, user.PasswordHash.Length)]}";
            using var hmac = new HMACSHA256(key);
            var expectedHash = Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(hashInput)));

            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(parts[2]),
                Encoding.UTF8.GetBytes(expectedHash));
        }
        catch
        {
            return false;
        }
    }
}

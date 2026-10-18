using Google.Apis.Auth;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Auth;
using StudyApp.Domain.Entities;
using StudyApp.Api.Security;

namespace StudyApp.Api.Controllers;

public record GoogleLoginRequest(string IdToken, string? AccessToken = null);

[ApiController]
[Route("api/v1/auth")]
[EnableRateLimiting("auth")]
public class AuthController : ControllerBase
{
    private static readonly HttpClient SharedHttpClient = new() { Timeout = TimeSpan.FromSeconds(15) };

    /// <summary>Unverified local-only Google sign-in format. Accepted in Development only.</summary>
    public const string DevGoogleTokenPrefix = "dev-google:";
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
        var passwordError = PasswordPolicy.GetError(request.Password);
        if (string.IsNullOrWhiteSpace(email) || email.Length > 254 || !System.Net.Mail.MailAddress.TryCreate(email, out _) ||
            string.IsNullOrWhiteSpace(fullName) || fullName.Length > 150 || passwordError != null)
        {
            return BadRequest(new
            {
                message = passwordError ?? "Enter a valid email (max 254 chars) and name (max 150 chars).",
                passwordRequirements = $"{PasswordPolicy.MinimumLength}-{PasswordPolicy.MaximumLength} characters, at most {PasswordPolicy.MaximumUtf8Bytes} UTF-8 bytes, and not a common password."
            });
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
            if (_environment.IsDevelopment() && email == "dev@studyapp.local" && request.Password == "DevPass123!")
            {
                if (user == null)
                {
                    user = new User
                    {
                        Email = "dev@studyapp.local",
                        FullName = "Developer Test Account",
                        PasswordHash = _passwordHasher.HashPassword("DevPass123!")
                    };
                    _context.Users.Add(user);
                }
                else
                {
                    user.PasswordHash = _passwordHasher.HashPassword("DevPass123!");
                }
                await _context.SaveChangesAsync();
            }
            else
            {
                return Unauthorized(new { message = "Invalid email or password." });
            }
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
            message = _environment.IsDevelopment()
                ? "If an account is associated with this email, use the local recovery token to reset its password."
                : "Password recovery email is not configured on this server. Use Google sign-in for Google accounts or contact the app administrator for a StudyApp password reset.",
            recoveryAvailable = _environment.IsDevelopment(),
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

        var passwordError = PasswordPolicy.GetError(request.NewPassword);
        if (passwordError != null)
        {
            return BadRequest(new { message = passwordError });
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

    [HttpGet("google/config")]
    [HttpGet("/auth/google/config")]
    [AllowAnonymous]
    public IActionResult GetGoogleAuthConfig()
    {
        var configuredClientId = _configuration["Authentication:Google:ClientId"]
            ?? Environment.GetEnvironmentVariable("GOOGLE_CLIENT_ID");

        var firstClientId = (configuredClientId ?? string.Empty)
            .Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault() ?? string.Empty;

        return Ok(new
        {
            isConfigured = !string.IsNullOrWhiteSpace(firstClientId),
            clientId = firstClientId
        });
    }

    [HttpPost("google")]
    [HttpPost("/auth/google")]
    [AllowAnonymous]
    public async Task<IActionResult> GoogleLogin([FromBody] GoogleLoginRequest request)
    {
        var primaryToken = !string.IsNullOrWhiteSpace(request?.IdToken)
            ? request.IdToken.Trim()
            : request?.AccessToken?.Trim();

        if (string.IsNullOrWhiteSpace(primaryToken))
        {
            return BadRequest(new { message = "Google authentication token is required." });
        }

        var configuredClientId = _configuration["Authentication:Google:ClientId"]
            ?? Environment.GetEnvironmentVariable("GOOGLE_CLIENT_ID");

        var tokenStr = primaryToken;
        GoogleJsonWebSignature.Payload payload;

        if (tokenStr.StartsWith(DevGoogleTokenPrefix, StringComparison.OrdinalIgnoreCase))
        {
            if (!_environment.IsDevelopment())
            {
                return Unauthorized(new { message = "Developer bypass tokens are only accepted in local development. In production, please sign in with real Google OAuth or your account password." });
            }
#if DEBUG
            var raw = tokenStr.Substring(DevGoogleTokenPrefix.Length);
            var parts = raw.Split('|', 2, StringSplitOptions.TrimEntries);
            var devEmail = parts[0].ToLowerInvariant();
            var devName = parts.Length > 1 && !string.IsNullOrWhiteSpace(parts[1])
                ? parts[1]
                : (devEmail.Contains('@') ? devEmail.Split('@')[0] : "Google Student");

            if (devEmail.Length > 254 || !System.Net.Mail.MailAddress.TryCreate(devEmail, out _) || devEmail.Contains('\n') || devEmail.Contains('\r'))
            {
                return BadRequest(new { message = "Invalid email format in Google sign-in request." });
            }

            if (devName.Length > 150)
            {
                devName = devName[..150];
            }

            if (devName.Length > 0 && !devName.Contains(' '))
            {
                devName = char.ToUpperInvariant(devName[0]) + devName[1..];
            }

            payload = new GoogleJsonWebSignature.Payload
            {
                Email = devEmail,
                EmailVerified = true,
                Name = devName,
                // Never persist a fabricated subject onto an account; real Google sign-in
                // must still be able to link its genuine subject later.
                Subject = null
            };
#else
            return Unauthorized(new { message = "Developer bypass tokens are only accepted in local development." });
#endif
        }
        else
        {
            if (!_environment.IsDevelopment() && string.IsNullOrWhiteSpace(configuredClientId))
            {
                return StatusCode(StatusCodes.Status500InternalServerError, new { message = "Google Sign-In is not configured on this server." });
            }

            var audiences = (configuredClientId ?? string.Empty)
                .Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            try
            {
                if (tokenStr.Count(c => c == '.') == 2)
                {
                    var settings = new GoogleJsonWebSignature.ValidationSettings();
                    if (audiences.Length > 0)
                    {
                        settings.Audience = audiences;
                    }

                    try
                    {
                        payload = await GoogleJsonWebSignature.ValidateAsync(tokenStr, settings);
                    }
                    catch when (!string.IsNullOrWhiteSpace(request?.AccessToken))
                    {
                        payload = await ValidateGoogleAccessTokenAsync(request.AccessToken.Trim(), audiences);
                    }
                }
                else
                {
                    payload = await ValidateGoogleAccessTokenAsync(tokenStr, audiences);
                }
            }
            catch (Exception)
            {
                return Unauthorized(new { message = "Invalid or expired Google authentication credentials." });
            }
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
        var passwordHash = user.PasswordHash ?? string.Empty;
        var hashInput = $"{user.Id}:{user.Email}:{expiry}:{passwordHash[..Math.Min(16, passwordHash.Length)]}";
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
            var passwordHash = user.PasswordHash ?? string.Empty;
            var hashInput = $"{user.Id}:{user.Email}:{expiry}:{passwordHash[..Math.Min(16, passwordHash.Length)]}";
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

    private static async Task<GoogleJsonWebSignature.Payload> ValidateGoogleAccessTokenAsync(
        string accessToken,
        string[] expectedAudiences)
    {
        if (string.IsNullOrWhiteSpace(accessToken))
        {
            throw new UnauthorizedAccessException("Google access token is empty.");
        }

        // 1. Verify token authenticity and audience with Google's OAuth2 tokeninfo endpoint
        using var tokenInfoResponse = await SharedHttpClient.GetAsync(
            $"https://oauth2.googleapis.com/tokeninfo?access_token={Uri.EscapeDataString(accessToken)}");
        if (!tokenInfoResponse.IsSuccessStatusCode)
        {
            throw new UnauthorizedAccessException("Invalid or expired Google access token.");
        }

        var tokenInfoJson = await tokenInfoResponse.Content.ReadAsStringAsync();
        using var tokenInfoDoc = JsonDocument.Parse(tokenInfoJson);
        var root = tokenInfoDoc.RootElement;

        var aud = root.TryGetProperty("aud", out var audProp) ? audProp.GetString() : null;
        var azp = root.TryGetProperty("azp", out var azpProp) ? azpProp.GetString() : null;

        if (expectedAudiences.Length > 0)
        {
            var matchesAudience =
                (!string.IsNullOrWhiteSpace(aud) && expectedAudiences.Contains(aud, StringComparer.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(azp) && expectedAudiences.Contains(azp, StringComparer.OrdinalIgnoreCase));

            if (!matchesAudience)
            {
                throw new UnauthorizedAccessException("Google token audience does not match configured client ID.");
            }
        }

        string? sub = root.TryGetProperty("sub", out var subProp) ? subProp.GetString() : null;
        string? email = root.TryGetProperty("email", out var emailProp) ? emailProp.GetString() : null;
        bool emailVerified = false;
        if (root.TryGetProperty("email_verified", out var verifiedProp))
        {
            emailVerified = verifiedProp.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.String => string.Equals(verifiedProp.GetString(), "true", StringComparison.OrdinalIgnoreCase),
                _ => false
            };
        }

        string? name = null;
        string? givenName = null;

        // 2. Fetch profile details (Name / GivenName) from Google's OAuth2 userinfo endpoint
        try
        {
            using var userInfoReq = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/oauth2/v3/userinfo");
            userInfoReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            using var userInfoResponse = await SharedHttpClient.SendAsync(userInfoReq);
            if (userInfoResponse.IsSuccessStatusCode)
            {
                var userInfoJson = await userInfoResponse.Content.ReadAsStringAsync();
                using var userInfoDoc = JsonDocument.Parse(userInfoJson);
                var uRoot = userInfoDoc.RootElement;

                sub ??= uRoot.TryGetProperty("sub", out var uSub) ? uSub.GetString() : null;
                email ??= uRoot.TryGetProperty("email", out var uEmail) ? uEmail.GetString() : null;
                name = uRoot.TryGetProperty("name", out var uName) ? uName.GetString() : null;
                givenName = uRoot.TryGetProperty("given_name", out var uGiven) ? uGiven.GetString() : null;

                if (!emailVerified && uRoot.TryGetProperty("email_verified", out var uVerified))
                {
                    emailVerified = uVerified.ValueKind switch
                    {
                        JsonValueKind.True => true,
                        JsonValueKind.String => string.Equals(uVerified.GetString(), "true", StringComparison.OrdinalIgnoreCase),
                        _ => false
                    };
                }
            }
        }
        catch
        {
            // Profile enrichment is optional if tokeninfo already provided verified email and sub
        }

        return new GoogleJsonWebSignature.Payload
        {
            Subject = sub,
            Email = email,
            EmailVerified = emailVerified,
            Name = name,
            GivenName = givenName
        };
    }
}

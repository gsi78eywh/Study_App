namespace StudyApp.Application.DTOs.Auth;

public record RegisterRequest(string Email, string Password, string FullName);
public record LoginRequest(string Email, string Password);
public record AuthResponse(Guid UserId, string Email, string FullName, string Token, DateTime ExpiresAt);
public record ForgotPasswordRequest(string Email);
public record ResetPasswordRequest(string Email, string Token, string NewPassword);
public record OAuthLoginRequest(string Provider, string? IdToken, string? Email, string? FullName);

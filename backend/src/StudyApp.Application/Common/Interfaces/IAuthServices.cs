using System.Security.Claims;
using StudyApp.Domain.Entities;

namespace StudyApp.Application.Common.Interfaces;

public interface IJwtTokenGenerator
{
    (string Token, DateTime ExpiresAt) GenerateToken(User user);
    ClaimsPrincipal? ValidateToken(string token);
}

public interface IPasswordHasher
{
    string HashPassword(string password);
    bool VerifyPassword(string password, string passwordHash);
}

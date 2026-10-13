using System.Text;

namespace StudyApp.Api.Security;

/// <summary>Policy for new and reset passwords. BCrypt limits effective input to 72 UTF-8 bytes.</summary>
public static class PasswordPolicy
{
    public const int MinimumLength = 12;
    public const int MaximumLength = 128;
    public const int MaximumUtf8Bytes = 72;

    private static readonly HashSet<string> CommonPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "password123!", "password123", "password1!", "qwerty123456", "letmein12345",
        "welcome12345", "admin123456", "iloveyou123", "123456789012", "studyapp123"
    };

    public static string? GetError(string? password)
    {
        if (string.IsNullOrEmpty(password))
        {
            return "Password is required.";
        }

        if (password.Length < MinimumLength)
        {
            return $"Use at least {MinimumLength} characters.";
        }

        if (password.Length > MaximumLength)
        {
            return $"Use no more than {MaximumLength} characters.";
        }

        if (Encoding.UTF8.GetByteCount(password) > MaximumUtf8Bytes)
        {
            return "Password is too long when encoded. Use at most 72 UTF-8 bytes.";
        }

        if (CommonPasswords.Contains(password.Trim()))
        {
            return "Choose a less common password or a longer passphrase.";
        }

        return null;
    }
}

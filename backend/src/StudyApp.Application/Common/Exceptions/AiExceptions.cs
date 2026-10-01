namespace StudyApp.Application.Common.Exceptions;

public enum AiFailure
{
    NotConfigured,
    Timeout,
    RateLimited,
    Blocked,
    Unauthorized,
    BadResponse,
    Upstream
}

public sealed class AiUnavailableException : Exception
{
    public AiFailure Kind { get; }

    public AiUnavailableException(AiFailure kind, string message) : base(message)
    {
        Kind = kind;
    }

    public AiUnavailableException(AiFailure kind, string message, Exception innerException) : base(message, innerException)
    {
        Kind = kind;
    }
}

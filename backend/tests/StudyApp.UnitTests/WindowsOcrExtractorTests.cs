using StudyApp.Infrastructure.DocumentParsers;
using Xunit;

namespace StudyApp.UnitTests;

public class WindowsOcrExtractorTests
{
    [Fact]
    public async Task ExtractImageTextAsync_EmptyStream_ReturnsEmptyString()
    {
        var extractor = new DocumentExtractor();
        using var emptyStream = new MemoryStream();
        var result = await extractor.ExtractImageTextAsync(emptyStream, "image/png");
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public async Task ExtractImageTextAsync_WithUserScreenshot_ExtractsTextViaNativeWindowsOcr()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // Test with the user's uploaded sample screenshot if present
        var userScreenshotPath = @"C:\Users\SethAndreyJabagat\.gemini\antigravity-ide\brain\bf666538-0260-4588-a691-dfc70581fbd4\.user_uploaded\media_1789349862791.png";
        if (!File.Exists(userScreenshotPath))
        {
            return; // Skip if environment-specific path does not exist
        }

        var extractor = new DocumentExtractor();
        await using var stream = File.OpenRead(userScreenshotPath);
        var result = await extractor.ExtractImageTextAsync(stream, "image/png");

        Assert.False(string.IsNullOrWhiteSpace(result), "Extracted text should not be empty");
        Assert.Contains("Reinforcement Learning", result, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("exploration", result, StringComparison.OrdinalIgnoreCase);
    }
}

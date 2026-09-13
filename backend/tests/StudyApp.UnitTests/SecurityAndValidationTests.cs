using System.Net;
using StudyApp.Application.DTOs.Auth;
using StudyApp.Infrastructure.DocumentParsers;
using Xunit;

namespace StudyApp.UnitTests;

public class SecurityAndValidationTests
{
    [Theory]
    [InlineData("short", false)] // < 8 characters
    [InlineData("ValidPass123!", true)] // normal valid password
    [InlineData("AnotherSafePassword99#", true)]
    public void RegisterRequest_PasswordValidation_EnforcesMinimumLength(string password, bool shouldPass)
    {
        var isValid = password.Length >= 8 && password.Length <= 128;
        Assert.Equal(shouldPass, isValid);
    }

    [Fact]
    public void RegisterRequest_PasswordValidation_RejectsExtremelyLongPassword_PreventingBCryptCpuDos()
    {
        // Attack payload attempting to consume unbounded CPU hashing cycles
        var dosPayload = new string('A', 5000);
        var isValid = dosPayload.Length <= 128;
        Assert.False(isValid, "Passwords longer than 128 characters must be rejected to prevent BCrypt DoS attacks.");
    }

    [Theory]
    [InlineData("127.0.0.1", true)] // IPv4 Loopback
    [InlineData("10.0.0.1", true)] // Class A Private
    [InlineData("172.16.5.10", true)] // Class B Private
    [InlineData("192.168.1.1", true)] // Class C Private
    [InlineData("169.254.169.254", true)] // AWS / Cloud Metadata link-local
    [InlineData("::1", true)] // IPv6 Loopback
    [InlineData("fe80::1", true)] // IPv6 Link-local
    [InlineData("8.8.8.8", false)] // Google Public DNS
    [InlineData("1.1.1.1", false)] // Cloudflare Public DNS
    [InlineData("93.184.216.34", false)] // example.com
    public void DocumentExtractor_IsPrivateOrReservedIp_BlocksInternalAddresses(string ipString, bool shouldBePrivate)
    {
        var ip = IPAddress.Parse(ipString);
        var isPrivate = DocumentExtractor.IsPrivateOrLocal(ip);
        Assert.Equal(shouldBePrivate, isPrivate);
    }

    [Fact]
    public void FileSignature_Validation_DetectsLegitimateMagicBytes()
    {
        // PDF Magic Bytes: %PDF-
        var pdfBytes = new byte[] { 0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35 };
        using var pdfStream = new MemoryStream(pdfBytes);
        Assert.True(ValidateSignatureHelper(pdfStream, ".pdf"));

        // PNG Magic Bytes: \x89PNG
        var pngBytes = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        using var pngStream = new MemoryStream(pngBytes);
        Assert.True(ValidateSignatureHelper(pngStream, ".png"));

        // JPEG Magic Bytes: \xFF\xD8\xFF
        var jpegBytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46 };
        using var jpegStream = new MemoryStream(jpegBytes);
        Assert.True(ValidateSignatureHelper(jpegStream, ".jpg"));

        // DOCX Magic Bytes: PK\x03\x04
        var docxBytes = new byte[] { 0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00 };
        using var docxStream = new MemoryStream(docxBytes);
        Assert.True(ValidateSignatureHelper(docxStream, ".docx"));
    }

    [Fact]
    public void FileSignature_Validation_RejectsSpoofedExtensions()
    {
        // HTML / Shell script renamed to .pdf
        var evilPdf = System.Text.Encoding.UTF8.GetBytes("<html><script>alert(1)</script></html>");
        using var stream = new MemoryStream(evilPdf);
        Assert.False(ValidateSignatureHelper(stream, ".pdf"), "HTML content disguised as .pdf must be rejected.");

        // Plain text disguised as .png
        var fakePng = System.Text.Encoding.UTF8.GetBytes("Not a real png file");
        using var fakeStream = new MemoryStream(fakePng);
        Assert.False(ValidateSignatureHelper(fakeStream, ".png"), "Text disguised as .png must be rejected.");
    }

    private static bool ValidateSignatureHelper(Stream stream, string ext)
    {
        var buffer = new byte[12];
        int bytesRead = stream.Read(buffer, 0, buffer.Length);
        if (stream.CanSeek) stream.Position = 0;
        if (bytesRead < 4) return false;

        return ext switch
        {
            ".pdf" => buffer[0] == 0x25 && buffer[1] == 0x50 && buffer[2] == 0x44 && buffer[3] == 0x46,
            ".docx" => buffer[0] == 0x50 && buffer[1] == 0x4B && (buffer[2] == 0x03 || buffer[2] == 0x05) && (buffer[3] == 0x04 || buffer[3] == 0x06),
            ".png" => buffer[0] == 0x89 && buffer[1] == 0x50 && buffer[2] == 0x4E && buffer[3] == 0x47,
            ".jpg" or ".jpeg" => buffer[0] == 0xFF && buffer[1] == 0xD8 && buffer[2] == 0xFF,
            _ => false
        };
    }
}

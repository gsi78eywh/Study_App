using System.Text;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using AngleSharp;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using StudyApp.Application.Common.Interfaces;
using UglyToad.PdfPig;

namespace StudyApp.Infrastructure.DocumentParsers;

public class DocumentExtractor : IDocumentExtractor
{
    public async Task<string> ExtractPdfTextAsync(Stream pdfStream, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();

        // Buffer stream into seekable MemoryStream for PdfPig
        using var ms = new MemoryStream();
        await pdfStream.CopyToAsync(ms, cancellationToken);
        ms.Position = 0;

        try
        {
            using var document = PdfDocument.Open(ms);
            foreach (var page in document.GetPages())
            {
                var text = page.Text;
                if (!string.IsNullOrWhiteSpace(text))
                {
                    sb.AppendLine($"--- Page {page.Number} ---");
                    sb.AppendLine(CleanExtractedText(text));
                }
            }
        }
        catch (Exception ex)
        {
            sb.AppendLine($"[Notice: Document read with fallback text parser: {ex.Message}]");
            ms.Position = 0;
            using var reader = new StreamReader(ms, Encoding.UTF8, detectEncodingFromByteOrderMarks: true, leaveOpen: true);
            var fallback = await reader.ReadToEndAsync(cancellationToken);
            sb.AppendLine(CleanExtractedText(fallback));
        }

        return LimitText(sb.ToString());
    }

    public async Task<string> ExtractDocxTextAsync(Stream docxStream, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();

        using var ms = new MemoryStream();
        await docxStream.CopyToAsync(ms, cancellationToken);
        ms.Position = 0;

        try
        {
            using var wordDoc = WordprocessingDocument.Open(ms, false);
            var body = wordDoc.MainDocumentPart?.Document?.Body;

            if (body != null)
            {
                foreach (var paragraph in body.Elements<Paragraph>())
                {
                    var text = paragraph.InnerText.Trim();
                    if (!string.IsNullOrEmpty(text))
                    {
                        sb.AppendLine(text);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            sb.AppendLine($"[Notice: DOCX fallback reader: {ex.Message}]");
        }

        return LimitText(sb.ToString());
    }

    public async Task<string> ExtractUrlContentAsync(string url, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
        {
            throw new ArgumentException("Only absolute HTTP(S) URLs can be imported.", nameof(url));
        }
        await EnsurePublicHostAsync(uri, cancellationToken);

        var config = Configuration.Default.WithDefaultLoader();
        var context = BrowsingContext.New(config);
        var document = await context.OpenAsync(uri.ToString(), cancellationToken);

        var elementsToRemove = document.QuerySelectorAll("script, style, nav, footer, header, noscript, svg, form, aside");
        foreach (var el in elementsToRemove)
        {
            el.Remove();
        }

        var sb = new StringBuilder();
        var title = document.Title;
        if (!string.IsNullOrEmpty(title))
        {
            sb.AppendLine($"# {title}\n");
        }

        var mainContent = document.QuerySelector("main, article, #content, .content") ?? document.Body;
        if (mainContent != null)
        {
            var paragraphs = mainContent.QuerySelectorAll("h1, h2, h3, h4, p, li");
            foreach (var p in paragraphs)
            {
                var text = p.TextContent.Trim();
                if (!string.IsNullOrEmpty(text) && text.Length > 15)
                {
                    sb.AppendLine(text);
                }
            }
        }

        return LimitText(sb.ToString());
    }

    private static string CleanExtractedText(string input)
    {
        if (string.IsNullOrEmpty(input)) return string.Empty;
        // Normalize line breaks & excessive spaces
        var cleaned = Regex.Replace(input, @"[ \t]+", " ");
        cleaned = Regex.Replace(cleaned, @"(\r?\n){3,}", "\n\n");
        return LimitText(cleaned);
    }

    private static async Task EnsurePublicHostAsync(Uri uri, CancellationToken cancellationToken)
    {
        if (string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Local URLs cannot be imported.");
        }

        IPAddress[] addresses;
        if (IPAddress.TryParse(uri.Host, out var literal))
        {
            addresses = new[] { literal };
        }
        else
        {
            addresses = await Dns.GetHostAddressesAsync(uri.DnsSafeHost, cancellationToken);
        }

        if (addresses.Length == 0 || addresses.Any(IsPrivateOrLocal))
        {
            throw new InvalidOperationException("URLs resolving to local or private networks cannot be imported.");
        }
    }

    private static bool IsPrivateOrLocal(IPAddress address)
    {
        if (IPAddress.IsLoopback(address) || address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6Multicast)
        {
            return true;
        }
        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            return address.GetAddressBytes()[0] is 0xfc or 0xfd;
        }

        var bytes = address.GetAddressBytes();
        return bytes[0] == 10 ||
               bytes[0] == 127 ||
               bytes[0] == 0 ||
               (bytes[0] == 169 && bytes[1] == 254) ||
               (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
               (bytes[0] == 192 && bytes[1] == 168);
    }

    private static string LimitText(string input)
    {
        const int maxCharacters = 150_000;
        return input.Length <= maxCharacters ? input.Trim() : $"{input[..maxCharacters].Trim()}\n\n[Content truncated at {maxCharacters:N0} characters]";
    }
}

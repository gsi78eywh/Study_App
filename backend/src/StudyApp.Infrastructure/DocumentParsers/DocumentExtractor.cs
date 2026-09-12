using System.Text;
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

        return sb.ToString().Trim();
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

        return sb.ToString().Trim();
    }

    public async Task<string> ExtractUrlContentAsync(string url, CancellationToken cancellationToken = default)
    {
        var config = Configuration.Default.WithDefaultLoader();
        var context = BrowsingContext.New(config);
        var document = await context.OpenAsync(url, cancellationToken);

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

        return sb.ToString().Trim();
    }

    private static string CleanExtractedText(string input)
    {
        if (string.IsNullOrEmpty(input)) return string.Empty;
        // Normalize line breaks & excessive spaces
        var cleaned = Regex.Replace(input, @"[ \t]+", " ");
        cleaned = Regex.Replace(cleaned, @"(\r?\n){3,}", "\n\n");
        return cleaned.Trim();
    }
}

using System.Text;
using AngleSharp;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using StudyApp.Application.Common.Interfaces;
using UglyToad.PdfPig;

namespace StudyApp.Infrastructure.DocumentParsers;

public class DocumentExtractor : IDocumentExtractor
{
    public Task<string> ExtractPdfTextAsync(Stream pdfStream, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();
        using var document = PdfDocument.Open(pdfStream);
        
        foreach (var page in document.GetPages())
        {
            sb.AppendLine($"--- Page {page.Number} ---");
            sb.AppendLine(page.Text);
        }

        return Task.FromResult(sb.ToString());
    }

    public Task<string> ExtractDocxTextAsync(Stream docxStream, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();
        using var wordDoc = WordprocessingDocument.Open(docxStream, false);
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

        return Task.FromResult(sb.ToString());
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
                if (!string.IsNullOrEmpty(text) && text.Length > 20)
                {
                    sb.AppendLine(text);
                }
            }
        }

        return sb.ToString();
    }
}

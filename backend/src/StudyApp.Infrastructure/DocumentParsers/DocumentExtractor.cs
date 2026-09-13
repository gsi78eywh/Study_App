using System.Text;
using System.Text.Json;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using AngleSharp;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using StudyApp.Application.Common.Interfaces;
using UglyToad.PdfPig;

namespace StudyApp.Infrastructure.DocumentParsers;

public class DocumentExtractor : IDocumentExtractor
{
    private readonly HttpClient? _httpClient;
    private readonly Microsoft.Extensions.Configuration.IConfiguration? _configuration;
    private readonly ILogger<DocumentExtractor>? _logger;

    public DocumentExtractor(
        Microsoft.Extensions.Configuration.IConfiguration? configuration = null,
        HttpClient? httpClient = null,
        ILogger<DocumentExtractor>? logger = null)
    {
        _configuration = configuration;
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<string> ExtractImageTextAsync(Stream imageStream, string mimeType, CancellationToken cancellationToken = default)
    {
        using var ms = new MemoryStream();
        await imageStream.CopyToAsync(ms, cancellationToken);
        var bytes = ms.ToArray();
        if (bytes.Length == 0) return string.Empty;

        var apiKey = _configuration?["AiSettings:ApiKey"] ?? string.Empty;
        if (string.IsNullOrWhiteSpace(apiKey) || apiKey.Contains("YOUR_GEMINI_API_KEY"))
        {
            apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY") ?? string.Empty;
        }

        if (!string.IsNullOrWhiteSpace(apiKey) && _httpClient != null)
        {
            try
            {
                var payload = new
                {
                    contents = new[]
                    {
                        new
                        {
                            parts = new object[]
                            {
                                new { text = "You are a precise, verbatim OCR transcription engine. Extract and transcribe all text, notes, equations, questions, options, and answers visible in this image verbatim. Do not generate new questions, do not summarize, and do not add external commentary. Return ONLY the verbatim transcribed text from the image." },
                                new
                                {
                                    inlineData = new
                                    {
                                        mimeType = mimeType,
                                        data = Convert.ToBase64String(bytes)
                                    }
                                }
                            }
                        }
                    },
                    generationConfig = new
                    {
                        temperature = 0.1
                    }
                };

                var json = JsonSerializer.Serialize(payload);
                var url = $"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key={apiKey}";
                using var request = new HttpRequestMessage(HttpMethod.Post, url);
                request.Content = new StringContent(json, Encoding.UTF8, "application/json");

                using var response = await _httpClient.SendAsync(request, cancellationToken);
                if (response.IsSuccessStatusCode)
                {
                    var responseStr = await response.Content.ReadAsStringAsync(cancellationToken);
                    using var doc = JsonDocument.Parse(responseStr);
                    if (doc.RootElement.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0)
                    {
                        var firstCandidate = candidates[0];
                        if (firstCandidate.TryGetProperty("content", out var content) &&
                            content.TryGetProperty("parts", out var parts) &&
                            parts.GetArrayLength() > 0)
                        {
                            var text = parts[0].GetProperty("text").GetString();
                            if (!string.IsNullOrWhiteSpace(text))
                            {
                                return LimitText(text.Trim());
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "Gemini Vision OCR extraction failed, using fallback");
            }
        }

        // Local extraction fallback: scan image byte stream for readable text chunks
        var extractedMetadata = ExtractTextFromRawImageBytes(bytes);
        if (!string.IsNullOrWhiteSpace(extractedMetadata))
        {
            return LimitText(extractedMetadata);
        }

        return "[Image Content: Uploaded Note Material]";
    }

    private static string ExtractTextFromRawImageBytes(byte[] bytes)
    {
        var sb = new StringBuilder();
        var currentWord = new StringBuilder();

        for (int i = 0; i < bytes.Length; i++)
        {
            byte b = bytes[i];
            if (b >= 32 && b <= 126) // printable ASCII
            {
                currentWord.Append((char)b);
            }
            else if (b == '\n' || b == '\r')
            {
                if (currentWord.Length >= 8)
                {
                    sb.AppendLine(currentWord.ToString());
                }
                currentWord.Clear();
            }
            else
            {
                if (currentWord.Length >= 8)
                {
                    var word = currentWord.ToString();
                    // filter common binary chunk noise
                    if (Regex.IsMatch(word, @"^[A-Za-z0-9\s.,:;?!-]{8,}$"))
                    {
                        sb.AppendLine(word);
                    }
                }
                currentWord.Clear();
            }
        }

        if (currentWord.Length >= 8)
        {
            sb.AppendLine(currentWord.ToString());
        }

        return sb.ToString().Trim();
    }

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

        var htmlContent = await DownloadPublicUrlAsync(uri, cancellationToken);
        var config = Configuration.Default;
        var context = BrowsingContext.New(config);
        var document = await context.OpenAsync(req => req.Content(htmlContent).Address(uri), cancellationToken);

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

    private static async Task<string> DownloadPublicUrlAsync(Uri uri, CancellationToken cancellationToken)
    {
        if (string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Local URLs cannot be imported.");
        }

        var handler = new SocketsHttpHandler
        {
            ConnectCallback = async (context, token) =>
            {
                var entry = await Dns.GetHostEntryAsync(context.DnsEndPoint.Host, token);
                var address = entry.AddressList.FirstOrDefault(ip => !IsPrivateOrLocal(ip))
                    ?? throw new InvalidOperationException("URLs resolving to local or private networks cannot be imported.");

                var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                try
                {
                    await socket.ConnectAsync(new IPEndPoint(address, context.DnsEndPoint.Port), token);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            },
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            PooledConnectionLifetime = TimeSpan.FromMinutes(1)
        };

        using var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(15)
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("StudyApp-Extractor/1.0");

        using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Failed to load URL. Remote server returned status {(int)response.StatusCode}.");
        }

        const long maxBytes = 5 * 1024 * 1024; // 5 MB max
        if (response.Content.Headers.ContentLength > maxBytes)
        {
            throw new InvalidOperationException("Page content exceeds the 5MB size limit.");
        }

        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var ms = new MemoryStream();
        var buffer = new byte[8192];
        int read;
        while ((read = await stream.ReadAsync(buffer, cancellationToken)) > 0)
        {
            if (ms.Length + read > maxBytes)
            {
                throw new InvalidOperationException("Page content exceeds the 5MB size limit.");
            }
            ms.Write(buffer, 0, read);
        }

        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private static string CleanExtractedText(string input)
    {
        if (string.IsNullOrEmpty(input)) return string.Empty;
        // Normalize line breaks & excessive spaces
        var cleaned = Regex.Replace(input, @"[ \t]+", " ");
        cleaned = Regex.Replace(cleaned, @"(\r?\n){3,}", "\n\n");
        return LimitText(cleaned);
    }

    public static bool IsPrivateOrLocal(IPAddress address)
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

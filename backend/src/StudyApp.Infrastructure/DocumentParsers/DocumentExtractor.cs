using System.Text;
using System.Text.Json;
using System.Diagnostics;
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

    public async Task<string> ExtractImageTextAsync(Stream imageStream, string mimeType, string? apiKeyOverride = null, CancellationToken cancellationToken = default)
    {
        using var ms = new MemoryStream();
        await imageStream.CopyToAsync(ms, cancellationToken);
        var bytes = ms.ToArray();
        if (bytes.Length == 0) return string.Empty;

        var apiKey = !string.IsNullOrWhiteSpace(apiKeyOverride)
            ? apiKeyOverride.Trim()
            : (_configuration?["AiSettings:ApiKey"] ?? string.Empty);

        if (string.IsNullOrWhiteSpace(apiKey) || apiKey.Contains("YOUR_GEMINI_API_KEY"))
        {
            apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY")
                ?? Environment.GetEnvironmentVariable("GOOGLE_API_KEY")
                ?? string.Empty;
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
                var candidateModels = new[] { "gemini-3.6-flash", "gemini-3.8-flash", "gemini-2.5-flash", "gemini-2.0-flash" };

                foreach (var model in candidateModels)
                {
                    if (cancellationToken.IsCancellationRequested) break;

                    try
                    {
                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";
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
                                        var cleaned = OcrTextCleaner.CleanAndReconstructText(text.Trim());
                                        return LimitText(!string.IsNullOrWhiteSpace(cleaned) ? cleaned : text.Trim());
                                    }
                                }
                            }
                        }
                        else
                        {
                            _logger?.LogWarning("Gemini Vision OCR with model {Model} returned status {StatusCode}", model, response.StatusCode);
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "Gemini Vision OCR attempt for model {Model} failed", model);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "Gemini Vision OCR extraction failed, falling back to local OCR");
            }
        }

        // 2. Native Offline Local OCR (Windows.Media.Ocr.OcrEngine via PowerShell)
        if (OperatingSystem.IsWindows())
        {
            try
            {
                var localOcrText = await ExtractWithWindowsOcrAsync(bytes, mimeType, cancellationToken);
                if (!string.IsNullOrWhiteSpace(localOcrText))
                {
                    _logger?.LogInformation("Extracted {CharCount} characters using native offline Windows OCR", localOcrText.Length);
                    var cleaned = OcrTextCleaner.CleanAndReconstructText(localOcrText);
                    return LimitText(!string.IsNullOrWhiteSpace(cleaned) ? cleaned : localOcrText);
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "Native Windows OCR extraction failed, falling back to raw byte inspection");
            }
        }

        // 3. Local extraction fallback: scan image byte stream for readable text chunks (e.g. metadata, embedded notes)
        var extractedMetadata = ExtractTextFromRawImageBytes(bytes);
        if (!string.IsNullOrWhiteSpace(extractedMetadata))
        {
            var cleaned = OcrTextCleaner.CleanAndReconstructText(extractedMetadata);
            return LimitText(!string.IsNullOrWhiteSpace(cleaned) ? cleaned : extractedMetadata);
        }

        return string.Empty;
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

    private async Task<string> ExtractWithWindowsOcrAsync(byte[] bytes, string mimeType, CancellationToken cancellationToken)
    {
        var scriptPath = FindOcrScriptPath();
        if (string.IsNullOrEmpty(scriptPath) || !File.Exists(scriptPath))
        {
            _logger?.LogWarning("Windows OCR script not found at candidate paths");
            return string.Empty;
        }

        var ext = mimeType.ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ".jpg",
            "image/webp" => ".webp",
            "image/bmp" => ".bmp",
            _ => ".png"
        };

        var tempImagePath = Path.Combine(Path.GetTempPath(), $"ocr_{Guid.NewGuid():N}{ext}");
        try
        {
            await File.WriteAllBytesAsync(tempImagePath, bytes, cancellationToken);

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" -ImagePath \"{tempImagePath}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8
            };

            using var process = new Process { StartInfo = startInfo };
            process.Start();

            var readOutputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var readErrorTask = process.StandardError.ReadToEndAsync(cancellationToken);

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(15));

            await process.WaitForExitAsync(cts.Token);
            var output = await readOutputTask;
            var error = await readErrorTask;

            if (!string.IsNullOrWhiteSpace(error))
            {
                _logger?.LogDebug("Windows OCR stderr: {Error}", error);
            }

            return output?.Trim() ?? string.Empty;
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "Error invoking native Windows OCR process");
            return string.Empty;
        }
        finally
        {
            try
            {
                if (File.Exists(tempImagePath))
                {
                    File.Delete(tempImagePath);
                }
            }
            catch
            {
                // Ignore cleanup errors
            }
        }
    }

    private static string? FindOcrScriptPath()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "DocumentParsers", "windows_ocr.ps1"),
            Path.Combine(baseDir, "windows_ocr.ps1"),
            Path.Combine(Directory.GetCurrentDirectory(), "backend", "src", "StudyApp.Infrastructure", "DocumentParsers", "windows_ocr.ps1"),
            Path.Combine(Directory.GetCurrentDirectory(), "src", "StudyApp.Infrastructure", "DocumentParsers", "windows_ocr.ps1"),
            Path.Combine(Directory.GetCurrentDirectory(), "DocumentParsers", "windows_ocr.ps1")
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate)) return candidate;
        }

        // Try climbing parent directories
        var dir = new DirectoryInfo(baseDir);
        while (dir != null && dir.Exists)
        {
            var testPath = Path.Combine(dir.FullName, "backend", "src", "StudyApp.Infrastructure", "DocumentParsers", "windows_ocr.ps1");
            if (File.Exists(testPath)) return testPath;
            testPath = Path.Combine(dir.FullName, "src", "StudyApp.Infrastructure", "DocumentParsers", "windows_ocr.ps1");
            if (File.Exists(testPath)) return testPath;
            testPath = Path.Combine(dir.FullName, "DocumentParsers", "windows_ocr.ps1");
            if (File.Exists(testPath)) return testPath;
            dir = dir.Parent;
        }

        return null;
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

        // Remove extraneous script, styles, interactive controls and navigation
        var elementsToRemove = document.QuerySelectorAll("script, style, nav, footer, header, noscript, svg, form, aside, dialog, .cookie-banner, .advertisement");
        foreach (var el in elementsToRemove)
        {
            el.Remove();
        }

        var sb = new StringBuilder();
        var title = document.Title?.Trim();
        if (!string.IsNullOrEmpty(title))
        {
            sb.AppendLine($"# {title}\n");
        }

        // Check for page description metadata (common on educational & doc sites)
        var metaDesc = document.QuerySelector("meta[name='description'], meta[property='og:description']")?.GetAttribute("content")?.Trim();
        if (!string.IsNullOrEmpty(metaDesc))
        {
            sb.AppendLine($"**Overview:** {metaDesc}\n");
        }

        var mainContent = document.QuerySelector("main, article, [role='main'], #content, .content, .article-content, .post-content, .entry-content, .course-content")
            ?? document.Body;

        if (mainContent != null)
        {
            var nodes = mainContent.QuerySelectorAll("h1, h2, h3, h4, h5, h6, p, li, dt, dd, blockquote, tr");
            int extractedNodeCount = 0;

            foreach (var node in nodes)
            {
                var text = node.TextContent.Trim();
                if (string.IsNullOrWhiteSpace(text) || text.Length < 3) continue;

                var tag = node.TagName.ToLowerInvariant();
                if (tag is "h1" or "h2" or "h3" or "h4" or "h5" or "h6")
                {
                    sb.AppendLine($"\n### {text}");
                    extractedNodeCount++;
                }
                else if (tag == "li")
                {
                    sb.AppendLine($"• {text}");
                    extractedNodeCount++;
                }
                else if (tag == "blockquote")
                {
                    sb.AppendLine($"> {text}");
                    extractedNodeCount++;
                }
                else
                {
                    sb.AppendLine(text);
                    extractedNodeCount++;
                }
            }

            // Fallback: If query selectors yielded very little text, extract from mainContent text content directly
            if (extractedNodeCount < 3 || sb.Length < 150)
            {
                var rawText = CleanExtractedText(mainContent.TextContent);
                if (!string.IsNullOrWhiteSpace(rawText) && rawText.Length > sb.Length)
                {
                    sb.Clear();
                    if (!string.IsNullOrEmpty(title)) sb.AppendLine($"# {title}\n");
                    if (!string.IsNullOrEmpty(metaDesc)) sb.AppendLine($"**Overview:** {metaDesc}\n");
                    sb.AppendLine(rawText);
                }
            }
        }

        var result = LimitText(sb.ToString().Trim());
        if (string.IsNullOrWhiteSpace(result))
        {
            throw new InvalidOperationException("No readable study text could be extracted from that URL. The page may require JavaScript rendering or a login.");
        }

        return result;
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
                var publicAddresses = entry.AddressList.Where(ip => !IsPrivateOrLocal(ip)).ToList();
                if (publicAddresses.Count == 0)
                {
                    throw new InvalidOperationException("URLs resolving to local or private networks cannot be imported.");
                }

                // Prefer IPv4 addresses for broad network route compatibility, then IPv6
                var candidateAddresses = publicAddresses
                    .OrderBy(ip => ip.AddressFamily == AddressFamily.InterNetwork ? 0 : 1)
                    .ToList();

                Exception? lastException = null;
                foreach (var address in candidateAddresses)
                {
                    var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                    try
                    {
                        await socket.ConnectAsync(new IPEndPoint(address, context.DnsEndPoint.Port), token);
                        return new NetworkStream(socket, ownsSocket: true);
                    }
                    catch (Exception ex)
                    {
                        socket.Dispose();
                        lastException = ex;
                    }
                }

                throw lastException ?? new InvalidOperationException("Failed to establish a network connection to the specified host.");
            },
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            PooledConnectionLifetime = TimeSpan.FromMinutes(1)
        };

        using var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(20)
        };

        // Realistic modern browser headers so CDNs/WAFs do not reject crawler requests
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36");
        client.DefaultRequestHeaders.Accept.ParseAdd("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8");
        client.DefaultRequestHeaders.AcceptLanguage.ParseAdd("en-US,en;q=0.9");

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

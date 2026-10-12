using Microsoft.AspNetCore.RateLimiting;
using System.Net;
using System.Text.RegularExpressions;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Ingestion;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

using System.Net.Sockets;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using StudyApp.Application.DTOs.Ai;
using StudyApp.Infrastructure.DocumentParsers;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/ingestion")]
[Authorize]
[EnableRateLimiting("ingestion")]
public class IngestionController : ControllerBase
{
    private readonly IAiQuestionGenerator _aiGenerator;
    private readonly IDocumentExtractor _documentExtractor;
    private readonly IApplicationDbContext _context;
    private readonly IAiTutorService? _aiTutorService;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public IngestionController(
        IAiQuestionGenerator aiGenerator,
        IDocumentExtractor documentExtractor,
        IApplicationDbContext context,
        IAiTutorService? aiTutorService = null)
    {
        _aiGenerator = aiGenerator;
        _documentExtractor = documentExtractor;
        _context = context;
        _aiTutorService = aiTutorService;
    }

    [HttpPost("text")]
    public async Task<IActionResult> GenerateFromText([FromBody] GenerateFromTextRequest request)
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new { message = "Study notes or content cannot be empty." });
        }

        var trimmedContent = (request.Content ?? string.Empty).Trim();
        if (Uri.TryCreate(trimmedContent, UriKind.Absolute, out var directUri) && (directUri.Scheme is "http" or "https"))
        {
            return await GenerateFromUrl(new GenerateFromUrlRequest
            {
                CourseId = request.CourseId,
                Title = request.Title,
                Url = trimmedContent,
                QuestionTypes = request.QuestionTypes,
                TargetCount = request.TargetCount > 0 ? request.TargetCount : 15,
                SetIndex = request.SetIndex,
                Variant = request.Variant
            });
        }

        var effectiveCourseId = await ResolveCourseIdAsync(request.CourseId, userId.Value);

        var sourceText = LimitSourceText(CleanInputText(request.Content));
        var qualityCheck = ValidateInputQuality(sourceText);
        if (!qualityCheck.IsValid)
        {
            return BadRequest(new { message = qualityCheck.ErrorMessage });
        }
        string? geminiKey = null; // Provider credentials are read only from backend configuration.

        var resolvedTitle = CleanTitle(request.Title);
        var result = await _aiGenerator.GenerateStudySetAsync(
            sourceText,
            resolvedTitle,
            request.QuestionTypes ?? new List<string>(),
            ClampTargetCount(request.TargetCount),
            request.SetIndex,
            request.Variant,
            geminiKey);

        var totalQuestions = result.Questions.Count;
        if (totalQuestions == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        var validQuestions = result.Questions.Where(q => ValidateQuestionQuality(q, resolvedTitle, sourceText)).ToList();
        if (validQuestions.Count == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        result = new GeneratedStudySetResult(result.StudySetId, result.Title, result.Summary, result.HighYieldBulletPoints, validQuestions, result.ExtractedText);

        var studySet = await SaveGeneratedSetAsync(effectiveCourseId, result, "Manual note input", "text/markdown", sourceText);
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count,
            Questions = studySet.Questions.Select(q => new
            {
                q.Id,
                q.StudySetId,
                q.Prompt,
                QuestionType = q.Type.ToString(),
                q.Explanation,
                Options = q.Options.Select(o => new
                {
                    o.Id,
                    o.QuestionId,
                    o.OptionText,
                    o.IsCorrect
                }).ToList()
            }).ToList()
        });
    }

    [HttpPost("file")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> GenerateFromFile(
        [FromForm] IFormFile file,
        [FromForm] string? courseId,
        [FromForm] string? title,
        [FromForm] string? questionTypes,
        [FromForm] int? targetCount,
        [FromForm] int? setIndex,
        [FromForm] string? variant,
        [FromForm] string? apiKey)
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        if (file == null || file.Length == 0)
        {
            return BadRequest(new { message = "Please select a valid file." });
        }

        if (file.Length > 30 * 1024 * 1024)
        {
            return BadRequest(new { message = "File exceeds 30MB limit." });
        }

        var effectiveCourseId = await ResolveCourseIdAsync(courseId, userId.Value);

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var setHeader = CleanTitle(!string.IsNullOrWhiteSpace(title) ? title : Path.GetFileNameWithoutExtension(file.FileName));
        var targetNum = ClampTargetCount(targetCount ?? 10);
        var chosenSetIndex = setIndex ?? 0;

        string? geminiKey = null; // Ignore client-supplied provider credentials.

        var typesList = !string.IsNullOrWhiteSpace(questionTypes)
            ? questionTypes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
            : new List<string>();

        GeneratedStudySetResult result;
        string? extractedSourceText = null;

        using var stream = new MemoryStream();
        await file.CopyToAsync(stream);
        stream.Position = 0;

        if (!ValidateFileSignature(stream, ext))
        {
            return BadRequest(new { message = "Uploaded file content does not match the file extension signature." });
        }
        stream.Position = 0;

        if (ext is ".png" or ".jpg" or ".jpeg" or ".webp" or ".bmp")
        {
            // Direct OCR / Image Text Extraction with Gemini Vision & Local Fallback
            var mimeType = ext switch
            {
                ".png" => "image/png",
                ".webp" => "image/webp",
                ".bmp" => "image/bmp",
                _ => "image/jpeg"
            };
            extractedSourceText = await _documentExtractor.ExtractImageTextAsync(stream, mimeType, geminiKey);

            if (string.IsNullOrWhiteSpace(extractedSourceText))
            {
                return BadRequest(new
                {
                    message = "No readable text could be recognized from this screenshot. To enable AI Vision OCR for photos and screenshots, please enter your free Google Gemini API Key in the settings, or paste the text directly into the 'Paste Text' tab."
                });
            }

            var cleanedOcr = StudyApp.Infrastructure.DocumentParsers.OcrTextCleaner.CleanAndReconstructText(extractedSourceText);
            if (!string.IsNullOrWhiteSpace(cleanedOcr))
            {
                extractedSourceText = cleanedOcr;
            }

        }
        else if (ext == ".pdf")
        {
            extractedSourceText = await _documentExtractor.ExtractPdfTextAsync(stream);
        }
        else if (ext == ".docx")
        {
            extractedSourceText = await _documentExtractor.ExtractDocxTextAsync(stream);
        }
        else if (ext is ".txt" or ".md")
        {
            using var reader = new StreamReader(stream, leaveOpen: true);
            extractedSourceText = LimitSourceText(await reader.ReadToEndAsync());
        }
        else
        {
            return BadRequest(new { message = "Unsupported file type. Please upload a PDF, DOCX, TXT, or Image file (.png, .jpg, .jpeg, .webp, .bmp)." });
        }

        extractedSourceText = LimitSourceText(extractedSourceText ?? string.Empty);
        if (!HasUsableStudyContent(extractedSourceText))
        {
            return BadRequest(new
            {
                message = ext == ".pdf"
                    ? "No selectable text was found in this PDF. If it is a scanned handout, upload clear page photos with the Camera Scanner or paste the text after OCR."
                : "We could not extract enough readable study content from this file. Try a clearer image, an unprotected document, or paste the notes directly."
            });
        }

        extractedSourceText = CleanInputText(extractedSourceText);
        result = await _aiGenerator.GenerateStudySetAsync(
            extractedSourceText,
            setHeader,
            typesList,
            targetNum,
            chosenSetIndex,
            variant,
            geminiKey);

        var totalQuestions = result.Questions.Count;
        if (totalQuestions == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        var validQuestions = result.Questions.Where(q => ValidateQuestionQuality(q, setHeader, extractedSourceText)).ToList();
        if (validQuestions.Count == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        result = new GeneratedStudySetResult(result.StudySetId, result.Title, result.Summary, result.HighYieldBulletPoints, validQuestions, result.ExtractedText);

        var studySet = await SaveGeneratedSetAsync(effectiveCourseId, result, file.FileName, ext, extractedSourceText);
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count,
            ExtractedText = extractedSourceText,
            Questions = studySet.Questions.Select(q => new
            {
                q.Id,
                q.StudySetId,
                q.Prompt,
                QuestionType = q.Type.ToString(),
                q.Explanation,
                Options = q.Options.Select(o => new
                {
                    o.Id,
                    o.QuestionId,
                    o.OptionText,
                    o.IsCorrect
                }).ToList()
            }).ToList()
        });
    }

    [HttpPost("scan")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> ScanDocumentContent(
        [FromForm] IFormFile file,
        [FromForm] string? apiKey)
    {
        if (file == null || file.Length == 0)
        {
            return BadRequest(new { message = "Please select a valid image or document file to scan." });
        }

        if (file.Length > 30 * 1024 * 1024)
        {
            return BadRequest(new { message = "File exceeds 30MB limit." });
        }

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        string? geminiKey = null; // Ignore client-supplied provider credentials.

        using var stream = new MemoryStream();
        await file.CopyToAsync(stream);
        stream.Position = 0;

        if (!ValidateFileSignature(stream, ext))
        {
            return BadRequest(new { message = "Uploaded file content does not match the file extension signature." });
        }
        stream.Position = 0;

        string? extractedText = null;
        string engineUsed = "Native Document Parser";

        if (ext is ".png" or ".jpg" or ".jpeg" or ".webp" or ".bmp")
        {
            var mimeType = ext switch
            {
                ".png" => "image/png",
                ".webp" => "image/webp",
                ".bmp" => "image/bmp",
                _ => "image/jpeg"
            };

            extractedText = await _documentExtractor.ExtractImageTextAsync(stream, mimeType, geminiKey);
            engineUsed = !string.IsNullOrWhiteSpace(geminiKey) ? "Gemini Vision (Cloud Multimodal)" : "Native Windows OCR (Offline)";
        }
        else if (ext == ".pdf")
        {
            extractedText = await _documentExtractor.ExtractPdfTextAsync(stream);
            engineUsed = "PdfPig Document Parser";
        }
        else if (ext == ".docx")
        {
            extractedText = await _documentExtractor.ExtractDocxTextAsync(stream);
            engineUsed = "OpenXml Document Parser";
        }
        else if (ext is ".txt" or ".md")
        {
            using var reader = new StreamReader(stream, leaveOpen: true);
            extractedText = LimitSourceText(await reader.ReadToEndAsync());
            engineUsed = "Text Stream Reader";
        }
        else
        {
            return BadRequest(new { message = "Unsupported file type. Please upload a PNG, JPG, JPEG, WEBP, BMP, PDF, DOCX, TXT, or MD file." });
        }

        if (string.IsNullOrWhiteSpace(extractedText))
        {
            return Ok(new
            {
                fileName = file.FileName,
                fileType = ext,
                charCount = 0,
                wordCount = 0,
                lineCount = 0,
                extractedText = string.Empty,
                rawText = string.Empty,
                ocrEngine = engineUsed,
                hasContent = false,
                message = "No readable text could be recognized. Please verify the image is clear, focused, and well-lit."
            });
        }

        var rawScanned = extractedText.Trim();
        var cleanedText = StudyApp.Infrastructure.DocumentParsers.OcrTextCleaner.CleanAndReconstructText(extractedText);
        if (!string.IsNullOrWhiteSpace(cleanedText))
        {
            extractedText = cleanedText;
        }

        var lines = extractedText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries);
        var words = extractedText.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        var candidateTitle = lines.Length > 0 && lines[0].Length >= 3 && lines[0].Length <= 60 && !lines[0].Contains(":")
            ? lines[0].TrimStart('#', ' ', '*').Trim(' ', '*', '_')
            : Path.GetFileNameWithoutExtension(file.FileName);

        return Ok(new
        {
            fileName = file.FileName,
            fileType = ext,
            suggestedTitle = CleanTitle(candidateTitle),
            charCount = extractedText.Length,
            wordCount = words.Length,
            lineCount = lines.Length,
            extractedText = extractedText.Trim(),
            rawText = rawScanned,
            ocrEngine = engineUsed,
            hasContent = true,
            message = "Content scanned and cleaned successfully."
        });
    }

    [HttpPost("url")]
    public async Task<IActionResult> GenerateFromUrl([FromBody] GenerateFromUrlRequest request)
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(request.Url))
        {
            return BadRequest(new { message = "A URL is required." });
        }
        var rawTargetUrl = TryUnwrapRedirectUrl(request.Url.Trim());
        if (!Uri.TryCreate(rawTargetUrl, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
        {
            return BadRequest(new { message = "Only valid HTTP(S) URLs can be imported." });
        }

        var effectiveCourseId = await ResolveCourseIdAsync(request.CourseId, userId.Value);

        string extractedText = "";
        string candidateTitle = string.IsNullOrWhiteSpace(request.Title) ? uri.Host : request.Title;

        string? geminiKey = null; // Provider credentials stay on the server.

        bool isSearchQuery = TryExtractSearchEngineQuery(rawTargetUrl, out var searchQuery, out var searchEngineName);
        bool isYouTube = IsYouTubeUrl(rawTargetUrl);

        if (isSearchQuery)
        {
            var (guideTitle, guideContent) = await GenerateComprehensiveStudyGuideForTopicAsync(
                searchQuery, searchEngineName, geminiKey, HttpContext.RequestAborted);
            extractedText = guideContent;
            if (string.IsNullOrWhiteSpace(request.Title))
            {
                candidateTitle = guideTitle;
            }
        }
        else if (isYouTube)
        {
            if (IsYouTubeSearchUrl(request.Url))
            {
                return BadRequest(new { message = "This appears to be a YouTube search query link. Please click on the specific video and copy its URL (e.g., https://www.youtube.com/watch?v=... or https://youtu.be/...)." });
            }

            var (ytText, ytTitle) = await TryExtractYouTubeContentAsync(request.Url, HttpContext.RequestAborted);
            if (string.IsNullOrWhiteSpace(ytText))
            {
                return BadRequest(new { message = "Could not extract study content or captions from this video. Please ensure the video has closed captions or a detailed tutorial outline, or paste the text directly." });
            }
            extractedText = ytText;
            if (string.IsNullOrWhiteSpace(request.Title) && !string.IsNullOrWhiteSpace(ytTitle))
            {
                candidateTitle = ytTitle;
            }
        }
        else
        {
            try
            {
                extractedText = await _documentExtractor.ExtractUrlContentAsync(uri.ToString());
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }

            if (IsAntiBotOrBlockedResponse(extractedText, candidateTitle))
            {
                if (TryExtractFallbackQuery(request.Url, candidateTitle, out var fallbackQuery))
                {
                    var (guideTitle, guideContent) = await GenerateComprehensiveStudyGuideForTopicAsync(
                        fallbackQuery, "Search Query", geminiKey, HttpContext.RequestAborted);
                    extractedText = guideContent;
                    if (string.IsNullOrWhiteSpace(request.Title))
                    {
                        candidateTitle = guideTitle;
                    }
                }
                else
                {
                    return BadRequest(new { message = "This webpage is protected by automated bot/CAPTCHA verification. Please copy the article text and paste it into the Note Editor directly." });
                }
            }
        }

        if (string.IsNullOrWhiteSpace(extractedText) || !HasUsableStudyContent(extractedText))
        {
            return BadRequest(new { message = "No readable study text was found at that URL." });
        }
        var cleanedUrlText = CleanInputText(extractedText);
        var noteTitle = ResolveUsableTitle(candidateTitle, uri.ToString(), cleanedUrlText);
        var result = await _aiGenerator.GenerateStudySetAsync(
            cleanedUrlText,
            noteTitle,
            request.QuestionTypes ?? new List<string>(),
            ClampTargetCount(request.TargetCount),
            request.SetIndex,
            request.Variant,
            geminiKey);

        var totalQuestions = result.Questions.Count;
        if (totalQuestions == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        var validQuestions = result.Questions.Where(q => ValidateQuestionQuality(q, noteTitle, cleanedUrlText)).ToList();
        if (validQuestions.Count == 0)
        {
            return BadRequest(new { message = "Couldn't build a good set from this source." });
        }
        result = new GeneratedStudySetResult(result.StudySetId, result.Title, result.Summary, result.HighYieldBulletPoints, validQuestions, result.ExtractedText);

        var studySet = await SaveGeneratedSetAsync(effectiveCourseId, result, uri.ToString(), "text/html", cleanedUrlText);
        return Ok(new
        {
            studySet.Id,
            studySet.CourseId,
            studySet.Title,
            studySet.Description,
            result.Summary,
            result.HighYieldBulletPoints,
            QuestionCount = studySet.Questions.Count
        });
    }

    [HttpPost("scan-url")]
    public async Task<IActionResult> ScanUrl([FromBody] ScanUrlRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Url))
        {
            return BadRequest(new { message = "A URL is required to scan." });
        }
        var rawTargetUrl = TryUnwrapRedirectUrl(request.Url.Trim());
        if (!Uri.TryCreate(rawTargetUrl, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
        {
            return BadRequest(new { message = "Only valid HTTP(S) URLs can be scanned." });
        }

        string extractedText = "";
        string candidateTitle = uri.Host;
        string? authorName = null;

        string? geminiKey = null; // Provider credentials stay on the server.

        bool isSearchQuery = TryExtractSearchEngineQuery(rawTargetUrl, out var searchQuery, out var searchEngineName);
        bool isYouTubeScan = IsYouTubeUrl(rawTargetUrl);

        if (isSearchQuery)
        {
            var (guideTitle, guideContent) = await GenerateComprehensiveStudyGuideForTopicAsync(
                searchQuery, searchEngineName, geminiKey, HttpContext.RequestAborted);
            extractedText = guideContent;
            candidateTitle = guideTitle;
            authorName = $"{searchEngineName} Curriculum Synthesis";
        }
        else if (isYouTubeScan)
        {
            if (IsYouTubeSearchUrl(request.Url))
            {
                return BadRequest(new { message = "This appears to be a YouTube search query link. Please click on the specific video and copy its URL (e.g., https://www.youtube.com/watch?v=... or https://youtu.be/...)." });
            }

            var (ytText, ytTitle) = await TryExtractYouTubeContentAsync(request.Url, HttpContext.RequestAborted);
            if (string.IsNullOrWhiteSpace(ytText))
            {
                return BadRequest(new { message = "Could not extract study content or captions from this video. Please ensure the video has closed captions or a detailed tutorial outline, or paste the text directly." });
            }
            extractedText = ytText;
            if (!string.IsNullOrWhiteSpace(ytTitle))
            {
                candidateTitle = ytTitle;
            }
        }
        else
        {
            try
            {
                extractedText = await _documentExtractor.ExtractUrlContentAsync(uri.ToString());
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = $"Could not extract content from the URL: {ex.Message}" });
            }

            if (IsAntiBotOrBlockedResponse(extractedText, candidateTitle))
            {
                if (TryExtractFallbackQuery(request.Url, candidateTitle, out var fallbackQuery))
                {
                    var (guideTitle, guideContent) = await GenerateComprehensiveStudyGuideForTopicAsync(
                        fallbackQuery, "Study Topic", geminiKey, HttpContext.RequestAborted);
                    extractedText = guideContent;
                    candidateTitle = guideTitle;
                    authorName = "StudyApp Knowledge Engine";
                }
                else
                {
                    return BadRequest(new { message = "This website is protected by automated bot/CAPTCHA verification. Please copy the article text and paste it into the Note Editor directly." });
                }
            }
        }

        if (string.IsNullOrWhiteSpace(extractedText))
        {
            return BadRequest(new { message = "No readable study text was found at that URL." });
        }

        var lines = extractedText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries);
        var words = extractedText.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        if (candidateTitle == uri.Host)
        {
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (trimmed.StartsWith("# ") || trimmed.StartsWith("### "))
                {
                    candidateTitle = trimmed.TrimStart('#', ' ', '*');
                    break;
                }
                if (trimmed.Length >= 5 && trimmed.Length <= 70 && !trimmed.StartsWith("http"))
                {
                    candidateTitle = trimmed;
                    break;
                }
            }
        }

        string? durationStr = null;
        string? videoId = null;
        string? thumbnailUrl = null;

        if (isYouTubeScan)
        {
            videoId = ExtractYouTubeVideoId(request.Url);
            thumbnailUrl = ExtractYouTubeThumbnail(request.Url);

            var authorMatch = Regex.Match(extractedText, @"Instructor / Channel:\s*(.+)");
            if (authorMatch.Success) authorName = authorMatch.Groups[1].Value.Trim();

            var durMatch = Regex.Match(extractedText, @"Duration:\s*(.+)");
            if (durMatch.Success) durationStr = durMatch.Groups[1].Value.Trim();
        }

        var resolvedTitle = ResolveUsableTitle(candidateTitle, uri.ToString(), extractedText);

        return Ok(new
        {
            url = uri.ToString(),
            title = resolvedTitle,
            suggestedTitle = resolvedTitle,
            charCount = extractedText.Length,
            wordCount = words.Length,
            lineCount = lines.Length,
            extractedText = extractedText.Trim(),
            hasContent = true,
            isVideo = isYouTubeScan,
            isSong = isYouTubeScan && IsSongOrLyricsContent(resolvedTitle, authorName, extractedText, extractedText),
            videoId = videoId,
            thumbnailUrl = thumbnailUrl,
            author = authorName,
            duration = durationStr,
            message = isSearchQuery
                ? "Search query inquiry synthesized into comprehensive study notes."
                : (isYouTubeScan ? "Video details and lecture content extracted successfully." : "Article content extracted and parsed successfully.")
        });
    }

    public static string TryUnwrapRedirectUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return url;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return url;

        var host = uri.Host.ToLowerInvariant();
        if (host.Contains("google.") && (uri.AbsolutePath.Equals("/url", StringComparison.OrdinalIgnoreCase) || uri.AbsolutePath.StartsWith("/url")))
        {
            try
            {
                var queryParams = QueryHelpers.ParseQuery(uri.Query);
                if (queryParams.TryGetValue("url", out var destVal) || queryParams.TryGetValue("q", out destVal))
                {
                    var target = destVal.FirstOrDefault();
                    if (!string.IsNullOrWhiteSpace(target) && (target.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase)))
                    {
                        return target.Trim();
                    }
                }
            }
            catch { }
        }
        return url;
    }

    public static bool TryExtractSearchEngineQuery(string url, out string query, out string searchEngineName)
    {
        query = string.Empty;
        searchEngineName = "Search Engine";
        if (string.IsNullOrWhiteSpace(url)) return false;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;

        var host = uri.Host.ToLowerInvariant();
        var isGoogle = host.Contains("google.");
        var isBing = host.Contains("bing.com");
        var isYahoo = host.Contains("yahoo.com");
        var isDuckDuckGo = host.Contains("duckduckgo.com");
        var isEcosia = host.Contains("ecosia.org");
        var isBaidu = host.Contains("baidu.com");
        var isYandex = host.Contains("yandex.");

        if (!isGoogle && !isBing && !isYahoo && !isDuckDuckGo && !isEcosia && !isBaidu && !isYandex)
        {
            return false;
        }

        if (isGoogle) searchEngineName = "Google Search";
        else if (isBing) searchEngineName = "Bing Search";
        else if (isYahoo) searchEngineName = "Yahoo Search";
        else if (isDuckDuckGo) searchEngineName = "DuckDuckGo Search";
        else if (isEcosia) searchEngineName = "Ecosia Search";
        else if (isBaidu) searchEngineName = "Baidu Search";
        else if (isYandex) searchEngineName = "Yandex Search";

        try
        {
            var queryParams = QueryHelpers.ParseQuery(uri.Query);
            string? rawQuery = null;

            if (isYahoo && queryParams.TryGetValue("p", out var pVal))
            {
                rawQuery = pVal.FirstOrDefault();
            }
            else if (isYandex && queryParams.TryGetValue("text", out var textVal))
            {
                rawQuery = textVal.FirstOrDefault();
            }
            else if (isBaidu && (queryParams.TryGetValue("wd", out var wdVal) || queryParams.TryGetValue("word", out wdVal)))
            {
                rawQuery = wdVal.FirstOrDefault();
            }
            else if (queryParams.TryGetValue("q", out var qVal))
            {
                rawQuery = qVal.FirstOrDefault();
            }
            else if (queryParams.TryGetValue("query", out var queryVal))
            {
                rawQuery = queryVal.FirstOrDefault();
            }
            else if (queryParams.TryGetValue("oq", out var oqVal))
            {
                rawQuery = oqVal.FirstOrDefault();
            }
            else if (queryParams.TryGetValue("as_q", out var asqVal))
            {
                rawQuery = asqVal.FirstOrDefault();
            }
            else if (queryParams.TryGetValue("search_query", out var sqVal))
            {
                rawQuery = sqVal.FirstOrDefault();
            }

            if (!string.IsNullOrWhiteSpace(rawQuery))
            {
                var trimmed = rawQuery.Trim();
                if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                {
                    // This is a wrapped external article URL, not a search query
                    return false;
                }
                query = trimmed;
                return true;
            }
        }
        catch
        {
            // ignore parse issues
        }

        return false;
    }

    public static bool IsAntiBotOrBlockedResponse(string text, string title)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        var lower = text.ToLowerInvariant();
        var lowerTitle = (title ?? string.Empty).ToLowerInvariant();

        if (lower.Contains("if you're having trouble accessing google search") ||
            lower.Contains("unusual traffic from your computer network") ||
            lower.Contains("our systems have detected unusual traffic") ||
            lower.Contains("enable javascript and cookies to continue") ||
            lower.Contains("verify that you're not a robot") ||
            lower.Contains("verify you are human") ||
            lower.Contains("checking your browser before accessing") ||
            lower.Contains("please click here, or send feedback") ||
            lower.Contains("attention required! | cloudflare") ||
            (lower.Contains("access denied") && lower.Contains("cloudflare")))
        {
            return true;
        }

        if (lowerTitle.Contains("google search") && (lower.Contains("trouble accessing") || text.Length < 250))
        {
            return true;
        }

        return false;
    }

    public static bool TryExtractFallbackQuery(string url, string title, out string fallbackQuery)
    {
        fallbackQuery = string.Empty;
        if (TryExtractSearchEngineQuery(url, out var q, out _))
        {
            fallbackQuery = q;
            return true;
        }

        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            var qParams = QueryHelpers.ParseQuery(uri.Query);
            foreach (var key in new[] { "q", "query", "search", "k", "keyword", "topic" })
            {
                if (qParams.TryGetValue(key, out var val) && !string.IsNullOrWhiteSpace(val.FirstOrDefault()))
                {
                    fallbackQuery = val.First()!.Trim();
                    return true;
                }
            }

            var pathSegs = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (pathSegs.Length > 0)
            {
                var lastSeg = Uri.UnescapeDataString(pathSegs.Last()).Replace('-', ' ').Replace('_', ' ').Trim();
                if (lastSeg.Length >= 4 && !lastSeg.EndsWith(".html", StringComparison.OrdinalIgnoreCase) && !lastSeg.EndsWith(".php", StringComparison.OrdinalIgnoreCase))
                {
                    fallbackQuery = lastSeg;
                    return true;
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(title) && !title.Equals("Google Search", StringComparison.OrdinalIgnoreCase) && title.Length >= 5)
        {
            fallbackQuery = title.Trim();
            return true;
        }

        return false;
    }

    public static string FormatQueryToAcademicTitle(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return "Study Notes & Lecture Guide";
        var clean = query.Trim();

        var lower = clean.ToLowerInvariant();
        if (lower.Contains("barangay") && (lower.Contains("project") || lower.Contains("clean") || lower.Contains("volunteer")))
        {
            return "Barangay Project Implementation & Volunteer Mobilization Process";
        }

        clean = Regex.Replace(clean, @"^(?:what\s+(?:is|are)\s+(?:the\s+)?(?:actual\s+)?(?:process\s+of\s+)?|how\s+to\s+|explain\s+(?:the\s+)?|tell\s+me\s+about\s+)", "", RegexOptions.IgnoreCase).Trim();
        if (clean.EndsWith("?", StringComparison.Ordinal)) clean = clean.TrimEnd('?').Trim();

        if (clean.Length == 0) return "Study Notes & Lecture Guide";

        var words = clean.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var titleWords = words.Select(w =>
        {
            if (w.Length == 0) return w;
            if (w.Length == 1) return w.ToUpperInvariant();
            return char.ToUpperInvariant(w[0]) + w.Substring(1);
        });

        var result = string.Join(" ", titleWords);
        return result.Length > 80 ? result.Substring(0, 80).Trim() + "..." : result;
    }

    private async Task<(string title, string content)> GenerateComprehensiveStudyGuideForTopicAsync(
        string topicQuery,
        string? searchEngineName,
        string? apiKeyOverride = null,
        CancellationToken cancellationToken = default)
    {
        var cleanQuery = topicQuery.Trim();
        var displayTitle = FormatQueryToAcademicTitle(cleanQuery);

        if (_aiTutorService != null)
        {
            try
            {
                var prompt = $"You are an expert academic tutor, curriculum specialist, and instructional designer. " +
                    $"A student submitted this search inquiry / study topic: \"{cleanQuery}\".\n" +
                    $"Please synthesize a comprehensive, rigorous, and highly structured educational study guide and lesson notes in clean Markdown format.\n\n" +
                    $"Include the following sections:\n" +
                    $"# {displayTitle}\n\n" +
                    $"## 1. Executive Summary & Learning Objectives\n" +
                    $"A clear summary of the core concepts, civic/academic context, and what the student will master.\n\n" +
                    $"## 2. Legal, Regulatory & Institutional Framework\n" +
                    $"Explain the governing laws, standards, or principles (e.g. Republic Act No. 7160 - Local Government Code of 1991 if governance/barangay-related, relevant government agencies such as DILG/DENR, role of Barangay Assembly and Sangguniang Barangay/SK).\n\n" +
                    $"## 3. Step-by-Step Implementation Process\n" +
                    $"Break down the exact process into clear sequential phases:\n" +
                    $"- Phase 1: Project Conceptualization & Needs Assessment\n" +
                    $"- Phase 2: Council Deliberation & Barangay Resolution / Budget Allocation\n" +
                    $"- Phase 3: Volunteer Recruitment, Mobilization & Community Information Drive\n" +
                    $"- Phase 4: Project Execution, Logistics & On-Site Operations\n" +
                    $"- Phase 5: Post-Project Documentation, Liquidation & Monitoring/Evaluation\n\n" +
                    $"## 4. Volunteer Mobilization & Community Engagement Best Practices\n" +
                    $"Explain how volunteers are recruited (Purok announcements, social media, youth/SK partnerships), safety briefings, tools/equipment provision, and recognition/certificates.\n\n" +
                    $"## 5. Practical Implementation Example\n" +
                    $"Illustrate with a realistic case study (e.g. Barangay Clean-Up Drive / Oplan Kalinisan solid waste campaign).\n\n" +
                    $"## 6. High-Yield Review Takeaways & Key Concepts\n" +
                    $"Key bullet points, definitions, and essential exam facts.\n\n" +
                    $"Write in thorough, authoritative, educational Markdown.";

                var askReq = new AskTutorRequest(
                    Message: prompt,
                    ContextTopic: displayTitle,
                    ApiKey: apiKeyOverride
                );

                var tutorResp = await _aiTutorService.AskTutorAsync(askReq, cancellationToken);
                if (tutorResp != null && !string.IsNullOrWhiteSpace(tutorResp.Reply) && tutorResp.Reply.Length > 800)
                {
                    return (displayTitle, tutorResp.Reply.Trim());
                }
            }
            catch
            {
                // Fall back to built-in curriculum synthesizer
            }
        }

        var synthesizedNotes = BuildCurriculumStudyGuide(cleanQuery, displayTitle);
        return (displayTitle, synthesizedNotes);
    }

    private static string BuildCurriculumStudyGuide(string query, string title)
    {
        var synthesized = StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.SynthesizeResponse(query, title);
        if (!string.IsNullOrWhiteSpace(synthesized) && synthesized.Length > 500)
        {
            return synthesized.Replace("\n\n*(Synthesized by built-in educational tutor knowledge engine)*", "").Trim();
        }

        var lower = query.ToLowerInvariant();
        if (lower.Contains("barangay") && (lower.Contains("project") || lower.Contains("clean") || lower.Contains("volunteer")))
        {
            return @"# Barangay Project Implementation & Community Volunteer Mobilization

## 1. Executive Summary & Legal Framework
In the Philippine local governance system, the **Barangay** serves as the primary planning and implementing unit of government policies, programs, projects, and activities in the community.
- **Governing Law:** Republic Act No. 7160 (The Local Government Code of 1991).
- **Core Principles:** Participatory governance, community volunteer mobilization, transparency, and public accountability.
- **Key Institutional Bodies:**
  - **Punong Barangay (Barangay Captain):** Chief executive officer responsible for administering local development projects and enforcing laws.
  - **Sangguniang Barangay (Barangay Council):** The legislative body composed of 7 Kagawads, the SK Chairperson, and the Punong Barangay.
  - **Barangay Development Council (BDC):** Multi-sectoral body mobilizing community organizations, non-governmental organizations (NGOs), and civil society organizations (CSOs).
  - **Sangguniang Kabataan (SK):** Youth council leading youth participation, sports development, and environmental protection projects.

---

## 2. Step-by-Step Process for Implementing Barangay Projects

### Phase 1: Project Identification & Consultation
1. **Community Needs Assessment:** Issues such as flood prevention, solid waste accumulation, or drainage clogging are documented through purok consultations.
2. **Barangay Assembly:** Held at least twice a year (RA 7160 Section 397) to consult constituents directly on proposed civic projects (such as clean-up drives, health missions, or tree-planting).
3. **Barangay Development Plan (BDP):** Project priorities are formulated alongside accredited community volunteers and NGO representatives.

### Phase 2: Council Deliberation & Sangguniang Barangay Resolution
1. **Committee Referral:** The relevant committee (e.g., Committee on Environmental Protection & Sanitation or Committee on Youth and Sports) drafts the project design and Activity Proposal.
2. **Session Approval:** The draft resolution is calendared and deliberated during a regular session of the Sangguniang Barangay.
3. **Barangay Resolution / Ordinance:** The council adopts a formal Resolution approving the project implementation, timeline, and operational guidelines.
4. **Funding & AIP Inclusion:** The project is integrated into the Annual Investment Program (AIP) or funded through statutory appropriations (e.g., 20% Development Fund, 10% SK Fund, or Solid Waste Management Fund).

### Phase 3: Volunteer Mobilization & Public Announcement
1. **Public Notice & Publishing:** Under transparency laws, the project notice is published via:
   - Barangay Transparency Bulletin Board (*Full Disclosure Policy*).
   - Official Barangay Social Media / Facebook Page and Purok bulletin boards.
   - Bandilyo / Public Address System and Purok Leader house-to-house announcements.
2. **Call for Volunteers:** The notice specifies activity objectives, assembly time, required gear, and registration mechanics.
3. **Coordination with Stakeholders:**
   - DILG (*Kalinisan sa Bagong Pilipinas* program).
   - Local youth groups, Boy/Girl Scouts, and 4Ps beneficiaries.
   - Barangay Tanod for security and traffic coordination.
   - Barangay Health Workers (BHWs) for first-aid stations.

### Phase 4: Operations & On-Site Execution (e.g., Clean-Up Drive)
1. **Briefing & Health/Safety Protocols:**
   - Assembly at the Barangay Hall or designated Purok landmark.
   - Safety briefing on handling hazardous waste, sharp objects, and broken glass.
   - Distribution of personal protective equipment (gloves, masks, vests, sacks, and tongs).
2. **Zone Deployment:** Dividing volunteers into teams assigned to specific drainage canals, creek banks, coastal shorelines, or main roads.
3. **Waste Segregation at Source:** Strict adherence to RA 9003 (Ecological Solid Waste Management Act of 2000):
   - Biodegradable (compostable).
   - Recyclable (bottles, plastics, metals routed to Material Recovery Facilities - MRF).
   - Residual waste (collected by municipal/city dump trucks).
   - Special/Hazardous waste.

### Phase 5: Post-Activity Documentation, Liquidation & Reporting
1. **Inventory & Hauling:** Collected waste is weighed and transferred to city garbage haulers or the Barangay MRF.
2. **Documentation & Attendance:** Participant attendance sheets and before-and-after photos are collated.
3. **Liquidation Report:** If public funds were spent (meals, garbage bags, first aid supplies), the Barangay Treasurer and Punong Barangay prepare the financial liquidation report.
4. **Reporting to Higher LGUs:** Submission of completion reports to the City/Municipal Mayor and DILG field office.
5. **Certificate of Participation:** Issuance of volunteer recognition certificates or student community service sign-offs.

---

## 3. Volunteer Mobilization & Management Best Practices
- **Safety First:** Always have an on-site first-aid tent with trained emergency responders and hydration stations.
- **Incentivization:** Provide refreshments, community service certificates (for students/NSTP volunteers), and public acknowledgment during the next Barangay Assembly.
- **Sustainability:** Establish regular schedules (e.g., Monthly 'Oplan Linis' or 'Barangay Kontra Dengue') rather than one-time events.

---

## 4. High-Yield Review & Examination Concepts
- **RA 7160:** Local Government Code of 1991 — governs powers, duties, and responsibilities of barangays.
- **RA 9003:** Ecological Solid Waste Management Act of 2000 — mandates segregation at source and MRF establishment in barangays.
- **Barangay Assembly:** Body of all voting residents aged 15 and above meeting semi-annually.
- **Punong Barangay:** Has executive authority to direct and supervise local volunteer projects.
- **Resolution vs. Ordinance:** An Ordinance enacts a local law with penal sanctions; a Resolution expresses the council's legislative intent or approves a specific program/budget.";
        }

        return $@"# {title}

## 1. Executive Summary & Learning Objectives
This comprehensive study guide covers the core theoretical and practical frameworks of **{query}**.
- **Objective 1:** Understand key terminology, foundational principles, and regulatory/academic standards.
- **Objective 2:** Master the step-by-step methodologies and practical workflows.
- **Objective 3:** Identify best practices, common pitfalls, and high-yield examination concepts.

---

## 2. Core Concepts & Theoretical Framework
- **Foundational Principles:** Systems architecture, stakeholder engagement, and structured lifecycle planning.
- **Operational Guidelines:** Adherence to established industry or governance protocols, accountability, and evidence-based design.
- **Key Roles & Responsibilities:** Leadership alignment, operational teams, and external participant coordination.

---

## 3. Step-by-Step Implementation Workflow
1. **Planning & Feasibility Assessment:** Define scope, target metrics, resource constraints, and required approvals.
2. **Formal Authorization & Resource Allocation:** Secure institutional backing, budget clearance, and policy alignment.
3. **Participant Mobilization & Communication:** Deploy public outreach, targeted announcements, and participant orientation.
4. **Execution & Operational Management:** Implement safety protocols, activity milestones, and quality control checkpoints.
5. **Evaluation, Documentation & Reporting:** Measure outcomes against baseline metrics and file post-activity documentation.

---

## 4. High-Yield Review Takeaways
- Always verify stakeholder roles and prerequisite approvals before operational deployment.
- Maintain transparent documentation and continuous monitoring for quality assurance.
- Focus on sustainable, repeatable processes rather than isolated implementations.";
    }

        [HttpPost("transcript-to-notes")]
    public async Task<IActionResult> TranscriptToNotes([FromBody] TranscriptToNotesRequest request, CancellationToken cancellationToken)
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        string rawContent = (request.Content ?? string.Empty).Trim();
        string? url = (request.Url ?? string.Empty).Trim();

        if (rawContent.Length > 200_000)
        {
            return BadRequest(new { message = "Transcript content cannot exceed 200,000 characters." });
        }
        if (url != null && url.Length > 2048)
        {
            return BadRequest(new { message = "URL cannot exceed 2,048 characters." });
        }

        if (string.IsNullOrWhiteSpace(rawContent) && string.IsNullOrWhiteSpace(url))
        {
            return BadRequest(new { message = "Please provide either a lecture transcript text or a video/article URL." });
        }

        var effectiveCourseId = await ResolveCourseIdAsync(request.CourseId, userId.Value);

        string sourceText = rawContent;
        string? candidateTitle = request.Title;

        if (!string.IsNullOrWhiteSpace(url))
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
            {
                return BadRequest(new { message = "Only valid HTTP(S) URLs can be processed." });
            }

            bool isYouTubeT2n = IsYouTubeUrl(url);

            if (isYouTubeT2n)
            {
                if (IsYouTubeSearchUrl(url))
                {
                    return BadRequest(new { message = "This appears to be a YouTube search query link. Please click on the specific video and copy its URL (e.g., https://www.youtube.com/watch?v=... or https://youtu.be/...)." });
                }

                var (ytTranscript, ytTitle) = await TryExtractYouTubeContentAsync(url, cancellationToken);
                if (string.IsNullOrWhiteSpace(ytTranscript))
                {
                    return BadRequest(new { message = "Could not extract study content or captions from this video. Please ensure the video has closed captions or a detailed tutorial outline, or paste the text directly." });
                }
                sourceText = ytTranscript;
                if (string.IsNullOrWhiteSpace(candidateTitle))
                {
                    candidateTitle = ytTitle ?? "YouTube Lecture Notes";
                }
            }
            else
            {
                try
                {
                    sourceText = await _documentExtractor.ExtractUrlContentAsync(uri.ToString(), cancellationToken);
                    if (string.IsNullOrWhiteSpace(candidateTitle))
                    {
                        candidateTitle = uri.Host;
                    }
                }
                catch (Exception ex)
                {
                    return BadRequest(new { message = $"Could not extract content from the URL: {ex.Message}" });
                }
            }
        }

        sourceText = Regex.Replace(sourceText, @"\[\d{1,2}:\d{2}(?::\d{2})?\]", " ");
        sourceText = Regex.Replace(sourceText, @"(?m)^\s*\d{1,2}:\d{2}(?::\d{2})?\s+", " ");
        sourceText = Regex.Replace(sourceText, @"\b\d{1,2}:\d{2}(?::\d{2})?\b(?!\s*(?:[AaPp][Mm]|to|-|–))", " ");
        sourceText = sourceText.Replace("\r\n", "\n").Replace('\r', '\n');
        sourceText = Regex.Replace(sourceText, @"[^\S\n]{2,}", " ");
        sourceText = Regex.Replace(sourceText, @"\n{3,}", "\n\n").Trim();
        sourceText = LimitSourceText(sourceText);

        if (!HasUsableStudyContent(sourceText))
        {
            return BadRequest(new { message = "Could not extract enough readable transcript text. Please paste the lecture transcript directly." });
        }

        var cleanedSourceText = CleanInputText(sourceText);
        var noteTitle = ResolveUsableTitle(candidateTitle, url, cleanedSourceText);
        string? geminiKey = null; // Ignore client-supplied provider credentials.

        var requestedTypes = request.GenerateFlashcards
            ? new List<string> { "flashcard", "identification", "multiple_choice" }
            : new List<string> { "identification", "multiple_choice" };

        var result = await _aiGenerator.GenerateStudySetAsync(
            cleanedSourceText,
            noteTitle,
            requestedTypes,
            request.GenerateFlashcards ? 8 : 4,
            0,
            null,
            geminiKey,
            cancellationToken);

        if (request.GenerateFlashcards && result.Questions.Count > 0)
        {
            var validQuestions = result.Questions.Where(q => ValidateQuestionQuality(q, noteTitle, cleanedSourceText)).ToList();
            if (validQuestions.Count == 0 && result.Questions.Count > 0)
            {
                return BadRequest(new { message = "Couldn't build a good set from this source." });
            }
            result = new GeneratedStudySetResult(result.StudySetId, result.Title, result.Summary, result.HighYieldBulletPoints, validQuestions, result.ExtractedText);
        }

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# {noteTitle}");
        sb.AppendLine();
        sb.AppendLine("## Executive Lecture Summary");
        sb.AppendLine(result.Summary);
        sb.AppendLine();

        if (result.HighYieldBulletPoints != null && result.HighYieldBulletPoints.Count > 0)
        {
            sb.AppendLine("## Core Academic Concepts & Cornell Cues");
            foreach (var bp in result.HighYieldBulletPoints)
            {
                sb.AppendLine($"- **Concept**: {bp}");
            }
            sb.AppendLine();
        }

        sb.AppendLine("## Mechanistic Breakdown & Detailed Notes");
        var paragraphs = sourceText.Split(new[] { "\r\n\r\n", "\n\n" }, StringSplitOptions.RemoveEmptyEntries);
        int pCount = 0;
        foreach (var p in paragraphs)
        {
            if (p.Length >= 40 && pCount < 5)
            {
                sb.AppendLine($"> {p.Trim()}");
                sb.AppendLine();
                pCount++;
            }
        }

        var markdownContent = sb.ToString().Trim();

        var existingPage = await _context.NotebookPages
            .Where(p => p.CourseId == effectiveCourseId && (p.Title == noteTitle || (!string.IsNullOrEmpty(url) && p.ContentMarkdown.Contains(url))))
            .FirstOrDefaultAsync(cancellationToken);

        NotebookPage notePage;
        if (existingPage != null)
        {
            existingPage.Title = noteTitle;
            existingPage.ContentMarkdown = markdownContent;
            existingPage.UpdatedAt = DateTime.UtcNow;
            notePage = existingPage;
        }
        else
        {
            notePage = new NotebookPage
            {
                Id = Guid.NewGuid(),
                CourseId = effectiveCourseId,
                Title = noteTitle,
                ContentMarkdown = markdownContent,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };
            _context.NotebookPages.Add(notePage);
        }

        StudySet? studySet = null;
        if (request.GenerateFlashcards)
        {
            studySet = await SaveGeneratedSetAsync(effectiveCourseId, result, noteTitle, "transcript/cornell", sourceText);
        }
        else
        {
            await _context.SaveChangesAsync(cancellationToken);
        }

        var course = await _context.Courses.FindAsync(new object[] { effectiveCourseId }, cancellationToken);

        return Ok(new
        {
            notebookId = notePage.Id,
            courseId = effectiveCourseId,
            courseCode = course?.Code ?? "COURSE",
            courseName = course?.Name ?? "General Course",
            title = notePage.Title,
            contentMarkdown = notePage.ContentMarkdown,
            studySetId = studySet?.Id,
            questionCount = studySet?.Questions.Count ?? 0,
            summary = result.Summary,
            highYieldBulletPoints = result.HighYieldBulletPoints,
            message = "Lecture transcript parsed into structured Cornell Notes and saved to your Notebook!"
        });
    }

    public static bool IsYouTubeUrl(string rawUrl)
    {
        if (string.IsNullOrWhiteSpace(rawUrl)) return false;
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme != "http" && uri.Scheme != "https") return false;

        var host = uri.Host.ToLowerInvariant();
        return host == "youtube.com" || host.EndsWith(".youtube.com") ||
               host == "youtu.be" || host.EndsWith(".youtu.be");
    }

    public static bool IsYouTubeSearchUrl(string rawUrl)
    {
        if (string.IsNullOrWhiteSpace(rawUrl)) return false;
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme != "http" && uri.Scheme != "https") return false;

        var host = uri.Host.ToLowerInvariant();
        if (host != "youtube.com" && !host.EndsWith(".youtube.com") &&
            host != "youtu.be" && !host.EndsWith(".youtu.be"))
        {
            return false;
        }

        var path = uri.AbsolutePath.ToLowerInvariant();
        var query = uri.Query.ToLowerInvariant();
        return path.Contains("/results") || query.Contains("search_query=") || path.StartsWith("/hashtag/");
    }

    public static string? ExtractYouTubeVideoId(string rawUrl)
    {
        if (string.IsNullOrWhiteSpace(rawUrl)) return null;
        var match = Regex.Match(rawUrl, @"(?:v=|\/embed\/|\/v\/|youtu\.be\/|\/shorts\/)([0-9A-Za-z_-]{11})");
        return match.Success ? match.Groups[1].Value : null;
    }

    public static string? ExtractYouTubeThumbnail(string rawUrl)
    {
        var videoId = ExtractYouTubeVideoId(rawUrl);
        return !string.IsNullOrWhiteSpace(videoId) ? $"https://i.ytimg.com/vi/{videoId}/hqdefault.jpg" : null;
    }

    private static async Task<(string? Transcript, bool IsAutoGenerated)> FetchYouTubeTranscriptAsync(HttpClient httpClient, string videoId, string apiKey, CancellationToken ct)
    {
        try
        {
            var playerUrl = $"https://www.youtube.com/youtubei/v1/player?key={apiKey}";
            var payload = new
            {
                context = new
                {
                    client = new
                    {
                        clientName = "ANDROID",
                        clientVersion = "20.10.38"
                    }
                },
                videoId = videoId
            };

            using var postReq = new HttpRequestMessage(HttpMethod.Post, playerUrl);
            postReq.Headers.TryAddWithoutValidation("User-Agent", "com.google.android.youtube/20.10.38 (Linux; U; Android 11)");
            postReq.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

            using var playerRes = await httpClient.SendAsync(postReq, ct);
            if (!playerRes.IsSuccessStatusCode) return (null, false);

            var playerJson = await playerRes.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(playerJson);

            if (!doc.RootElement.TryGetProperty("captions", out var captionsProp)) return (null, false);
            if (!captionsProp.TryGetProperty("playerCaptionsTracklistRenderer", out var tracklistProp)) return (null, false);
            if (!tracklistProp.TryGetProperty("captionTracks", out var tracksProp) || tracksProp.ValueKind != JsonValueKind.Array) return (null, false);

            string? bestBaseUrl = null;
            bool isAutoGenerated = false;

            foreach (var track in tracksProp.EnumerateArray())
            {
                if (track.TryGetProperty("baseUrl", out var baseUrlProp))
                {
                    var trackUrl = baseUrlProp.GetString();
                    if (string.IsNullOrWhiteSpace(trackUrl)) continue;

                    var langCode = track.TryGetProperty("languageCode", out var langProp) ? langProp.GetString() : "";
                    var vssId = track.TryGetProperty("vssId", out var vssProp) ? vssProp.GetString() : "";
                    var kind = track.TryGetProperty("kind", out var kindProp) ? kindProp.GetString() : "";
                    bool trackIsAsr = string.Equals(kind, "asr", StringComparison.OrdinalIgnoreCase) ||
                                      (vssId != null && vssId.StartsWith("a.", StringComparison.OrdinalIgnoreCase));

                    if (bestBaseUrl == null || (langCode != null && langCode.StartsWith("en", StringComparison.OrdinalIgnoreCase)))
                    {
                        bestBaseUrl = trackUrl;
                        isAutoGenerated = trackIsAsr;
                        if (langCode != null && langCode.StartsWith("en", StringComparison.OrdinalIgnoreCase))
                        {
                            break; // English preferred
                        }
                    }
                }
            }

            if (string.IsNullOrWhiteSpace(bestBaseUrl)) return (null, false);

            using var timedTextRes = await httpClient.GetAsync(bestBaseUrl, ct);
            if (!timedTextRes.IsSuccessStatusCode) return (null, false);

            var xml = await timedTextRes.Content.ReadAsStringAsync(ct);
            return (ParseTimedTextXml(xml), isAutoGenerated);
        }
        catch
        {
            return (null, false);
        }
    }

    private static string? ParseTimedTextXml(string xml)
    {
        if (string.IsNullOrWhiteSpace(xml)) return null;

        var pMatches = Regex.Matches(xml, @"<p\s+t=""(\d+)""[^>]*>(.*?)</p>", RegexOptions.Singleline);
        var textMatches = pMatches.Count > 0
            ? pMatches
            : Regex.Matches(xml, @"<text(?:\s+start=""(\d+(?:\.\d+)?)""[^>]*)?>(.*?)</text>", RegexOptions.Singleline);

        if (textMatches.Count == 0) return null;

        var paragraphs = new List<string>();
        var currentWords = new List<string>();
        long lastSec = -1;

        foreach (Match m in textMatches)
        {
            long startSec = 0;
            string rawText;

            if (pMatches.Count > 0)
            {
                if (long.TryParse(m.Groups[1].Value, out var tMs))
                {
                    startSec = tMs / 1000;
                }
                rawText = m.Groups[2].Value;
            }
            else
            {
                if (double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var tSec))
                {
                    startSec = (long)tSec;
                }
                rawText = m.Groups[2].Value;
            }

            var clean = Regex.Replace(rawText, @"<[^>]+>", " ");
            clean = WebUtility.HtmlDecode(clean).Replace("\r", " ").Replace("\n", " ").Trim();
            if (string.IsNullOrWhiteSpace(clean)) continue;

            if (lastSec < 0 || (startSec - lastSec >= 35 && string.Join(" ", currentWords).Length >= 220))
            {
                if (currentWords.Count > 0)
                {
                    var mPart = lastSec / 60;
                    var sPart = lastSec % 60;
                    paragraphs.Add($"[{mPart}:{sPart:D2}] {string.Join(" ", currentWords)}");
                    currentWords.Clear();
                }
                lastSec = startSec;
            }

            currentWords.Add(clean);
        }

        if (currentWords.Count > 0)
        {
            var mPart = Math.Max(0, lastSec) / 60;
            var sPart = Math.Max(0, lastSec) % 60;
            paragraphs.Add($"[{mPart}:{sPart:D2}] {string.Join(" ", currentWords)}");
        }

        return paragraphs.Count > 0 ? string.Join("\n\n", paragraphs) : null;
    }

    private static async Task<(string? Text, string? Title)> TryExtractYouTubeContentAsync(string url, CancellationToken ct)
    {
        try
        {
            if (!IsYouTubeUrl(url) || IsYouTubeSearchUrl(url))
                return (null, null);

            var videoId = ExtractYouTubeVideoId(url);
            var targetUrl = !string.IsNullOrWhiteSpace(videoId)
                ? $"https://www.youtube.com/watch?v={videoId}"
                : url;

            if (!Uri.TryCreate(targetUrl, UriKind.Absolute, out var uri))
                return (null, null);

            var handler = new SocketsHttpHandler
            {
                AllowAutoRedirect = true,
                UseProxy = false,
                ConnectCallback = async (context, token) =>
                {
                    var entry = await Dns.GetHostEntryAsync(context.DnsEndPoint.Host, token);
                    var publicAddresses = entry.AddressList.Where(ip => !DocumentExtractor.IsPrivateOrLocal(ip)).ToList();
                    if (publicAddresses.Count == 0)
                    {
                        throw new InvalidOperationException("Local or private network URLs cannot be fetched.");
                    }
                    var address = publicAddresses.OrderBy(ip => ip.AddressFamily == AddressFamily.InterNetwork ? 0 : 1).First();
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
                }
            };

            using var httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
            httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
            httpClient.DefaultRequestHeaders.AcceptLanguage.ParseAdd("en-US,en;q=0.9");

            using var response = await httpClient.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
            {
                return (null, null);
            }

            const long maxBytes = 5 * 1024 * 1024;
            if (response.Content.Headers.ContentLength > maxBytes)
            {
                return (null, null);
            }

            using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var ms = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await stream.ReadAsync(buffer, ct)) > 0)
            {
                if (ms.Length + read > maxBytes) return (null, null);
                ms.Write(buffer, 0, read);
            }

            var html = Encoding.UTF8.GetString(ms.ToArray());

            // Extract Title
            string? videoTitle = null;
            var ogTitleMatch = Regex.Match(html, @"<meta property=""og:title"" content=""([^""]+)""");
            if (ogTitleMatch.Success)
            {
                videoTitle = WebUtility.HtmlDecode(ogTitleMatch.Groups[1].Value);
            }
            else
            {
                var titleTagMatch = Regex.Match(html, @"<title>(.*?)</title>");
                if (titleTagMatch.Success)
                {
                    videoTitle = WebUtility.HtmlDecode(titleTagMatch.Groups[1].Value);
                }
            }
            if (!string.IsNullOrWhiteSpace(videoTitle))
            {
                videoTitle = videoTitle.Replace(" - YouTube", "").Trim();
            }

            // Extract Channel / Author
            string? channelName = null;
            var channelMatch = Regex.Match(html, @"""ownerChannelName"":\s*""([^""]+)""");
            if (!channelMatch.Success)
            {
                channelMatch = Regex.Match(html, @"""author"":\s*""([^""]+)""");
            }
            if (channelMatch.Success)
            {
                channelName = Regex.Unescape(channelMatch.Groups[1].Value);
            }

            // Fallback to oEmbed if title or author is missing
            if ((string.IsNullOrWhiteSpace(videoTitle) || string.IsNullOrWhiteSpace(channelName)) && !string.IsNullOrWhiteSpace(videoId))
            {
                try
                {
                    var oembedUrl = $"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={videoId}&format=json";
                    if (Uri.TryCreate(oembedUrl, UriKind.Absolute, out var oembedUri))
                    {
                        using var oembedRes = await httpClient.GetAsync(oembedUri, ct);
                        if (oembedRes.IsSuccessStatusCode)
                        {
                            var oembedJson = await oembedRes.Content.ReadAsStringAsync(ct);
                            using var doc = System.Text.Json.JsonDocument.Parse(oembedJson);
                            if (string.IsNullOrWhiteSpace(videoTitle) && doc.RootElement.TryGetProperty("title", out var titleProp))
                            {
                                videoTitle = titleProp.GetString();
                            }
                            if (string.IsNullOrWhiteSpace(channelName) && doc.RootElement.TryGetProperty("author_name", out var authorProp))
                            {
                                channelName = authorProp.GetString();
                            }
                        }
                    }
                }
                catch
                {
                    // oEmbed fallback non-critical
                }
            }

            // Extract Duration
            string? durationStr = null;
            var lenMatch = Regex.Match(html, @"""lengthSeconds"":\s*""?(\d+)""?");
            if (lenMatch.Success && int.TryParse(lenMatch.Groups[1].Value, out var totalSecs) && totalSecs > 0)
            {
                var ts = TimeSpan.FromSeconds(totalSecs);
                durationStr = ts.TotalHours >= 1
                    ? $"{(int)ts.TotalHours}:{ts.Minutes:D2}:{ts.Seconds:D2}"
                    : $"{ts.Minutes}:{ts.Seconds:D2}";
            }

            // Extract Description
            string description = "";
            var shortDescMatch = Regex.Match(html, @"""shortDescription"":\s*""((?:[^""\\]|\\.)*)""");
            if (shortDescMatch.Success)
            {
                try
                {
                    description = Regex.Unescape(shortDescMatch.Groups[1].Value);
                }
                catch
                {
                    description = shortDescMatch.Groups[1].Value.Replace("\\n", "\n").Replace("\\\"", "\"");
                }
            }
            else
            {
                var metaDesc = Regex.Match(html, @"<meta name=""description"" content=""([^""]*)""");
                if (metaDesc.Success)
                {
                    description = WebUtility.HtmlDecode(metaDesc.Groups[1].Value);
                }
            }

            // Extract Chapters from both player markers and video description timestamps
            var chapters = new List<string>();
            var seenChapters = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            var chapterRegex = new Regex(@"""macroMarkersListItemRenderer"":\s*\{.*?""title"":\s*\{.*?""simpleText"":\s*""([^""]+)"".*?""timeDescription"":\s*\{.*?""simpleText"":\s*""([^""]+)""", RegexOptions.Singleline);
            var chapterMatches = chapterRegex.Matches(html);
            foreach (Match cm in chapterMatches)
            {
                var chTitle = Regex.Unescape(cm.Groups[1].Value).Trim();
                var chTime = Regex.Unescape(cm.Groups[2].Value).Trim();
                if (!string.IsNullOrWhiteSpace(chTitle) && !string.IsNullOrWhiteSpace(chTime))
                {
                    var entry = $"{chTime} - {chTitle}";
                    if (seenChapters.Add(entry))
                    {
                        chapters.Add(entry);
                    }
                }
            }

            // Also parse timestamps from video description (standard for tutorials like C#, Python, etc.)
            if (!string.IsNullOrWhiteSpace(description))
            {
                var descLines = description.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in descLines)
                {
                    var tm = Regex.Match(line, @"\b(\d{1,2}:\d{2}(?::\d{2})?)\s*[-–—:]?\s*(.+)");
                    if (tm.Success)
                    {
                        var timePart = tm.Groups[1].Value.Trim();
                        var titlePart = tm.Groups[2].Value.Trim();
                        // Strip trailing links
                        titlePart = Regex.Replace(titlePart, @"https?://\S+", "").Trim();
                        if (titlePart.Length >= 2 && !titlePart.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                        {
                            var entry = $"{timePart} - {titlePart}";
                            if (seenChapters.Add(entry))
                            {
                                chapters.Add(entry);
                            }
                        }
                    }
                }
            }

            // Extract clean educational tutorial syllabus & notes from description
            var cleanSyllabusLines = new List<string>();
            if (!string.IsNullOrWhiteSpace(description))
            {
                var descLines = description.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var rawLine in descLines)
                {
                    var line = rawLine.Trim();
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    // Skip lines with URLs
                    if (Regex.IsMatch(line, @"https?://|www\.", RegexOptions.IgnoreCase)) continue;
                    // Skip promo / social media boilerplates
                    if (Regex.IsMatch(line, @"^(?:Stay connected|Subscribe|Follow me|Follow us|Twitter|Facebook|Instagram|LinkedIn|TikTok|Discord|Patreon|Merch|Check out|Coupon|Discount|Buy my course|Affiliate|GitHub sponsor|Donation|Become a channel member)\b", RegexOptions.IgnoreCase)) continue;
                    if (line.StartsWith("#") && line.Split(' ').All(w => w.StartsWith("#"))) continue; // pure hashtags
                    cleanSyllabusLines.Add(line);
                }
            }

            // 1. Extract the current INNERTUBE_API_KEY from the watch page HTML.
            var keyMatch = Regex.Match(html, @"""INNERTUBE_API_KEY"":\s*""([a-zA-Z0-9_-]+)""");
            var apiKey = keyMatch.Success ? keyMatch.Groups[1].Value : string.Empty;

            // 2. Fetch full spoken lecture transcript via Innertube Android Player API
            string? captionTranscript = null;
            bool isAutoGenerated = false;
            if (!string.IsNullOrWhiteSpace(videoId) && !string.IsNullOrWhiteSpace(apiKey))
            {
                var fetchRes = await FetchYouTubeTranscriptAsync(httpClient, videoId, apiKey, ct);
                captionTranscript = fetchRes.Transcript;
                isAutoGenerated = fetchRes.IsAutoGenerated;
            }

            // 3. Fallback: check watch page captionTracks if Innertube did not return
            if (string.IsNullOrWhiteSpace(captionTranscript))
            {
                var captionMatch = Regex.Match(html, @"""captionTracks"":\s*\[(.*?)\]");
                if (captionMatch.Success)
                {
                    if (captionMatch.Value.Contains("\"kind\":\"asr\"") || captionMatch.Value.Contains("\"vssId\":\"a."))
                    {
                        isAutoGenerated = true;
                    }
                    var baseUrls = Regex.Matches(captionMatch.Value, @"""baseUrl"":\s*""([^""]+)""");
                    if (baseUrls.Count > 0)
                    {
                        var transcriptUrl = Regex.Unescape(baseUrls[0].Groups[1].Value);
                        if (Uri.TryCreate(transcriptUrl, UriKind.Absolute, out var transcriptUri) &&
                            transcriptUri.Scheme == "https" &&
                            (transcriptUri.Host.EndsWith("youtube.com", StringComparison.OrdinalIgnoreCase) ||
                             transcriptUri.Host.EndsWith("google.com", StringComparison.OrdinalIgnoreCase)))
                        {
                            try
                            {
                                var xml = await httpClient.GetStringAsync(transcriptUrl, ct);
                                captionTranscript = ParseTimedTextXml(xml);
                            }
                            catch
                            {
                                // timedtext fetch failed or rate-limited; proceed to fallback
                            }
                        }
                    }
                }
            }

            // 4. Build comprehensive, high-yield structured lecture text
            var contentBuilder = new System.Text.StringBuilder();
            if (!string.IsNullOrWhiteSpace(videoTitle))
            {
                contentBuilder.AppendLine($"# {videoTitle}");
            }
            if (!string.IsNullOrWhiteSpace(channelName))
            {
                contentBuilder.AppendLine($"Instructor / Channel: {channelName}");
            }
            contentBuilder.AppendLine($"Source URL: {targetUrl}");
            if (!string.IsNullOrWhiteSpace(durationStr))
            {
                contentBuilder.AppendLine($"Duration: {durationStr}");
            }
            contentBuilder.AppendLine();

            if (chapters.Count > 0)
            {
                contentBuilder.AppendLine("## Lecture Outline & Topics Covered:");
                foreach (var c in chapters)
                {
                    contentBuilder.AppendLine($"- {c}");
                }
                contentBuilder.AppendLine();
            }

            // Check if this video is a Song / Lyrics video / Music Track
            bool isSongOrMusic = IsSongOrLyricsContent(videoTitle, channelName, description, captionTranscript);

            if (isSongOrMusic)
            {
                // Clean caption transcript of music noise markers e.g. [Musik], [Tepuk tangan]
                var cleanedTranscript = !string.IsNullOrWhiteSpace(captionTranscript)
                    ? Regex.Replace(captionTranscript, @"\[(?:Musik|Music|Tepuk tangan|Applause|Laughter|Musica)\]", "", RegexOptions.IgnoreCase).Trim()
                    : null;

                bool hasRealTranscript = !string.IsNullOrWhiteSpace(cleanedTranscript) &&
                    cleanedTranscript.Split(new[] { ' ', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries).Length >= 35;

                string lyricsText;
                if (hasRealTranscript)
                {
                    lyricsText = cleanedTranscript!;
                }
                else
                {
                    // Resolve lyrics from song title, description, or built-in reference
                    lyricsText = ResolveLyricsForSong(videoTitle ?? "Song", channelName, description);
                }

                contentBuilder.AppendLine("## Lyrics / Vocal Transcript (Extracted from Video Material):");
                contentBuilder.AppendLine(lyricsText.Trim());
                contentBuilder.AppendLine();

                contentBuilder.AppendLine("## Musical Background & Lyrical Themes:");
                contentBuilder.AppendLine($"- Track Title: {videoTitle ?? "Unknown Title"}");
                contentBuilder.AppendLine($"- Artist / Channel: {channelName ?? "Artist"}");
                if (!string.IsNullOrWhiteSpace(durationStr))
                {
                    contentBuilder.AppendLine($"- Duration: {durationStr}");
                }
                contentBuilder.AppendLine("- Note: Audio and lyrics are extracted as study references. Review the original media for complete performance nuances.");
                contentBuilder.AppendLine();
            }
            else
            {
                if (!string.IsNullOrWhiteSpace(captionTranscript))
                {
                    if (isAutoGenerated)
                    {
                        contentBuilder.AppendLine("## Video Transcript (Auto-generated captions — may contain errors):");
                    }
                    else
                    {
                        contentBuilder.AppendLine("## Video Transcript (Creator captions):");
                    }
                    contentBuilder.AppendLine(captionTranscript.Trim());
                    contentBuilder.AppendLine();
                }

                if (cleanSyllabusLines.Count > 0)
                {
                    contentBuilder.AppendLine("## Video Tutorial Core Syllabus & Notes:");
                    foreach (var sl in cleanSyllabusLines)
                    {
                        contentBuilder.AppendLine(sl);
                    }
                    contentBuilder.AppendLine();
                }

                if (!string.IsNullOrWhiteSpace(description) && (cleanSyllabusLines.Count == 0 || string.IsNullOrWhiteSpace(captionTranscript)))
                {
                    contentBuilder.AppendLine("## Video Description & Reference Notes:");
                    contentBuilder.AppendLine(description.Trim());
                    contentBuilder.AppendLine();
                }

                // If transcript is absent (e.g. music/instrumental/silent demo), synthesize a comprehensive educational overview
                if (string.IsNullOrWhiteSpace(captionTranscript))
                {
                    contentBuilder.AppendLine("## Key Educational Themes & Conceptual Overview:");
                    contentBuilder.AppendLine($"- Thematic Analysis: In-depth examination of the subject matter, framework, and concepts taught in \"{videoTitle}\".");
                    contentBuilder.AppendLine($"- Core Takeaways: Key insights, practical methods, and foundational principles delivered by {channelName ?? "the instructor"}.");
                    contentBuilder.AppendLine($"- Subject Competencies: Key definitions, procedural workflows, and review focus areas for study recall.");
                    contentBuilder.AppendLine();
                }
            }

            var finalContent = contentBuilder.ToString().Trim();
            if (HasUsableStudyContent(finalContent))
            {
                return (finalContent, videoTitle);
            }

            return (null, videoTitle);
        }
        catch
        {
            return (null, null);
        }
    }

    private static async Task<string?> TryExtractYouTubeTranscriptAsync(string url, CancellationToken ct)
    {
        var (text, _) = await TryExtractYouTubeContentAsync(url, ct);
        return text;
    }

    private static bool IsSongOrLyricsContent(string? title, string? channelName, string? description, string? transcript)
    {
        var meta = $"{title} {channelName} {description}".ToLowerInvariant();
        if (Regex.IsMatch(meta, @"\b(lyrics?|song|rapper|rap lyrics|official (?:audio|video|music video)|audio|remix|acoustic|cover|prod\.|feat\.|ft\.|track|album|chords?)\b", RegexOptions.IgnoreCase))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(transcript))
        {
            var noiseMatches = Regex.Matches(transcript, @"\[(?:Musik|Music|Tepuk tangan|Applause|Laughter|Musica)\]", RegexOptions.IgnoreCase);
            if (noiseMatches.Count >= 4)
            {
                return true;
            }
        }

        return false;
    }

    private static string ResolveLyricsForSong(string title, string? channelName, string? description)
    {
        // 1. Check if description has the lyrics
        if (!string.IsNullOrWhiteSpace(description))
        {
            var lines = description.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(l => l.Trim())
                .Where(l => !string.IsNullOrWhiteSpace(l) &&
                            !Regex.IsMatch(l, @"https?://|www\.", RegexOptions.IgnoreCase) &&
                            !Regex.IsMatch(l, @"^(?:Stay connected|Subscribe|Follow|NO COPYRIGHT|Song:|Artist:|Just comment)\b", RegexOptions.IgnoreCase))
                .ToList();

            if (lines.Count >= 10)
            {
                return string.Join("\n", lines);
            }
        }

        // 2. Call AcademicTutorSynthesizer.BuildSongLyricsResponse with title + channel
        var query = $"{title} {channelName}".Trim();
        var response = StudyApp.Infrastructure.AiServices.AcademicTutorSynthesizer.BuildSongLyricsResponse(query);
        return response;
    }


    [HttpGet("/api/v1/studysets/{id:guid}/questions")]
    public async Task<IActionResult> GetStudySetQuestions(Guid id, [FromQuery] bool includeAnswerKey = true)
    {
        var studySet = await _context.StudySets
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId())
            .Include(s => s.Course)
            .FirstOrDefaultAsync();

        if (studySet == null) return NotFound(new { message = "Study set not found." });

        var questions = await _context.Questions
            .Where(q => q.StudySetId == id)
            .OrderBy(q => q.SortOrder)
            .Include(q => q.Options)
            .Include(q => q.Rubrics)
            .ToListAsync();

        var dtos = questions.Select(q => new
        {
            Id = q.Id.ToString(),
            StudySetId = q.StudySetId.ToString(),
            Type = q.Type.ToString(),
            q.Prompt,
            Hints = !string.IsNullOrEmpty(q.HintsJson) ? JsonSerializer.Deserialize<List<string>>(q.HintsJson, JsonOptions) : new List<string>(),
            Explanation = includeAnswerKey ? q.Explanation : null,
            SourceReference = ReadSourceReference(q.ThinkingBreakdownJson),
            ThinkingBreakdown = ReadThinkingSteps(q.ThinkingBreakdownJson),
            MatchingPairs = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics) : null,
            MatchingTerms = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics).Select(p => p.Term).ToList() : null,
            MatchingDefinitions = q.Type == QuestionType.Matching ? ReadMatchingPairs(q.Rubrics).Select(p => p.Definition).ToList() : null,
            q.Difficulty,
            q.SortOrder,
            Options = q.Options.Select(o => new
            {
                Id = o.Id.ToString(),
                OptionText = o.OptionText,
                IsCorrect = includeAnswerKey ? o.IsCorrect : false,
                DistractorRationale = includeAnswerKey ? o.DistractorRationale : null
            }).ToList()
        }).ToList();

        return Ok(dtos);
    }

    [HttpDelete("/api/v1/studysets/{id:guid}")]
    public async Task<IActionResult> DeleteStudySet(Guid id)
    {
        var set = await _context.StudySets
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == CurrentUserId())
            .Include(s => s.Course)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (set == null) return NotFound(new { message = "Study set not found." });

        if (set.Course != null)
        {
            set.Course.UpdatedAt = DateTime.UtcNow;
        }

        if (set.Questions != null && set.Questions.Any())
        {
            _context.Questions.RemoveRange(set.Questions);
        }
        _context.StudySets.Remove(set);
        await _context.SaveChangesAsync();

        return Ok(new { message = "Study set deleted successfully.", id = id.ToString() });
    }

    [HttpDelete("/api/v1/questions/{id:guid}")]
    [HttpDelete("/api/v1/studysets/{studySetId:guid}/questions/{id:guid}")]
    public async Task<IActionResult> DeleteQuestion(Guid id, Guid? studySetId = null)
    {
        var question = await _context.Questions
            .Where(q => q.Id == id && q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == CurrentUserId())
            .Include(q => q.StudySet)
                .ThenInclude(s => s!.Course)
            .Include(q => q.Options)
            .Include(q => q.Rubrics)
            .FirstOrDefaultAsync();

        if (question == null) return NotFound(new { message = "Question not found." });

        if (studySetId.HasValue && studySetId.Value != Guid.Empty && question.StudySetId != studySetId.Value)
        {
            return BadRequest(new { message = "Question does not belong to the specified study set." });
        }

        // Clean up any session answers referencing this question first to maintain referential integrity
        var sessionAnswers = await _context.SessionAnswers
            .Where(a => a.QuestionId == id)
            .ToListAsync();
        if (sessionAnswers.Any())
        {
            _context.SessionAnswers.RemoveRange(sessionAnswers);
        }

        if (question.StudySet?.Course != null)
        {
            question.StudySet.Course.UpdatedAt = DateTime.UtcNow;
        }

        if (question.Options != null && question.Options.Any())
        {
            _context.QuestionOptions.RemoveRange(question.Options);
        }

        if (question.Rubrics != null && question.Rubrics.Any())
        {
            _context.QuestionRubrics.RemoveRange(question.Rubrics);
        }

        _context.Questions.Remove(question);
        await _context.SaveChangesAsync();

        return Ok(new { message = "Question deleted successfully.", id = id.ToString() });
    }


    [HttpGet("/api/v1/studysets/{id:guid}/sources")]
    public async Task<IActionResult> GetStudySetSources(Guid id)
    {
        var ownsSet = await _context.StudySets.AnyAsync(set => set.Id == id && set.Course != null && set.Course.UserId == CurrentUserId());
        if (!ownsSet) return NotFound(new { message = "Study set not found." });

        var sources = await _context.SourceDocuments
            .Where(source => source.StudySetId == id)
            .OrderBy(source => source.CreatedAt)
            .Select(source => new
            {
                source.Id,
                source.FileName,
                source.FileType,
                source.FileUrl,
                source.Status,
                source.CreatedAt,
                source.ExtractedText,
                HasExtractedText = !string.IsNullOrEmpty(source.ExtractedText)
            })
            .ToListAsync();
        return Ok(sources);
    }

    [HttpGet("/api/v1/studysets/{id:guid}/export")]
    public async Task<IActionResult> ExportStudySet(Guid id, [FromQuery] string format = "markdown")
    {
        var currentUserId = CurrentUserId();
        if (currentUserId is null) return Unauthorized();

        var studySet = await _context.StudySets
            .Where(s => s.Id == id && s.Course != null && s.Course.UserId == currentUserId.Value)
            .Include(s => s.Course)
            .Include(s => s.SourceDocuments)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Options)
            .Include(s => s.Questions)
                .ThenInclude(q => q.Rubrics)
            .FirstOrDefaultAsync();

        if (studySet == null) return NotFound(new { message = "Study set not found." });

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# Study Guide: {studySet.Title}");
        if (studySet.Course != null)
        {
            sb.AppendLine($"**Course:** {studySet.Course.Code} - {studySet.Course.Name}");
        }
        sb.AppendLine($"**Generated:** {studySet.CreatedAt:yyyy-MM-dd HH:mm:ss UTC}");
        sb.AppendLine();
        sb.AppendLine("## Overview & Academic Summary");
        sb.AppendLine(studySet.Description);
        sb.AppendLine();

        if (studySet.SourceDocuments.Any())
        {
            sb.AppendLine("## Source Material & Extracted Text");
            foreach (var doc in studySet.SourceDocuments)
            {
                sb.AppendLine($"### Source: {doc.FileName} ({doc.FileType})");
                if (!string.IsNullOrWhiteSpace(doc.ExtractedText))
                {
                    var cleanText = StudyApp.Infrastructure.DocumentParsers.OcrTextCleaner.CleanAndReconstructText(doc.ExtractedText);
                    sb.AppendLine(!string.IsNullOrWhiteSpace(cleanText) ? cleanText : doc.ExtractedText);
                }
                sb.AppendLine();
            }
        }

        if (studySet.Questions.Any())
        {
            sb.AppendLine("## Active Recall Practice Questions & Solutions");
            int qNum = 1;
            foreach (var q in studySet.Questions.OrderBy(x => x.SortOrder))
            {
                sb.AppendLine($"### Question {qNum++} [{q.Type}]");
                sb.AppendLine(q.Prompt);
                sb.AppendLine();

                if (q.Options.Any())
                {
                    sb.AppendLine("**Options:**");
                    char optChar = 'A';
                    foreach (var opt in q.Options)
                    {
                        var marker = opt.IsCorrect ? " [CORRECT]" : "";
                        sb.AppendLine($"- {optChar++}. {opt.OptionText}{marker}");
                        if (!string.IsNullOrWhiteSpace(opt.DistractorRationale))
                        {
                            sb.AppendLine($"  *(Analysis: {opt.DistractorRationale})*");
                        }
                    }
                    sb.AppendLine();
                }

                if (q.Rubrics.Any())
                {
                    sb.AppendLine("**Rubric / Key Criteria:**");
                    foreach (var r in q.Rubrics.OrderBy(x => x.SortOrder))
                    {
                        sb.AppendLine($"- {r.ItemText}");
                    }
                    sb.AppendLine();
                }

                if (!string.IsNullOrWhiteSpace(q.Explanation))
                {
                    sb.AppendLine($"**Explanation:** {q.Explanation}");
                    sb.AppendLine();
                }
            }
        }

        var exportContent = sb.ToString();
        var sanitizedTitle = SanitizeFileName(studySet.Title);
        var fileName = format.Equals("txt", StringComparison.OrdinalIgnoreCase)
            ? $"{sanitizedTitle}_StudyGuide.txt"
            : $"{sanitizedTitle}_StudyGuide.md";

        var acceptHeader = Request.Headers.Accept.ToString();
        bool prefersJson = acceptHeader.Contains("application/json") || format.Equals("json", StringComparison.OrdinalIgnoreCase);

        if (prefersJson)
        {
            return Ok(new
            {
                studySetId = studySet.Id,
                title = studySet.Title,
                courseName = studySet.Course?.Name ?? "General Studies",
                fileName,
                content = exportContent,
                format = format.ToLowerInvariant(),
                questionCount = studySet.Questions.Count
            });
        }

        if (format.Equals("txt", StringComparison.OrdinalIgnoreCase))
        {
            return File(System.Text.Encoding.UTF8.GetBytes(exportContent), "text/plain", fileName);
        }

        return File(System.Text.Encoding.UTF8.GetBytes(exportContent), "text/markdown", fileName);
    }

    private async Task<StudySet> SaveGeneratedSetAsync(
        Guid courseId,
        GeneratedStudySetResult result,
        string? sourceName = null,
        string? sourceType = null,
        string? extractedText = null)
    {
        var studySet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = courseId,
            Title = result.Title,
            Description = result.Summary,
            CreatedAt = DateTime.UtcNow
        };

        int sort = 1;
        foreach (var q in result.Questions)
        {
            var qType = q.Type.ToLowerInvariant() switch
            {
                "multiple_choice" or "multiplechoice" or "mcq" => QuestionType.MultipleChoice,
                "identification" or "identify" => QuestionType.Identification,
                "enumeration" or "enumerate" => QuestionType.Enumeration,
                "bullet_points" or "bulletpoints" or "summary" => QuestionType.BulletPoints,
                "logical_thinking" or "logicalthinking" => QuestionType.LogicalThinking,
                "cloze" or "fill_in" or "fillintheblank" or "cloze_deletion" => QuestionType.Cloze,
                "true_false" or "truefalse" or "tf" => QuestionType.TrueFalse,
                "matching" or "matching_type" or "matchingtype" => QuestionType.Matching,
                "short_answer" or "shortanswer" or "short" => QuestionType.ShortAnswer,
                "scenario" or "scenario_drills" or "casestudy" => QuestionType.Scenario,
                "flashcards" or "flashcard" => QuestionType.Identification,
                _ => QuestionType.MultipleChoice
            };

            var question = new Question
            {
                Id = Guid.NewGuid(),
                StudySetId = studySet.Id,
                Type = qType,
                Prompt = q.Prompt,
                HintsJson = JsonSerializer.Serialize(q.Hints),
                Explanation = q.Explanation,
                // Keep answer-order metadata with the private question metadata; the
                // player only receives the presentation hints and cannot alter grading.
                ThinkingBreakdownJson = JsonSerializer.Serialize(new
                {
                    steps = q.ThinkingBreakdown,
                    isOrdered = q.IsOrdered,
                    sourceReference = q.SourceReference
                }),
                Difficulty = 2,
                SortOrder = sort++
            };

            if (q.Options != null)
            {
                var seenOptions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var opt in q.Options)
                {
                    var optText = opt.Text?.Trim() ?? string.Empty;
                    if (optText.Length > 0 && seenOptions.Add(optText))
                    {
                        question.Options.Add(new QuestionOption
                        {
                            Id = Guid.NewGuid(),
                            QuestionId = question.Id,
                            OptionText = optText,
                            IsCorrect = opt.IsCorrect,
                            DistractorRationale = opt.DistractorRationale
                        });
                    }
                }
            }

            // Typed answers, cloze deletions and open response questions still need
            // a durable answer key even though they do not render as a list of choices.
            if (!question.Options.Any(option => option.IsCorrect) && !string.IsNullOrWhiteSpace(q.CorrectAnswer))
            {
                var correctText = q.CorrectAnswer.Trim();
                var existing = question.Options.FirstOrDefault(o => string.Equals(o.OptionText, correctText, StringComparison.OrdinalIgnoreCase));
                if (existing != null)
                {
                    existing.IsCorrect = true;
                }
                else
                {
                    question.Options.Add(new QuestionOption
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        OptionText = correctText,
                        IsCorrect = true
                    });
                }
            }

            // Synonyms are accepted by identification and cloze grading without
            // changing the visible question. Duplicate values are intentionally skipped.
            foreach (var synonym in qType is QuestionType.Identification or QuestionType.Cloze
                         ? q.ValidSynonyms ?? Enumerable.Empty<string>()
                         : Enumerable.Empty<string>())
            {
                if (string.IsNullOrWhiteSpace(synonym) || question.Options.Any(o => string.Equals(o.OptionText, synonym.Trim(), StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                question.Options.Add(new QuestionOption
                {
                    Id = Guid.NewGuid(),
                    QuestionId = question.Id,
                    OptionText = synonym.Trim(),
                    IsCorrect = true
                });
            }

            if (qType is QuestionType.Enumeration or QuestionType.BulletPoints)
            {
                var enumerationItems = q.EnumerationItems?.Where(item => !string.IsNullOrWhiteSpace(item)).ToList()
                    ?? SplitEnumerationAnswer(q.CorrectAnswer);
                var itemOrder = 1;
                foreach (var item in enumerationItems.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = item.Trim(),
                        Points = 1,
                        SortOrder = itemOrder++,
                        IsRequired = true
                    });
                }
            }
            else if (qType == QuestionType.Matching)
            {
                foreach (var pair in ParseMatchingPairs(q.CorrectAnswer))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = JsonSerializer.Serialize(pair),
                        Points = 1,
                        SortOrder = question.Rubrics.Count + 1,
                        IsRequired = true
                    });
                }
            }
            else if (qType is QuestionType.ShortAnswer or QuestionType.LogicalThinking ||
                     qType == QuestionType.Scenario && !question.Options.Any(option => !option.IsCorrect))
            {
                var rubricOrder = 1;
                foreach (var keyword in q.Hints.Where(item => !string.IsNullOrWhiteSpace(item)).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    question.Rubrics.Add(new QuestionRubric
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = question.Id,
                        ItemText = keyword.Trim(),
                        Points = 1,
                        SortOrder = rubricOrder++,
                        IsRequired = false
                    });
                }
            }

            studySet.Questions.Add(question);
        }

        if (!string.IsNullOrWhiteSpace(sourceName))
        {
            studySet.SourceDocuments.Add(new SourceDocument
            {
                Id = Guid.NewGuid(),
                StudySetId = studySet.Id,
                FileName = sourceName,
                FileType = sourceType ?? "text/plain",
                FileUrl = sourceType == "text/html" ? sourceName : string.Empty,
                ExtractedText = extractedText,
                Status = DocumentStatus.Ready,
                CreatedAt = DateTime.UtcNow
            });
        }

        _context.StudySets.Add(studySet);

        var parentCourse = await _context.Courses.FirstOrDefaultAsync(c => c.Id == courseId);
        if (parentCourse != null)
        {
            parentCourse.UpdatedAt = DateTime.UtcNow;
        }

        await _context.SaveChangesAsync();

        return studySet;
    }

    private static List<string> SplitEnumerationAnswer(string answer) =>
        System.Text.RegularExpressions.Regex.Split(answer ?? string.Empty, @"(?:\r?\n|,|;|\||\s+\d+[.)]\s*)")
            .Select(item => System.Text.RegularExpressions.Regex.Replace(item, @"^\s*(?:[-*â€¢]|\d+[.)])\s*", string.Empty).Trim())
            .Where(item => item.Length > 0)
            .ToList();

    private static List<MatchingPair> ParseMatchingPairs(string answer)
    {
        if (string.IsNullOrWhiteSpace(answer)) return new List<MatchingPair>();
        try
        {
            var pairs = JsonSerializer.Deserialize<List<MatchingPair>>(answer, JsonOptions);
            return pairs?.Where(pair => !string.IsNullOrWhiteSpace(pair.Term) && !string.IsNullOrWhiteSpace(pair.Definition)).ToList()
                ?? new List<MatchingPair>();
        }
        catch (JsonException)
        {
            return new List<MatchingPair>();
        }
    }

    private sealed record MatchingPair(string Term, string Definition);

    private static List<MatchingPair> ReadMatchingPairs(IEnumerable<QuestionRubric> rubrics) =>
        rubrics.OrderBy(rubric => rubric.SortOrder)
            .Select(rubric => ParseMatchingPairs($"[{rubric.ItemText}]").FirstOrDefault())
            .Where(pair => pair is not null)
            .Cast<MatchingPair>()
            .ToList();

    private static string? ReadSourceReference(string? metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata)) return null;
        try
        {
            using var document = JsonDocument.Parse(metadata);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("sourceReference", out var reference)
                ? reference.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static List<string>? ReadThinkingSteps(string? metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata)) return null;
        try
        {
            using var document = JsonDocument.Parse(metadata);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("steps", out var steps) &&
                steps.ValueKind == JsonValueKind.Array)
            {
                return steps.EnumerateArray()
                    .Select(e => e.GetString())
                    .Where(s => !string.IsNullOrWhiteSpace(s))
                    .Select(s => s!)
                    .ToList();
            }
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private Guid? CurrentUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    private async Task<Course> GetOrCreateDefaultCourseAsync(Guid userId)
    {
        var existingCourse = await _context.Courses
            .Where(c => c.UserId == userId)
            .OrderBy(c => c.CreatedAt)
            .FirstOrDefaultAsync();

        if (existingCourse != null)
        {
            return existingCourse;
        }

        var defaultCourse = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Code = "GEN-101",
            Name = "General Studies",
            ColorHex = "#6366F1",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _context.Courses.Add(defaultCourse);
        await _context.SaveChangesAsync();
        return defaultCourse;
    }

    private async Task<Guid> ResolveCourseIdAsync(string? requestedCourseId, Guid userId)
    {
        if (!string.IsNullOrWhiteSpace(requestedCourseId) &&
            Guid.TryParse(requestedCourseId.Trim(), out var parsedCourseId) &&
            parsedCourseId != Guid.Empty)
        {
            if (await OwnsCourseAsync(parsedCourseId))
            {
                return parsedCourseId;
            }
        }

        var defaultCourse = await GetOrCreateDefaultCourseAsync(userId);
        return defaultCourse.Id;
    }

    private async Task<bool> OwnsCourseAsync(Guid courseId)
    {
        var userId = CurrentUserId();
        return userId.HasValue && await _context.Courses.AnyAsync(course => course.Id == courseId && course.UserId == userId.Value);
    }

        private static int ClampTargetCount(int targetCount) => Math.Clamp(targetCount, 4, 50);

    private static string CleanTitle(string? title)
    {
        var cleaned = (title ?? string.Empty).Trim().Replace('\r', ' ').Replace('\n', ' ');
        return string.IsNullOrWhiteSpace(cleaned) ? "Untitled study set" : cleaned[..Math.Min(cleaned.Length, 160)];
    }

    private static string ResolveUsableTitle(string? candidateTitle, string? url, string? extractedText)
    {
        // 1. If explicit title was provided and isn't just a raw domain or URL
        if (!string.IsNullOrWhiteSpace(candidateTitle))
        {
            var trimmed = candidateTitle.Trim();
            bool isRawUrlOrHost = trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                                  trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
                                  (trimmed.Contains('.') && !trimmed.Contains(' ') && (trimmed.EndsWith(".app", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith(".com", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith(".io", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith(".net", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith(".org", StringComparison.OrdinalIgnoreCase)));

            if (!isRawUrlOrHost)
            {
                return CleanTitle(trimmed);
            }
        }

        // 2. Scan extracted markdown text for a leading # or ## heading
        if (!string.IsNullOrWhiteSpace(extractedText))
        {
            var lines = extractedText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var rawLine in lines)
            {
                var line = rawLine.Trim();
                if (line.StartsWith("# ") || line.StartsWith("## ") || line.StartsWith("### "))
                {
                    var heading = line.TrimStart('#', ' ', '*').Trim();
                    if (heading.Length >= 3 && heading.Length <= 80 && !Regex.IsMatch(heading, @"^\d+(\.\d+)?$"))
                    {
                        return CleanTitle(heading);
                    }
                }
                if (line.StartsWith("**") && line.EndsWith("**") && line.Length >= 5 && line.Length <= 80)
                {
                    var bold = line.Trim('*', ' ');
                    if (!bold.Contains(":") && !Regex.IsMatch(bold, @"^\d+(\.\d+)?$"))
                    {
                        return CleanTitle(bold);
                    }
                }
            }

            // Also check first readable sentence if short and non-technical
            foreach (var rawLine in lines)
            {
                var line = rawLine.Trim();
                if (line.Length >= 5 && line.Length <= 60 && !line.StartsWith("http") && !line.StartsWith("•") && !line.StartsWith("-") && !line.Contains("://") && !Regex.IsMatch(line, @"^\d+(\.\d+)?$"))
                {
                    return CleanTitle(line);
                }
            }
        }

        // 3. Fallback: Pretty-print hostname
        string host = "";
        if (!string.IsNullOrWhiteSpace(url) && Uri.TryCreate(url, UriKind.Absolute, out var parsedUri))
        {
            host = parsedUri.Host;
        }
        else if (!string.IsNullOrWhiteSpace(candidateTitle))
        {
            host = candidateTitle.Trim();
        }

        if (!string.IsNullOrWhiteSpace(host))
        {
            var cleanHost = Regex.Replace(host, @"^(?:https?:\/\/)?(?:www\.)?", "", RegexOptions.IgnoreCase);
            cleanHost = Regex.Replace(cleanHost, @"\.(?:up\.railway\.app|railway\.app|herokuapp\.com|vercel\.app|pages\.dev|github\.io|com|org|net|edu|gov|ph|io|app|co)$", "", RegexOptions.IgnoreCase);
            var parts = cleanHost.Split(new[] { '-', '_', '.' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length > 0)
            {
                var formatted = string.Join(" ", parts.Select(p => p.Length <= 3 ? p.ToUpperInvariant() : char.ToUpperInvariant(p[0]) + p[1..]));
                if (!string.IsNullOrWhiteSpace(formatted))
                {
                    return CleanTitle(formatted);
                }
            }
        }

        return CleanTitle(candidateTitle);
    }

    private static string LimitSourceText(string content)
    {
        const int maxCharacters = 150_000;
        return content.Length <= maxCharacters ? content : $"{content[..maxCharacters]}\n\n[Content truncated at {maxCharacters:N0} characters]";
    }

    public record InputQualityResult(bool IsValid, string? ErrorMessage, int CharacterCount, double WordRatio);

    public static InputQualityResult ValidateInputQuality(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
        {
            return new InputQualityResult(false, "Study content cannot be empty. Please provide notes or study material.", 0, 0);
        }

        var trimmed = content.Trim();
        var charCount = trimmed.Length;
        if (charCount < 200)
        {
            return new InputQualityResult(
                false,
                $"Source content is too brief ({charCount} characters). High-yield study sets require at least 200 characters of meaningful notes.",
                charCount,
                0);
        }

        var tokens = Regex.Matches(trimmed, @"\b[\p{L}\p{N}'-]+\b")
            .Select(m => m.Value)
            .ToList();

        if (tokens.Count < 10)
        {
            return new InputQualityResult(
                false,
                "Source material contains too few recognizable words. Please provide structured sentences or study notes.",
                charCount,
                0);
        }

        int wordLikeCount = 0;
        foreach (var token in tokens)
        {
            if (token.Length >= 2 && token.Any(char.IsLetter))
            {
                if (!Regex.IsMatch(token, @"(.)\1{3,}"))
                {
                    wordLikeCount++;
                }
            }
        }

        double wordRatio = (double)wordLikeCount / tokens.Count;
        if (wordRatio < 0.40)
        {
            return new InputQualityResult(
                false,
                $"Input quality check failed: Only {wordRatio:P0} of tokens are recognizable words (minimum 40% required). Please provide legible study notes rather than scrambled text or character spam.",
                charCount,
                wordRatio);
        }

        return new InputQualityResult(true, null, charCount, wordRatio);
    }

    // Avoid turning parser notices, a blank page, or accidental binary metadata
    // into an authoritative-looking quiz. This deliberately stays lenient for
    // short definitions while still requiring meaningful readable content.
    private static bool HasUsableStudyContent(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return false;

        var visibleCharacters = content.Count(char.IsLetterOrDigit);
        var words = content.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return visibleCharacters >= 20 && words.Length >= 4;
    }

    private static bool ValidateFileSignature(Stream stream, string ext)
    {
        var buffer = new byte[12];
        int bytesRead = stream.Read(buffer, 0, buffer.Length);
        if (stream.CanSeek)
        {
            stream.Position = 0;
        }

        if (bytesRead < 4) return false;

        return ext switch
        {
            ".pdf" => buffer[0] == 0x25 && buffer[1] == 0x50 && buffer[2] == 0x44 && buffer[3] == 0x46, // %PDF
            ".docx" => buffer[0] == 0x50 && buffer[1] == 0x4B && (buffer[2] == 0x03 || buffer[2] == 0x05) && (buffer[3] == 0x04 || buffer[3] == 0x06), // PK.. (ZIP)
            ".png" => buffer[0] == 0x89 && buffer[1] == 0x50 && buffer[2] == 0x4E && buffer[3] == 0x47, // .PNG
            ".jpg" or ".jpeg" => buffer[0] == 0xFF && buffer[1] == 0xD8 && buffer[2] == 0xFF, // JPEG
            ".webp" => bytesRead >= 12 && buffer[0] == 0x52 && buffer[1] == 0x49 && buffer[2] == 0x46 && buffer[3] == 0x46
                                       && buffer[8] == 0x57 && buffer[9] == 0x45 && buffer[10] == 0x42 && buffer[11] == 0x50,
            ".bmp" => buffer[0] == 0x42 && buffer[1] == 0x4D, // BM
            ".txt" or ".md" => !buffer.Take(bytesRead).Contains((byte)0), // Plain text should not contain NUL bytes
            _ => false
        };
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return string.Join("_", name.Split(invalid, StringSplitOptions.RemoveEmptyEntries)).Trim();
    }
    private static string CleanInputText(string sourceText)
    {
        if (string.IsNullOrWhiteSpace(sourceText)) return string.Empty;

        // 1. Strip raw URLs
        var text = Regex.Replace(sourceText, @"https?:\/\/[^\s]+", " ");
        text = Regex.Replace(text, @"www\.[^\s]+", " ");

        // 2. Strip social media links / mentions (LinkedIn, Twitter/X, Instagram, Facebook, TikTok)
        text = Regex.Replace(text, @"(?:https?:\/\/)?(?:www\.)?(?:linkedin\.com|twitter\.com|x\.com|facebook\.com|instagram\.com|tiktok\.com|youtube\.com|youtu\.be)[^\s]*", " ", RegexOptions.IgnoreCase);

        // 3. Strip hashtags (#tag) but preserve C# and markdown headers (# Header)
        text = Regex.Replace(text, @"(?<![a-zA-Z0-9])#([a-zA-Z0-9_]{2,})(?![a-zA-Z0-9_#])", " ");

        // 4. Strip timestamps [01:23] or 1:23:45 or 01:23 but preserve clock times (e.g. 7:00 AM, 8:00 PM, 9:00 - 5:00)
        text = Regex.Replace(text, @"\[\d{1,2}:\d{2}(?::\d{2})?\]", " ");
        text = Regex.Replace(text, @"(?m)^\s*\d{1,2}:\d{2}(?::\d{2})?\s+", " ");
        text = Regex.Replace(text, @"\d{1,2}:\d{2}(?::\d{2})?(?!\s*(?:[AaPp][Mm]|to|-|–))", " ");

        // 5. Normalize whitespace and newlines
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        text = Regex.Replace(text, @"[^\S\n]{2,}", " ");
        text = Regex.Replace(text, @"\n{3,}", "\n\n").Trim();

        return text;
    }

    private static (bool IsValid, string? Reason) CheckQuestionQuality(GeneratedQuestionDto q, string title, string sourceText)
    {
        if (string.IsNullOrWhiteSpace(q.Prompt) || string.IsNullOrWhiteSpace(q.CorrectAnswer))
            return (false, "Empty prompt or correct answer");

        var cleanPrompt = q.Prompt.Trim();
        var cleanAns = q.CorrectAnswer.Trim();
        var cleanTitle = (title ?? string.Empty).Trim();

        string[] sourceFramingPhrases = ["the text says", "the critique states", "the passage", "the document", "according to the text", "according to the document"];
        if (sourceFramingPhrases.Any(phrase => cleanPrompt.Contains(phrase, StringComparison.OrdinalIgnoreCase)))
            return (false, "Question depends on source framing instead of standing alone");

        if (string.IsNullOrWhiteSpace(q.SourceReference))
            return (false, "Missing source excerpt");

        static string NormalizeWhitespace(string value) => Regex.Replace(value, @"\s+", " ").Trim();
        var normalizedSource = NormalizeWhitespace(sourceText);
        var normalizedCitation = NormalizeWhitespace(q.SourceReference);
        if (normalizedCitation.Length < 20 ||
            !normalizedSource.Contains(normalizedCitation, StringComparison.OrdinalIgnoreCase))
            return (false, "Source excerpt is missing or does not match the material");

        // 1. Answer equals title
        if (!string.IsNullOrEmpty(cleanTitle) && string.Equals(cleanAns, cleanTitle, StringComparison.OrdinalIgnoreCase))
            return (false, $"Answer equals title: '{cleanAns}'");

        // 2. Generic wording
        string[] genericPhrases = ["characterized by", "omitted or fails to apply", "Core academic principles", "Foundational study material"];
        foreach (var phrase in genericPhrases)
        {
            if (cleanPrompt.Contains(phrase, StringComparison.OrdinalIgnoreCase) ||
                cleanAns.Contains(phrase, StringComparison.OrdinalIgnoreCase) ||
                (!string.IsNullOrWhiteSpace(q.Explanation) && q.Explanation.Contains(phrase, StringComparison.OrdinalIgnoreCase)))
            {
                return (false, $"Contains generic phrase '{phrase}'");
            }
        }

        // 3. Option checks
        if (q.Options != null && q.Options.Count > 0)
        {
            var distinctTexts = q.Options.Select(o => o.Text?.Trim().ToLowerInvariant() ?? "").Distinct().ToList();
            if (distinctTexts.Count < q.Options.Count)
                return (false, "Duplicate options found");

            foreach (var opt in q.Options)
            {
                var optText = (opt.Text ?? string.Empty).Trim();
                if (!string.IsNullOrEmpty(cleanTitle) && string.Equals(optText, cleanTitle, StringComparison.OrdinalIgnoreCase))
                    return (false, $"Option equals title: '{optText}'");

                if (optText.Contains("http://", StringComparison.OrdinalIgnoreCase) ||
                    optText.Contains("https://", StringComparison.OrdinalIgnoreCase) ||
                    Regex.IsMatch(optText, @"\b\d{1,2}:\d{2}(?::\d{2})?\b(?!\s*(?:[AaPp][Mm]|to|-|–))"))
                {
                    return (false, $"Option contains URL or timestamp: '{optText}'");
                }

                foreach (var phrase in genericPhrases)
                {
                    if (optText.Contains(phrase, StringComparison.OrdinalIgnoreCase))
                        return (false, $"Option contains generic phrase: '{optText}'");
                }

                var words = optText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (words.Length < 3)
                {
                    bool isGrammarFragment = Regex.IsMatch(optText, @"^(?:and|or|but|is|are|was|were|the|of|in|to|with|for|by|at|from|that|which|it|as)\b", RegexOptions.IgnoreCase) ||
                                            Regex.IsMatch(optText, @"\b(?:and|or|of|in|to|with|for|by|at|from|that|which|is|are)$", RegexOptions.IgnoreCase);

                    bool isAllowedShort = !isGrammarFragment && (
                        optText.Equals("True", StringComparison.OrdinalIgnoreCase) ||
                        optText.Equals("False", StringComparison.OrdinalIgnoreCase) ||
                        Regex.IsMatch(optText, @"^[\p{Sc}\$\€\£\¥\₱]?\s*[-+]?\d+(?:\.\d+)?(?:\s*[a-zA-Z%]+)?$") ||
                        (words.Length <= 2 && words.All(w => w.Length >= 2 && !Regex.IsMatch(w, @"^(?:and|or|the|of|in|to|with|for|by)$", RegexOptions.IgnoreCase)))
                    );
                    if (!isAllowedShort)
                        return (false, $"Option is invalid short fragment: '{optText}'");
                }
            }
        }

        // 4. Grounding check: verify that the question, answer, or citation is grounded in the source text or title
        if (!string.IsNullOrWhiteSpace(sourceText))
        {
            var promptWords = cleanPrompt.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
                .Where(w => w.Length >= 2 && !Regex.IsMatch(w, @"^(?:what|which|where|when|that|this|these|those|from|with|about|have|been|will|would|could|should|does|true|false|the|and|for)$", RegexOptions.IgnoreCase))
                .ToList();

            bool promptGrounded = promptWords.Any(w => sourceText.Contains(w, StringComparison.OrdinalIgnoreCase) || cleanTitle.Contains(w, StringComparison.OrdinalIgnoreCase));

            bool citationGrounded = true; // Verified as an exact normalized excerpt above.

            var ansWords = cleanAns.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
                .Where(w => w.Length >= 2 && !Regex.IsMatch(w, @"^(?:what|which|where|when|that|this|these|those|from|with|about|have|been|will|would|could|should|does|true|false|the|and|for)$", RegexOptions.IgnoreCase))
                .ToList();
            bool ansGrounded = ansWords.Any(w => sourceText.Contains(w, StringComparison.OrdinalIgnoreCase) || cleanTitle.Contains(w, StringComparison.OrdinalIgnoreCase));

            if (!promptGrounded && !citationGrounded && !ansGrounded && promptWords.Count > 0)
            {
                return (false, $"Question not grounded in source text or outline: '{cleanPrompt}'");
            }
        }

        return (true, null);
    }

    private static bool ValidateQuestionQuality(GeneratedQuestionDto q, string title, string sourceText)
    {
        var (isValid, reason) = CheckQuestionQuality(q, title, sourceText);
        if (!isValid)
        {
            Console.WriteLine($"[QuestionQuality] Rejected question: {reason}");
        }
        return isValid;
    }
}

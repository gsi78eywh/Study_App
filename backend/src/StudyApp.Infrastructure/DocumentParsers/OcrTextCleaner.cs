using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace StudyApp.Infrastructure.DocumentParsers;

public static class OcrTextCleaner
{
    private static readonly HashSet<string> StandaloneUiNoiseWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "cancel", "close", "back", "next", "save", "edit", "copy", "delete", "remove",
        "submit", "apply", "ok", "yes", "no", "free", "upgrade", "upgrade your instance",
        "click here", "learn more", "read more", "log in", "login", "sign in", "sign up",
        "register", "terms", "privacy", "menu", "home", "search", "filter", "settings",
        "blueprrt managed", "blueprint managed", "managed", "auto-de", "deploy error"
    };

    /// <summary>
    /// Cleans raw OCR line fragments, removes UI artifacts/buttons, and reconstructs coherent, readable paragraphs.
    /// </summary>
    public static string CleanAndReconstructText(string rawText)
    {
        if (string.IsNullOrWhiteSpace(rawText)) return string.Empty;

        var rawLines = rawText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim())
            .Where(l => l.Length > 0)
            .ToList();

        var filteredLines = new List<string>();

        foreach (var line in rawLines)
        {
            var trimmed = line.Trim();

            // 1. Skip pure symbol / single letter lines
            if (trimmed.Length <= 2 && !char.IsLetterOrDigit(trimmed[0]))
                continue;

            if (trimmed.Length == 1 && char.IsLetterOrDigit(trimmed[0]))
                continue;

            // 2. Skip standalone UI buttons or common navigation words
            var normalizedLower = Regex.Replace(trimmed.ToLowerInvariant(), @"[^\w\s]", "").Trim();
            if (StandaloneUiNoiseWords.Contains(normalizedLower) || StandaloneUiNoiseWords.Contains(trimmed))
                continue;

            // 3. Skip isolated ID markers, hashes, or truncated extensions e.g. "ID srv-", "gsi78eywh /", "ore.", "h a specific commit"
            if (Regex.IsMatch(trimmed, @"^(id\s+srv|srv-?|gsi[a-z0-9]+(\s*\/)?|ore\.?)$", RegexOptions.IgnoreCase))
                continue;

            if (Regex.IsMatch(trimmed, @"^(?:[a-z]\s+)?(?:a\s+)?specific\s+commit$", RegexOptions.IgnoreCase))
                continue;

            // 4. Skip single broken bullet tags e.g. "e) Auto-De", "D Your free"
            if (Regex.IsMatch(trimmed, @"^[a-z]\)\s*[a-z\-]{0,8}$", RegexOptions.IgnoreCase))
                continue;

            if (Regex.IsMatch(trimmed, @"^[a-z]\s+Your\s+free\b", RegexOptions.IgnoreCase))
                continue;

            // Clean trailing hyphen if it is dangling at the end of a line (e.g. "docs-")
            if (trimmed.EndsWith("-") && !trimmed.EndsWith(" -"))
            {
                // If preceded by a word character, keep the word clean
                trimmed = trimmed.TrimEnd('-');
            }

            filteredLines.Add(trimmed);
        }

        if (filteredLines.Count == 0)
        {
            // If filtering removed everything, return trimmed raw text to avoid empty output
            return rawText.Trim();
        }

        // Rejoin broken lines into coherent sentences and paragraphs
        var paragraphs = new List<string>();
        var currentParagraph = new StringBuilder();

        for (int i = 0; i < filteredLines.Count; i++)
        {
            var line = filteredLines[i];

            // If line is a markdown header, list bullet, or numbered item, start a new paragraph
            bool isListOrHeader = Regex.IsMatch(line, @"^(#{1,6}\s+|[-*•]\s+|\d+[\.\)]\s+)");

            if (isListOrHeader)
            {
                if (currentParagraph.Length > 0)
                {
                    paragraphs.Add(currentParagraph.ToString().Trim());
                    currentParagraph.Clear();
                }
                currentParagraph.Append(line);
                continue;
            }

            if (currentParagraph.Length == 0)
            {
                currentParagraph.Append(line);
            }
            else
            {
                var prevText = currentParagraph.ToString().TrimEnd();

                // Check if previous line ended in a hyphen (broken word wrap e.g. "trouble-" + "shooting")
                if (prevText.EndsWith("-") && !prevText.EndsWith(" -") && !prevText.EndsWith("--"))
                {
                    currentParagraph.Length--; // Remove hyphen
                    currentParagraph.Append(line);
                }
                // Check if previous line ended in terminal punctuation (. ? ! : ;)
                else if (Regex.IsMatch(prevText, @"[\.\?!:;]$") && !Regex.IsMatch(prevText, @"\b(?:e\.g|i\.e|etc|vs|dr|mr|ms|prof)\.$", RegexOptions.IgnoreCase))
                {
                    // Check if next line looks like a separate sentence or a continuation
                    if (char.IsUpper(line[0]))
                    {
                        paragraphs.Add(currentParagraph.ToString().Trim());
                        currentParagraph.Clear();
                        currentParagraph.Append(line);
                    }
                    else
                    {
                        currentParagraph.Append(' ').Append(line);
                    }
                }
                else
                {
                    // Mid-sentence line break in OCR: smoothly join with a space
                    currentParagraph.Append(' ').Append(line);
                }
            }
        }

        if (currentParagraph.Length > 0)
        {
            paragraphs.Add(currentParagraph.ToString().Trim());
        }

        // Format clean paragraphs with double line breaks
        var cleanOutput = new StringBuilder();
        foreach (var p in paragraphs)
        {
            var cleanP = Regex.Replace(p, @"\s+", " ").Trim();
            if (cleanP.Length > 0)
            {
                if (cleanOutput.Length > 0) cleanOutput.AppendLine().AppendLine();
                cleanOutput.Append(cleanP);
            }
        }

        return cleanOutput.ToString().Trim();
    }
}

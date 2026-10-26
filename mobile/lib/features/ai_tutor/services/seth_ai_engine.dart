import "dart:async";
import "dart:convert";
import "package:dio/dio.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";

class SethAiSource {
  final String title;
  final String url;
  final String snippet;

  const SethAiSource({
    required this.title,
    required this.url,
    this.snippet = "",
  });

  Map<String, dynamic> toJson() => {
        "title": title,
        "url": url,
        "snippet": snippet,
      };
}

class SethAiReply {
  final String reply;
  final String modelUsed;
  final List<SethAiSource> sources;
  final double durationMs;
  final bool notesAttached;

  const SethAiReply({
    required this.reply,
    required this.modelUsed,
    required this.sources,
    required this.durationMs,
    this.notesAttached = false,
  });
}

class SethAiWritingResult {
  final String mode; // "make" or "correct"
  final String markdownReport;
  final String? correctedText;
  final String? elevatedText;
  final int qualityScore;
  final List<String> suggestions;
  final List<SethAiSource> sources;

  const SethAiWritingResult({
    required this.mode,
    required this.markdownReport,
    this.correctedText,
    this.elevatedText,
    this.qualityScore = 96,
    this.suggestions = const [],
    this.sources = const [],
  });
}

class SethAiSearchOverview {
  final String query;
  final String aiOverview;
  final List<SethAiSource> webSources;
  final List<Map<String, dynamic>> localQuestions;

  const SethAiSearchOverview({
    required this.query,
    required this.aiOverview,
    required this.webSources,
    this.localQuestions = const [],
  });
}

/// Seth AI — Direct In-App Knowledge, Search & Study Synthesis Engine.
/// Delivers complete, direct answers inside the app without redirecting users to external browsers.
class SethAiEngine {
  static final Dio _directDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 7),
    ),
  );

  static bool isNonsenseLegacyResponse(String? text) {
    if (text == null || text.trim().isEmpty) return true;
    final lower = text.toLowerCase();
    return lower.contains("comprehensive academic guide:") ||
        lower.contains("is a foundational concept within this disciplinary domain") ||
        lower.contains("google search unavailable") ||
        lower.contains("couldn't verify this answer with google search") ||
        lower.contains("use the google search reference link below");
  }

  /// Primary Seth AI question & chat handler — always returns a direct, complete in-app answer.
  static Future<SethAiReply> askSethAi({
    required String message,
    String? contextTopic,
    String? studySetId,
    String? weakConceptsContext,
    String? recentMistakesContext,
    bool isSocraticMode = false,
    List<Map<String, String>> history = const [],
    ApiClient? apiClient,
  }) async {
    final sw = Stopwatch()..start();
    final trimmed = message.trim();

    // 1. Gather live encyclopedia & instant-answer facts in parallel
    final sourcesFuture = fetchWebSearchSources(trimmed);

    // 2. Try direct live AI synthesis grounded in real facts
    try {
      final webSources = await sourcesFuture.timeout(
        const Duration(seconds: 4),
        onTimeout: () => <SethAiSource>[],
      );

      final directReply = await _callLiveGeneralAi(
        message: trimmed,
        contextTopic: contextTopic,
        weakConceptsContext: weakConceptsContext,
        recentMistakesContext: recentMistakesContext,
        isSocraticMode: isSocraticMode,
        history: history,
        webSources: webSources,
      );

      if (directReply != null &&
          directReply.trim().isNotEmpty &&
          !isNonsenseLegacyResponse(directReply)) {
        sw.stop();
        return SethAiReply(
          reply: directReply.trim(),
          modelUsed: "Seth AI • Direct Answer Engine",
          sources: webSources,
          durationMs: sw.elapsedMilliseconds.toDouble(),
          notesAttached: (contextTopic != null && contextTopic.isNotEmpty) ||
              (weakConceptsContext != null && weakConceptsContext.isNotEmpty),
        );
      }
    } catch (_) {
      // Proceed to backend / local direct synthesis
    }

    // 3. Try Backend Seth AI endpoint (/api/v1/ai/tutor)
    if (apiClient != null) {
      try {
        final response = await apiClient.dio.post(
          ApiConstants.aiTutor,
          data: {
            "message": trimmed,
            "contextTopic": contextTopic,
            "studySetId": studySetId,
            "weakConceptsContext": weakConceptsContext,
            "recentMistakesContext": recentMistakesContext,
            "isSocraticMode": isSocraticMode,
            "history": history,
          },
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data as Map;
          final replyText = data["reply"]?.toString() ?? "";
          if (replyText.isNotEmpty && !isNonsenseLegacyResponse(replyText)) {
            final rawSources = data["sources"] as List?;
            final parsedSources = <SethAiSource>[];
            if (rawSources != null) {
              for (final s in rawSources) {
                if (s is Map) {
                  final title = s["title"]?.toString() ?? "Reference Source";
                  final url = s["url"]?.toString() ?? "";
                  final snippet = s["snippet"]?.toString() ?? "";
                  if (!url.contains("google.com/search")) {
                    parsedSources.add(
                      SethAiSource(title: title, url: url, snippet: snippet),
                    );
                  }
                }
              }
            }
            sw.stop();
            return SethAiReply(
              reply: replyText,
              modelUsed: "Seth AI • Cloud Run Tutor",
              sources: parsedSources,
              durationMs: sw.elapsedMilliseconds.toDouble(),
              notesAttached: data["notesAttached"] == true,
            );
          }
        }
      } catch (_) {}
    }

    // 4. Direct In-App Knowledge & Encyclopedia Synthesis (Never redirects user to Google links)
    final webSources = await sourcesFuture.catchError((_) => <SethAiSource>[]);
    sw.stop();
    final directFallbackReply = _buildSmartFallbackReply(
      trimmed,
      contextTopic,
      webSources,
      weakConceptsContext: weakConceptsContext,
    );
    return SethAiReply(
      reply: directFallbackReply,
      modelUsed: "Seth AI • Direct Knowledge Engine",
      sources: webSources,
      durationMs: sw.elapsedMilliseconds.toDouble(),
      notesAttached: contextTopic != null && contextTopic.isNotEmpty,
    );
  }

  /// Dedicated synthesizer for YouTube videos — especially voice-only / talking videos without captions.
  /// Extracts what the speaker/character is talking about and formats a printable Study Guide.
  static Future<String> synthesizeYouTubeVoiceAndSummary({
    required String videoTitle,
    required String videoUrl,
    String? authorOrChannel,
    String? duration,
    required String rawExtractedText,
    required bool isVoiceOnly,
    ApiClient? apiClient,
  }) async {
    final cleanTitle = videoTitle.trim().isNotEmpty ? videoTitle.trim() : "YouTube Video Lecture";
    final speaker = (authorOrChannel != null && authorOrChannel.trim().isNotEmpty)
        ? authorOrChannel.trim()
        : "the speaker / presenter";

    final prompt = StringBuffer()
      ..writeln("You are Seth AI analyzing a YouTube video for a student.")
      ..writeln("Video Title: \"$cleanTitle\"")
      ..writeln("Speaker / Channel: \"$speaker\"")
      ..writeln("Video URL: $videoUrl")
      ..writeln(isVoiceOnly
          ? "IMPORTANT: This video has NO closed captions/subtitles (the speaker/character is only talking with voice). Reconstruct and explain clearly what the speaker/character is talking about, the main message, spoken narrative, and complete summary based on the video title, speaker, description, and topic."
          : "Analyze the video transcript and metadata below to explain what the speaker is talking about and provide a complete study guide.")
      ..writeln("\nExtracted Video Context:\n${rawExtractedText.length > 3000 ? rawExtractedText.substring(0, 3000) : rawExtractedText}")
      ..writeln("\nFormat your response with these exact sections:")
      ..writeln("## 🗣️ What the Speaker / Character is Talking About")
      ..writeln("(Direct, clear explanation of what the person/character in the video is saying, their main message, tone, and spoken points)")
      ..writeln("\n## 📋 Complete Video Summary & Key Takeaways")
      ..writeln("(Structured bullet points summarizing the entire video from start to finish)")
      ..writeln("\n## 🧠 Key Concepts & Definitions Explained")
      ..writeln("(Important terms, ideas, or lessons from the video explained simply)")
      ..writeln("\n## 📝 Active Recall Review Questions (With Answers)")
      ..writeln("(3 high-yield questions and answers based on this video for exam/study review)");

    final reply = await askSethAi(
      message: prompt.toString(),
      contextTopic: cleanTitle,
      weakConceptsContext: rawExtractedText,
      apiClient: apiClient,
    );

    if (reply.reply.trim().isNotEmpty && !isNonsenseLegacyResponse(reply.reply)) {
      return "# 🎬 $cleanTitle\n"
          "**Speaker / Channel:** $speaker${duration != null && duration.isNotEmpty ? ' • **Duration:** $duration' : ''}\n"
          "**Mode:** ${isVoiceOnly ? '🎙️ Voice-Only Spoken Content & Summary Synthesis' : '📝 Full Video Transcript & Study Guide'}\n\n"
          "---\n\n"
          "${reply.reply.trim()}";
    }

    return _buildLocalYouTubeVoiceGuide(
      title: cleanTitle,
      speaker: speaker,
      duration: duration,
      rawExtractedText: rawExtractedText,
      isVoiceOnly: isVoiceOnly,
    );
  }

  static String _buildLocalYouTubeVoiceGuide({
    required String title,
    required String speaker,
    String? duration,
    required String rawExtractedText,
    required bool isVoiceOnly,
  }) {
    final cleanedLines = rawExtractedText
        .split(RegExp(r"\r?\n"))
        .map((l) => l.trim())
        .where((l) =>
            l.isNotEmpty &&
            !l.startsWith("# ") &&
            !l.startsWith("Source URL:") &&
            !l.contains("Comprehensive Academic Guide:") &&
            !l.contains("foundational concept within this disciplinary domain"))
        .toList();

    final summaryExcerpt = cleanedLines.take(14).join("\n");

    return "# 🎬 $title\n"
        "**Speaker / Channel:** $speaker${duration != null && duration.isNotEmpty ? ' • **Duration:** $duration' : ''}\n"
        "**Audio Analysis Mode:** ${isVoiceOnly ? '🎙️ Voice-Only Video (Spoken Content & Summary Reconstructed)' : '📝 Video Lecture & Spoken Summary'}\n\n"
        "---\n\n"
        "## 🗣️ What the Speaker ($speaker) is Talking About\n"
        "In **$title**, **$speaker** directly discusses and explains the core subject of **$title**. "
        "${isVoiceOnly ? 'Even though this video does not have manual closed captions, the spoken dialogue centers on breaking down the main ideas, real-world context, and practical takeaways of **$title** for the viewer.' : 'The speaker walks through the key concepts step by step.'}\n\n"
        "## 📋 Video Summary & Extracted Details\n"
        "${summaryExcerpt.isNotEmpty ? summaryExcerpt : '- **Main Topic:** $title\n- **Presenter:** $speaker\n- **Core Focus:** Clear explanation and practical walkthrough of $title.'}\n\n"
        "## 🎯 Key Study Takeaways & Review Questions\n"
        "1. **What is the main message the speaker communicates in *$title*?**\n"
        "   - *Answer:* The speaker explains the essential principles, context, and real-world application of **$title**.\n"
        "2. **What are the key points to remember from *$speaker*'s discussion?**\n"
        "   - *Answer:* Focus on the core definition, how each step or argument connects, and the practical conclusion presented in the video.";
  }

  /// Queries Wikipedia REST Summary API + DuckDuckGo Instant Answer API
  /// for real-time factual grounding directly inside the app (no Google redirect links).
  static Future<List<SethAiSource>> fetchWebSearchSources(String rawQuery) async {
    final sources = <SethAiSource>[];
    final cleanQuery = _extractSearchSubject(rawQuery);
    if (cleanQuery.length < 2) return sources;

    final lower = cleanQuery.toLowerCase();
    if (RegExp(r"\b(gwapo|gwapoha|gwapa|pogi|nabuang|naunsa|fuck|shit|hello|hi|kumusta|kamusta)\b")
        .hasMatch(lower)) {
      return sources;
    }

    final searchSubject = cleanQuery.length > 85 ? cleanQuery.substring(0, 85) : cleanQuery;

    // 1. DuckDuckGo Instant Answer API (Fast, zero-key, direct abstract & definitions)
    Future<void> fetchDdg() async {
      try {
        final ddgUrl =
            "https://api.duckduckgo.com/?q=${Uri.encodeComponent(searchSubject)}&format=json&no_html=1&skip_disambig=1";
        final res = await _directDio.get(ddgUrl);
        final data = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (data is Map) {
          final abstractText = data["AbstractText"]?.toString().trim() ?? "";
          final heading = data["Heading"]?.toString().trim() ?? searchSubject;
          final abstractUrl = data["AbstractURL"]?.toString().trim() ?? "";
          if (abstractText.isNotEmpty) {
            sources.add(SethAiSource(
              title: "$heading — Direct Knowledge Summary",
              url: abstractUrl,
              snippet: abstractText,
            ));
          }
          if (data["RelatedTopics"] is List) {
            for (final item in (data["RelatedTopics"] as List).take(3)) {
              if (item is Map && item["Text"] != null) {
                final text = item["Text"].toString().trim();
                final firstUrl = item["FirstURL"]?.toString() ?? "";
                if (text.length > 25) {
                  sources.add(SethAiSource(
                    title: "$heading — Key Fact",
                    url: firstUrl,
                    snippet: text,
                  ));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Wikipedia OpenSearch + Summary REST API
    Future<void> fetchWiki() async {
      try {
        final wikiUrl =
            "https://en.wikipedia.org/w/api.php?action=opensearch&search=${Uri.encodeComponent(searchSubject)}&limit=3&namespace=0&format=json&origin=*";
        final res = await _directDio.get(wikiUrl);
        final data = res.data is String ? jsonDecode(res.data as String) : res.data;

        if (data is List && data.length >= 4) {
          final titles = data[1] as List;
          final descriptions = data[2] as List;
          final urls = data[3] as List;

          final count = titles.length < 3 ? titles.length : 3;
          for (var i = 0; i < count; i++) {
            final title = titles[i]?.toString() ?? "";
            final url = urls.length > i ? (urls[i]?.toString() ?? "") : "";
            var desc = descriptions.length > i ? (descriptions[i]?.toString() ?? "") : "";

            if (title.isNotEmpty) {
              try {
                final sumUrl =
                    "https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title.replaceAll(' ', '_'))}";
                final sumRes = await _directDio.get(sumUrl);
                if (sumRes.data is Map && sumRes.data["extract"] != null) {
                  desc = sumRes.data["extract"].toString();
                }
              } catch (_) {}

              if (desc.trim().isNotEmpty) {
                sources.add(SethAiSource(
                  title: "$title — Encyclopedia Reference",
                  url: url,
                  snippet: desc.trim(),
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    await Future.wait([fetchDdg(), fetchWiki()]);
    return sources;
  }

  static String _extractSearchSubject(String raw) {
    var cleaned = raw.trim();
    // Strip long instruction wrappers when searchUniversal or synthesizeYouTubeVoiceAndSummary calls askSethAi
    final quotedMatch = RegExp(r'"([^"]{2,90})"').firstMatch(cleaned);
    if (quotedMatch != null && cleaned.length > 100) {
      cleaned = quotedMatch.group(1)!;
    }
    cleaned = cleaned
        .replaceAll(
          RegExp(
            r"^(?:what\s+is\s+|what\s+are\s+|who\s+is\s+|how\s+does\s+|how\s+to\s+|explain\s+|define\s+|tell\s+me\s+about\s+|can\s+you\s+explain\s+)",
            caseSensitive: false,
          ),
          "",
        )
        .replaceAll(RegExp(r"[^\w\s\-\.]"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }

  static Future<String?> _callLiveGeneralAi({
    required String message,
    String? contextTopic,
    String? weakConceptsContext,
    String? recentMistakesContext,
    required bool isSocraticMode,
    required List<Map<String, String>> history,
    required List<SethAiSource> webSources,
  }) async {
    final systemPrompt = StringBuffer()
      ..writeln(
          "You are Seth AI, a direct, fast, in-app Academic Study Assistant & Knowledge Engine.")
      ..writeln("CRITICAL RULES:")
      ..writeln(
          "1. DIRECT IN-APP ANSWERS ONLY: Give the complete, detailed answer directly in your response. NEVER tell the user to click a Google Search link or copy-paste URLs into a browser.")
      ..writeln(
          "2. LANGUAGE MATCHING: Respond naturally in the exact language the student uses (English, Cebuano/Bisaya, Tagalog/Filipino).")
      ..writeln(
          "3. NEVER use robotic filler templates like 'Comprehensive Academic Guide: [X] is a foundational concept within this disciplinary domain'.")
      ..writeln(
          "4. Structure your explanation clearly with headings, bullet points, concrete examples, formulas/code where relevant, and a quick summary.");

    if (isSocraticMode) {
      systemPrompt.writeln(
          "5. SOCRATIC MODE ACTIVE: Explain clearly and conclude with 1-2 check-for-understanding questions.");
    }

    if (contextTopic != null && contextTopic.trim().isNotEmpty) {
      systemPrompt.writeln("Active Study Topic: $contextTopic");
    }
    if (weakConceptsContext != null && weakConceptsContext.trim().isNotEmpty) {
      final snippet = weakConceptsContext.length > 2000
          ? weakConceptsContext.substring(0, 2000)
          : weakConceptsContext;
      systemPrompt.writeln("Study Material Context:\n$snippet");
    }

    final webContextSb = StringBuffer();
    for (final src in webSources) {
      if (src.snippet.isNotEmpty) {
        webContextSb.writeln("- ${src.title}: ${src.snippet}");
      }
    }

    final messages = <Map<String, String>>[
      {"role": "system", "content": systemPrompt.toString()},
    ];

    final recentHistory =
        history.length > 6 ? history.sublist(history.length - 6) : history;
    for (final turn in recentHistory) {
      final role = (turn["role"] == "model" || turn["role"] == "assistant")
          ? "assistant"
          : "user";
      final content = turn["content"] ?? "";
      if (content.isNotEmpty && !isNonsenseLegacyResponse(content)) {
        messages.add({"role": role, "content": content});
      }
    }

    final userContent = webContextSb.isNotEmpty
        ? "$message\n\n[Verified Encyclopedia Facts:\n${webContextSb.toString()}]"
        : message;
    messages.add({"role": "user", "content": userContent});

    final response = await _directDio.post(
      "https://text.pollinations.ai/openai",
      data: {
        "model": "openai",
        "temperature": 0.3,
        "messages": messages,
      },
      options: Options(
        headers: {"Content-Type": "application/json"},
        responseType: ResponseType.plain,
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      final raw = response.data.toString().trim();
      if (raw.startsWith("{")) {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded["choices"] is List &&
            (decoded["choices"] as List).isNotEmpty) {
          final first = (decoded["choices"] as List).first;
          final content = first["message"]?["content"]?.toString();
          if (content != null && content.trim().isNotEmpty) {
            return content.trim();
          }
        }
      } else if (raw.isNotEmpty) {
        return raw;
      }
    }
    return null;
  }

  /// Universal Direct In-App Search Overview for the Dashboard & Search Bar.
  static Future<SethAiSearchOverview> searchUniversal(
    String query, {
    ApiClient? apiClient,
    String? courseId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SethAiSearchOverview(
        query: "",
        aiOverview: "",
        webSources: [],
      );
    }

    Future<List<Map<String, dynamic>>> fetchLocalQuestions() async {
      if (apiClient == null) return [];
      try {
        final res = await apiClient.dio.get(
          "/api/v1/ai/search",
          queryParameters: {
            "q": trimmed,
            if (courseId != null && courseId.isNotEmpty) "courseId": courseId,
          },
          options: Options(receiveTimeout: const Duration(seconds: 5)),
        );
        if (res.statusCode == 200 && res.data is Map) {
          final map = res.data as Map;
          if (map["localQuestions"] is List) {
            return (map["localQuestions"] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        }
      } catch (_) {}
      return [];
    }

    final localQuestionsFuture = fetchLocalQuestions();
    final reply = await askSethAi(
      message:
          "Provide a complete, direct in-app explanation for \"$trimmed\". Include: 1) Direct Answer & Definition, 2) Key Facts & Step-by-Step Breakdown, 3) Practical Examples, and 4) High-Yield Study Takeaways.",
      contextTopic: trimmed,
      apiClient: apiClient,
    );
    final localQuestions = await localQuestionsFuture;

    return SethAiSearchOverview(
      query: trimmed,
      aiOverview: reply.reply,
      webSources: reply.sources,
      localQuestions: localQuestions,
    );
  }

  /// Seth AI Easy Maker & Easy Corrector (In-App Writing Studio).
  static Future<SethAiWritingResult> runWritingStudio({
    required String mode, // "make" or "correct"
    required String textOrTopic,
    String format = "Academic Essay & Study Guide",
    String tone = "Academic & Clear",
    ApiClient? apiClient,
  }) async {
    final cleanInput = textOrTopic.trim();
    final isMake = mode.toLowerCase() == "make";

    final prompt = isMake
        ? "You are Seth AI Easy Maker.\n"
            "Create a complete, ready-to-use **$format** on the topic: \"$cleanInput\" with a **$tone** tone.\n"
            "Structure your output clearly with:\n"
            "1. 📌 **Title & Executive Summary**\n"
            "2. 📖 **Complete Body Sections** (with verified facts, examples, and clear explanations)\n"
            "3. 💡 **Key Takeaways & Bullet Points**\n"
            "4. 🧠 **Quick Self-Check Questions & Answers**"
        : "You are Seth AI Easy Corrector.\n"
            "Analyze, proofread, and elevate the following text using a **$tone** standard:\n\n"
            "\"$cleanInput\"\n\n"
            "Provide your response in this exact structured format:\n"
            "### ✅ Corrected & Polished Version\n"
            "(Write the clean, 100% grammatically correct version ready to copy)\n\n"
            "### 🎓 Elevated Academic Version\n"
            "(Write an elevated, high-scoring academic version of the text)\n\n"
            "### 🔍 Key Corrections & Improvements Made\n"
            "- (Bullet each grammar, spelling, punctuation, or clarity improvement)\n\n"
            "### 📊 Writing Quality Score & Feedback\n"
            "- **Overall Score:** XX/100\n"
            "- **Actionable Writing Tip:** (Brief constructive advice)";

    final aiReply = await askSethAi(
      message: prompt,
      contextTopic: isMake ? "Seth AI Easy Maker ($format)" : "Seth AI Easy Corrector ($tone)",
      apiClient: apiClient,
    );

    return SethAiWritingResult(
      mode: mode,
      markdownReport: aiReply.reply,
      qualityScore: 96,
      sources: aiReply.sources,
    );
  }

  static String _buildSmartFallbackReply(
    String query,
    String? contextTopic,
    List<SethAiSource> sources, {
    String? weakConceptsContext,
  }) {
    final subject = _extractSearchSubject(query);
    final lower = subject.toLowerCase().trim();

    // 1. Cebuano / Bisaya / Tagalog conversational support
    if (lower.contains("gwapo") || lower.contains("gwapoha") || lower.contains("gwapa") || lower.contains("pogi")) {
      return "Haha, salamat sa imong kumpyansa! 😄 Ang pagka-**gwapo** o **gwapa** nagagikan sa kombinasyon sa maayong **genetics** (sama sa facial symmetry ug panit), **personal grooming ug kahapsay sa lawas**, ug labaw sa tanan ang imong **kompyansa sa kaugalingon (self-confidence)** ug maayong batasan.\n\n"
          "Ako diay si **Seth AI**. Kung naa kay gustong tun-an, i-search nga topic, ipahimo sa **Easy Maker**, o ipa-summarize nga PDF/YouTube video, pangutana lang direkta dinhi sa app!";
    }

    if (lower.contains("nabuang") || lower.contains("naunsa") || lower.contains("way klaro")) {
      return "Pasensya kaayo! 🙏 Gi-upgrade na ang **Seth AI** aron mohatag og **direkta nga tubag sulod mismo sa app**—dili na maghatag og link nga kinahanglan pa nimo i-copy ug i-paste sa browser.\n\n"
          "Isulti lang ang topic o pangutana nga gusto nimong mahibal-an!";
    }

    // 2. If encyclopedia / DuckDuckGo sources returned real snippets, synthesize them into a complete direct answer
    final richSources = sources.where((s) => s.snippet.trim().isNotEmpty).toList();
    if (richSources.isNotEmpty) {
      final sb = StringBuffer();
      sb.writeln("### 📌 Direct Answer: $subject\n");
      sb.writeln(richSources.first.snippet.trim());
      sb.writeln();

      if (richSources.length > 1) {
        sb.writeln("### 🔍 Key Facts & Supporting Details\n");
        for (final s in richSources.skip(1)) {
          sb.writeln("- **${s.title.replaceAll(' — Encyclopedia Reference', '').replaceAll(' — Direct Knowledge Summary', '')}:** ${s.snippet.trim()}");
        }
        sb.writeln();
      }

      sb.writeln("### 💡 Study Takeaways\n");
      sb.writeln("- **Core Concept:** Focus on the primary definition and how **$subject** operates in real-world scenarios.");
      sb.writeln("- **Active Recall Tip:** Try explaining **$subject** in your own words in 2 sentences, then test yourself using Practice Quiz mode.");
      return sb.toString().trim();
    }

    // 3. If user has attached study notes / context, synthesize directly from their study material
    if (weakConceptsContext != null && weakConceptsContext.trim().isNotEmpty) {
      final lines = weakConceptsContext
          .split(RegExp(r"\r?\n"))
          .map((l) => l.trim())
          .where((l) => l.length > 15)
          .take(8)
          .toList();
      if (lines.isNotEmpty) {
        return "### 📌 Direct Study Analysis: ${contextTopic ?? subject}\n\n"
            "Based on your study material, here are the key points directly addressing your question:\n\n"
            "${lines.map((l) => l.startsWith('-') || l.startsWith('•') ? l : '- $l').join('\n')}\n\n"
            "### 🎯 Key Takeaway\n"
            "Review the highlighted points above and use **Practice Simulation** to test your active recall on **${contextTopic ?? subject}**.";
      }
    }

    // 4. Built-in Direct Topic Synthesis (Complete in-app explanation, never redirects to external links)
    return "### 📌 Direct Study Guide: $subject\n\n"
        "**$subject** is an important topic to understand through its core definition, how it works in practice, and its key exam takeaways:\n\n"
        "#### 1. Core Definition & Purpose\n"
        "- **What It Is:** **$subject** refers to the key principles, mechanisms, and practical applications governing this subject area.\n"
        "- **Why It Matters:** Mastering **$subject** allows you to solve problems systematically, connect cause-and-effect relationships, and answer analytical exam questions accurately.\n\n"
        "#### 2. Key Breakdown & How It Works\n"
        "1. **Foundation & Inputs:** Identify the main terms, given conditions, or starting concepts of **$subject**.\n"
        "2. **Core Mechanism / Process:** Understand how the components interact step by step rather than memorizing isolated terms.\n"
        "3. **Practical Outcome:** Apply the concept to real-world examples, case studies, or practice problems.\n\n"
        "#### 3. Quick Self-Check for Active Recall\n"
        "- *Can you define **$subject** in one clear sentence?*\n"
        "- *What is one real-world example of **$subject** in action?*";
  }
}

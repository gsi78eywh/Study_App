import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

class ChatMessage {
  final String role; // "user" or "assistant"
  final String text;
  final String? modelUsed;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.text,
    this.modelUsed,
    required this.timestamp,
  });
}

class AiTutorScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<CourseModel> courses;
  final String? initialPrompt;
  final String? initialCourseContext;

  const AiTutorScreen({
    super.key,
    required this.apiClient,
    required this.courses,
    this.initialPrompt,
    this.initialCourseContext,
  });

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _selectedCourseContext;

  final List<String> _quickPrompts = [
    "💡 Explain this simply with an analogy",
    "🧪 Break down key formulas and variables",
    "📝 Give me a high-yield practice problem",
    "🎯 What are the common exam pitfalls?",
    "🔍 Summarize the core theoretical principles",
  ];

  @override
  void initState() {
    super.initState();
    _selectedCourseContext =
        widget.initialCourseContext ??
        (widget.courses.isNotEmpty ? widget.courses.first.name : null);

    // Initial greeting from Tutor
    final hasGeminiKey =
        widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false;
    _messages.add(
      ChatMessage(
        role: "assistant",
        text:
            "👋 Hi! I'm your **Gemini Study Tutor**, powered by Google Gemini AI.\n\n"
            "I can help you master complex coursework, explain tricky equations, break down practice problems, and give you conceptual clarity.\n\n"
            "What topic or question are we tackling today?",
        modelUsed: hasGeminiKey ? "gemini-1.5-flash" : "Built-In Academic Engine",
        timestamp: DateTime.now(),
      ),
    );

    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendMessage(widget.initialPrompt!.trim());
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isLoading) return;

    _textController.clear();
    setState(() {
      _messages.add(
        ChatMessage(role: "user", text: query, timestamp: DateTime.now()),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.role == "user" || m.role == "assistant")
          .map(
            (m) => {
              "role": m.role == "assistant" ? "model" : "user",
              "content": m.text,
            },
          )
          .toList();

      final geminiKey = widget.apiClient.sessionService.geminiApiKey;

      final response = await widget.apiClient.dio.post(
        ApiConstants.aiTutor,
        data: {
          "message": query,
          "contextTopic": _selectedCourseContext,
          "apiKey": geminiKey,
          "history": history.length > 6
              ? history.sublist(history.length - 6)
              : history,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final reply =
            response.data["reply"] as String? ?? "No response received.";
        final model =
            response.data["modelUsed"] as String? ?? "gemini-flash-latest";

        if (mounted) {
          setState(() {
            _messages.add(
              ChatMessage(
                role: "assistant",
                text: reply,
                modelUsed: model,
                timestamp: DateTime.now(),
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              role: "assistant",
              text:
                  "⚠️ Gemini Tutor connection error: $e\n\nPlease check your network or try again shortly.",
              modelUsed: "offline-fallback",
              timestamp: DateTime.now(),
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _saveExplanationToNotebook(String text) async {
    if (widget.courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Create a course before saving a notebook entry."),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      final title = text
          .split('\n')
          .first
          .replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '')
          .trim();
      final cleanTitle = title.isNotEmpty
          ? (title.length > 40 ? title.substring(0, 40) : title)
          : "Gemini Study Note";
      await widget.apiClient.dio.post(
        "/api/v1/notebooks",
        data: {
          "courseId": widget.courses.first.id,
          "title": cleanTitle,
          "contentMarkdown": text,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "✨ Saved explanation directly to your Digital Notebook!",
            ),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to save this explanation to the notebook."),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _showGeminiKeyDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(
      text: widget.apiClient.sessionService.geminiApiKey ?? "",
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "Google Gemini API Key",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Configure your free Google Gemini API key to enable live cloud AI reasoning with Google Gemini models.\n\n"
                  "Even without an API key, your tutor runs fully functional with the built-in offline educational engine.",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: "Gemini API Key",
                    hintText: "AIzaSy...",
                    prefixIcon: const Icon(Icons.key, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => controller.clear(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Keys are stored securely on your device and sent directly to Google Gemini.",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final key = controller.text.trim();
                await widget.apiClient.sessionService.setGeminiApiKey(key);
                if (mounted) {
                  setState(() {});
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        key.isNotEmpty
                            ? "✨ Gemini API Key saved! Live Cloud AI active."
                            : "Gemini API Key cleared. Using built-in academic engine.",
                      ),
                      backgroundColor:
                          key.isNotEmpty ? AppColors.accent : AppColors.primary,
                    ),
                  );
                }
              },
              child: const Text("Save Key"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                    Color(0xFFEC4899),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Gemini Study Tutor",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  "Google Gemini Multimodal AI Engine",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Gemini Key Status / Configuration Action
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _showGeminiKeyDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                          ? Icons.auto_awesome
                          : Icons.vpn_key_rounded,
                      size: 13,
                      color: (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                          ? "Cloud AI"
                          : "API Key",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false)
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.courses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.tune_rounded, color: context.textSecondary),
                tooltip: "Set Study Subject Context",
                initialValue: _selectedCourseContext,
                onSelected: (val) {
                  setState(() => _selectedCourseContext = val);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: null,
                    child: Text("All Subjects (General)"),
                  ),
                  ...widget.courses.map(
                    (c) => PopupMenuItem(value: c.name, child: Text(c.name)),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Subject context badge
            if (_selectedCourseContext != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFEEF2FF),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          size: 16,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Context: $_selectedCourseContext",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : const Color(0xFF3730A3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Quick Prompt Chips
            Container(
              height: 44,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _quickPrompts.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final prompt = _quickPrompts[index];
                      return ActionChip(
                        label: Text(
                          prompt,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        backgroundColor: context.surfaceColor,
                        side: BorderSide(color: context.cardBorderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onPressed: () => _sendMessage(
                          prompt.replaceFirst(RegExp(r'^[^a-zA-Z0-9]+'), ''),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Chat Message Thread with Desktop MaxWidth Centering
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.role == "user";

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          mainAxisAlignment: isUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? (isDark
                                            ? const Color(0xFF4F46E5)
                                            : const Color(0xFF4338CA))
                                      : context.surfaceColor,
                                  border: Border.all(
                                    color: isUser
                                        ? Colors.transparent
                                        : context.cardBorderColor,
                                  ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(
                                      isUser ? 16 : 4,
                                    ),
                                    bottomRight: Radius.circular(
                                      isUser ? 4 : 16,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.2 : 0.04,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      msg.text,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        height: 1.5,
                                        color: isUser
                                            ? Colors.white
                                            : context.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (msg.modelUsed != null) ...[
                                          Text(
                                            msg.modelUsed!,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: isUser
                                                  ? Colors.white.withValues(
                                                      alpha: 0.7,
                                                    )
                                                  : context.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (!isUser) ...[
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(
                                                ClipboardData(text: msg.text),
                                              );
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        "Copied explanation to clipboard!",
                                                      ),
                                                      duration: Duration(
                                                        seconds: 2,
                                                      ),
                                                    ),
                                                  );
                                            },
                                            child: Icon(
                                              Icons.copy_rounded,
                                              size: 14,
                                              color: context.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          InkWell(
                                            onTap: () =>
                                                _saveExplanationToNotebook(
                                                  msg.text,
                                                ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.bookmark_add_outlined,
                                                  size: 14,
                                                  color: AppColors.accent,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "Save to Notebook",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.accent,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (isUser) const SizedBox(width: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Thinking / Loading indicator
            if (_isLoading)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Gemini is analyzing context and formulating step-by-step response...",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom Input Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                border: Border(top: BorderSide(color: context.cardBorderColor)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: "Ask Gemini any academic concept, formula, or question...",
                            hintStyle: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 13,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: _sendMessage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _sendMessage(_textController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

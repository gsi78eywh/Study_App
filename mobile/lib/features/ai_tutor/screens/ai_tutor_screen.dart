import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/audio_speech_service.dart";
import "../../../core/services/child_safety_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

class ChatMessage {
  final String role; // "user" or "assistant"
  final String text;
  final String? modelUsed;
  final double? latencySeconds;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.text,
    this.modelUsed,
    this.latencySeconds,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    "role": role,
    "text": text,
    "modelUsed": modelUsed,
    "latencySeconds": latencySeconds,
    "timestamp": timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json["role"] as String? ?? "assistant",
      text: json["text"] as String? ?? "",
      modelUsed: json["modelUsed"] as String?,
      latencySeconds: (json["latencySeconds"] as num?)?.toDouble(),
      timestamp: DateTime.tryParse(json["timestamp"]?.toString() ?? "") ?? DateTime.now(),
    );
  }
}

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "createdAt": createdAt.toIso8601String(),
    "updatedAt": updatedAt.toIso8601String(),
    "messages": messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json["id"] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json["title"] as String? ?? "Study Chat",
      createdAt: DateTime.tryParse(json["createdAt"]?.toString() ?? "") ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json["updatedAt"]?.toString() ?? "") ?? DateTime.now(),
      messages: (json["messages"] as List?)
              ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

abstract class _TutorMessageBlock {}

class _TextMessageBlock extends _TutorMessageBlock {
  final String text;
  _TextMessageBlock(this.text);
}

class _MermaidMessageBlock extends _TutorMessageBlock {
  final String code;
  _MermaidMessageBlock(this.code);
}

class _CodeMessageBlock extends _TutorMessageBlock {
  final String language;
  final String code;
  _CodeMessageBlock(this.language, this.code);
}

class AiTutorScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<CourseModel> courses;
  final String? initialPrompt;
  final String? initialCourseContext;
  final String? initialWeakConcepts;
  final String? initialMistakesContext;
  final bool startInSocraticMode;

  const AiTutorScreen({
    super.key,
    required this.apiClient,
    required this.courses,
    this.initialPrompt,
    this.initialCourseContext,
    this.initialWeakConcepts,
    this.initialMistakesContext,
    this.startInSocraticMode = false,
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
  late bool _isSocraticMode;
  bool _isTeachMeMode = false;
  String? _weakConceptsContext;
  String? _recentMistakesContext;
  bool? _isTutorOnline = true;
  String _tutorStatusLabel = "AI Tutor Online";

  static const String _sessionsPrefKey = "ai_tutor_saved_sessions_v1";
  final List<ChatSession> _sessions = [];
  String? _activeSessionId;

  final List<String> _quickPrompts = [
    "👨‍🏫 Test me: Ask me to explain a concept (Feynman Technique)",
    "💡 Give me a hint (don't reveal the answer)",
    "🧠 Why did I get this wrong?",
    "🎯 Test my understanding with a question",
    "💡 Explain this simply with an analogy",
    "🧪 Break down key formulas and variables",
    "📝 Give me a high-yield practice problem",
    "🔍 Summarize the core theoretical principles",
  ];

  List<String> get _currentQuickPrompts {
    if (ChildSafetyService.instance.isJuniorMode) {
      final grade = ChildSafetyService.instance.gradeLevelText;
      return [
        "🎈 Explain this simply like I am in $grade",
        "🌟 Can you give me a fun real-world example?",
        "📝 Ask me a friendly question to test my understanding",
        "💡 Give me a gentle hint without telling the answer",
        "🎨 Use a simple story or analogy to explain this",
        "✨ What are the 3 most important words to remember?",
      ];
    }
    return _quickPrompts;
  }

  ChatMessage _createDefaultGreeting() {
    final hasGeminiKey =
        widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false;
    final isJunior = ChildSafetyService.instance.isJuniorMode;
    return ChatMessage(
      role: "assistant",
      text: isJunior
          ? "👋 Hello friend! I'm your **Study Buddy**, powered by Gemini AI!\n\n"
              "I can explain lessons simply, tell fun learning stories, give gentle hints, and help you practice without stress! 🌟\n\n"
              "What topic would you like to explore today?"
          : "👋 Hi! I'm your **Study Tutor**, powered by Gemini.\n\n"
              "I can help you master complex coursework, explain tricky equations, break down practice problems, and give you conceptual clarity.\n\n"
              "What topic or question are we tackling today?",
      modelUsed: hasGeminiKey ? "gemini-3.1-flash-lite" : "Built-In Academic Engine",
      timestamp: DateTime.now(),
    );
  }

  void _loadSessions() {
    try {
      final raw = widget.apiClient.sessionService.prefs.getString(_sessionsPrefKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _sessions.clear();
        for (final item in list) {
          _sessions.add(ChatSession.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint("Error loading chat sessions: $e");
    }

    if (_sessions.isEmpty) {
      final newSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: "New Study Chat",
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [_createDefaultGreeting()],
      );
      _sessions.add(newSession);
    }

    _activeSessionId = _sessions.first.id;
    _messages.clear();
    _messages.addAll(_sessions.first.messages);
  }

  Future<void> _saveSessions() async {
    try {
      final current = _sessions.where((s) => s.id == _activeSessionId).firstOrNull;
      if (current != null) {
        current.messages.clear();
        current.messages.addAll(_messages);
        current.updatedAt = DateTime.now();
      }

      // Cap to 30 sessions x 100 messages
      if (_sessions.length > 30) {
        _sessions.removeRange(30, _sessions.length);
      }
      for (final s in _sessions) {
        if (s.messages.length > 100) {
          s.messages.removeRange(0, s.messages.length - 100);
        }
      }

      final encoded = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      await widget.apiClient.sessionService.prefs.setString(_sessionsPrefKey, encoded);
    } catch (e) {
      debugPrint("Error saving chat sessions: $e");
    }
  }

  void _createNewChat() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "New Study Chat",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [_createDefaultGreeting()],
    );
    setState(() {
      _sessions.insert(0, newSession);
      _activeSessionId = newSession.id;
      _messages.clear();
      _messages.addAll(newSession.messages);
    });
    _saveSessions();
    _scrollToBottom();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✨ New chat session started!"),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  void _switchSession(ChatSession session) {
    _saveSessions();
    setState(() {
      _activeSessionId = session.id;
      _messages.clear();
      _messages.addAll(session.messages);
    });
    _scrollToBottom();
  }

  void _deleteSession(String sessionId) {
    setState(() {
      _sessions.removeWhere((s) => s.id == sessionId);
      if (_activeSessionId == sessionId) {
        if (_sessions.isNotEmpty) {
          _activeSessionId = _sessions.first.id;
          _messages.clear();
          _messages.addAll(_sessions.first.messages);
        } else {
          final newSession = ChatSession(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: "New Study Chat",
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            messages: [_createDefaultGreeting()],
          );
          _sessions.add(newSession);
          _activeSessionId = newSession.id;
          _messages.clear();
          _messages.addAll(newSession.messages);
        }
      }
    });
    _saveSessions();
  }

  Future<void> _clearAllChats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogCtx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_sweep_rounded, color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Text("Clear All Chats?"),
          ],
        ),
        content: const Text(
          "Are you sure you want to delete all chat history? This will permanently erase all previous conversations from memory and local storage.",
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text("Clear All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1. Purge from local persistent storage
      await widget.apiClient.sessionService.prefs.remove(_sessionsPrefKey);

      // 2. Purge from active memory
      setState(() {
        _sessions.clear();
        _messages.clear();

        // 3. Re-initialize a single clean default greeting
        final freshSession = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "New Study Chat",
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: [_createDefaultGreeting()],
        );
        _sessions.add(freshSession);
        _activeSessionId = freshSession.id;
        _messages.addAll(freshSession.messages);
      });

      await _saveSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text("🧹 Chat history purged from memory & local storage!"),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showChatHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.85,
              expand: false,
              builder: (sheetCtx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.forum_outlined, size: 20, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Text(
                                "Chat History",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: context.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (_sessions.isNotEmpty) ...[
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.danger,
                                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 15),
                                  label: const Text("Clear All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _clearAllChats();
                                  },
                                ),
                                const SizedBox(width: 6),
                              ],
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text("New Chat", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _createNewChat();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      Expanded(
                        child: _sessions.isEmpty
                            ? Center(
                                child: Text(
                                  "No chat sessions found.",
                                  style: TextStyle(color: context.textSecondary),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _sessions.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (itemCtx, index) {
                                  final s = _sessions[index];
                                  final isActive = s.id == _activeSessionId;
                                  final userMsgCount = s.messages.where((m) => m.role == "user").length;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: isActive
                                          ? const BorderSide(color: AppColors.accent, width: 1.5)
                                          : BorderSide.none,
                                    ),
                                    tileColor: isActive
                                        ? AppColors.accent.withValues(alpha: 0.08)
                                        : Colors.transparent,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isActive
                                          ? AppColors.accent.withValues(alpha: 0.2)
                                          : context.cardBorderColor,
                                      child: Icon(
                                        isActive ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                        size: 16,
                                        color: isActive ? AppColors.accent : context.textSecondary,
                                      ),
                                    ),
                                    title: Text(
                                      s.title,
                                      style: GoogleFonts.outfit(
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 14,
                                        color: context.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      "$userMsgCount queries • ${s.updatedAt.month}/${s.updatedAt.day} ${s.updatedAt.hour.toString().padLeft(2, '0')}:${s.updatedAt.minute.toString().padLeft(2, '0')}",
                                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                      tooltip: "Delete Chat",
                                      onPressed: () {
                                        _deleteSession(s.id);
                                        setModalState(() {});
                                      },
                                    ),
                                    onTap: () {
                                      _switchSession(s);
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _isSocraticMode = widget.startInSocraticMode;
    _weakConceptsContext = widget.initialWeakConcepts;
    _recentMistakesContext = widget.initialMistakesContext;
    _selectedCourseContext =
        widget.initialCourseContext ??
        (widget.courses.isNotEmpty ? widget.courses.first.name : null);

    _loadSessions();
    _checkTutorStatus();

    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendMessage(widget.initialPrompt!.trim());
      });
    }
  }

  @override
  void didUpdateWidget(AiTutorScreen old) {
    super.didUpdateWidget(old);
    if (_selectedCourseContext == null && widget.courses.isNotEmpty) {
      setState(() => _selectedCourseContext = widget.courses.first.name);
    }
  }

  @override
  void dispose() {
    AudioSpeechHelper.instance.stop();
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

  Future<void> _checkTutorStatus() async {
    try {
      final res = await widget.apiClient.dio.get(ApiConstants.health);
      if (res.statusCode == 200) {
        bool isGemini = false;
        bool isOnline = true;
        if (res.data is Map) {
          final data = res.data as Map;
          isGemini = data["gemini"] == true;
          if (data.containsKey("ok")) {
            isOnline = data["ok"] == true;
          } else if (data.containsKey("status")) {
            isOnline = data["status"] == "healthy";
          }
        }
        if (mounted) {
          setState(() {
            _isTutorOnline = isOnline;
            _tutorStatusLabel = isOnline
                ? (isGemini ? "Gemini Online" : "AI Tutor Online")
                : "Tutor Offline";
          });
        }
        return;
      }
    } catch (_) {}

    try {
      final res = await widget.apiClient.dio.get("/api/v1/dev/diagnostics");
      if (res.statusCode == 200 && res.data is Map && (res.data as Map).containsKey("aiService")) {
        final aiService = res.data["aiService"] as Map?;
        final isOnline = aiService?["reachable"] == true;
        if (mounted) {
          setState(() {
            _isTutorOnline = isOnline;
            _tutorStatusLabel = isOnline ? "AI Tutor Online" : "Tutor Offline";
          });
        }
        return;
      }
    } catch (_) {}
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isLoading) return;

    // _sendMessage: build history BEFORE adding the new message; drop greeting and offline bubbles
    final history = _messages
        .skip(_messages.isNotEmpty && _messages.first.role == 'assistant' ? 1 : 0)
        .where((m) => m.modelUsed != 'Offline')
        .map((m) => {'role': m.role == 'assistant' ? 'model' : 'user', 'content': m.text})
        .toList();

    _textController.clear();
    setState(() {
      _messages.add(
        ChatMessage(role: "user", text: query, timestamp: DateTime.now()),
      );
      _isLoading = true;
    });

    // Auto-update session title from first user query if still generic
    final active = _sessions.where((s) => s.id == _activeSessionId).firstOrNull;
    if (active != null && (active.title == "New Study Chat" || active.messages.length <= 1)) {
      final clean = query.replaceAll(RegExp(r'\s+'), ' ').trim();
      active.title = clean.length > 32 ? "${clean.substring(0, 32)}..." : clean;
    }

    _scrollToBottom();

    final stopwatch = Stopwatch()..start();
    try {
      final effectiveMessage = ChildSafetyService.instance.isJuniorMode
          ? ChildSafetyService.instance.enrichPromptForChildSafety(query)
          : query;

      final response = await widget.apiClient.dio.post(
        ApiConstants.aiTutor,
        data: {
          "message": effectiveMessage,
          "contextTopic": _selectedCourseContext,
          "isSocraticMode": _isSocraticMode,
          "isTeachMeMode": _isTeachMeMode,
          "weakConceptsContext": _weakConceptsContext,
          "recentMistakesContext": _recentMistakesContext,
          "history": history.length > 6
              ? history.sublist(history.length - 6)
              : history,
        },
      );
      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final reply =
            response.data["reply"] as String? ?? "No response received.";
        final model =
            response.data["modelUsed"] as String? ?? "gemini-3.1-flash-lite";
        final latency = response.data["latencySeconds"] is num
            ? (response.data["latencySeconds"] as num).toDouble()
            : (stopwatch.elapsedMilliseconds / 1000.0);

        if (mounted) {
          setState(() {
            _isTutorOnline = true;
            _tutorStatusLabel = "AI Tutor Online";
            _messages.add(
              ChatMessage(
                role: "assistant",
                text: reply,
                modelUsed: model,
                latencySeconds: latency,
                timestamp: DateTime.now(),
              ),
            );
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _messages.add(
              ChatMessage(
                role: "assistant",
                text: "⚠️ Server returned status code ${response.statusCode}. Please try again later.",
                modelUsed: "Error",
                latencySeconds: stopwatch.elapsedMilliseconds / 1000.0,
                timestamp: DateTime.now(),
              ),
            );
          });
        }
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isTutorOnline = false;
          _tutorStatusLabel = "Tutor Offline";
          _messages.add(
            ChatMessage(
              role: "assistant",
              text:
                  "📡 **Tutor is currently offline.**\n\nPlease ensure your backend API is running and reachable, then tap the status badge to retry.",
              modelUsed: "Offline",
              latencySeconds: stopwatch.elapsedMilliseconds / 1000.0,
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
      _saveSessions();
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
      if (widget.courses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("⚠️ Please create a course first before saving notebook entries."),
            ),
          );
        }
        return;
      }
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
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: "New Chat",
            onPressed: _createNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22),
            tooltip: "Chat History",
            onPressed: _showChatHistorySheet,
          ),
          // AI Tutor Online Status Badge (Driven by real server health check)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: InkWell(
              onTap: _checkTutorStatus,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_isTutorOnline == true
                          ? const Color(0xFF10B981)
                          : (_isTutorOnline == false
                              ? AppColors.danger
                              : const Color(0xFFF59E0B)))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (_isTutorOnline == true
                            ? const Color(0xFF10B981)
                            : (_isTutorOnline == false
                                ? AppColors.danger
                                : const Color(0xFFF59E0B)))
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isTutorOnline == true
                            ? const Color(0xFF10B981)
                            : (_isTutorOnline == false
                                ? AppColors.danger
                                : const Color(0xFFF59E0B)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _tutorStatusLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _isTutorOnline == true
                            ? const Color(0xFF10B981)
                            : (_isTutorOnline == false
                                ? AppColors.danger
                                : const Color(0xFFF59E0B)),
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
                initialValue: _selectedCourseContext ?? '',
                onSelected: (val) {
                  setState(() => _selectedCourseContext = val.isEmpty ? null : val);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: '',
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
            // Subject context & Socratic mode banner
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
                          _selectedCourseContext != null
                              ? "Context: $_selectedCourseContext"
                              : "General Study Mode",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF3730A3),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: "UNESCO Guidance: Guides with hints & questions instead of revealing direct answers",
                        child: InkWell(
                          onTap: () => setState(() => _isSocraticMode = !_isSocraticMode),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isSocraticMode
                                  ? const Color(0xFF6366F1)
                                  : (isDark ? const Color(0xFF334155) : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isSocraticMode
                                    ? const Color(0xFF6366F1)
                                    : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lightbulb_rounded,
                                  size: 13,
                                  color: _isSocraticMode ? Colors.white : const Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isSocraticMode ? "Socratic Mode ON" : "Socratic Hints",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isSocraticMode
                                        ? Colors.white
                                        : (isDark ? Colors.white : const Color(0xFF1E293B)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: "Feynman Technique: You teach the concept, and the AI probes your understanding with thoughtful follow-up questions",
                        child: InkWell(
                          onTap: () => setState(() {
                            _isTeachMeMode = !_isTeachMeMode;
                            if (_isTeachMeMode) _isSocraticMode = false;
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isTeachMeMode
                                  ? const Color(0xFFEC4899)
                                  : (isDark ? const Color(0xFF334155) : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isTeachMeMode
                                    ? const Color(0xFFEC4899)
                                    : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.record_voice_over_rounded,
                                  size: 13,
                                  color: _isTeachMeMode ? Colors.white : const Color(0xFFEC4899),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isTeachMeMode ? "Teach AI ON" : "Teach the AI",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isTeachMeMode
                                        ? Colors.white
                                        : (isDark ? Colors.white : const Color(0xFF1E293B)),
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
              ),
            ),

            // Quick Prompt Chips
            Container(
              height: 48,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _currentQuickPrompts.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final prompt = _currentQuickPrompts[index];
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
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
                                    _buildMessageContent(msg.text, isUser, context),
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
                                              if (!ChildSafetyService.instance.readAloudEnabled) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text("Read Aloud is disabled in settings."),
                                                    duration: Duration(milliseconds: 1500),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (AudioSpeechHelper.instance.isSpeaking) {
                                                AudioSpeechHelper.instance.stop();
                                              } else {
                                                AudioSpeechHelper.instance.speak(msg.text);
                                              }
                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.volume_up_rounded,
                                                  size: 14,
                                                  color: context.textSecondary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "Read",
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    color: context.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
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

  Widget _buildMessageContent(String rawText, bool isUser, BuildContext context) {
    final blocks = _parseMessageBlocks(rawText);

    if (blocks.length == 1 && blocks.first is _TextMessageBlock) {
      return _buildFormattedMarkdownText((blocks.first as _TextMessageBlock).text, isUser, context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < blocks.length; i++) ...[
          if (blocks[i] is _TextMessageBlock)
            _buildFormattedMarkdownText((blocks[i] as _TextMessageBlock).text, isUser, context)
          else if (blocks[i] is _MermaidMessageBlock)
            _buildMermaidDiagramCard((blocks[i] as _MermaidMessageBlock).code, context)
          else if (blocks[i] is _CodeMessageBlock)
            _buildCodeBlockCard(
              (blocks[i] as _CodeMessageBlock).language,
              (blocks[i] as _CodeMessageBlock).code,
              context,
            ),
          if (i < blocks.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  List<_TutorMessageBlock> _parseMessageBlocks(String rawText) {
    final List<_TutorMessageBlock> blocks = [];
    final codeBlockRegex = RegExp(r'```([a-zA-Z0-9_\-\+#]*)\r?\n([\s\S]*?)```');
    int lastIndex = 0;

    for (final match in codeBlockRegex.allMatches(rawText)) {
      if (match.start > lastIndex) {
        final textBefore = rawText.substring(lastIndex, match.start).trim();
        if (textBefore.isNotEmpty) {
          blocks.add(_TextMessageBlock(textBefore));
        }
      }

      final lang = (match.group(1) ?? "").trim().toLowerCase();
      final code = (match.group(2) ?? "").trim();

      if (lang == "mermaid") {
        blocks.add(_MermaidMessageBlock(code));
      } else {
        blocks.add(_CodeMessageBlock(lang.isEmpty ? "code" : lang, code));
      }

      lastIndex = match.end;
    }

    if (lastIndex < rawText.length) {
      final trailingText = rawText.substring(lastIndex).trim();
      if (trailingText.isNotEmpty) {
        blocks.add(_TextMessageBlock(trailingText));
      }
    }

    if (blocks.isEmpty && rawText.isNotEmpty) {
      blocks.add(_TextMessageBlock(rawText));
    }

    return blocks;
  }

  Widget _buildCodeBlockCard(String language, String code, BuildContext context) {
    final displayLang = language.isEmpty ? "CODE" : language.toUpperCase();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Sleek developer slate dark
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFF334155), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    displayLang,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Clean Executable Source",
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text("✨ Clean source code copied! Ready to paste & run with 0 errors."),
                            ),
                          ],
                        ),
                        backgroundColor: Color(0xFF10B981),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF34D399)),
                        const SizedBox(width: 5),
                        Text(
                          "Copy Code",
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF34D399),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code Display Area with Monospace Font & Horizontal Scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              code,
              style: GoogleFonts.firaCode(
                fontSize: 12.5,
                height: 1.5,
                color: const Color(0xFFF1F5F9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMermaidDiagramCard(String code, BuildContext context) {
    final isDark = context.isDarkMode;
    // Extract node labels from mermaid e.g. A[Order Placed] --> B[Inventory Check]
    final stepMatches = RegExp(r'\[([^\]]+)\]').allMatches(code).map((m) => m.group(1)!).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_rounded, size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Flowchart Diagram (Mermaid)",
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF6366F1)),
                  tooltip: "Copy Mermaid Code",
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Diagram Mermaid syntax copied!"),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Flowchart Step Visualization
          if (stepMatches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (int i = 0; i < stepMatches.length; i++) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${i + 1}",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              stepMatches[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < stepMatches.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFF6366F1)),
                      ),
                  ],
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                code,
                style: const TextStyle(fontFamily: "monospace", fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFormattedMarkdownText(String rawText, bool isUser, BuildContext context) {
    final baseColor = isUser ? Colors.white : context.textPrimary;
    final lines = rawText.split('\n');
    final List<InlineSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: '\n'));

      if (line.startsWith('### ')) {
        spans.add(TextSpan(
          text: line.substring(4),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: baseColor,
          ),
        ));
      } else if (line.startsWith('## ')) {
        spans.add(TextSpan(
          text: line.substring(3),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: baseColor,
          ),
        ));
      } else if (line.startsWith('# ')) {
        spans.add(TextSpan(
          text: line.substring(2),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: baseColor,
          ),
        ));
      } else {
        spans.addAll(_parseInlineMarkdown(line, baseColor));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: GoogleFonts.inter(
        fontSize: 14,
        height: 1.5,
        color: baseColor,
      ),
    );
  }

  List<InlineSpan> _parseInlineMarkdown(String line, Color baseColor) {
    final List<InlineSpan> spans = [];
    final regex = RegExp(r'(\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`)');
    int lastIndex = 0;

    for (final match in regex.allMatches(line)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: line.substring(lastIndex, match.start),
          style: TextStyle(color: baseColor),
        ));
      }

      final boldGroup = match.group(2);
      final italicGroup = match.group(3);
      final codeGroup = match.group(4);

      if (boldGroup != null) {
        spans.add(TextSpan(
          text: boldGroup,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: baseColor,
          ),
        ));
      } else if (italicGroup != null) {
        spans.add(TextSpan(
          text: italicGroup,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: baseColor,
          ),
        ));
      } else if (codeGroup != null) {
        spans.add(TextSpan(
          text: codeGroup,
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: baseColor.withValues(alpha: 0.15),
            color: baseColor,
          ),
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastIndex),
        style: TextStyle(color: baseColor),
      ));
    }

    return spans;
  }

}

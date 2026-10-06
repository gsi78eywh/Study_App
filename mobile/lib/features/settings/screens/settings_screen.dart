import "dart:convert";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/app_session.dart";
import "../../../core/services/child_safety_service.dart";
import "../../../core/services/notification_service.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../auth/widgets/terms_and_privacy_modal.dart";
import "../../courses/widgets/user_manual_sheet.dart";
import "../../quiz/models/quiz_models.dart";
import "../models/study_settings_model.dart";
import "../services/settings_service.dart";
import "../widgets/dswd_safety_modal.dart";

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;
  final SettingsService settingsService;
  final VoidCallback? onLogout;
  final bool initialDeveloperModeUnlocked;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
    required this.settingsService,
    this.onLogout,
    this.initialDeveloperModeUnlocked = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StudySettingsModel _current;
  late final TextEditingController _geminiApiKeyController;
  late final TextEditingController _serverUrlController;
  bool _isSaving = false;
  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool? _connectionSuccess;
  bool _lowDataMode = false;
  int? _connectionLatencyMs;
  late bool _developerModeUnlocked;
  bool? _hasGeminiOnServer;
  List<String>? _diagnosticsPlainLines;

  late String _selectedSchoolLevel;
  late String _selectedGradingScale;

  @override
  void initState() {
    super.initState();
    _developerModeUnlocked = widget.initialDeveloperModeUnlocked;
    _current = widget.settingsService.settings;
    _geminiApiKeyController = TextEditingController(text: widget.sessionService.geminiApiKey ?? "");
    _serverUrlController = TextEditingController(
      text: widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl,
    );
    _selectedSchoolLevel = widget.sessionService.schoolLevel;
    _selectedGradingScale = widget.sessionService.gradingScale;
    _loadRemote();
    _checkServerHealth();
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _checkServerHealth() async {
    try {
      final resp = await widget.apiClient.dio.get("/health");
      if (resp.statusCode == 200 && resp.data is Map) {
        if (mounted) {
          setState(() {
            _hasGeminiOnServer = resp.data["gemini"] == true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasGeminiOnServer = false;
        });
      }
    }
  }

  Future<void> _loadRemote() async {
    final remote = await widget.settingsService.fetchRemoteSettings();
    if (mounted) {
      setState(() => _current = remote);
    }
  }

  void _showUrlValidationError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 22),
            const SizedBox(width: 8),
            Text(
              "Endpoint Validation Failed",
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: ctx.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Acknowledge"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final newUrl = _serverUrlController.text.trim();

    if (kDebugMode && _developerModeUnlocked && newUrl.isNotEmpty) {
      final uri = Uri.tryParse(newUrl);
      if (uri == null || (!uri.isScheme("http") && !uri.isScheme("https")) || uri.host.isEmpty) {
        _showUrlValidationError("Invalid URL format: Base URL must begin with 'http://' or 'https://'.");
        return;
      }

      setState(() => _isSaving = true);
      try {
        final dio = Dio(BaseOptions(
          baseUrl: newUrl,
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ));
        final resp = await dio.get("/health");
        if (resp.statusCode != 200) {
          throw Exception("Status ${resp.statusCode}");
        }
      } catch (e) {
        setState(() => _isSaving = false);
        _showUrlValidationError("Server Unreachable: The endpoint '$newUrl' is offline or did not pass the health check.");
        return;
      }
    }

    setState(() => _isSaving = true);
    await widget.sessionService.setGeminiApiKey(_geminiApiKeyController.text.trim());

    if (newUrl.isNotEmpty) {
      await widget.sessionService.setBaseUrl(newUrl);
    }

    await widget.sessionService.setSchoolLevel(_selectedSchoolLevel);
    await widget.sessionService.setGradingScale(_selectedGradingScale);

    final saved = await widget.settingsService.saveSettings(_current);
    if (!mounted) return;
    setState(() {
      _current = saved;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✨ Study configurations saved successfully!"),
        backgroundColor: AppColors.accent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testServerConnection() async {
    final targetUrl = _serverUrlController.text.trim();
    if (targetUrl.isEmpty) return;

    setState(() {
      _isTestingConnection = true;
      _diagnosticsPlainLines = null;
      _connectionTestResult = null;
      _connectionSuccess = null;
      _connectionLatencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final token = widget.sessionService.token;
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers["Authorization"] = "Bearer $token";
      }

      final dio = Dio(BaseOptions(
        baseUrl: targetUrl,
        headers: headers,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));

      final response = await dio.get("/api/v1/dev/diagnostics");
      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final version = data["version"]?.toString() ?? "1.0.0-prod";
        final aiService = data["aiService"] as Map?;
        final geminiReachable = aiService?["reachable"] == true;
        final geminiModel = aiService?["model"]?.toString() ?? "gemini-3.1-flash-lite";
        final auth = data["auth"] as Map?;
        final userAccepted = auth?["accepted"] == true;
        final userName = auth?["name"]?.toString() ?? auth?["email"]?.toString();

        if (mounted) {
          setState(() {
            _connectionSuccess = true;
            _connectionLatencyMs = latency;
            _connectionTestResult = "All systems operational.";
            _diagnosticsPlainLines = [
              "Server reachable: yes (${latency}ms)",
              "Backend version: v$version",
              "Gemini reachable: ${geminiReachable ? 'yes ($geminiModel)' : 'no'}",
              "Logged-in user accepted by the server: ${userAccepted ? 'yes ($userName)' : 'no (unauthenticated)'}",
            ];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _connectionSuccess = false;
            _connectionLatencyMs = null;
            _diagnosticsPlainLines = [
              "Server reachable: no (HTTP ${response.statusCode})",
              "Backend version: unreachable",
              "Gemini reachable: no",
              "Logged-in user accepted by the server: no",
            ];
          });
        }
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _connectionSuccess = false;
          _connectionLatencyMs = null;
          final errorMsg = e is DioException ? (e.message ?? "connection refused") : "unreachable";
          _diagnosticsPlainLines = [
            "Server reachable: no ($errorMsg)",
            "Backend version: unreachable",
            "Gemini reachable: no",
            "Logged-in user accepted by the server: no",
          ];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  Future<void> _confirmAndClearChatLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 24),
            const SizedBox(width: 10),
            Text(
              "Clear AI Chat Logs?",
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: ctx.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          "This will permanently delete your AI tutoring conversation history both locally and from the backend server. This action cannot be undone.",
          style: TextStyle(color: ctx.textSecondary, height: 1.4, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Clear Logs"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.sessionService.prefs.remove('ai_tutor_saved_sessions_v1');
      final response = await widget.apiClient.dio.delete("/api/v1/ai/chat-logs");
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✨ Cleared: AI chat logs permanently removed on server and local cache."),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to clear server chat logs: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportLearningData() async {
    try {
      final userEmail = widget.sessionService.email ?? "student";
      final data = {
        "exportFormat": "StudyApp_StudentDataVault_v1",
        "exportTimestampUtc": DateTime.now().toUtc().toIso8601String(),
        "user": {
          "userId": widget.sessionService.userId,
          "email": widget.sessionService.email,
          "fullName": widget.sessionService.fullName,
          "schoolLevel": widget.sessionService.schoolLevel,
          "gradingScale": widget.sessionService.gradingScale,
        },
        "studySettings": _current.toJson(),
      };

      final jsonStr = const JsonEncoder.withIndent("  ").convert(data);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.download_done_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              Text(
                "Export Learning Data",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: ctx.textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Academic profile and study configurations for $userEmail:",
                style: TextStyle(color: ctx.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                height: 140,
                width: double.maxFinite,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    jsonStr,
                    style: const TextStyle(fontFamily: "monospace", fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("Copy JSON"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonStr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("📋 Learning data JSON copied to clipboard!"),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Export failed: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Delete My Account?",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: ctx.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          "Permanently delete your account and all associated courses, flashcards, quizzes, grades, notes, and study progress. This action is irreversible and immediate.",
          style: TextStyle(color: ctx.textSecondary, height: 1.4, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete Permanently"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    final ok = await AppSession.deleteAccount(api: widget.apiClient, session: widget.sessionService);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Your account and all associated data have been permanently deleted."),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 4),
        ),
      );
      widget.onLogout?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not delete account. Check your connection and try again."),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Reset to Academic Defaults?",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          "This will reset all study timers, default question count, and AI curriculum preferences back to recommended evidence-based settings.",
          style: TextStyle(color: ctx.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reset All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final reset = await widget.settingsService.resetSettings();
      if (mounted) {
        setState(() => _current = reset);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Configurations restored to academic defaults."),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(
          "Study Configurations",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: context.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: "Reset to Defaults",
            onPressed: _resetDefaults,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        children: [
          // 1. Study Preferences
          _buildSectionHeader("📚 Study Preferences"),
          _buildCard([
            _buildSliderTile(
              title: "Default Question Count",
              subtitle: "Number of questions retrieved for practice sessions",
              value: _current.defaultQuestionCount.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              displayValue: "${_current.defaultQuestionCount} questions",
              onChanged: (val) {
                setState(() => _current = _current.copyWith(defaultQuestionCount: val.round()));
              },
            ),
            const Divider(height: 1),
            _buildDropdownTile(
              title: "Preferred Practice Mode",
              subtitle: "Primary assessment mode used when starting study sets",
              value: _current.preferredStudyMode,
              items: const [
                DropdownMenuItem(
                  value: StudyModeValue.simulatedExam,
                  child: Text("🎯 Simulated Exam (All Types)"),
                ),
                DropdownMenuItem(
                  value: StudyModeValue.multipleChoice,
                  child: Text("📚 Multiple Choice Practice"),
                ),
                DropdownMenuItem(
                  value: StudyModeValue.flashcards,
                  child: Text("🃏 Spaced Repetition Flashcards"),
                ),
                DropdownMenuItem(
                  value: StudyModeValue.matchingType,
                  child: Text("🧩 Two-Column Matching"),
                ),
                DropdownMenuItem(
                  value: StudyModeValue.rapidFireBlitz,
                  child: Text("⚡ Rapid-Fire Blitz"),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  setState(() => _current = _current.copyWith(preferredStudyMode: mode));
                }
              },
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: "Instant Answer Feedback",
              subtitle: "Show explanation and rationales immediately after answering",
              value: _current.instantFeedback,
              icon: Icons.feedback_outlined,
              onChanged: (val) => setState(() => _current = _current.copyWith(instantFeedback: val)),
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: "Shuffle Option Choices",
              subtitle: "Randomize distractor order to prevent positional memorization",
              value: _current.shuffleOptions,
              icon: Icons.shuffle_rounded,
              onChanged: (val) => setState(() => _current = _current.copyWith(shuffleOptions: val)),
            ),
            const Divider(height: 1),
            _buildSliderTile(
              title: "Daily Study Goal Target",
              subtitle: "Target daily active recall minutes",
              value: _current.dailyStudyGoalMinutes.toDouble(),
              min: 10,
              max: 120,
              divisions: 11,
              displayValue: "${_current.dailyStudyGoalMinutes} min/day",
              onChanged: (val) {
                setState(() => _current = _current.copyWith(dailyStudyGoalMinutes: val.round()));
              },
            ),
            const Divider(height: 1),
            // AI Synthesizer Difficulty
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Default Synthesizer Difficulty",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Complexity of generated questions and distractor rationales",
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDifficultyChip("Introductory", 1),
                      _buildDifficultyChip("Intermediate", 2),
                      _buildDifficultyChip("Advanced", 3),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Theme Mode
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Theme Mode",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "Minimal high-contrast student reading theme",
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.accent),
                        SizedBox(width: 4),
                        Text(
                          "Student Light",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: "Haptic Feedback",
              subtitle: "Vibrate upon answer submissions and drill completion",
              value: _current.hapticFeedbackEnabled,
              icon: Icons.vibration_rounded,
              onChanged: (val) => setState(() => _current = _current.copyWith(hapticFeedbackEnabled: val)),
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: "Low Data Mode",
              subtitle: "Compresses network payloads and prioritizes text for spotty campus Wi-Fi",
              value: _lowDataMode,
              icon: Icons.data_saver_on_rounded,
              onChanged: (val) {
                setState(() => _lowDataMode = val);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(val ? "📶 Low Data Mode activated: network payloads minimized." : "Low Data Mode turned off."),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ]),

          const SizedBox(height: 20),

          // 2. Timers & Reminders
          _buildSectionHeader("⏱️ Timers & Reminders"),
          _buildCard([
            // Daily Study Session Reminder
            ListenableBuilder(
              listenable: NotificationService.instance,
              builder: (context, _) {
                final notif = NotificationService.instance;
                return Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined, color: AppColors.accent),
                      title: Text(
                        "Daily Study Reminder",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        "Keep your study momentum alive with a scheduled daily alert",
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                      value: notif.dailyReminderEnabled,
                      activeThumbColor: AppColors.accent,
                      onChanged: (val) => notif.setDailyReminderEnabled(val),
                    ),
                    if (notif.dailyReminderEnabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Reminder Time",
                              style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.access_time_rounded, size: 16),
                              label: Text(notif.reminderTimeFormatted),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(hour: notif.reminderHour, minute: notif.reminderMinute),
                                );
                                if (picked != null) {
                                  notif.setReminderTime(picked.hour, picked.minute);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const Divider(height: 1),
            // Eye break reminder (default 20 min based on 20-20-20 rule)
            ListenableBuilder(
              listenable: ChildSafetyService.instance,
              builder: (context, _) {
                final cs = ChildSafetyService.instance;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Eye break reminder",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Periodic pause based on the 20-20-20 eye-care rule",
                              style: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: cs.eyeBreakMinutes,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 20, child: Text("Every 20 mins (Recommended)")),
                          DropdownMenuItem(value: 30, child: Text("Every 30 mins")),
                          DropdownMenuItem(value: 45, child: Text("Every 45 mins")),
                          DropdownMenuItem(value: 0, child: Text("Disabled")),
                        ],
                        onChanged: (val) {
                          if (val != null) cs.setEyeBreakMinutes(val);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
            _buildSliderTile(
              title: "Pomodoro Focus Duration",
              subtitle: "Length of undisturbed study focus sprints",
              value: _current.pomodoroFocusMinutes.toDouble(),
              min: 15,
              max: 60,
              divisions: 9,
              displayValue: "${_current.pomodoroFocusMinutes} minutes",
              onChanged: (val) {
                setState(() => _current = _current.copyWith(pomodoroFocusMinutes: val.round()));
              },
            ),
            const Divider(height: 1),
            _buildSliderTile(
              title: "Pomodoro Short Break",
              subtitle: "Rest pause between focus blocks",
              value: _current.pomodoroShortBreakMinutes.toDouble(),
              min: 3,
              max: 15,
              divisions: 4,
              displayValue: "${_current.pomodoroShortBreakMinutes} minutes",
              onChanged: (val) {
                setState(() => _current = _current.copyWith(pomodoroShortBreakMinutes: val.round()));
              },
            ),
            const Divider(height: 1),
            _buildSliderTile(
              title: "Rapid-Fire Blitz Timer",
              subtitle: "Countdown clock per question in Rapid-Fire mode",
              value: _current.blitzSecondsPerQuestion.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              displayValue: "${_current.blitzSecondsPerQuestion} seconds",
              onChanged: (val) {
                setState(() => _current = _current.copyWith(blitzSecondsPerQuestion: val.round()));
              },
            ),
          ]),

          const SizedBox(height: 20),

          // 3. Accessibility & Wellbeing
          _buildSectionHeader("🌱 Accessibility & Wellbeing"),
          _buildCard([
            ListenableBuilder(
              listenable: ChildSafetyService.instance,
              builder: (context, _) {
                final cs = ChildSafetyService.instance;
                return Column(
                  children: [
                    _buildSwitchTile(
                      title: "Junior Learner Mode (Grades 1–6)",
                      subtitle: "Enables simplified vocabulary, cheerful encouragement, and age-calibrated learning guardrails",
                      icon: Icons.child_care_rounded,
                      value: cs.isJuniorMode,
                      onChanged: (val) => cs.setJuniorMode(val),
                    ),
                    if (cs.isJuniorMode) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "Elementary Grade Level",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    cs.gradeLevelText,
                                    style: const TextStyle(
                                      color: Color(0xFFD97706),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: List.generate(6, (i) {
                                final grade = i + 1;
                                final isSelected = cs.gradeLevel == grade;
                                return ChoiceChip(
                                  label: Text("Grade $grade"),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) cs.setGradeLevel(grade);
                                  },
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "Secondary & Higher Ed Stage",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cs.gradeLevel >= 7 && cs.gradeLevel <= 10
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : (cs.gradeLevel >= 11 && cs.gradeLevel <= 12
                                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                                            : const Color(0xFF6366F1).withValues(alpha: 0.15)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    cs.studentStage,
                                    style: TextStyle(
                                      color: cs.gradeLevel >= 7 && cs.gradeLevel <= 10
                                          ? const Color(0xFF059669)
                                          : (cs.gradeLevel >= 11 && cs.gradeLevel <= 12
                                              ? const Color(0xFF7C3AED)
                                              : const Color(0xFF4F46E5)),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text("Junior High (Gr 7–10)"),
                                  selected: cs.gradeLevel >= 7 && cs.gradeLevel <= 10,
                                  selectedColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                                  onSelected: (selected) {
                                    if (selected) cs.setGradeLevel(8);
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text("Senior High (Gr 11–12)"),
                                  selected: cs.gradeLevel >= 11 && cs.gradeLevel <= 12,
                                  selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                  onSelected: (selected) {
                                    if (selected) cs.setGradeLevel(11);
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text("College & University"),
                                  selected: cs.gradeLevel < 7 || cs.gradeLevel > 12,
                                  selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                  onSelected: (selected) {
                                    if (selected) cs.setGradeLevel(1);
                                  },
                                ),
                              ],
                            ),
                            if (cs.gradeLevel >= 7 && cs.gradeLevel <= 10) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [7, 8, 9, 10].map((g) {
                                  final isSelected = cs.gradeLevel == g;
                                  return ChoiceChip(
                                    label: Text("Grade $g", style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                                    onSelected: (sel) {
                                      if (sel) cs.setGradeLevel(g);
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                            if (cs.gradeLevel >= 11 && cs.gradeLevel <= 12) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [11, 12].map((g) {
                                  final isSelected = cs.gradeLevel == g;
                                  return ChoiceChip(
                                    label: Text("Grade $g", style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                    onSelected: (sel) {
                                      if (sel) cs.setGradeLevel(g);
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    // Text size
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Text size",
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  cs.textScale == AccessibilityTextScale.normal
                                      ? "Normal (100%)"
                                      : (cs.textScale == AccessibilityTextScale.large
                                          ? "Large (120%)"
                                          : "XL (135%)"),
                                  style: const TextStyle(
                                    color: Colors.teal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Adjust app typography scale for comfortable reading",
                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<AccessibilityTextScale>(
                            segments: const [
                              ButtonSegment(
                                value: AccessibilityTextScale.normal,
                                label: Text("Normal A"),
                              ),
                              ButtonSegment(
                                value: AccessibilityTextScale.large,
                                label: Text("Large A+"),
                              ),
                              ButtonSegment(
                                value: AccessibilityTextScale.extraLarge,
                                label: Text("XL A++"),
                              ),
                            ],
                            selected: {cs.textScale},
                            onSelectionChanged: (set) {
                              cs.setTextScale(set.first);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _buildSwitchTile(
                      title: "Read Aloud (Text-to-Speech)",
                      subtitle: "Enable audio buttons across questions, flashcards, and explanations",
                      icon: Icons.record_voice_over_rounded,
                      value: cs.readAloudEnabled,
                      onChanged: (val) => cs.setReadAloudEnabled(val),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10B981), size: 20),
              ),
              title: Text(
                "User Manual & Feature Guide",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                "Explore Passive Capture, Grade Tracker, Study Priority Engine, and study workflows",
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => UserManualSheet.show(context),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text("🛡️", style: TextStyle(fontSize: 20)),
              ),
              title: Text(
                "Child Safety Resources",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                "View MAKABATA 1383 Helpline, Bantay Bata 163, DepEd CPU, and safety protections",
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => DswdSafetyModal.show(context),
            ),
          ]),

          const SizedBox(height: 20),

          // 4. Student Account
          _buildSectionHeader("👤 Student Account"),
          _buildCard([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: Text(
                          (widget.sessionService.fullName ?? "S").isNotEmpty
                              ? (widget.sessionService.fullName ?? "S").substring(0, 1).toUpperCase()
                              : "S",
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.sessionService.fullName ?? "Student",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: context.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.sessionService.email ?? "Offline Session",
                              style: TextStyle(color: context.textSecondary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // School Level Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "School Level",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              "Curriculum and grading adaptation",
                              style: TextStyle(color: context.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<String>(
                        value: _selectedSchoolLevel,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: "Elementary", child: Text("Elementary")),
                          DropdownMenuItem(value: "High School", child: Text("High School")),
                          DropdownMenuItem(value: "College", child: Text("College")),
                          DropdownMenuItem(value: "Post-Graduate", child: Text("Post-Graduate")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedSchoolLevel = val);
                            widget.sessionService.setSchoolLevel(val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  // Grading Scale Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Grading Scale",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              "Target GPA and assessment metrics",
                              style: TextStyle(color: context.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<String>(
                        value: _selectedGradingScale,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: "USJ-R (1.00 - 5.00)", child: Text("1.00 - 5.00")),
                          DropdownMenuItem(value: "Percentage (0 - 100%)", child: Text("0 - 100%")),
                          DropdownMenuItem(value: "GPA (4.0 Scale)", child: Text("4.0 GPA")),
                          DropdownMenuItem(value: "Letter Grade (A - F)", child: Text("A - F")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedGradingScale = val);
                            widget.sessionService.setGradingScale(val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text("Sign Out", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          onPressed: widget.onLogout,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded, size: 16),
                          label: const Text("Delete Account", style: TextStyle(fontSize: 12)),
                          onPressed: _deleteAccount,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 5. Privacy & Data Governance
          _buildSectionHeader("🔐 Privacy & Data Governance"),
          _buildCard([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Data Protection & Ownership",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Your study notes, quiz logs, and scanned materials remain under your explicit control. AI is deployed as a learning companion to guide and test you—never to harvest personal academic data.",
                    style: TextStyle(color: context.textSecondary, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text("Export Learning Data (JSON)"),
                        onPressed: _exportLearningData,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                        label: const Text("Clear AI Chat Logs", style: TextStyle(color: AppColors.danger)),
                        onPressed: _confirmAndClearChatLogs,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.privacy_tip_outlined, size: 20),
              title: const Text("Privacy Policy", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => TermsAndPrivacyModal.showPrivacy(context),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.article_outlined, size: 20),
              title: const Text("Terms of Service", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => TermsAndPrivacyModal.showTerms(context),
            ),
          ]),

          // Developer Section (Only if debug build & unlocked)
          if (kDebugMode && _developerModeUnlocked) ...[
            const SizedBox(height: 20),
            _buildSectionHeader("🛠️ Developer & Cloud API Connection"),
            _buildCard([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.dns_rounded, color: Color(0xFF6366F1), size: 18),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Backend API Base URL",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        if (_connectionSuccess != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (_connectionSuccess! ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (_connectionSuccess! ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _connectionSuccess! ? const Color(0xFF10B981) : AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _connectionSuccess!
                                      ? (_connectionLatencyMs != null ? "ONLINE (${_connectionLatencyMs}ms)" : "ONLINE")
                                      : "OFFLINE",
                                  style: TextStyle(
                                    color: _connectionSuccess! ? const Color(0xFF10B981) : AppColors.danger,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Switch active API endpoint between local development and Railway cloud deployment without rebuilding:",
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key("server_url_input"),
                      controller: _serverUrlController,
                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "http://localhost:5000",
                        prefixIcon: const Icon(Icons.link_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          tooltip: "Reset to Default (${ApiConstants.defaultBaseUrl})",
                          onPressed: () {
                            _serverUrlController.text = ApiConstants.defaultBaseUrl;
                          },
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cloud_done_rounded, size: 14, color: Color(0xFF10B981)),
                          label: const Text("Railway (Production)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = ApiConstants.railwayProductionUrl);
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.phone_android_rounded, size: 14),
                          label: const Text("Android (10.0.2.2)", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = ApiConstants.androidEmulatorUrl);
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wifi_rounded, size: 14),
                          label: const Text("Phone Wi-Fi (172.23.249.209)", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = ApiConstants.localWifiUrl);
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.computer_rounded, size: 14),
                          label: const Text("Localhost:5000", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = ApiConstants.localhostUrl);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key("test_connection_btn"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6366F1),
                          side: const BorderSide(color: Color(0xFF6366F1)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isTestingConnection
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                              )
                            : const Icon(Icons.network_check_rounded, size: 16),
                        label: Text(
                          _isTestingConnection ? "Testing Connection & Latency..." : "Test Server Connection & Diagnostics",
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isTestingConnection ? null : _testServerConnection,
                      ),
                    ),
                    if (_diagnosticsPlainLines != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _connectionSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                  color: _connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _connectionSuccess == true ? "Server Diagnostics: ONLINE" : "Server Diagnostics: OFFLINE",
                                  style: TextStyle(
                                    color: _connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (_connectionTestResult != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _connectionTestResult!,
                                style: TextStyle(
                                  color: _connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            for (final line in _diagnosticsPlainLines!)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: "monospace",
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ],

          const SizedBox(height: 28),

          // App Version & Build Footer
          Center(
            child: GestureDetector(
              key: const Key("version_footer"),
              onLongPress: kDebugMode
                  ? () {
                      setState(() {
                        _developerModeUnlocked = !_developerModeUnlocked;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_developerModeUnlocked
                              ? "🛠️ Developer configurations visible."
                              : "🔒 Developer configurations hidden."),
                          backgroundColor: AppColors.accent,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    Text(
                      _hasGeminiOnServer == true
                          ? "StudyApp v1.0.0 (Build 104) • Powered by Gemini AI"
                          : "StudyApp v1.0.0 (Build 104)",
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (kDebugMode && !_developerModeUnlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "(Debug build • Long press to reveal developer options)",
                          style: TextStyle(
                            color: context.textSecondary.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Save Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              _isSaving ? "Saving Configurations..." : "Save Study Preferences",
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSaving ? null : _saveSettings,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: context.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final step = (max - min) / divisions;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: context.isDarkMode ? AppColors.primaryLight : AppColors.primaryDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                color: context.textSecondary,
                tooltip: "Decrease",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: value > min
                    ? () => onChanged((value - step).clamp(min, max))
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: displayValue,
                  activeColor: context.isDarkMode ? AppColors.primaryLight : AppColors.primary,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                color: context.textSecondary,
                tooltip: "Increase",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: value < max
                    ? () => onChanged((value + step).clamp(min, max))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.accent),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          color: context.textPrimary,
          fontSize: 14,
        ),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 12)),
      value: value,
      activeThumbColor: AppColors.accent,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<T>(
            value: items.any((item) => item.value == value)
                ? value
                : (items.isNotEmpty ? items.first.value : null),
            items: items,
            onChanged: onChanged,
            dropdownColor: context.surfaceColor,
            underline: const SizedBox(),
            style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyChip(String label, int level) {
    final isSelected = _current.defaultAiDifficulty == level;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: isSelected
            ? (context.isDarkMode ? AppColors.primaryLight : AppColors.primaryDark)
            : context.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _current = _current.copyWith(defaultAiDifficulty: level)),
    );
  }
}

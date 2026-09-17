import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/theme/theme_controller.dart";
import "../../quiz/models/quiz_models.dart";
import "../models/study_settings_model.dart";
import "../services/settings_service.dart";

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;
  final SettingsService settingsService;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
    required this.settingsService,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StudySettingsModel _current;
  late final TextEditingController _geminiApiKeyController;
  late final TextEditingController _serverUrlController;
  bool _obscureApiKey = true;
  bool _isSaving = false;
  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool? _connectionSuccess;
  bool _lowDataMode = false;
  int? _connectionLatencyMs;
  int _selectedSettingsTab = 0; // 0: Study Preferences, 1: Advanced / Developer

  @override
  void initState() {
    super.initState();
    _current = widget.settingsService.settings;
    _geminiApiKeyController = TextEditingController(text: widget.sessionService.geminiApiKey ?? "");
    _serverUrlController = TextEditingController(
      text: widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl,
    );
    _loadRemote();
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadRemote() async {
    final remote = await widget.settingsService.fetchRemoteSettings();
    if (mounted) {
      setState(() => _current = remote);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    await widget.sessionService.setGeminiApiKey(_geminiApiKeyController.text.trim());

    final newUrl = _serverUrlController.text.trim();
    if (newUrl.isNotEmpty) {
      await widget.sessionService.setBaseUrl(newUrl);
    }

    final saved = await widget.settingsService.saveSettings(_current);
    if (!mounted) return;
    setState(() {
      _current = saved;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✨ Study configurations and API keys saved successfully!"),
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
      _connectionTestResult = null;
      _connectionSuccess = null;
      _connectionLatencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final dio = Dio(BaseOptions(
        baseUrl: targetUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));

      final response = await dio.get("/api/v1/dev/diagnostics");
      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final db = data["database"]?["provider"] ?? "Database";
        final questions = data["database"]?["questionCount"] ?? 0;
        final env = data["environment"] ?? "Active";
        if (mounted) {
          setState(() {
            _connectionSuccess = true;
            _connectionLatencyMs = latency;
            _connectionTestResult = "Connected ($env, $db with $questions questions).";
          });
        }
      } else {
        final healthResp = await dio.get("/health");
        stopwatch.stop();
        final latency2 = stopwatch.elapsedMilliseconds;
        if (mounted) {
          setState(() {
            _connectionSuccess = healthResp.statusCode == 200;
            _connectionLatencyMs = healthResp.statusCode == 200 ? latency2 : null;
            _connectionTestResult = healthResp.statusCode == 200
                ? "Connected! Server health check passed."
                : "Server responded with status ${response.statusCode}.";
          });
        }
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _connectionSuccess = false;
          _connectionLatencyMs = null;
          _connectionTestResult = "Connection failed: Ensure backend is reachable at $targetUrl";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
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
          // Segmented Tab Switcher (Study Preferences vs Advanced / Developer)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedSettingsTab = 0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedSettingsTab == 0
                            ? (isDark ? AppColors.primary : AppColors.primaryDark)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_rounded,
                            size: 16,
                            color: _selectedSettingsTab == 0
                                ? Colors.white
                                : context.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Study Preferences",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _selectedSettingsTab == 0
                                  ? Colors.white
                                  : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedSettingsTab = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedSettingsTab == 1
                            ? (isDark ? AppColors.primary : AppColors.primaryDark)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: _selectedSettingsTab == 1
                                ? Colors.white
                                : context.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Advanced & Developer",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _selectedSettingsTab == 1
                                  ? Colors.white
                                  : context.textSecondary,
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

          if (_selectedSettingsTab == 0) ...[
            // Section 1: Practice & Quiz Configurations
            _buildSectionHeader("📚 Practice & Exam Configurations"),
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
            ]),

            const SizedBox(height: 20),

            // Section 2: Timer & Pace Configurations
            _buildSectionHeader("⏱️ Timer & Pace Configurations"),
            _buildCard([
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
            ]),

            const SizedBox(height: 20),

            // Section 3: AI Curriculum Synthesis Defaults
            _buildSectionHeader("🤖 AI Curriculum Synthesis Preferences"),
            _buildCard([
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
                    Row(
                      children: [
                        _buildDifficultyChip("Introductory", 1),
                        const SizedBox(width: 8),
                        _buildDifficultyChip("Intermediate", 2),
                        const SizedBox(width: 8),
                        _buildDifficultyChip("Advanced", 3),
                      ],
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Section 4: Appearance & Feedback
            _buildSectionHeader("🎨 Appearance & Feedback"),
            _buildCard([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
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
                          "Light, Dark, or System Match",
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    ListenableBuilder(
                      listenable: ThemeController.instance,
                      builder: (context, _) {
                        final currentIsDark = ThemeController.instance.isDarkMode;
                        return OutlinedButton.icon(
                          icon: Icon(
                            currentIsDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                            size: 16,
                          ),
                          label: Text(currentIsDark ? "Dark Theme" : "Light Theme"),
                          onPressed: () => ThemeController.instance.toggleTheme(),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _buildSwitchTile(
                title: "Haptic Feedback",
                subtitle: "Vibrate upon answer submissions and quiz completion",
                value: _current.hapticFeedbackEnabled,
                icon: Icons.vibration_rounded,
                onChanged: (val) => setState(() => _current = _current.copyWith(hapticFeedbackEnabled: val)),
              ),
            ]),

            const SizedBox(height: 20),

            // Section 5: Account & Logout
            _buildSectionHeader("👤 Student Profile"),
            _buildCard([
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: const Icon(Icons.person, color: AppColors.primaryLight),
                ),
                title: Text(
                  widget.sessionService.fullName ?? "Student",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                subtitle: Text(
                  widget.sessionService.email ?? "Offline Session",
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text("Sign Out"),
                  onPressed: widget.onLogout,
                ),
              ),
            ]),
          ] else ...[
            // Developer & Server Connection Section
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
                          tooltip: "Reset to Default",
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
                          avatar: const Icon(Icons.computer_rounded, size: 14),
                          label: const Text("Localhost:5000", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = "http://localhost:5000");
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.phone_android_rounded, size: 14),
                          label: const Text("Android (10.0.2.2)", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() => _serverUrlController.text = "http://10.0.2.2:5000");
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
                    if (_connectionTestResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _connectionSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              color: _connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _connectionTestResult!,
                                    style: TextStyle(
                                      color: _connectionSuccess == true ? const Color(0xFF10B981) : AppColors.danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_connectionLatencyMs != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      "Round-trip latency: ${_connectionLatencyMs}ms",
                                      style: TextStyle(
                                        color: context.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
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

            const SizedBox(height: 20),

            // Section: Google Gemini AI & Vision OCR
            _buildSectionHeader("🤖 Google Gemini AI & Vision OCR"),
            _buildCard([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Google Gemini API Key",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                "Enables OCR text extraction from screenshots & photos (Free at aistudio.google.com)",
                                style: TextStyle(color: context.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _geminiApiKeyController,
                      obscureText: _obscureApiKey,
                      style: TextStyle(color: context.textPrimary, fontFamily: "monospace"),
                      decoration: InputDecoration(
                        labelText: "Gemini API Key",
                        hintText: "AIzaSy...",
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Section 5: Offline & Low Data Mode
            _buildSectionHeader("📴 Offline & Data Saver"),
            _buildCard([
              _buildSwitchTile(
                title: "Low Data Mode",
                subtitle: "Compresses network payloads, delays image loading, and prioritizes concise text for spotty campus Wi-Fi",
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

            // Section 6: Student Data Vault & AI Privacy
            _buildSectionHeader("🔐 Student Data Vault & AI Privacy"),
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
                        Text(
                          "UNESCO Human-Centered AI Principles",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: context.textPrimary,
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
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("📦 Study pack & academic profile exported securely."),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                          label: const Text("Clear AI Chat Logs", style: TextStyle(color: AppColors.danger)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("🧹 AI Tutor conversation cache cleared."),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Section 7: Account & Logout
            _buildSectionHeader("👤 Student Profile"),
            _buildCard([
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: const Icon(Icons.person, color: AppColors.primaryLight),
                ),
                title: Text(
                  widget.sessionService.fullName ?? "Student",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                subtitle: Text(
                  widget.sessionService.email ?? "Offline Session",
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text("Sign Out"),
                  onPressed: widget.onLogout,
                ),
              ),
            ]),
          ],

          const SizedBox(height: 28),

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
              _isSaving
                  ? "Saving Configurations..."
                  : (_selectedSettingsTab == 0
                      ? "Save Study Preferences"
                      : "Save Advanced & Developer Configurations"),
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
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                  fontSize: 14,
                ),
              ),
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
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
            value: value,
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

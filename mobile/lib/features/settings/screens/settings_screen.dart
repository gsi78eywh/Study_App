import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _current = widget.settingsService.settings;
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    final remote = await widget.settingsService.fetchRemoteSettings();
    if (mounted) {
      setState(() => _current = remote);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
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
              _isSaving ? "Saving Configurations..." : "Save Study Configurations",
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
      child: Column(children: children),
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
          const SizedBox(height: 6),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: context.isDarkMode ? AppColors.primaryLight : AppColors.primary,
            onChanged: onChanged,
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

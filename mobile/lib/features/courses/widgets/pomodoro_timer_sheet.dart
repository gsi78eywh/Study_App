import "dart:async";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/theme/app_theme.dart";

class PomodoroTimerSheet extends StatefulWidget {
  final int focusMinutes;
  final int shortBreakMinutes;

  const PomodoroTimerSheet({
    super.key,
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
  });

  static void show(
    BuildContext context, {
    int focusMinutes = 25,
    int shortBreakMinutes = 5,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PomodoroTimerSheet(
        focusMinutes: focusMinutes,
        shortBreakMinutes: shortBreakMinutes,
      ),
    );
  }

  @override
  State<PomodoroTimerSheet> createState() => _PomodoroTimerSheetState();
}

class _PomodoroTimerSheetState extends State<PomodoroTimerSheet> {
  int get focusDuration => widget.focusMinutes * 60;
  int get breakDuration => widget.shortBreakMinutes * 60;

  int _selectedModeIndex = 0; // 0: Focus, 1: Short Break
  late int _remainingSeconds;
  bool _isRunning = false;
  Timer? _timer;
  int _completedSessions = 0;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = focusDuration;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_remainingSeconds > 0) {
          setState(() => _remainingSeconds--);
        } else {
          t.cancel();
          setState(() {
            _isRunning = false;
            if (_selectedModeIndex == 0) {
              _completedSessions++;
              _selectedModeIndex = 1;
              _remainingSeconds = breakDuration;
            } else {
              _selectedModeIndex = 0;
              _remainingSeconds = focusDuration;
            }
          });
        }
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _selectedModeIndex == 0 ? focusDuration : breakDuration;
    });
  }

  void _switchMode(int index) {
    _timer?.cancel();
    setState(() {
      _selectedModeIndex = index;
      _isRunning = false;
      _remainingSeconds = index == 0 ? focusDuration : breakDuration;
    });
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final totalDuration = _selectedModeIndex == 0 ? focusDuration : breakDuration;
    final progress = 1.0 - (_remainingSeconds / totalDuration);

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: context.cardBorderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: context.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppColors.accent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      "Pomodoro Focus Session",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode Selector
            Container(
              decoration: BoxDecoration(
                color: context.secondaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchMode(0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedModeIndex == 0
                              ? (isDark ? AppColors.primaryDark : AppColors.primary)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "🧠 Focus (${widget.focusMinutes}m)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _selectedModeIndex == 0 ? Colors.white : context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchMode(1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedModeIndex == 1
                              ? (isDark ? AppColors.primaryDark : AppColors.primary)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "☕ Break (${widget.shortBreakMinutes}m)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _selectedModeIndex == 1 ? Colors.white : context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Circular Timer
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 190,
                  height: 190,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    backgroundColor: context.cardBorderColor,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _selectedModeIndex == 0 ? const Color(0xFF6366F1) : const Color(0xFF10B981),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(_remainingSeconds),
                      style: GoogleFonts.outfit(
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      _selectedModeIndex == 0 ? "Deep Focus Block" : "Rest & Recharge",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Reset"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textSecondary,
                    side: BorderSide(color: context.cardBorderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _toggleTimer,
                  icon: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 22),
                  label: Text(_isRunning ? "Pause" : "Start Session"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedModeIndex == 0
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Daily session counter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.secondaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "$_completedSessions Pomodoro Sessions Completed Today",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
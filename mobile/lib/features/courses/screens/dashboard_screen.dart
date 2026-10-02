import "dart:async";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../../core/network/api_client.dart";
import "../../../core/services/app_session.dart";
import "../../../core/services/child_safety_service.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../models/course_models.dart";
import "../../auth/screens/login_screen.dart";
import "../../auth/widgets/google_sign_in_dialog.dart";
import "../../flashcards/screens/flashcards_screen.dart";
import "../../ingestion/screens/ingestion_screen.dart";
import "../../notebook/screens/notebook_screen.dart";
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/quiz_player_screen.dart";
import "../../quiz/screens/rapid_fire_screen.dart";
import "../../sync/services/sync_service.dart";
import "../../ai_tutor/screens/ai_tutor_screen.dart";
import "../../settings/services/settings_service.dart";
import "../../settings/screens/settings_screen.dart";
import "../../settings/widgets/dswd_safety_modal.dart";
import "../widgets/onboarding_modal.dart";
import "../../../core/constants/api_constants.dart";
import "../widgets/grade_tracker_sheet.dart";
import "../widgets/user_manual_sheet.dart";
import "../widgets/eye_break_dialog.dart";
import "../../ingestion/widgets/camera_scanner_modal.dart";
import "../../ingestion/widgets/progressive_exam_studio.dart";
import "../../practice/models/adaptive_models.dart";
import "../widgets/today_study_plan_widget.dart";
import "../widgets/student_brain_modal.dart";
import "../widgets/academic_planner_modal.dart";
import "../widgets/notification_sheet.dart";
import "../../../core/services/notification_service.dart";
import "../../quiz/screens/smart_session_player_screen.dart";
import "../../quiz/screens/mistake_bank_screen.dart";

class DashboardScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;

  const DashboardScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final SyncService _syncService;
  late final SettingsService _settingsService;
  int _currentTabIndex = 0;
  List<CourseModel> _courses = [];
  bool _isLoadingCourses = true;
  bool _isLoadingDemoPack = false;
  TodayStudyPlanModel? _todayStudyPlan;
  bool _isLoadingStudyPlan = false;
  String? _studioDraftTitle;
  String? _studioDraftContent;
  int _studioDraftRevision = 0;
  String? _activeCourseId;

  Future<void> _loadStarterDemoPack() async {
    setState(() => _isLoadingDemoPack = true);
    try {
      final response = await widget.apiClient.dio.post(ApiConstants.demoPack);
      if (response.statusCode == 200) {
        await _fetchCoursesAndSync(fullFetch: true, showSnackBar: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "✨ Starter Demo Pack loaded! Explore your new Biology 101 flashcards & quizzes.",
              ),
              backgroundColor: AppColors.accent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not load starter pack: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingDemoPack = false);
    }
  }

  Future<void> _removeStarterDemoPack() async {
    setState(() => _isLoadingCourses = true);
    try {
      final sampleCourses = _courses.where((c) => c.isSample).toList();
      for (final c in sampleCourses) {
        try {
          await widget.apiClient.dio.delete("/api/v1/courses/${c.id}");
        } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("has_loaded_sample_data", false);
      await _fetchCoursesAndSync(fullFetch: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sample data removed.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingCourses = false);
    }
  }

  String _cleanDescription(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return "Active recall practice deck and exam questions generated from lecture notes.";
    }
    var cleaned = raw
        .replaceAll(RegExp(r'\*\*Question\s*\d+:[^*]*\*\*', caseSensitive: false), '')
        .replaceAll(RegExp(r'Question\s*\d+:', caseSensitive: false), '')
        .replaceAll(RegExp(r'Answer:\s*[A-D]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'[*#_`•\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length < 8) {
      return "Active recall practice deck and exam questions generated from lecture notes.";
    }
    if (cleaned.length > 135) {
      cleaned = "${cleaned.substring(0, 132)}...";
    }
    return cleaned;
  }

  void _openCameraScanner([String? targetCourseId]) {
    CameraScannerModal.show(
      context,
      courses: _courses,
      initialCourseId: targetCourseId,
      apiClient: widget.apiClient,
      onExportAndCreateExam: (courseId, title, scannedText) {
        final course = _courses.firstWhere(
          (c) => c.id == courseId,
          orElse: () => _courses.isNotEmpty
              ? _courses.first
              : CourseModel(
                  id: courseId.isNotEmpty ? courseId : "default",
                  code: "GEN-101",
                  name: "General Studies",
                  colorHex: "#6366F1",
                  createdAt: DateTime.now(),
                ),
        );
        ProgressiveExamStudio.show(
          context,
          courseId: course.id,
          courseName: course.name,
          initialTitle: title,
          sourceText: scannedText,
          apiClient: widget.apiClient,
          onExamSaved: (newSet) {
            setState(() {
              final idx = _courses.indexWhere((c) => c.id == course.id);
              if (idx >= 0) {
                if (!_courses[idx].studySets.any((s) => s.id == newSet.id)) {
                  _courses[idx] = _courses[idx].copyWith(
                    studySets: [newSet, ..._courses[idx].studySets],
                  );
                }
              } else if (!course.studySets.any((s) => s.id == newSet.id)) {
                course.studySets.insert(0, newSet);
              }
            });
          },
        );
      },
      onExportToEditor: (title, scannedText) {
        setState(() {
          _studioDraftTitle = title;
          _studioDraftContent = scannedText;
          _studioDraftRevision++;
          _currentTabIndex = 3;
        });
      },
    );
  }

  Widget _buildQuickActionCard(
    String title,
    String desc,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: context.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                desc,
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Timer? _eyeBreakMonitoringTimer;
  Timer? _staleDataRefreshTimer;
  bool _eyeBreakOpen = false;

  final Set<int> _builtTabs = {0};
  Widget _lazy(int i, Widget Function() build) => _builtTabs.contains(i) ? build() : const SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(
      widget.sessionService.prefs,
      widget.apiClient,
    );
    _settingsService.fetchRemoteSettings();
    _syncService = SyncService(
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
    );
    if (SyncService.cachedCourses.isNotEmpty) {
      _courses = List.from(SyncService.cachedCourses);
      _isLoadingCourses = false;
      if (_courses.isNotEmpty && _activeCourseId == null) {
        _activeCourseId = _courses.first.id;
      }
    }
    _fetchCoursesAndSync(fullFetch: true);
    _initEyeBreakMonitoring();
    _initStaleDataAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        OnboardingModal.showIfNeeded(
          context,
          sessionService: widget.sessionService,
          onCompleted: () {
            if (mounted) setState(() {});
          },
        );
      }
    });
  }

  void _initEyeBreakMonitoring() {
    _eyeBreakMonitoringTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (!_eyeBreakOpen && ChildSafetyService.instance.shouldPromptEyeBreak) {
        _eyeBreakOpen = true;
        EyeBreakDialog.show(context).whenComplete(() => _eyeBreakOpen = false);
      }
    });
  }

  void _initStaleDataAutoRefresh() {
    _staleDataRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!mounted || !widget.sessionService.hasValidToken) return;
      if (_syncService.isDataStale(staleMinutes: 5)) {
        await _fetchCoursesAndSync(fullFetch: false);
      }
    });
  }

  @override
  void dispose() {
    _eyeBreakMonitoringTimer?.cancel();
    _staleDataRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTodayStudyPlan() async {
    if (!widget.sessionService.hasValidToken) return;
    setState(() => _isLoadingStudyPlan = true);
    try {
      final plan = await widget.apiClient.getTodayStudyPlan();
      if (mounted) {
        setState(() {
          _todayStudyPlan = plan;
          _isLoadingStudyPlan = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStudyPlan = false);
    }
  }

  void _startSmartStudySession([String? courseId]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmartSessionPlayerScreen(
          apiClient: widget.apiClient,
          initialCourseId: courseId,
          onSessionComplete: () {
            _fetchCoursesAndSync(fullFetch: true);
            _loadTodayStudyPlan();
          },
          onCreateStudySet: () => setState(() => _currentTabIndex = 3),
        ),
      ),
    );
  }

  void _openMistakeBank([String? courseId]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MistakeBankScreen(
          apiClient: widget.apiClient,
          initialCourseId: courseId,
          onMistakesChanged: () => _loadTodayStudyPlan(),
        ),
      ),
    );
  }

  void _openStudentBrainModal() {
    StudentBrainModal.show(
      context,
      apiClient: widget.apiClient,
      onStartSmartSession: () => _startSmartStudySession(_todayStudyPlan?.courseId),
      onOpenMistakeBank: () => _openMistakeBank(_todayStudyPlan?.courseId),
      onOpenAcademicPlanner: () => _openAcademicPlannerModal(),
      onLoadStarterPack: _loadStarterDemoPack,
      onAddCourse: _showAddCourseDialog,
    );
  }

  void _openAcademicPlannerModal() {
    AcademicPlannerModal.show(
      context,
      apiClient: widget.apiClient,
      courses: _courses,
      onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
    );
  }

  Future<void> _showReadinessBreakdown(String courseId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Calculating explainable readiness..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final readiness = await widget.apiClient.getExamReadiness(courseId);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (readiness == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to compute exam readiness. Try answering a quiz first."),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _buildReadinessModal(ctx, readiness),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error fetching exam readiness: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Widget _buildReadinessModal(BuildContext ctx, ExplainableReadinessModel readiness) {
    final readinessPercent = (readiness.readinessScore * 100).toInt();
    final Color scoreColor = readinessPercent >= 80
        ? const Color(0xFF10B981)
        : (readinessPercent >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: ctx.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: ctx.cardBorderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.analytics_rounded, color: scoreColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${readiness.courseName} — Readiness",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: ctx.textPrimary,
                      ),
                    ),
                    if (readiness.daysUntilExam != null)
                      Text(
                        "📅 ${readiness.daysUntilExam} days remaining until exam",
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        "Explainable Mastery Engine",
                        style: TextStyle(color: ctx.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ctx.secondaryBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ctx.cardBorderColor),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: readiness.readinessScore,
                                strokeWidth: 7,
                                backgroundColor: ctx.cardBorderColor,
                                color: scoreColor,
                              ),
                              Text(
                                "$readinessPercent%",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: ctx.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                readiness.readinessStatus,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: scoreColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                readiness.recommendationSummary,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ctx.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Score Composition Factors",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: ctx.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: ctx.secondaryBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildFactorRow(
                          ctx,
                          Icons.quiz_outlined,
                          "Retrieval Practice Accuracy",
                          "${(readiness.recentAccuracy * 100).toInt()}%",
                          readiness.recentAccuracy >= 0.75
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                        Divider(color: ctx.cardBorderColor, height: 16),
                        _buildFactorRow(
                          ctx,
                          Icons.style_outlined,
                          "Spaced Flashcard Retention",
                          "${(readiness.flashcardRetention * 100).toInt()}%",
                          readiness.flashcardRetention >= 0.8
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                        Divider(color: ctx.cardBorderColor, height: 16),
                        _buildFactorRow(
                          ctx,
                          Icons.schedule_rounded,
                          "Spacing & Consistency History",
                          "${(readiness.spacingConsistencyScore * 100).toInt()}%",
                          const Color(0xFF6366F1),
                        ),
                        Divider(color: ctx.cardBorderColor, height: 16),
                        _buildFactorRow(
                          ctx,
                          Icons.warning_amber_rounded,
                          "Unresolved Misconceptions",
                          "${readiness.unresolvedMistakesCount} items",
                          readiness.unresolvedMistakesCount == 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (readiness.topicMastery.isNotEmpty) ...[
                    Text(
                      "Topic-Level Mastery Engine",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: ctx.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...readiness.topicMastery.map((tm) {
                      final p = (tm.masteryPercentage * 100).toInt();
                      final color = p >= 80
                          ? const Color(0xFF10B981)
                          : (p >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    tm.topicName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: ctx.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  "$p%",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: tm.masteryPercentage,
                                minHeight: 6,
                                backgroundColor: ctx.cardBorderColor,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.bolt_rounded),
            label: const Text(
              "Start Targeted Smart Session",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _startSmartStudySession(readiness.courseId);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFactorRow(
    BuildContext ctx,
    IconData icon,
    String title,
    String value,
    Color valueColor,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ctx.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 12, color: ctx.textPrimary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Future<void> _showEditExamDialog(CourseModel course) async {
    DateTime? selectedDate = course.examDate;
    final titleController = TextEditingController(text: course.examTitle ?? "Final Exam");

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            backgroundColor: ctx.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.event_note_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Exam Countdown Target",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                      fontSize: 17,
                    ),
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
                    "Set your exam date for ${course.name}. Your daily study plan will adapt automatically as the exam approaches.",
                    style: TextStyle(color: ctx.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Exam Title",
                      hintText: "e.g. Finals, Midterm 1",
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, color: Color(0xFF6366F1)),
                    title: Text(
                      selectedDate == null
                          ? "Select Exam Date"
                          : "Exam: ${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: ctx.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: selectedDate != null
                        ? Text(
                            "${selectedDate!.difference(DateTime.now()).inDays + 1} days remaining",
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                          )
                        : null,
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? now.add(const Duration(days: 7)),
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: const Text("Pick Date"),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (course.examDate != null)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await widget.apiClient.updateCourseExam(course.id, null, null);
                    await _fetchCoursesAndSync(fullFetch: true);
                    await _loadTodayStudyPlan();
                  },
                  child: const Text("Clear Exam", style: TextStyle(color: AppColors.danger)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please select an exam date.")),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final success = await widget.apiClient.updateCourseExam(
                    course.id,
                    selectedDate,
                    titleController.text.trim().isNotEmpty ? titleController.text.trim() : "Exam",
                  );
                  if (success) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Exam countdown set for ${course.name}! Study plan adapted."),
                        backgroundColor: AppColors.accent,
                      ),
                    );
                    await _fetchCoursesAndSync(fullFetch: true);
                    await _loadTodayStudyPlan();
                  }
                },
                child: const Text("Save Target"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fetchCoursesAndSync({
    bool fullFetch = false,
    bool showSnackBar = false,
  }) async {
    if (!widget.sessionService.hasValidToken) {
      if (mounted) setState(() => _isLoadingCourses = false);
      return;
    }

    final result = await _syncService.performSync(
      fullFetch: fullFetch,
      currentCourses: _courses,
    );
    if (!mounted) return;

    setState(() {
      _isLoadingCourses = false;
      if (result.success && (result.syncedCourses.isNotEmpty || fullFetch)) {
        _courses = result.syncedCourses;
      }
      // Do not inject demo courses; keep clean for new user
      if (_courses.isEmpty) {
        _courses = [];
      }
      if (_courses.isNotEmpty && (_activeCourseId == null || !_courses.any((c) => c.id == _activeCourseId))) {
        _activeCourseId = _courses.first.id;
      }
    });
    _loadTodayStudyPlan();

    if (result.isUnauthorized ||
        result.message.contains("401") ||
        result.message.toLowerCase().contains("unauthorized") ||
        result.message.toLowerCase().contains("session expired")) {
      await widget.sessionService.clearAuth();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        );
      }
      return;
    }

    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppColors.accent : AppColors.danger,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAddCourseDialog() {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    String selectedColor = "#6366F1";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            "Create New Course",
            style: GoogleFonts.outfit(
              color: ctx.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  style: TextStyle(color: ctx.textPrimary),
                  decoration: const InputDecoration(
                    labelText: "Course Code",
                    hintText: "e.g. CS204",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: ctx.textPrimary),
                  decoration: const InputDecoration(
                    labelText: "Course Name",
                    hintText: "e.g. Algorithms & Data Structures",
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text("Accent: ", style: TextStyle(color: ctx.textSecondary)),
                    ...[
                      "#6366F1",
                      "#10B981",
                      "#F59E0B",
                      "#EF4444",
                      "#8B5CF6",
                      "#06B6D4",
                    ].map((hex) {
                      final color = Color(
                        int.parse("FF${hex.replaceAll('#', '')}", radix: 16),
                      );
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedColor = hex),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == hex
                                  ? (ctx.isDarkMode
                                        ? Colors.white
                                        : Colors.black87)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final name = nameController.text.trim();
                if (code.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Course code and name are required."),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                  return;
                }

                try {
                  final response = await widget.apiClient.dio.post(
                    "/api/v1/courses",
                    data: {
                      "code": code,
                      "name": name,
                      "colorHex": selectedColor,
                    },
                  );
                  if (!mounted) return;
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);

                  if (response.data is Map<String, dynamic>) {
                    final newCourse = CourseModel.fromJson(response.data);
                    setState(() {
                      _courses = [..._courses, newCourse];
                    });
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Course '$code' created successfully!"),
                      backgroundColor: AppColors.accent,
                    ),
                  );

                  await _fetchCoursesAndSync(fullFetch: true);
                } catch (e) {
                  if (!mounted) return;
                  String msg = "Unable to create the course. Please try again.";
                  bool isUnauthorized = false;

                  if (e is DioException) {
                    if (e.response?.statusCode == 401) {
                      isUnauthorized = true;
                      msg = "Session expired. Please sign in again.";
                    } else if (e.response?.data is Map &&
                        (e.response?.data as Map)["message"] != null) {
                      msg = (e.response!.data as Map)["message"].toString();
                    } else if (e.error != null && e.error.toString().isNotEmpty) {
                      msg = e.error.toString();
                    }
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: AppColors.danger,
                    ),
                  );

                  if (isUnauthorized) {
                    await widget.sessionService.clearAuth();
                    if (mounted) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(
                            apiClient: widget.apiClient,
                            sessionService: widget.sessionService,
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModePicker(StudySetModel set) async {
    final isDark = context.isDarkMode;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            maxWidth: 640,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: ctx.cardBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            Text(
              "Choose Practice Mode",
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: ctx.textPrimary,
              ),
            ),
            Text(
              set.title,
              style: TextStyle(color: ctx.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            // Group 1: Study Modes
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  "STUDY MODES",
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "🃏 Flashcards (Spaced Repetition)",
              "Flip, reveal key facts, and rate your recall with SM-2 spacing",
              AppColors.accent,
              () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FlashcardsScreen(
                      courses: _courses,
                      initialStudySetId: set.id,
                      apiClient: widget.apiClient,
                      onCardDeleted: () => _fetchCoursesAndSync(fullFetch: true),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "🧩 Two-Column Matching",
              "Connect academic terms to their precise definitions",
              const Color(0xFFF59E0B),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.matchingType);
              },
            ),
            const SizedBox(height: 16),

            // Group 2: Test Modes
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_rounded, size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 6),
                Text(
                  "TEST MODES",
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6366F1),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "📚 Multiple Choice Quiz",
              "Server-graded standard multiple-choice questions with full explanations",
              isDark ? AppColors.primary : AppColors.primaryDark,
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.multipleChoice);
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "🎯 Simulated Exam",
              "Comprehensive exam covering MCQ, True/False, and Identification",
              const Color(0xFF6366F1),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.simulatedExam);
              },
            ),
            const SizedBox(height: 16),

            // Group 3: Quick Mode
            Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  "QUICK MODE",
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "⚡ Rapid-Fire Blitz (${_settingsService.settings.blitzSecondsPerQuestion}s)",
              "${_settingsService.settings.blitzSecondsPerQuestion} seconds per question — race the countdown clock!",
              AppColors.warning,
              () {
                Navigator.pop(ctx);
                _startRapidFire(set);
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "📥 Export Study Guide",
              "View or copy formatted study guide with summary and OCR text",
              const Color(0xFF10B981),
              () {
                Navigator.pop(ctx);
                _exportStudyGuide(set);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _modeTile(
    BuildContext ctx,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: ctx.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _startRapidFire(StudySetModel set) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Loading Rapid-Fire session..."),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final resp = await widget.apiClient.dio.get(
        "/api/v1/practice/studysets/${set.id}/questions",
        queryParameters: {
          "mode": StudyModeValue.rapidFireBlitz,
          "count": _settingsService.settings.defaultQuestionCount,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (resp.statusCode == 200) {
        final raw = resp.data as List<dynamic>;
        final questions = raw
            .map((q) => QuestionModel.fromJson(q as Map<String, dynamic>))
            .toList();
        if (questions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "No questions available for Rapid-Fire. Generate a study set first.",
              ),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RapidFireScreen(
              studySet: set,
              questions: questions,
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
              secondsPerQuestion:
                  _settingsService.settings.blitzSecondsPerQuestion,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not start Rapid-Fire: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportStudyGuide(StudySetModel set) async {
    BuildContext? loadingDialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingDialogCtx = ctx;
        return Center(
          child: Card(
            color: context.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text(
                    "Generating exported study guide...",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/studysets/${set.id}/export",
        queryParameters: {"format": "markdown"},
      );

      if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
        loadingDialogCtx = null;
      }

      String markdownContent = "";
      String exportTitle = set.title;
      if (response.data is Map) {
        final map = response.data as Map;
        markdownContent = map["content"]?.toString() ?? "";
        exportTitle = map["title"]?.toString() ?? set.title;
      } else if (response.data is String) {
        markdownContent = response.data as String;
      } else {
        markdownContent = response.data?.toString() ?? "";
      }

      if (markdownContent.trim().isEmpty) {
        markdownContent = "# ${set.title}\n\n*No study questions or flashcards found in this set to export.*";
      }

      if (!mounted) return;

      final plainText = markdownContent
          .replaceAll(RegExp(r"^#+\s*", multiLine: true), "")
          .replaceAll(RegExp(r"\*\*([^*]+)\*\*"), r"$1")
          .replaceAll(RegExp(r"\*([^*]+)\*"), r"$1")
          .replaceAll(RegExp(r"`([^`]+)`"), r"$1");

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.description_rounded, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  exportTitle,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: ctx.textPrimary,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                markdownContent,
                style: TextStyle(
                  color: ctx.textPrimary,
                  fontFamily: "monospace",
                  fontSize: 12,
                ),
              ),
            ),
          ),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.text_snippet_outlined, size: 16),
                  label: const Text("Copy Text"),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: plainText));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text("Plain text copied to clipboard!"),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text("Copy Markdown"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: markdownContent));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text("Markdown study guide copied to clipboard!"),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Done"),
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to export study guide: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _startQuiz(StudySetModel set, {int? mode, int? count}) async {
    final effectiveMode = mode ?? _settingsService.settings.preferredStudyMode;
    final effectiveCount = count ?? _settingsService.settings.defaultQuestionCount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Loading practice questions..."),
              ],
            ),
          ),
        ),
      ),
    );

    List<QuestionModel> questions = [];
    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/practice/studysets/${set.id}/questions",
        queryParameters: {"mode": effectiveMode, "count": effectiveCount},
      );
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        questions = list
            .map((item) => QuestionModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();

    if (questions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No practice questions are available for this study set yet.",
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizPlayerScreen(
            studySet: set,
            questions: questions,
            apiClient: widget.apiClient,
            sessionService: widget.sessionService,
            initialMode: effectiveMode,
            instantFeedback: _settingsService.settings.instantFeedback,
            shuffleOptions: _settingsService.settings.shuffleOptions,
          ),
        ),
      );
    }
  }

  void _confirmDeleteStudySet(CourseModel course, StudySetModel set) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Delete Study Set?",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          "Are you sure you want to delete '${set.title}'? This will remove all practice questions.",
          style: TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.apiClient.dio.delete(
                  "/api/v1/studysets/${set.id}",
                );
                setState(() {
                  final newSets = List<StudySetModel>.from(course.studySets)
                    ..removeWhere((s) => s.id == set.id);
                  final idx = _courses.indexWhere((c) => c.id == course.id);
                  if (idx >= 0) {
                    _courses[idx] = course.copyWith(
                      studySets: newSets,
                      updatedAt: DateTime.now(),
                    );
                  }
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Deleted '${set.title}'"),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Delete failed: $e"),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text(
              "Delete",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCramSheet(StudySetModel set) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Preparing High-Yield Cram Sheet..."),
              ],
            ),
          ),
        ),
      ),
    );

    List<QuestionModel> questions = [];
    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/practice/studysets/${set.id}/questions",
        queryParameters: {"count": 50},
      );
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        questions = list
            .map((item) => QuestionModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();

    if (questions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No questions available for this study set cram sheet."),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ctx.cardBorderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "📖 Exam Cram Sheet",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: ctx.textPrimary,
                          ),
                        ),
                        Text(
                          "${set.title} • ${questions.length} High-Yield Concepts",
                          style: TextStyle(
                            fontSize: 12,
                            color: ctx.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text("Drill Now"),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _startQuiz(set);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: questions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final q = questions[idx];
                    final correctOpt = q.options.cast<QuestionOptionModel?>().firstWhere(
                      (o) => o?.isCorrect == true,
                      orElse: () => null,
                    );
                    final answerText = (correctOpt != null && correctOpt.text.isNotEmpty)
                        ? correctOpt.text
                        : (q.explanation?.isNotEmpty == true
                            ? q.explanation!
                            : "Mastered concept");

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ctx.secondaryBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ctx.cardBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "#${idx + 1}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  q.prompt,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: ctx.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 14,
                                  color: Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    answerText,
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (q.explanation != null &&
                              q.explanation!.isNotEmpty &&
                              q.explanation != answerText) ...[
                            const SizedBox(height: 6),
                            Text(
                              q.explanation!,
                              style: TextStyle(
                                color: ctx.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleLogout() async {
    await AppSession.signOut(api: widget.apiClient, session: widget.sessionService);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
        ),
      ),
    );
  }

  Future<void> _openGoogleSignInModal() async {
    final success = await GoogleSignInDialog.show(
      context,
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
      onSignedIn: () async {
        await _fetchCoursesAndSync(fullFetch: true, showSnackBar: true);
        await _loadTodayStudyPlan();
        if (mounted) setState(() {});
      },
    );
    if (success && mounted) {
      await _fetchCoursesAndSync(fullFetch: true);
      await _loadTodayStudyPlan();
      setState(() {});
    }
  }

  void _showAccountMenu(BuildContext context) {
    final isDark = context.isDarkMode;
    final email = widget.sessionService.email ?? "Unknown student";
    final fullName = widget.sessionService.fullName ?? "Student";
    final isDemo = email.contains("studyapp.local") || email == "dev@studyapp.local" || fullName == "Developer Test Account";

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: ctx.cardBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isDemo ? const Color(0xFFF59E0B) : const Color(0xFF4285F4),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : "S",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fullName,
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: ctx.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isDemo)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                ),
                                child: const Text(
                                  "Demo Mode",
                                  style: TextStyle(
                                    color: Color(0xFFD97706),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: ctx.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (isDemo) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.g_mobiledata_rounded, color: Color(0xFF4285F4), size: 24),
                  ),
                  title: const Text("Sign In with Gmail", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text("Replace demo mode with your personal account", style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openGoogleSignInModal();
                  },
                ),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync_rounded, color: Color(0xFF10B981), size: 22),
                ),
                title: const Text("Sync Workspace Now", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Pull latest courses and study sets from server", style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _fetchCoursesAndSync(fullFetch: true, showSnackBar: true);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
                ),
                title: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.danger)),
                subtitle: const Text("Return to the login screen", style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleLogout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildChildSafetyBanner(BuildContext context) {
    return ListenableBuilder(
      listenable: ChildSafetyService.instance,
      builder: (context, _) {
        final cs = ChildSafetyService.instance;
        final isDark = context.isDarkMode;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: cs.isJuniorMode
                  ? [
                      const Color(0xFFFEF3C7).withValues(alpha: isDark ? 0.2 : 0.8),
                      const Color(0xFFE0E7FF).withValues(alpha: isDark ? 0.2 : 0.8),
                    ]
                  : [
                      const Color(0xFFF0FDF4).withValues(alpha: isDark ? 0.15 : 0.7),
                      const Color(0xFFE0F2FE).withValues(alpha: isDark ? 0.15 : 0.7),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.isJuniorMode
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                  : const Color(0xFF10B981).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  // Mode indicator chip with descriptive tooltip
                  Tooltip(
                    message: "Study Mode Selector: Standard Academic Mode, Junior Learner Mode (Grades 1-6), or Exam Cram Sprint. Tap to switch.",
                    child: InkWell(
                      onTap: () => _showJuniorModeDialog(),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cs.isJuniorMode ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cs.isJuniorMode ? '🐣 Junior Mode (${cs.gradeLevelText})' : '🎓 Standard Mode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 20-20-20 Eye Break quick button with clear touchable affordance
                  Tooltip(
                    message: "20-20-20 Screen Wellness: Every 20 minutes, look at an object 20 feet away for 20 seconds to prevent digital eye strain.",
                    child: InkWell(
                      onTap: () => EyeBreakDialog.show(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🌿', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 4),
                            Text(
                              'Eye Rest (20-20-20)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (cs.isJuniorMode) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('🌟', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Junior Learner Guardrails Active: Elementary vocabulary, gentle hints, and audio speech enabled!',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showJuniorModeDialog() {
    final cs = ChildSafetyService.instance;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: context.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF6366F1), size: 22),
                const SizedBox(width: 10),
                Text(
                  'Select Study Mode',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Antigravity adapts question difficulty, vocabulary, and pacing to match your learning stage:',
                      style: TextStyle(fontSize: 12.5, color: context.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Option 1: Standard Mode
                    InkWell(
                      onTap: () {
                        cs.setJuniorMode(false);
                        setDialogState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !cs.isJuniorMode
                              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                              : context.secondaryBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !cs.isJuniorMode
                                ? const Color(0xFF6366F1)
                                : context.cardBorderColor,
                            width: !cs.isJuniorMode ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('🎓', style: TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Standard Mode',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: context.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (!cs.isJuniorMode)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Comprehensive college/senior high pacing, complete explanations & full question taxonomy.',
                                    style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Option 2: Junior Learner Mode
                    InkWell(
                      onTap: () {
                        cs.setJuniorMode(true);
                        setDialogState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.isJuniorMode
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                              : context.secondaryBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.isJuniorMode
                                ? const Color(0xFFF59E0B)
                                : context.cardBorderColor,
                            width: cs.isJuniorMode ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🐣', style: TextStyle(fontSize: 24)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Junior Learner Mode',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (cs.isJuniorMode)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Grades 1–6: Simplified vocabulary, cheerful hints, audio read-aloud & child safety protections.',
                                        style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (cs.isJuniorMode) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Text('Select Grade Level:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: context.textPrimary)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: List.generate(6, (i) {
                                  final grade = i + 1;
                                  final isSelected = cs.gradeLevel == grade;
                                  return ChoiceChip(
                                    label: Text('Grade $grade', style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                    onSelected: (selected) {
                                      if (selected) {
                                        cs.setGradeLevel(grade);
                                        setDialogState(() {});
                                        setState(() {});
                                      }
                                    },
                                  );
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Option 3: Exam Cram Sprint
                    InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (_todayStudyPlan?.courseId != null) {
                          _startSmartStudySession(_todayStudyPlan!.courseId);
                        } else if (_courses.isNotEmpty) {
                          _startSmartStudySession(_courses.first.id);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Add a course or load the Starter Demo Pack to begin Exam Cram.")),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Text('⚡', style: TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Exam Cram Sprint',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'High-yield retrieval drills prioritizing your mistake bank and weak topics for rapid review.',
                                    style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCoursesTab() {
    final isDark = context.isDarkMode;
    final totalSets = _courses.fold<int>(
      0,
      (sum, c) => sum + c.studySets.length,
    );
    final totalQuestions = _courses.fold<int>(
      0,
      (sum, c) =>
          sum + c.studySets.fold<int>(0, (s, set) => s + set.questionCount),
    );
    final studentName = widget.sessionService.fullName?.trim();
    final userEmail = widget.sessionService.email?.toLowerCase().trim() ?? '';
    final isDemoUser = userEmail == 'dev@studyapp.local' ||
        userEmail.contains('studyapp.local') ||
        studentName == 'Developer Test Account';

    final displayName = isDemoUser
        ? 'Demo Student'
        : ((studentName != null &&
                studentName.isNotEmpty &&
                studentName.toLowerCase() != 'google student')
            ? (studentName.toLowerCase().startsWith('google student ')
                ? studentName.substring(15).trim()
                : studentName)
            : (userEmail.isNotEmpty ? userEmail.split('@').first : 'Student'));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Student Welcome Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              "Welcome back, $displayName 👋",
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            if (isDemoUser)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: const Text(
                                  "Demo Mode",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ),
                            if ((_todayStudyPlan?.readiness.spacingDaysActive ?? 0) > 0 &&
                                _courses.any((c) => !c.isSample))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF97316).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text("🔥", style: TextStyle(fontSize: 12)),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${_todayStudyPlan?.readiness.spacingDaysActive ?? 1}-Day Streak",
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFF97316),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _courses.isEmpty
                              ? "Ready to organize your study workspace"
                              : (_courses.length == 1
                                  ? "Targeting mastery across 1 course"
                                  : "Targeting mastery across ${_courses.length} courses"),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListenableBuilder(
                        listenable: NotificationService.instance,
                        builder: (context, _) {
                          final unread = NotificationService.instance.unreadCount;
                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Badge(
                              isLabelVisible: unread > 0,
                              label: Text("$unread", style: const TextStyle(fontSize: 10)),
                              child: const Icon(
                                Icons.notifications_outlined,
                                color: Color(0xFF6366F1),
                                size: 22,
                              ),
                            ),
                            tooltip: "Notifications & Reminders",
                            onPressed: () => NotificationSheet.show(context),
                          );
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: const Icon(
                          Icons.sync_rounded,
                          color: AppColors.primaryDark,
                          size: 22,
                        ),
                        tooltip: "Sync with Cloud",
                        onPressed: () => _fetchCoursesAndSync(fullFetch: true, showSnackBar: true),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Color(0xFF6366F1),
                          size: 22,
                        ),
                        tooltip: "Study Configurations",
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                apiClient: widget.apiClient,
                                sessionService: widget.sessionService,
                                settingsService: _settingsService,
                                onLogout: _handleLogout,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: CircleAvatar(
                          radius: 13,
                          backgroundColor: isDemoUser ? const Color(0xFFF59E0B) : const Color(0xFF4285F4),
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : "S",
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        tooltip: "Account (${widget.sessionService.email ?? 'Student'})",
                        onPressed: () => _showAccountMenu(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Demo Account Notification & Quick Switch to Gmail Banner
              if (isDemoUser) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7).withValues(alpha: isDark ? 0.25 : 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Demo Student Account Active (${widget.sessionService.email})",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.amber.shade200 : const Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Sign in with your Gmail to connect your real courses, flashcards & cloud notes.",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.amber.shade100 : const Color(0xFF78350F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 20),
                        label: const Text("Sign In with Gmail", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _openGoogleSignInModal,
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        icon: const Icon(Icons.logout_rounded, size: 15),
                        label: const Text("Sign Out", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _handleLogout,
                      ),
                    ],
                  ),
                ),
              ],

              // Sample Data Banner (When sample pack is loaded)
              if (_courses.any((c) => c.isSample)) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.science_outlined, color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Sample Data active (excluded from streaks & sync)",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _removeStarterDemoPack,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text("Remove sample data", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],

              // Child Safety & Learner Mode Bar
              _buildChildSafetyBanner(context),
              const SizedBox(height: 16),

              if (_courses.isNotEmpty) ...[
                // Today's Study Plan (AI Adaptive Learning System)
                TodayStudyPlanWidget(
                  plan: _todayStudyPlan,
                  isLoading: _isLoadingStudyPlan,
                  onStartSmartSession: () => _startSmartStudySession(_todayStudyPlan?.courseId),
                  onOpenMistakeBank: () => _openMistakeBank(_todayStudyPlan?.courseId),
                  onOpenStudentBrain: () => _openStudentBrainModal(),
                  onOpenAcademicPlanner: () => _openAcademicPlannerModal(),
                  onShowReadinessBreakdown: (courseId) => _showReadinessBreakdown(courseId),
                  onStepTapped: (step) {
                    if (step.stepNumber == 1) {
                      setState(() => _currentTabIndex = 1);
                    } else if (step.stepNumber == 4) {
                      setState(() => _currentTabIndex = 4);
                    } else {
                      _startSmartStudySession(_todayStudyPlan?.courseId);
                    }
                  },
                ),
                const SizedBox(height: 18),

                // High-yield stats row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              AppColors.primary.withValues(alpha: 0.2),
                              context.surfaceColor,
                            ]
                          : [
                              AppColors.primaryLight.withValues(alpha: 0.12),
                              context.surfaceColor,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          "Enrolled",
                          "${_courses.length}",
                          "Courses",
                          Icons.book_rounded,
                          isDark ? AppColors.primaryLight : AppColors.primaryDark,
                        ),
                        Container(
                          height: 36,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: context.cardBorderColor,
                        ),
                        _buildStatItem(
                          "Active Sets",
                          "$totalSets",
                          "Study Sets",
                          Icons.auto_stories_rounded,
                          AppColors.accent,
                        ),
                        Container(
                          height: 36,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: context.cardBorderColor,
                        ),
                        _buildStatItem(
                          "Synthesized",
                          "$totalQuestions",
                          "Questions",
                          Icons.psychology_rounded,
                          AppColors.warning,
                        ),
                        Container(
                          height: 36,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: context.cardBorderColor,
                        ),
                        _buildStatItem(
                          "Streak",
                          "${_todayStudyPlan?.readiness.spacingDaysActive ?? 1}d",
                          "Momentum",
                          Icons.local_fire_department_rounded,
                          const Color(0xFFF97316),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Study Hub (1-Tap Workflows)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt_rounded,
                                color: Color(0xFFF59E0B),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Quick Study Hub",
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "Direct 1-Tap Action",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildQuickActionCard(
                            "Scan & Ingest Notes",
                            "Camera OCR, PDF & docs",
                            Icons.document_scanner_rounded,
                            const Color(0xFF6366F1),
                            () => setState(() => _currentTabIndex = 3),
                          ),
                          const SizedBox(width: 8),
                          _buildQuickActionCard(
                            "Mistake Bank",
                            "${_todayStudyPlan?.unresolvedMistakesCount ?? 0} errors",
                            Icons.psychology_alt_outlined,
                            const Color(0xFFEF4444),
                            () => _openMistakeBank(),
                          ),
                          const SizedBox(width: 8),
                          _buildQuickActionCard(
                            "Flashcards Deck",
                            "Spaced retrieval",
                            Icons.style_outlined,
                            const Color(0xFF10B981),
                            () => setState(() => _currentTabIndex = 1),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Enrolled Courses Header & Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    "Your Enrolled Courses",
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(
                            color: Color(0xFF10B981),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.bar_chart_rounded, size: 16),
                        label: const Text(
                          "Grade Tracker",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () => GradeTrackerSheet.show(
                          context,
                          widget.apiClient,
                          onGradesUpdated: () { _fetchCoursesAndSync(fullFetch: true); _loadTodayStudyPlan(); },
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColors.primary
                              : AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text(
                          "New Course",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: _showAddCourseDialog,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (_isLoadingCourses)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark,
                    ),
                  ),
                )
              else if (_courses.isEmpty)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.cardBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.school_outlined,
                              size: 48,
                              color: isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            "Welcome to Your Connected Study Loop",
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              color: context.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "One seamless loop: add lecture notes, generate spaced flashcards, and master weak spots through AI retrieval drills.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Connected 3-Step Flow Preview
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.secondaryBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.cardBorderColor),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildLoopStep("1. Course", Icons.school_outlined, "Add Course"),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF6366F1)),
                                  const SizedBox(width: 8),
                                  _buildLoopStep("2. Notes", Icons.notes_rounded, "Lecture 1"),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF6366F1)),
                                  const SizedBox(width: 8),
                                  _buildLoopStep("3. Mastery", Icons.bolt_rounded, "Flashcards"),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Single Primary CTA: Create Your First Course
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 4,
                                ),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text(
                                  "Create Your First Course",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                onPressed: _showAddCourseDialog,
                              ),
                              const SizedBox(height: 10),
                              // Receded Secondary Action: Explore with demo pack
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: context.textSecondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                icon: _isLoadingDemoPack
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF6366F1),
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome_outlined, size: 16),
                                label: Text(
                                  _isLoadingDemoPack
                                      ? "Loading Sample Curriculum..."
                                      : "Or explore with Starter Demo Pack",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                onPressed: _isLoadingDemoPack ? null : _loadStarterDemoPack,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ..._courses.map((course) {
                  final courseColor = Color(
                    int.parse(
                      "FF${course.colorHex.replaceAll('#', '')}",
                      radix: 16,
                    ),
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.cardBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: courseColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: courseColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                course.code,
                                style: TextStyle(
                                  color: courseColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                course.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.secondaryBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${course.studySets.length} sets",
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            // Exam Countdown Chip
                            InkWell(
                              onTap: () => _showEditExamDialog(course),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: course.hasUpcomingExam
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                      : context.secondaryBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: course.hasUpcomingExam
                                        ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                        : context.cardBorderColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_rounded,
                                      size: 13,
                                      color: course.hasUpcomingExam
                                          ? const Color(0xFFEF4444)
                                          : context.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      course.hasUpcomingExam
                                          ? "${course.daysUntilExam}d: ${course.examTitle ?? 'Exam'}"
                                          : "+ Exam Date",
                                      style: TextStyle(
                                        color: course.hasUpcomingExam
                                            ? const Color(0xFFEF4444)
                                            : context.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (course.studySets.isNotEmpty) ...[
                              InkWell(
                                onTap: () => _showReadinessBreakdown(course.id),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.analytics_outlined,
                                        size: 13,
                                        color: Color(0xFF10B981),
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        "Readiness",
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            InkWell(
                              onTap: () => _openCameraScanner(course.id),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.document_scanner_rounded,
                                      size: 13,
                                      color: Color(0xFF06B6D4),
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      "Scan",
                                      style: TextStyle(
                                        color: Color(0xFF06B6D4),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() => _currentTabIndex = 3),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: courseColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 13,
                                      color: courseColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      "Add Set",
                                      style: TextStyle(
                                        color: courseColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (course.studySets.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.secondaryBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline,
                                  color: AppColors.warning,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "No study sets yet. Ingest notes or lecture slides using AI Studio.",
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _currentTabIndex = 3),
                                  child: const Text("Ingest Now"),
                                ),
                              ],
                            ),
                          )
                        else
                          ...course.studySets.map((set) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.surfaceColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: context.cardBorderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.school_rounded,
                                                size: 16,
                                                color: Color(0xFF6366F1),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                set.title,
                                                style: GoogleFonts.outfit(
                                                  color: context.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      PopupMenuButton<String>(
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          size: 20,
                                          color: context.textSecondary,
                                        ),
                                        tooltip: "Set Options",
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        onSelected: (val) {
                                          if (val == "cram") _showCramSheet(set);
                                          if (val == "export") _exportStudyGuide(set);
                                          if (val == "delete") _confirmDeleteStudySet(course, set);
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: "cram",
                                            child: Row(
                                              children: [
                                                Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF6366F1)),
                                                SizedBox(width: 8),
                                                Text("Exam Cram Sheet"),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: "export",
                                            child: Row(
                                              children: [
                                                Icon(Icons.download_rounded, size: 18, color: Color(0xFF10B981)),
                                                SizedBox(width: 8),
                                                Text("Export Study Guide"),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: "delete",
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                                SizedBox(width: 8),
                                                Text("Delete Set", style: TextStyle(color: AppColors.danger)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (set.attemptsCount == 0
                                                  ? context.cardBorderColor
                                                  : const Color(0xFF10B981))
                                              .withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              set.attemptsCount == 0
                                                  ? Icons.hourglass_empty_rounded
                                                  : Icons.verified_rounded,
                                              size: 12,
                                              color: set.attemptsCount == 0
                                                  ? context.textSecondary
                                                  : const Color(0xFF10B981),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              set.attemptsCount == 0
                                                  ? "Not started"
                                                  : (set.masteryScore > 0 ? "${set.masteryScore.round()}% Ready" : "No data yet"),
                                              style: TextStyle(
                                                color: set.attemptsCount == 0
                                                    ? context.textSecondary
                                                    : const Color(0xFF10B981),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "${set.questionCount} Questions",
                                          style: TextStyle(
                                            color: isDark
                                                ? AppColors.primaryLight
                                                : AppColors.primaryDark,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _cleanDescription(set.description),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isDark
                                                ? AppColors.primary
                                                : AppColors.primaryDark,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                          label: const Text(
                                            "Practice",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          onPressed: () => _showModePicker(set),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.warning,
                                            side: const BorderSide(color: AppColors.warning),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.bolt_rounded, size: 16),
                                          label: Text(
                                            "Blitz (${_settingsService.settings.blitzSecondsPerQuestion}s)",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          onPressed: () => _startRapidFire(set),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: context.textSecondary,
                                            side: BorderSide(color: context.cardBorderColor),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.style_outlined, size: 16),
                                          label: const Text(
                                            "Cards",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => FlashcardsScreen(
                                                  courses: _courses,
                                                  initialStudySetId: set.id,
                                                  apiClient: widget.apiClient,
                                                  onCardDeleted: () => _fetchCoursesAndSync(fullFetch: true),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    String sub,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: context.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLoopStep(String title, IconData icon, String detail) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF6366F1)),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        Text(
          detail,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebar(bool isDark) {
    final cs = ChildSafetyService.instance;
    final navItems = [
      (Icons.dashboard_rounded, cs.getFriendlyTabName(0, "Courses"), 0),
      (Icons.style_outlined, cs.getFriendlyTabName(1, "Flashcards"), 1),
      (Icons.menu_book_outlined, cs.getFriendlyTabName(2, "Notebook"), 2),
      (Icons.psychology_outlined, cs.getFriendlyTabName(3, "AI Studio"), 3),
      (Icons.auto_awesome_rounded, cs.getFriendlyTabName(4, "AI Tutor"), 4),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          right: BorderSide(color: context.cardBorderColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "StudyApp",
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        "Study Workspace",
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: navItems.map((item) {
                final isSelected = _currentTabIndex == item.$3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isSelected
                        ? (isDark
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.primaryLight.withValues(alpha: 0.12))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => setState(() => _currentTabIndex = item.$3),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: isDark
                                      ? AppColors.primary.withValues(alpha: 0.4)
                                      : AppColors.primaryDark.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.$1,
                              size: 20,
                              color: isSelected
                                  ? (isDark ? AppColors.primaryLight : AppColors.primaryDark)
                                  : context.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? (isDark ? AppColors.primaryLight : AppColors.primaryDark)
                                      : context.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),
          // Sidebar Footer with utilities
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 4,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(
                    Icons.sync_rounded,
                    size: 19,
                    color: AppColors.primaryDark,
                  ),
                  tooltip: "Sync Courses",
                  onPressed: () => _fetchCoursesAndSync(fullFetch: true, showSnackBar: true),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.menu_book_rounded, size: 19, color: Color(0xFF10B981)),
                  tooltip: "User Manual & Feature Guide",
                  onPressed: () => UserManualSheet.show(
                    context,
                    onOpenIngest: () => setState(() => _currentTabIndex = 3),
                    onOpenGradeTracker: () => GradeTrackerSheet.show(
                      context,
                      widget.apiClient,
                      onGradesUpdated: () { _fetchCoursesAndSync(fullFetch: true); _loadTodayStudyPlan(); },
                    ),
                    onOpenFlashcards: () => setState(() => _currentTabIndex = 1),
                    onOpenAiTutor: () => setState(() => _currentTabIndex = 4),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.verified_user_rounded, size: 19, color: Colors.teal),
                  tooltip: "Child safety resources & MAKABATA 1383",
                  onPressed: () => DswdSafetyModal.show(context),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF6366F1)),
                  tooltip: "Study Configurations",
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          apiClient: widget.apiClient,
                          sessionService: widget.sessionService,
                          settingsService: _settingsService,
                          onLogout: _handleLogout,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: Icon(Icons.logout_rounded, size: 19, color: context.textSecondary),
                  tooltip: "Sign Out",
                  onPressed: _handleLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _builtTabs.add(_currentTabIndex);
    final isDark = context.isDarkMode;
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) _buildDesktopSidebar(isDark),
          Expanded(
            child: IndexedStack(
              index: _currentTabIndex,
              children: [
                // Tab 0: Courses
                _lazy(0, () => _buildCoursesTab()),
                // Tab 1: Flashcards
                _lazy(
                  1,
                  () => FlashcardsScreen(
                    courses: _courses,
                    apiClient: widget.apiClient,
                    onLoadStarterPack: _loadStarterDemoPack,
                    onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
                    onCardDeleted: () => _fetchCoursesAndSync(fullFetch: true),
                  ),
                ),
                // Tab 2: Notebook
                _lazy(
                  2,
                  () => NotebookScreen(
                    courses: _courses,
                    apiClient: widget.apiClient,
                    onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
                    onLoadStarterPack: _loadStarterDemoPack,
                  ),
                ),
                // Tab 3: AI Studio
                _lazy(
                  3,
                  () => IngestionScreen(
                    courses: _courses,
                    apiClient: widget.apiClient,
                    initialCourseId: _activeCourseId,
                    settingsService: _settingsService,
                    onCourseSelected: (id) => setState(() => _activeCourseId = id),
                    draftTitle: _studioDraftTitle,
                    draftContent: _studioDraftContent,
                    draftRevision: _studioDraftRevision,
                    onStudySetCreated: (newSet) async {
                      await _fetchCoursesAndSync();
                      if (!mounted) return;
                      setState(() {
                        final course = _courses.firstWhere(
                          (c) => c.id == newSet.courseId,
                          orElse: () => _courses.isNotEmpty
                              ? _courses.first
                              : CourseModel(
                                  id: newSet.courseId,
                                  code: "GEN-101",
                                  name: "General Studies",
                                  colorHex: "#6366F1",
                                  createdAt: DateTime.now(),
                                  studySets: [newSet],
                                ),
                        );
                        if (!course.studySets.any((s) => s.id == newSet.id)) {
                          course.studySets.insert(0, newSet);
                        }
                        _currentTabIndex = 0;
                      });
                    },
                  ),
                ),
                // Tab 4: AI Tutor
                _lazy(4, () => AiTutorScreen(apiClient: widget.apiClient, courses: _courses)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                border: Border(
                  top: BorderSide(color: context.cardBorderColor, width: 1),
                ),
              ),
              child: BottomNavigationBar(
                currentIndex: _currentTabIndex,
                onTap: (index) => setState(() => _currentTabIndex = index),
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: isDark
                    ? AppColors.primaryLight
                    : AppColors.primaryDark,
                unselectedItemColor: context.textSecondary,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.dashboard_rounded),
                    label: ChildSafetyService.instance.getFriendlyTabName(0, "Courses"),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.style_outlined),
                    label: ChildSafetyService.instance.getFriendlyTabName(1, "Flashcards"),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.menu_book_outlined),
                    label: ChildSafetyService.instance.getFriendlyTabName(2, "Notebook"),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.psychology_outlined),
                    label: ChildSafetyService.instance.getFriendlyTabName(3, "AI Studio"),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: ChildSafetyService.instance.getFriendlyTabName(4, "AI Tutor"),
                  ),
                ],
              ),
            ),
      floatingActionButton: null,
    );
  }
}

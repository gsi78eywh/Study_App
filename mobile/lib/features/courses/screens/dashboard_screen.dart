import "dart:async";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/network/api_client.dart";
import "../../../core/services/app_session.dart";
import "../../../core/services/child_safety_service.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/widgets/study_app_brand_logo.dart";
import "../../../core/widgets/pdf_study_guide_viewer_modal.dart";
import "../models/course_models.dart";
import "../../auth/screens/login_screen.dart";
import "../../flashcards/screens/flashcards_screen.dart";
import "../../ingestion/screens/ingestion_screen.dart";
import "../../ingestion/services/local_pdf_extractor.dart";
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/quiz_player_screen.dart";
import "../../quiz/screens/rapid_fire_screen.dart";
import "../../sync/services/sync_service.dart";
import "../../settings/services/settings_service.dart";
import "../../settings/screens/settings_screen.dart";
import "../../settings/widgets/dswd_safety_modal.dart";
import "../widgets/onboarding_modal.dart";
import "../widgets/grade_tracker_sheet.dart";
import "../widgets/user_manual_sheet.dart";
import "../widgets/eye_break_dialog.dart";
import "../../practice/models/adaptive_models.dart";
import "../widgets/today_study_plan_widget.dart";
import "../widgets/student_brain_modal.dart";
import "../widgets/academic_planner_modal.dart";
import "../widgets/notification_sheet.dart";
import "../../../core/services/notification_service.dart";
import "../../quiz/screens/smart_session_player_screen.dart";
import "../../quiz/screens/mistake_bank_screen.dart";
import "../../practice/screens/practice_screen.dart";

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
  TodayStudyPlanModel? _todayStudyPlan;
  bool _isLoadingStudyPlan = false;
  String? _studioDraftTitle;
  String? _studioDraftContent;
  final int _studioDraftRevision = 0;
  String? _activeCourseId;

  // Local workspace filter
  final TextEditingController _universalSearchController = TextEditingController();
  String _universalSearchQuery = "";

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

  void _openAddMaterial([String? targetCourseId]) async {
    final createdSet = await Navigator.of(context).push<StudySetModel>(
      MaterialPageRoute(
        builder: (_) => IngestionScreen(
          courses: _courses,
          apiClient: widget.apiClient,
          initialCourseId: targetCourseId ?? _activeCourseId,
          settingsService: _settingsService,
          onCourseSelected: (id) => setState(() => _activeCourseId = id),
          draftTitle: _studioDraftTitle,
          draftContent: _studioDraftContent,
          draftRevision: _studioDraftRevision,
          onStudySetCreated: (newSet) {
            if (!mounted) return;
            setState(() {
              final idx = _courses.indexWhere((c) => c.id == newSet.courseId);
              if (idx >= 0) {
                final existing = _courses[idx];
                final updatedSets = [
                  newSet,
                  ...existing.studySets.where((s) => s.id != newSet.id),
                ];
                _courses[idx] = existing.copyWith(studySets: updatedSets);
              } else if (_courses.isNotEmpty) {
                final first = _courses.first;
                final updatedSets = [
                  newSet,
                  ...first.studySets.where((s) => s.id != newSet.id),
                ];
                _courses[0] = first.copyWith(studySets: updatedSets);
              } else {
                _courses = [
                  CourseModel(
                    id: newSet.courseId.isNotEmpty
                        ? newSet.courseId
                        : "local_course_default",
                    code: "GEN-101",
                    name: "General Studies",
                    colorHex: "#2E7D5B",
                    createdAt: DateTime.now(),
                    studySets: [newSet],
                  ),
                ];
              }
              SyncService.cachedCourses = List.from(_courses);
            });
          },
        ),
      ),
    );

    if (createdSet != null && mounted) {
      _fetchCoursesAndSync();
      // Immediately redirect to exams and simulation!
      _startPracticeForSet(createdSet);
    }
  }

  List<QuestionModel> _buildInstantLocalQuestions(StudySetModel set) {
    return LocalExamSynthesizer.getQuestionsForSet(set);
  }

  void _startPracticeForSet(StudySetModel set) async {
    List<QuestionModel> loadedQuestions = [];
    if (!set.id.startsWith("local_")) {
      BuildContext? loadingDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          loadingDialogCtx = ctx;
          return const Center(child: CircularProgressIndicator());
        },
      );
      try {
        final res = await widget.apiClient.dio
            .get(
              '/api/v1/studysets/${set.id}/questions',
              options: Options(receiveTimeout: const Duration(milliseconds: 2500)),
            )
            .timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200 && res.data is List) {
          loadedQuestions = (res.data as List)
              .map((q) => QuestionModel.fromJson(q as Map<String, dynamic>))
              .toList();
          if (loadedQuestions.isNotEmpty) {
            LocalExamSynthesizer.registerQuestions(set.id, loadedQuestions);
          }
        }
      } catch (_) {}
      if (loadingDialogCtx != null &&
          loadingDialogCtx!.mounted &&
          Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
    }

    if (!mounted) return;
    if (loadedQuestions.isEmpty) {
      loadedQuestions = _buildInstantLocalQuestions(set);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPlayerScreen(
          studySet: set,
          questions: loadedQuestions,
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
        ),
      ),
    ).then((_) => _fetchCoursesAndSync(fullFetch: false));
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
    _universalSearchController.dispose();
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
          onCreateStudySet: _openAddMaterial,
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
      onAddCourse: _showAddCourseDialog,
    );
  }

  void _openAcademicPlannerModal() {
    AcademicPlannerModal.show(
      context,
      apiClient: widget.apiClient,
      courses: _courses,
      onNavigateToStudio: _openAddMaterial,
    );
  }

  Future<void> _showReadinessBreakdown(String courseId) async {
    BuildContext? loadingDialogCtx;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        loadingDialogCtx = ctx;
        return const Center(
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
        );
      },
    );

    try {
      final readiness = await widget.apiClient.getExamReadiness(courseId);
      if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
      if (!mounted) return;

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

    final localCoursesBackup = List<CourseModel>.from(_courses);
    final result = await _syncService.performSync(
      fullFetch: fullFetch,
      currentCourses: _courses,
    );
    if (!mounted) return;

    setState(() {
      _isLoadingCourses = false;
      if (result.success && result.syncedCourses.isNotEmpty) {
        // Merge any local study sets that haven't been synced to backend yet
        final merged = List<CourseModel>.from(result.syncedCourses);
        for (final localC in localCoursesBackup) {
          final localSets = localC.studySets
              .where((s) => s.id.startsWith("local_"))
              .toList();
          final targetIdx = merged.indexWhere((c) => c.id == localC.id);
          if (targetIdx >= 0 && localSets.isNotEmpty) {
            final existingSets = merged[targetIdx].studySets;
            final combinedSets = [
              ...localSets.where((ls) => !existingSets.any((es) => es.id == ls.id)),
              ...existingSets,
            ];
            merged[targetIdx] = merged[targetIdx].copyWith(studySets: combinedSets);
          } else if (targetIdx == -1 &&
              (localC.id.startsWith("local_") || localSets.isNotEmpty)) {
            merged.insert(0, localC);
          }
        }
        _courses = merged;
        SyncService.cachedCourses = List.from(_courses);
      }
      if (_courses.isNotEmpty &&
          (_activeCourseId == null ||
              !_courses.any((c) => c.id == _activeCourseId))) {
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
                  final response = await widget.apiClient.dio
                      .post(
                        "/api/v1/courses",
                        data: {
                          "code": code,
                          "name": name,
                          "colorHex": selectedColor,
                        },
                      )
                      .timeout(const Duration(milliseconds: 2500));
                  if (!mounted) return;
                  if (ctx.mounted) Navigator.pop(ctx);

                  if (response.data is Map<String, dynamic>) {
                    final newCourse = CourseModel.fromJson(response.data);
                    setState(() {
                      _courses = [..._courses, newCourse];
                      _activeCourseId ??= newCourse.id;
                      SyncService.cachedCourses = List.from(_courses);
                    });
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Course '$code' created successfully!"),
                      backgroundColor: AppColors.accent,
                    ),
                  );

                  await _fetchCoursesAndSync(fullFetch: false);
                } catch (_) {
                  // Instant offline fallback: create the course locally without failing
                  if (!mounted) return;
                  if (ctx.mounted) Navigator.pop(ctx);
                  final localCourse = CourseModel(
                    id: "local_course_${DateTime.now().millisecondsSinceEpoch}",
                    code: code,
                    name: name,
                    colorHex: selectedColor,
                    createdAt: DateTime.now(),
                    studySets: const [],
                  );
                  setState(() {
                    _courses = [..._courses, localCourse];
                    _activeCourseId ??= localCourse.id;
                    SyncService.cachedCourses = List.from(_courses);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Course '$code' created!"),
                      backgroundColor: AppColors.accent,
                    ),
                  );
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
              "Flip and rate recall",
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
              "Multiple choice with answers",
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
              "MCQ, True/False, ID",
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
              "View or copy guide",
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
    List<QuestionModel> questions = [];
    if (!set.id.startsWith("local_")) {
      BuildContext? loadingDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          loadingDialogCtx = ctx;
          return const Center(
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
          );
        },
      );
      try {
        final resp = await widget.apiClient.dio
            .get(
              "/api/v1/practice/studysets/${set.id}/questions",
              queryParameters: {
                "mode": StudyModeValue.rapidFireBlitz,
                "count": _settingsService.settings.defaultQuestionCount,
              },
            )
            .timeout(const Duration(milliseconds: 2500));
        if (resp.statusCode == 200 && resp.data is List) {
          final raw = resp.data as List<dynamic>;
          questions = raw
              .map((q) => QuestionModel.fromJson(q as Map<String, dynamic>))
              .toList();
          if (questions.isNotEmpty) {
            LocalExamSynthesizer.registerQuestions(set.id, questions);
          }
        }
      } catch (_) {}
      if (loadingDialogCtx != null &&
          loadingDialogCtx!.mounted &&
          Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
    }

    if (questions.isEmpty) {
      questions = _buildInstantLocalQuestions(set);
    }
    if (!mounted) return;

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

  String _buildRichLocalStudyGuide(StudySetModel set) {
    final buffer = StringBuffer();
    buffer.writeln("# ${set.title}");
    buffer.writeln();
    buffer.writeln("## Key Concepts & Summary");
    if (set.bulletPoints.isNotEmpty) {
      for (final bp in set.bulletPoints) {
        final clean = bp.trim();
        if (clean.isNotEmpty) {
          buffer.writeln("- $clean");
        }
      }
    } else {
      final desc = _cleanDescription(set.description);
      if (desc.isNotEmpty) {
        buffer.writeln(desc);
      } else {
        buffer.writeln("- Core definitions, principles, and exam takeaways for ${set.title}.");
      }
    }
    buffer.writeln();
    final questions = LocalExamSynthesizer.getQuestionsForSet(set);
    if (questions.isNotEmpty) {
      buffer.writeln("## Practice Exam Questions (${questions.length})");
      buffer.writeln();
      for (int i = 0; i < questions.length; i++) {
        final q = questions[i];
        buffer.writeln("${i + 1}. **${q.questionText}**");
        if (q.options.isNotEmpty) {
          for (final opt in q.options) {
            buffer.writeln("   - ${opt.optionText}");
          }
        }
        final correctOpt = q.options.where((o) => o.isCorrect).firstOrNull;
        final ans = correctOpt?.optionText ?? q.correctAnswer ?? "";
        if (ans.isNotEmpty) {
          buffer.writeln("   - **Answer:** $ans");
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  Future<void> _exportStudyGuide(StudySetModel set) async {
    final localGuide = _buildRichLocalStudyGuide(set);

    if (set.id.startsWith("local_")) {
      if (!mounted) return;
      PdfStudyGuideViewerModal.show(
        context,
        title: set.title,
        content: localGuide,
        sourceType: "PDF Study Guide",
        onGenerateQuiz: () => _startQuiz(set),
      );
      return;
    }

    BuildContext? loadingDialogCtx;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        loadingDialogCtx = ctx;
        return Center(
          child: Card(
            color: context.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFFF6B00)),
                  const SizedBox(height: 14),
                  Text(
                    "Preparing PDF...",
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
      final response = await widget.apiClient.dio
          .get(
            "/api/v1/studysets/${set.id}/export",
            queryParameters: {"format": "markdown"},
            options: Options(
              sendTimeout: const Duration(milliseconds: 2500),
              receiveTimeout: const Duration(milliseconds: 2500),
            ),
          )
          .timeout(const Duration(milliseconds: 2500));

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
        markdownContent = localGuide;
      }

      if (!mounted) return;

      PdfStudyGuideViewerModal.show(
        context,
        title: exportTitle,
        content: markdownContent,
        sourceType: "PDF Study Guide",
        onGenerateQuiz: () => _startQuiz(set),
      );
    } catch (_) {
      if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
      if (!mounted) return;
      PdfStudyGuideViewerModal.show(
        context,
        title: set.title,
        content: localGuide,
        sourceType: "PDF Study Guide",
        onGenerateQuiz: () => _startQuiz(set),
      );
    }
  }

  Future<void> _startQuiz(StudySetModel set, {int? mode, int? count}) async {
    final effectiveMode = mode ?? _settingsService.settings.preferredStudyMode;
    final effectiveCount = count ?? _settingsService.settings.defaultQuestionCount;

    List<QuestionModel> questions = [];
    if (!set.id.startsWith("local_")) {
      BuildContext? loadingDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          loadingDialogCtx = ctx;
          return const Center(
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
          );
        },
      );

      try {
        final response = await widget.apiClient.dio
            .get(
              "/api/v1/practice/studysets/${set.id}/questions",
              queryParameters: {"mode": effectiveMode, "count": effectiveCount},
              options: Options(receiveTimeout: const Duration(milliseconds: 2500)),
            )
            .timeout(const Duration(milliseconds: 2500));
        if (response.statusCode == 200 && response.data is List) {
          final List list = response.data;
          questions = list
              .map((item) => QuestionModel.fromJson(item as Map<String, dynamic>))
              .toList();
          if (questions.isNotEmpty) {
            LocalExamSynthesizer.registerQuestions(set.id, questions);
          }
        }
      } catch (_) {}

      if (loadingDialogCtx != null &&
          loadingDialogCtx!.mounted &&
          Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
    }

    if (questions.isEmpty) {
      questions = _buildInstantLocalQuestions(set);
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
                SyncService.cachedCourses = List.from(_courses);
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Deleted '${set.title}'"),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              if (!set.id.startsWith("local_")) {
                try {
                  await widget.apiClient.dio
                      .delete("/api/v1/studysets/${set.id}")
                      .timeout(const Duration(seconds: 3));
                } catch (_) {}
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
    BuildContext? loadingDialogCtx;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        loadingDialogCtx = ctx;
        return const Center(
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
        );
      },
    );

    List<QuestionModel> questions = [];
    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/practice/studysets/${set.id}/questions",
        queryParameters: {"count": 50},
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        questions = list
            .map((item) => QuestionModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
      Navigator.pop(loadingDialogCtx!);
    }

    if (questions.isEmpty) {
      questions = _buildInstantLocalQuestions(set);
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

  void _showAccountMenu(BuildContext context) {
    final email = widget.sessionService.email ?? "Unknown student";
    final fullName = widget.sessionService.fullName ?? "Student";

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.sessionService.isGoogleLinked
                                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                : const Color(0xFF64748B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: widget.sessionService.isGoogleLinked
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF64748B),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.sessionService.isGoogleLinked
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_queue_rounded,
                                size: 13,
                                color: widget.sessionService.isGoogleLinked
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.sessionService.isGoogleLinked
                                    ? "Google sign-in connected"
                                    : "Email sign-in",
                                style: TextStyle(
                                  color: widget.sessionService.isGoogleLinked
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF64748B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF6366F1), size: 22),
                ),
                title: const Text("Study Mode & Eye Rest", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("Level: ${ChildSafetyService.instance.shortStageBadgeText} • 20-20-20 Eye Care", style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showJuniorModeDialog();
                },
              ),
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
    ),
  );
  }


  Widget _buildChildSafetyBanner(BuildContext context) {
    return ListenableBuilder(
      listenable: ChildSafetyService.instance,
      builder: (context, _) {
        final cs = ChildSafetyService.instance;
        if (!cs.isJuniorMode) return const SizedBox.shrink();
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mode indicator chip with descriptive tooltip
                  Flexible(
                    child: Tooltip(
                      message: "Study Mode Selector: Standard Academic Mode, Junior Learner Mode (Grades 1-6), or Exam Cram Sprint. Tap to switch.",
                      child: InkWell(
                        onTap: () => _showJuniorModeDialog(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.isJuniorMode
                                ? const Color(0xFFF59E0B)
                                : (cs.gradeLevel >= 7 && cs.gradeLevel <= 10
                                    ? const Color(0xFF10B981)
                                    : (cs.gradeLevel >= 11 && cs.gradeLevel <= 12
                                        ? const Color(0xFF8B5CF6)
                                        : const Color(0xFF6366F1))),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  cs.shortStageBadgeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

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
                              'Eye Break',
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
                  'Study Level',
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
                      'Pick your level:',
                      style: TextStyle(fontSize: 12.5, color: context.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Option 1: Elementary Learner Mode (Grades 1-6)
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
                                          Flexible(child: Text(
                                            'Elementary (Gr 1–6)',
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          )),
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
                                        'Simple words, hints & read-aloud.',
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
                              Text('Select Elementary Grade:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: context.textPrimary)),
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

                    // Option 2: Junior High School (Grades 7-10)
                    InkWell(
                      onTap: () {
                        cs.setJuniorMode(false);
                        if (cs.gradeLevel < 7 || cs.gradeLevel > 10) cs.setGradeLevel(8);
                        setDialogState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !cs.isJuniorMode && cs.gradeLevel >= 7 && cs.gradeLevel <= 10
                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                              : context.secondaryBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !cs.isJuniorMode && cs.gradeLevel >= 7 && cs.gradeLevel <= 10
                                ? const Color(0xFF10B981)
                                : context.cardBorderColor,
                            width: !cs.isJuniorMode && cs.gradeLevel >= 7 && cs.gradeLevel <= 10 ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🎒', style: TextStyle(fontSize: 24)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(
                                            'Junior High (Gr 7–10)',
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          )),
                                          const SizedBox(width: 6),
                                          if (!cs.isJuniorMode && cs.gradeLevel >= 7 && cs.gradeLevel <= 10)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Core concepts & balanced quizzes.',
                                        style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (!cs.isJuniorMode && cs.gradeLevel >= 7 && cs.gradeLevel <= 10) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Text('Select JHS Grade:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: context.textPrimary)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [7, 8, 9, 10].map((grade) {
                                  final isSelected = cs.gradeLevel == grade;
                                  return ChoiceChip(
                                    label: Text('Grade $grade', style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF10B981).withValues(alpha: 0.3),
                                    onSelected: (selected) {
                                      if (selected) {
                                        cs.setGradeLevel(grade);
                                        setDialogState(() {});
                                        setState(() {});
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Option 3: Senior High School (Grades 11-12)
                    InkWell(
                      onTap: () {
                        cs.setJuniorMode(false);
                        if (cs.gradeLevel < 11 || cs.gradeLevel > 12) cs.setGradeLevel(11);
                        setDialogState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !cs.isJuniorMode && cs.gradeLevel >= 11 && cs.gradeLevel <= 12
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                              : context.secondaryBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !cs.isJuniorMode && cs.gradeLevel >= 11 && cs.gradeLevel <= 12
                                ? const Color(0xFF8B5CF6)
                                : context.cardBorderColor,
                            width: !cs.isJuniorMode && cs.gradeLevel >= 11 && cs.gradeLevel <= 12 ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🔬', style: TextStyle(fontSize: 24)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(
                                            'Senior High (Gr 11–12)',
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          )),
                                          const SizedBox(width: 6),
                                          if (!cs.isJuniorMode && cs.gradeLevel >= 11 && cs.gradeLevel <= 12)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF8B5CF6),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'STEM/ABM/HUMSS & entrance drills.',
                                        style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (!cs.isJuniorMode && cs.gradeLevel >= 11 && cs.gradeLevel <= 12) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Text('Select SHS Grade:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: context.textPrimary)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [11, 12].map((grade) {
                                  final isSelected = cs.gradeLevel == grade;
                                  return ChoiceChip(
                                    label: Text('Grade $grade', style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                    onSelected: (selected) {
                                      if (selected) {
                                        cs.setGradeLevel(grade);
                                        setDialogState(() {});
                                        setState(() {});
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Option 4: College / University Mode
                    InkWell(
                      onTap: () {
                        cs.setJuniorMode(false);
                        cs.setGradeLevel(1); // Set to neutral college level
                        setDialogState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !cs.isJuniorMode && (cs.gradeLevel < 7 || cs.gradeLevel > 12)
                              ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                              : context.secondaryBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !cs.isJuniorMode && (cs.gradeLevel < 7 || cs.gradeLevel > 12)
                                ? const Color(0xFF6366F1)
                                : context.cardBorderColor,
                            width: !cs.isJuniorMode && (cs.gradeLevel < 7 || cs.gradeLevel > 12) ? 1.5 : 1,
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
                                      Flexible(child: Text(
                                        'College / University',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: context.textPrimary,
                                        ),
                                      )),
                                      const SizedBox(width: 6),
                                      if (!cs.isJuniorMode && (cs.gradeLevel < 7 || cs.gradeLevel > 12))
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
                                    'GWA tracking & advanced drills.',
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
                            const SnackBar(content: Text("Add a course and study material to start an exam session.")),
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
                                    'Fast review of weak topics.',
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

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtlePill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUniversalSearchAndQuickHub(bool isDark) {
    final qLower = _universalSearchQuery.trim().toLowerCase();
    final matchingLocalSets = <StudySetModel>[];
    if (qLower.isNotEmpty) {
      for (final c in _courses) {
        for (final s in c.studySets) {
          if (s.title.toLowerCase().contains(qLower) ||
              (s.description?.toLowerCase().contains(qLower) ?? false) ||
              c.name.toLowerCase().contains(qLower) ||
              c.code.toLowerCase().contains(qLower)) {
            matchingLocalSets.add(s);
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // UnionBank-Inspired Clean Icon-First Quick Actions Card
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.cardBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D5B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Quick Actions",
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 12, color: Color(0xFF10B981)),
                        SizedBox(width: 3),
                        Text(
                          "Offline Ready",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 4 Core Actions in single clean row
              Row(
                children: [
                  _buildQuickActionTile(
                    icon: Icons.note_add_rounded,
                    label: "Add Notes",
                    color: const Color(0xFF2E7D5B),
                    isDark: isDark,
                    onTap: () => _openAddMaterial(),
                  ),
                  _buildQuickActionTile(
                    icon: Icons.quiz_rounded,
                    label: "Take Exam",
                    color: const Color(0xFF6366F1),
                    isDark: isDark,
                    onTap: () => setState(() => _currentTabIndex = 1),
                  ),
                  _buildQuickActionTile(
                    icon: Icons.style_rounded,
                    label: "Flashcards",
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FlashcardsScreen(
                            courses: _courses,
                            apiClient: widget.apiClient,
                            onNavigateToStudio: _openAddMaterial,
                            onCardDeleted: () => _fetchCoursesAndSync(fullFetch: true),
                          ),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    icon: Icons.folder_special_rounded,
                    label: "Courses",
                    color: const Color(0xFF3B82F6),
                    isDark: isDark,
                    onTap: _showAddCourseDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _universalSearchController,
                onChanged: (v) => setState(() => _universalSearchQuery = v),
                style: TextStyle(fontSize: 13, color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: "Search study sets, notes, or topics...",
                  hintStyle: TextStyle(fontSize: 12, color: context.textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF2E7D5B)),
                  suffixIcon: _universalSearchQuery.isNotEmpty
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, size: 16, color: context.textSecondary),
                          onPressed: () {
                            _universalSearchController.clear();
                            setState(() => _universalSearchQuery = "");
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.cardBorderColor),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildSubtlePill(
                      icon: Icons.bar_chart_rounded,
                      label: "Grade Tracker",
                      color: const Color(0xFF0D9488),
                      onTap: () => GradeTrackerSheet.show(
                        context,
                        widget.apiClient,
                        onGradesUpdated: () {
                          _fetchCoursesAndSync(fullFetch: true);
                          _loadTodayStudyPlan();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSubtlePill(
                      icon: Icons.calendar_month_rounded,
                      label: "Study Plan",
                      color: const Color(0xFF8B5CF6),
                      onTap: _openAcademicPlannerModal,
                    ),
                    const SizedBox(width: 8),
                    _buildSubtlePill(
                      icon: Icons.slideshow_rounded,
                      label: "Guide",
                      color: const Color(0xFFF59E0B),
                      onTap: () => OnboardingModal.showForce(
                        context,
                        sessionService: widget.sessionService,
                        onCompleted: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (qLower.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: matchingLocalSets.isEmpty
                ? Text(
                    "No sets found for \"$_universalSearchQuery\".",
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Results (${matchingLocalSets.length})",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF6B00)),
                      ),
                      const SizedBox(height: 8),
                      ...matchingLocalSets.take(6).map((set) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: context.secondaryBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.cardBorderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFFFF6B00)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        set.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary),
                                      ),
                                      Text(
                                        "${set.questionCount} Qs",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: context.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: "Export PDF",
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFF10B981)),
                                  onPressed: () => _exportStudyGuide(set),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B00),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  onPressed: () => _startPracticeForSet(set),
                                  child: const Text("Quiz", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildHomeTab() {
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
    final displayName = (studentName != null &&
                studentName.isNotEmpty &&
                studentName.toLowerCase() != 'google student')
            ? (studentName.toLowerCase().startsWith('google student ')
                ? studentName.substring(15).trim()
                : studentName)
            : (userEmail.isNotEmpty ? userEmail.split('@').first : 'Student');

    final hasCompletedQuiz = _courses.any(
      (course) => course.studySets.any((set) => set.attemptsCount > 0),
    );
    final isFirstRun = _courses.isEmpty || totalSets == 0 || !hasCompletedQuiz;

    CourseModel? upcomingExamCourse;
    for (final c in _courses) {
      if (c.hasUpcomingExam) {
        if (upcomingExamCourse == null || (c.daysUntilExam ?? 999) < (upcomingExamCourse.daysUntilExam ?? 999)) {
          upcomingExamCourse = c;
        }
      }
    }

    StudySetModel? recentSet;
    CourseModel? recentSetCourse;
    for (final c in _courses) {
      if (c.studySets.isNotEmpty) {
        recentSet = c.studySets.first;
        recentSetCourse = c;
        break;
      }
    }

    final activeStudyDays = _todayStudyPlan?.readiness.spacingDaysActive ?? 0;
    final hasActiveStudyDays = activeStudyDays > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            if ((_todayStudyPlan?.readiness.spacingDaysActive ?? 0) > 0)
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
                                        "$activeStudyDays active study ${activeStudyDays == 1 ? 'day' : 'days'}",
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
                        const SizedBox(height: 2),
                        Text(
                          _courses.isEmpty
                              ? "PDF • Scan • Exam • Offline Ready"
                              : "${_courses.length} ${_courses.length == 1 ? 'Course' : 'Courses'} • Offline Ready",
                          style: GoogleFonts.inter(
                            fontSize: 12,
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
                                color: Color(0xFF2E7D5B),
                                size: 22,
                              ),
                            ),
                            tooltip: "Notifications & Reminders",
                            onPressed: () => NotificationSheet.show(context),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: CircleAvatar(
                          radius: 13,
                          backgroundColor: const Color(0xFF2E7D5B),
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : "S",
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        tooltip: "Profile & Account (${widget.sessionService.email ?? 'Student'})",
                        onPressed: () => _showAccountMenu(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Google-Style Universal Search Bar + Feature Hub
              _buildUniversalSearchAndQuickHub(isDark),
              const SizedBox(height: 14),

              // Child Safety & Learner Mode Bar (only when Junior Learner Mode is active)
              if (ChildSafetyService.instance.isJuniorMode) ...[
                _buildChildSafetyBanner(context),
                const SizedBox(height: 14),
              ],

              // Next Upcoming Exam Card
              if (upcomingExamCourse != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF7F1D1D).withValues(alpha: 0.35), context.surfaceColor]
                          : [const Color(0xFFFEF2F2), Colors.white],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_available_rounded, color: Color(0xFFEF4444), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Target Exam: ${upcomingExamCourse.name} (${upcomingExamCourse.examTitle ?? 'Exam'})",
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: context.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${upcomingExamCourse.daysUntilExam} days remaining • Spaced review active",
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => setState(() => _currentTabIndex = 1),
                        child: const Text("Study Now", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              // Continue Where You Left Off Card
              if (recentSet != null && recentSetCourse != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF6366F1), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Continue Where You Left Off",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${recentSetCourse.code}: ${recentSet.title}",
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: context.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${recentSet.questionCount} practice questions ready",
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _startPracticeForSet(recentSet!),
                        child: const Text("Resume", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              // Your Study Sets (Direct 1-tap exams & flashcards)
              if (_courses.isNotEmpty && totalSets > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Your Study Sets",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      "$totalSets ${totalSets == 1 ? 'Set' : 'Sets'}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._courses.expand((course) => course.studySets.map((set) => _buildHomeStudySetCard(context, course, set, isDark))),
                const SizedBox(height: 16),
              ],

              // Empty State for First-Time or Empty Sets
              if (_courses.isEmpty || totalSets == 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D5B).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.note_add_rounded, color: Color(0xFF2E7D5B), size: 28),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No Study Sets Yet",
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Paste lecture notes or upload a PDF to instantly create your first exam simulation.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D5B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text("Create First Study Set", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        onPressed: () => _openAddMaterial(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_courses.isNotEmpty &&
                  (_isLoadingStudyPlan ||
                      (_todayStudyPlan?.totalEstimatedMinutes ?? 0) > 0 ||
                      (_todayStudyPlan?.priorities.isNotEmpty ?? false))) ...[
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
                    if (step.stepType == "spaced_flashcards" || step.stepNumber == 1) {
                      setState(() => _currentTabIndex = 1);
                    } else if (step.stepType == "mistake_drill") {
                      _openMistakeBank(_todayStudyPlan?.courseId);
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
                        if (hasActiveStudyDays) ...[
                          Container(
                            height: 36,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: context.cardBorderColor,
                          ),
                          _buildStatItem(
                            "Study Days",
                            "$activeStudyDays",
                            "Recorded",
                            Icons.local_fire_department_rounded,
                            const Color(0xFFF97316),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeStudySetCard(BuildContext context, CourseModel course, StudySetModel set, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  course.code,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  set.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${set.questionCount} Qs",
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D5B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.quiz_rounded, size: 15),
                  label: const Text(
                    "Take Exam",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => _startPracticeForSet(set),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.style_rounded, size: 15),
                  label: const Text(
                    "Flashcards",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FlashcardsScreen(
                          courses: _courses,
                          apiClient: widget.apiClient,
                          onNavigateToStudio: _openAddMaterial,
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
  }

  Widget _buildLibraryTab() {
    final isDark = context.isDarkMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                            "Add notes. Make cards. Practice.",
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
                              onTap: _openAddMaterial,
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
                                      "Add Material",
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
                              onTap: _openAddMaterial,
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
                                    "No study sets yet. Tap + to add.",
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _openAddMaterial,
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
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFF6B00),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 17),
                                          label: const Text(
                                            "Quiz",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          onPressed: () => _showModePicker(set),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.warning,
                                            side: const BorderSide(color: AppColors.warning),
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.bolt_rounded, size: 15),
                                          label: const Text(
                                            "Blitz",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          onPressed: () => _startRapidFire(set),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: context.textSecondary,
                                            side: BorderSide(color: context.cardBorderColor),
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.style_outlined, size: 15),
                                          label: const Text(
                                            "Cards",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                                      const SizedBox(width: 6),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: "Export PDF",
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.picture_as_pdf_rounded,
                                          size: 18,
                                          color: Color(0xFF10B981),
                                        ),
                                        onPressed: () => _exportStudyGuide(set),
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

  Widget _buildProfileTab() {
    final studentName = widget.sessionService.fullName?.trim() ?? 'Student';
    final userEmail = widget.sessionService.email?.trim() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Profile & Settings",
                style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 4),
              Text("Account, grade tracker, study preferences & compliance", style: TextStyle(fontSize: 13, color: context.textSecondary)),
              const SizedBox(height: 20),

              // Student Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF4285F4),
                      child: Text(
                        studentName.isNotEmpty ? studentName[0].toUpperCase() : "S",
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(studentName, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: context.textPrimary)),
                          const SizedBox(height: 2),
                          Text(userEmail.isNotEmpty ? userEmail : "Email not available", style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text("Account", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Grade Tracker Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bar_chart_rounded, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Grade Tracker", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                          const SizedBox(height: 2),
                          Text("Track grades & GWA", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => GradeTrackerSheet.show(
                        context,
                        widget.apiClient,
                        onGradesUpdated: () { _fetchCoursesAndSync(fullFetch: true); _loadTodayStudyPlan(); },
                      ),
                      child: const Text("Open Tracker", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Study Configurations & Settings Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings_outlined, color: Color(0xFF6366F1), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("App Settings & Preferences", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                          const SizedBox(height: 2),
                          Text("Theme, audio, alerts", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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
                      child: const Text("Configure", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Privacy & Data Protection (RA 10173 Compliance)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, color: Color(0xFF06B6D4), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Privacy & Study Data", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                              const SizedBox(height: 2),
                              Text("Check before uploading.", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text("Don't upload sensitive personal info. Material may be sent to AI when you generate questions.", style: TextStyle(fontSize: 11.5, height: 1.5, color: context.textSecondary)),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text("View Learner Safety & Privacy Guidelines", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => DswdSafetyModal.show(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Account Actions: Sign Out
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _handleLogout,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
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
      (Icons.home_rounded, cs.getFriendlyTabName(0, "Home"), 0),
      (Icons.fitness_center_rounded, "Practice", 1),
      (Icons.local_library_rounded, "Library", 2),
      (Icons.person_rounded, "Profile", 3),
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
                const StudyAppBrandLogo(size: 42),
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
                        "PDF Layout & Exam Studio",
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
          // Prominent + Add Material button for Desktop
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ElevatedButton.icon(
              onPressed: () => _openAddMaterial(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                "Add Material",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () => OnboardingModal.showForce(
                context,
                sessionService: widget.sessionService,
              ),
              icon: const Icon(Icons.slideshow_rounded, size: 18),
              label: const Text(
                "4-Step Walkthrough",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                    onOpenIngest: _openAddMaterial,
                    onOpenGradeTracker: () => GradeTrackerSheet.show(
                      context,
                      widget.apiClient,
                      onGradesUpdated: () { _fetchCoursesAndSync(fullFetch: true); _loadTodayStudyPlan(); },
                    ),
                    onOpenFlashcards: () => setState(() => _currentTabIndex = 1),
                    onOpenAiTutor: () => setState(() => _currentTabIndex = 1),
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
                  icon: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF2E7D5B)),
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
    final safeTabIndex = _currentTabIndex.clamp(0, 3);
    _builtTabs.add(safeTabIndex);
    final isDark = context.isDarkMode;
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) _buildDesktopSidebar(isDark),
          Expanded(
            child: IndexedStack(
              index: safeTabIndex,
              children: [
                // Tab 0: Home
                _lazy(0, () => _buildHomeTab()),
                // Tab 1: Practice (Quizzes, Flashcards, Blitz, Mistake Bank, Simulated Exam)
                _lazy(
                  1,
                  () => PracticeScreen(
                    apiClient: widget.apiClient,
                    sessionService: widget.sessionService,
                    courses: _courses,
                    studyPlan: _todayStudyPlan,
                    onRefresh: () => _fetchCoursesAndSync(fullFetch: true),
                    onNavigateToStudio: () => _openAddMaterial(),
                  ),
                ),
                // Tab 2: Library (Courses, Study Sets, Course Notebooks)
                _lazy(2, () => _buildLibraryTab()),
                // Tab 3: Profile (Grades, Settings, Privacy & NPC DPA Compliance, Account)
                _lazy(3, () => _buildProfileTab()),
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
                currentIndex: safeTabIndex,
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
                    icon: const Icon(Icons.home_rounded),
                    label: ChildSafetyService.instance.getFriendlyTabName(0, "Home"),
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.fitness_center_rounded),
                    label: "Practice",
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.local_library_rounded),
                    label: "Library",
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.person_rounded),
                    label: "Profile",
                  ),
                ],
              ),
            ),
      // No floatingActionButton overlapping buttons across tabs
      floatingActionButton: null,
    );
  } 
}

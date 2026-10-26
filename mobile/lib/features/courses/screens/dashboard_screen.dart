import "dart:async";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
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
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/quiz_player_screen.dart";
import "../../quiz/screens/rapid_fire_screen.dart";
import "../../sync/services/sync_service.dart";
import "../../ai_tutor/screens/ai_tutor_screen.dart";
import "../../ai_tutor/services/seth_ai_engine.dart";
import "../../ai_tutor/widgets/easy_writing_studio_modal.dart";
import "../../../core/utils/url_launcher_helper.dart";
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

  // Universal Search (Google Search + Seth AI + Local Courses/StudySets/Questions)
  final TextEditingController _universalSearchController = TextEditingController();
  bool _isSearchingUniversal = false;
  String _universalSearchQuery = "";
  SethAiSearchOverview? _universalSearchResult;

  Future<void> _executeUniversalSearch([String? customQuery]) async {
    final q = (customQuery ?? _universalSearchController.text).trim();
    if (q.isEmpty) {
      setState(() {
        _universalSearchQuery = "";
        _universalSearchResult = null;
        _isSearchingUniversal = false;
      });
      return;
    }
    if (customQuery != null) {
      _universalSearchController.text = customQuery;
    }
    setState(() {
      _universalSearchQuery = q;
      _isSearchingUniversal = true;
    });
    try {
      final res = await SethAiEngine.searchUniversal(
        q,
        apiClient: widget.apiClient,
        courseId: _activeCourseId,
      );
      if (mounted) {
        setState(() {
          _universalSearchResult = res;
          _isSearchingUniversal = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearchingUniversal = false);
      }
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

  void _openAddMaterial([String? targetCourseId]) {
    Navigator.of(context).push(
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
                        colorHex: "#2E7D5B",
                        createdAt: DateTime.now(),
                        studySets: [newSet],
                      ),
              );
              if (!course.studySets.any((s) => s.id == newSet.id)) {
                course.studySets.insert(0, newSet);
              }
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  List<QuestionModel> _buildInstantLocalQuestions(StudySetModel set) {
    final topic = set.title.trim().isNotEmpty ? set.title.trim() : "Core Study Concept";
    final desc = _cleanDescription(set.description);
    return [
      QuestionModel(
        id: "local-${set.id}-1",
        studySetId: set.id,
        type: QuestionTypeEnum.multipleChoice,
        prompt: "What is the primary focus and core principle of $topic?",
        hints: const ["Focus on the core definition of the study set."],
        explanation: desc,
        difficulty: 2,
        options: [
          QuestionOptionModel(
            id: "opt-1a",
            optionText: desc,
            isCorrect: true,
          ),
          QuestionOptionModel(
            id: "opt-1b",
            optionText: "Unrelated external assumption not grounded in $topic.",
            isCorrect: false,
          ),
          QuestionOptionModel(
            id: "opt-1c",
            optionText: "Random trial-and-error without structured verification.",
            isCorrect: false,
          ),
          QuestionOptionModel(
            id: "opt-1d",
            optionText: "Ignoring boundary conditions and core definitions.",
            isCorrect: false,
          ),
        ],
      ),
      QuestionModel(
        id: "local-${set.id}-2",
        studySetId: set.id,
        type: QuestionTypeEnum.trueFalse,
        prompt: "True or False: Mastering $topic requires understanding both its core definition and its practical application.",
        hints: const ["Consider how theory and practice work together."],
        explanation: "Understanding both theory and real-world application is essential for exam readiness in $topic.",
        difficulty: 1,
        isTrue: true,
        options: [
          QuestionOptionModel(id: "opt-2a", optionText: "True", isCorrect: true),
          QuestionOptionModel(id: "opt-2b", optionText: "False", isCorrect: false),
        ],
      ),
      QuestionModel(
        id: "local-${set.id}-3",
        studySetId: set.id,
        type: QuestionTypeEnum.identification,
        prompt: "Identify the study topic described: $desc",
        hints: [topic],
        explanation: "This study set focuses on $topic.",
        difficulty: 2,
        correctAnswer: topic,
        options: [
          QuestionOptionModel(id: "opt-3a", optionText: topic, isCorrect: true),
        ],
      ),
    ];
  }

  void _startPracticeForSet(StudySetModel set) async {
    List<QuestionModel> loadedQuestions = [];
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
      final res = await widget.apiClient.dio.get(
        '/api/v1/studysets/${set.id}/questions',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      if (res.statusCode == 200 && res.data is List) {
        loadedQuestions = (res.data as List)
            .map((q) => QuestionModel.fromJson(q as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
      Navigator.pop(loadingDialogCtx!);
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
    ).then((_) => _fetchCoursesAndSync(fullFetch: true));
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

      PdfStudyGuideViewerModal.show(
        context,
        title: exportTitle,
        content: markdownContent,
        sourceType: "Printable PDF Study Guide",
        onGenerateQuiz: () => _startQuiz(set),
      );
    } catch (_) {
      if (loadingDialogCtx != null && loadingDialogCtx!.mounted && Navigator.canPop(loadingDialogCtx!)) {
        Navigator.pop(loadingDialogCtx!);
      }
      if (!mounted) return;
      final fallbackGuide = "# Study Guide: ${set.title}\n\n"
          "## Overview & Key Concepts\n"
          "${set.description != null && set.description!.trim().isNotEmpty ? set.description! : _cleanDescription(set.description)}\n\n"
          "## Active Recall Practice Questions\n"
          "1. **What is the core definition and purpose of ${set.title}?**\n"
          "2. **How are the key principles of ${set.title} applied in real-world scenarios?**\n"
          "3. **What are the top takeaways to remember for your upcoming exam?**";
      PdfStudyGuideViewerModal.show(
        context,
        title: set.title,
        content: fallbackGuide,
        sourceType: "Printable PDF Study Guide (Offline Ready)",
        onGenerateQuiz: () => _startQuiz(set),
      );
    }
  }

  Future<void> _startQuiz(StudySetModel set, {int? mode, int? count}) async {
    final effectiveMode = mode ?? _settingsService.settings.preferredStudyMode;
    final effectiveCount = count ?? _settingsService.settings.defaultQuestionCount;

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

    List<QuestionModel> questions = [];
    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/practice/studysets/${set.id}/questions",
        queryParameters: {"mode": effectiveMode, "count": effectiveCount},
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
                            Text(
                              cs.stageBadgeText,
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
                                          Text(
                                            'Elementary Learner (Grades 1–6)',
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
                                        'Simplified vocabulary, cheerful hints, audio read-aloud & DSWD 20-20-20 pediatric eye breaks.',
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
                                          Text(
                                            'Junior High School (Grades 7–10)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          ),
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
                                        'Structured concept building, foundational formulas, balanced practice quizzes & exam preparation.',
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
                                          Text(
                                            'Senior High School (Grades 11–12)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                          ),
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
                                        'Specialized academic tracks (STEM, ABM, HUMSS, TVL), college entrance exam readiness & deep drills.',
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
                                      Text(
                                        'College / University',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: context.textPrimary,
                                        ),
                                      ),
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
                                    'Collegiate academic curriculum, GWA grade tracking, advanced AI lectures & comprehensive question taxonomy.',
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

  Widget _buildQuickFeatureChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUniversalSearchAndQuickHub(bool isDark) {
    final qLower = _universalSearchQuery.toLowerCase();
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
        // Google-Standard Universal Search Bar (Seth AI + Web + Local Workspace)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF2E7D5B).withValues(alpha: 0.45),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.travel_explore_rounded, color: Color(0xFF2E7D5B), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _universalSearchController,
                  onSubmitted: (_) => _executeUniversalSearch(),
                  style: TextStyle(fontSize: 13.5, color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: "Search Google + Seth AI + all courses, study sets & flashcards...",
                    hintStyle: TextStyle(fontSize: 12.5, color: context.textSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_universalSearchController.text.isNotEmpty || _universalSearchQuery.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
                  tooltip: "Clear search",
                  onPressed: () {
                    _universalSearchController.clear();
                    setState(() {
                      _universalSearchQuery = "";
                      _universalSearchResult = null;
                      _isSearchingUniversal = false;
                    });
                  },
                ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D5B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                onPressed: _isSearchingUniversal ? null : () => _executeUniversalSearch(),
                icon: _isSearchingUniversal
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search_rounded, size: 16),
                label: Text(
                  _isSearchingUniversal ? "..." : "Search",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Quick Feature Action Pills (Mobile-Friendly Wrap)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickFeatureChip(
              icon: Icons.auto_awesome_rounded,
              label: "Seth AI Search",
              color: const Color(0xFF2E7D5B),
              isDark: isDark,
              onTap: () => setState(() => _currentTabIndex = 3),
            ),
            _buildQuickFeatureChip(
              icon: Icons.edit_note_rounded,
              label: "Easy Maker & Corrector",
              color: const Color(0xFF0D9488),
              isDark: isDark,
              onTap: () => EasyWritingStudioModal.show(
                context,
                apiClient: widget.apiClient,
              ),
            ),
            _buildQuickFeatureChip(
              icon: Icons.calendar_month_rounded,
              label: "Study Planner",
              color: const Color(0xFF3B82F6),
              isDark: isDark,
              onTap: _openAcademicPlannerModal,
            ),
            _buildQuickFeatureChip(
              icon: Icons.document_scanner_rounded,
              label: "Scan Screenshot / YouTube",
              color: const Color(0xFFD97706),
              isDark: isDark,
              onTap: () => _openAddMaterial(),
            ),
            _buildQuickFeatureChip(
              icon: Icons.android_rounded,
              label: "Download Android APK",
              color: const Color(0xFF16A34A),
              isDark: isDark,
              onTap: () => launchWebUrl("https://github.com/gsi78eywh/Study_App/raw/main/StudyApp-release.apk"),
            ),
          ],
        ),

        // Universal Search Results Panel (loads ALL local & web data like Google Search)
        if (_universalSearchQuery.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF2E7D5B).withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public_rounded, color: Color(0xFF2E7D5B), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "All Search Results for \"$_universalSearchQuery\"",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _currentTabIndex = 3),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                      label: const Text("Open in Seth AI", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const Divider(height: 18),

                // 1. Local Matching Study Sets
                if (matchingLocalSets.isNotEmpty) ...[
                  Text(
                    "📚 Matching Study Sets in Your Workspace (${matchingLocalSets.length})",
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF2E7D5B)),
                  ),
                  const SizedBox(height: 8),
                  ...matchingLocalSets.take(5).map((set) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.secondaryBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.cardBorderColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF2E7D5B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    set.title,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary),
                                  ),
                                  Text(
                                    "${set.questionCount} questions • ${_cleanDescription(set.description)}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D5B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: () => _startPracticeForSet(set),
                              child: const Text("Practice", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 10),
                ],

                // 2. Seth AI Google Search Overview
                if (_isSearchingUniversal)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: Color(0xFF2E7D5B)),
                          SizedBox(height: 10),
                          Text(
                            "Seth AI is searching Google-standard web sources & your workspace...",
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_universalSearchResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D5B).withValues(alpha: isDark ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E7D5B).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF2E7D5B)),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                "Seth AI • Google-Standard Direct Answer & Overview",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF2E7D5B)),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF2E7D5B)),
                              tooltip: "Copy answer",
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _universalSearchResult!.aiOverview));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Copied Seth AI overview to clipboard")),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _universalSearchResult!.aiOverview,
                          style: TextStyle(fontSize: 13, height: 1.5, color: context.textPrimary),
                        ),
                      ],
                    ),
                  ),

                  // 3. Verified Web & Encyclopedia Sources
                  if (_universalSearchResult!.webSources.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      "🌐 Verified Web & Reference Sources (${_universalSearchResult!.webSources.length})",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    ..._universalSearchResult!.webSources.map((src) => InkWell(
                          onTap: () {
                            PdfStudyGuideViewerModal.show(
                              context,
                              title: src.title,
                              content: src.snippet.isNotEmpty
                                  ? "## \n\n\n\n---\n\n"
                                  : _universalSearchResult!.aiOverview,
                              sourceType: "Direct In-App Knowledge Reader",
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.secondaryBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.cardBorderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.language_rounded, size: 15, color: Color(0xFF2E7D5B)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        src.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF2E7D5B),
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF2E7D5B)),
                                  ],
                                ),
                                if (src.snippet.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    src.snippet,
                                    style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.4),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )),
                  ],

                  // 4. Local Questions from Backend Search
                  if (_universalSearchResult!.localQuestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      "🎯 Matching Flashcards & Questions (${_universalSearchResult!.localQuestions.length})",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    ..._universalSearchResult!.localQuestions.take(5).map((q) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.secondaryBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.cardBorderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (q["prompt"] ?? "").toString(),
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: context.textPrimary),
                              ),
                              if ((q["explanation"] ?? "").toString().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  "Answer: ${q["explanation"]}",
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF2E7D5B), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        )),
                  ],
                ],
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
                        const SizedBox(height: 4),
                        Text(
                          _courses.isEmpty
                              ? "Powered by Seth AI (Google Search Mode) • Online & Offline Ready"
                              : (_courses.length == 1
                                  ? "Targeting mastery across 1 course • Seth AI Active"
                                  : "Targeting mastery across ${_courses.length} courses • Seth AI Active"),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
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

              // Child Safety & Learner Mode Bar
              _buildChildSafetyBanner(context),
              const SizedBox(height: 16),

              // First-Run Checklist for New Users (add course -> add material -> generate set -> first quiz)
              if (isFirstRun) ...[
                _buildFirstRunChecklist(isDark, totalSets, hasCompletedQuiz),
                const SizedBox(height: 16),
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
                    if (step.stepNumber == 1) {
                      setState(() => _currentTabIndex = 1);
                    } else if (step.stepNumber == 4) {
                      setState(() => _currentTabIndex = 3);
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

  Widget _buildFirstRunChecklist(bool isDark, int totalSets, bool hasCompletedQuiz) {
    final hasCourse = _courses.isNotEmpty;
    final hasMaterial = totalSets > 0;
    final hasGeneratedSet = totalSets > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.checklist_rounded, color: Color(0xFF6366F1), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "First-Run Setup Checklist",
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Complete these quick steps to build your connected study loop:",
            style: TextStyle(fontSize: 12.5, color: context.textSecondary),
          ),
          const SizedBox(height: 16),

          _buildChecklistItem(
            stepNumber: 1,
            title: "Add your first course",
            description: "Organize notes and exams by subject (e.g. CS-101, Bio 101)",
            isDone: hasCourse,
            actionLabel: "Add Course",
            onTap: _showAddCourseDialog,
          ),
          const Divider(height: 20),
          _buildChecklistItem(
            stepNumber: 2,
            title: "Add study material",
            description: "Paste notes, upload PDF, or scan textbook photos",
            isDone: hasMaterial,
            actionLabel: "Add Material",
            onTap: () => _openAddMaterial(),
          ),
          const Divider(height: 20),
          _buildChecklistItem(
            stepNumber: 3,
            title: "Generate study set & flashcards",
            description: "Review your extracted material, then generate practice questions.",
            isDone: hasGeneratedSet,
            actionLabel: "Generate",
            onTap: () => _openAddMaterial(),
          ),
          const Divider(height: 20),
          _buildChecklistItem(
            stepNumber: 4,
            title: "Take your first practice quiz",
            description: "Active retrieval updates your Mistake Bank & spaced review",
            isDone: hasCompletedQuiz,
            actionLabel: hasGeneratedSet ? "Start Quiz" : "Add Material",
            onTap: hasGeneratedSet
                ? () => setState(() => _currentTabIndex = 1)
                : _openAddMaterial,
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required int stepNumber,
    required String title,
    required String description,
    required bool isDone,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isDone ? const Color(0xFF10B981) : Colors.transparent,
            border: Border.all(
              color: isDone ? const Color(0xFF10B981) : context.cardBorderColor,
              width: 1.5,
            ),
            shape: BoxShape.circle,
          ),
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Center(
                  child: Text(
                    "$stepNumber",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textSecondary),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone ? context.textSecondary : context.textPrimary,
                ),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: const Color(0xFF6366F1),
          ),
          child: Text(isDone ? "Review" : actionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
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
                                    "No study sets yet. Add study material to create your first set.",
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
                          Text("Track assignments, prelims, midterms, and finals with target GPA", style: TextStyle(fontSize: 12, color: context.textSecondary)),
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
                          Text("Study pacing, dark/light theme, audio voice read-aloud & notifications", style: TextStyle(fontSize: 12, color: context.textSecondary)),
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
                              Text("Review data handling before uploading personal documents.", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text("Avoid uploading documents with sensitive personal information. Study material may be sent to the configured AI service when you request extraction, tutoring, or question generation.", style: TextStyle(fontSize: 11.5, height: 1.5, color: context.textSecondary)),
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
      (Icons.auto_awesome_rounded, "Seth AI", 3),
      (Icons.person_rounded, "Profile", 4),
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
                        "Seth AI • Study Workspace",
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
              onPressed: () => EasyWritingStudioModal.show(
                context,
                apiClient: widget.apiClient,
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text(
                "Easy Maker & Corrector",
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
                    onOpenAiTutor: () => setState(() => _currentTabIndex = 3),
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
                // Tab 3: Seth AI (Google Search AI Mode + Easy Maker & Corrector)
                _lazy(3, () => AiTutorScreen(apiClient: widget.apiClient, courses: _courses)),
                // Tab 4: Profile (Grades, Settings, Privacy & NPC DPA Compliance, Account)
                _lazy(4, () => _buildProfileTab()),
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
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: "Seth AI",
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.person_rounded),
                    label: "Profile",
                  ),
                ],
              ),
            ),
      floatingActionButton: _currentTabIndex == 3
          ? null
          : FloatingActionButton.extended(
              heroTag: 'dashboard_fab_add_material',
              onPressed: () => _openAddMaterial(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                "Add Material",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
    );
  } 
}

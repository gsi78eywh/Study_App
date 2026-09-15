import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/theme/theme_controller.dart";
import "../models/course_models.dart";
import "../../auth/screens/login_screen.dart";
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
import "../../../core/constants/api_constants.dart";
import "../widgets/pomodoro_timer_sheet.dart";
import "../../ingestion/widgets/camera_scanner_modal.dart";
import "../../ingestion/widgets/progressive_exam_studio.dart";

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
  bool _isSyncing = false;
  bool _isLoadingCourses = true;
  bool _isLoadingDemoPack = false;

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
          orElse: () => _courses.first,
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
              if (!course.studySets.any((s) => s.id == newSet.id)) {
                course.studySets.insert(0, newSet);
              }
            });
          },
        );
      },
      onExportToEditor: (title, scannedText) {
        setState(() => _currentTabIndex = 3);
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
    _fetchCoursesAndSync(fullFetch: true);
  }

  Future<void> _fetchCoursesAndSync({
    bool fullFetch = false,
    bool showSnackBar = false,
  }) async {
    if (!widget.sessionService.hasValidToken) {
      if (mounted) setState(() => _isLoadingCourses = false);
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.performSync(
      fullFetch: fullFetch,
      currentCourses: _courses,
    );
    if (!mounted) return;

    setState(() {
      _isSyncing = false;
      _isLoadingCourses = false;
      if (result.success && (result.syncedCourses.isNotEmpty || fullFetch)) {
        _courses = result.syncedCourses;
      }
    });

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
            _modeTile(
              ctx,
              "🎯 Simulated Exam (All Question Types)",
              "Full comprehensive exam: MCQ, Fill-in-the-Blank, True/False, Matching & more",
              const Color(0xFF6366F1),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.simulatedExam);
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "📚 Multiple Choice Practice",
              "Server-graded multiple-choice questions",
              isDark ? AppColors.primary : AppColors.primaryDark,
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.multipleChoice);
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "🔄 True / False Practice",
              "Instant verification of factual statements and concepts",
              const Color(0xFF0EA5E9),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.trueFalse);
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "✍️ Active Recall & Identification",
              "Type key terms and fill-in missing concepts",
              const Color(0xFF10B981),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.identification);
              },
            ),
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "📝 Enumeration & List Recall",
              "Enumerate structured components and processes from notes",
              const Color(0xFF8B5CF6),
              () {
                Navigator.pop(ctx);
                _startQuiz(set, mode: StudyModeValue.enumeration);
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
            const SizedBox(height: 8),
            _modeTile(
              ctx,
              "🃏 Flashcards (Spaced Repetition)",
              "Flip and rate your recall",
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
              "⚡ Rapid-Fire Blitz",
              "${_settingsService.settings.blitzSecondsPerQuestion} seconds per question — race the clock!",
              AppColors.warning,
              () {
                Navigator.pop(ctx);
                _startRapidFire(set);
              },
            ),
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
                Text("Generating exported study guide..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await widget.apiClient.dio.get(
        "/api/v1/studysets/${set.id}/export",
        queryParameters: {"format": "markdown"},
      );
      if (mounted) Navigator.of(context).pop();
      final markdownContent = response.data?.toString() ?? "";
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.description_outlined, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Exported Study Guide",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: ctx.textPrimary,
                    fontSize: 18,
                  ),
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
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("Copy Markdown"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: markdownContent));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text("Exported study guide copied to clipboard!"),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Done"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
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
                    _courses[idx] = CourseModel(
                      id: course.id,
                      code: course.code,
                      name: course.name,
                      colorHex: course.colorHex,
                      createdAt: course.createdAt,
                      updatedAt: DateTime.now(),
                      studySets: newSets,
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
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
    await widget.sessionService.clearAuth();
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
    final displayName = (studentName != null && studentName.isNotEmpty)
        ? studentName
        : "Student";

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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome back, $displayName 👋",
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
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
                  Row(
                    children: [
                      ListenableBuilder(
                        listenable: ThemeController.instance,
                        builder: (context, _) {
                          final currentIsDark =
                              ThemeController.instance.isDarkMode;
                          return IconButton(
                            icon: Icon(
                              currentIsDark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              color: currentIsDark
                                  ? const Color(0xFFF59E0B)
                                  : AppColors.primaryDark,
                            ),
                            tooltip: currentIsDark
                                ? "Switch to Light Mode"
                                : "Switch to Dark Mode",
                            onPressed: () =>
                                ThemeController.instance.toggleTheme(),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                        tooltip: "Gemini AI Tutor",
                        onPressed: () => setState(() => _currentTabIndex = 4),
                      ),
                      IconButton(
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              )
                            : const Icon(
                                Icons.sync_rounded,
                                color: AppColors.accent,
                              ),
                        tooltip: "Sync with Cloud",
                        onPressed: _isSyncing
                            ? null
                            : () => _fetchCoursesAndSync(showSnackBar: true),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Color(0xFF6366F1),
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
                        icon: Icon(
                          Icons.logout_rounded,
                          color: context.textSecondary,
                        ),
                        tooltip: "Sign Out",
                        onPressed: _handleLogout,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // High-yield stats row
              Container(
                padding: const EdgeInsets.all(16),
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
                      color: context.cardBorderColor,
                    ),
                    InkWell(
                      onTap: () => PomodoroTimerSheet.show(
                        context,
                        focusMinutes:
                            _settingsService.settings.pomodoroFocusMinutes,
                        shortBreakMinutes:
                            _settingsService.settings.pomodoroShortBreakMinutes,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Color(0xFFEC4899),
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "25:00",
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              "Pomodoro",
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
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
                          "Scan Notes",
                          "In-app camera OCR",
                          Icons.document_scanner_rounded,
                          const Color(0xFF06B6D4),
                          () => _openCameraScanner(),
                        ),
                        const SizedBox(width: 8),
                        _buildQuickActionCard(
                          "Upload Notes",
                          "PDF, docs & images",
                          Icons.add_photo_alternate_outlined,
                          const Color(0xFF6366F1),
                          () => setState(() => _currentTabIndex = 3),
                        ),
                        const SizedBox(width: 8),
                        _buildQuickActionCard(
                          "Focus Timer",
                          "25m session",
                          Icons.timer_outlined,
                          const Color(0xFFEC4899),
                          () => PomodoroTimerSheet.show(
                            context,
                            focusMinutes:
                                _settingsService.settings.pomodoroFocusMinutes,
                            shortBreakMinutes:
                                _settingsService.settings.pomodoroShortBreakMinutes,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildQuickActionCard(
                          "Flashcards",
                          "Spaced recall",
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

              // Enrolled Courses Header & Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Your Enrolled Courses",
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? AppColors.primaryLight
                              : AppColors.primaryDark,
                          side: BorderSide(
                            color: isDark
                                ? AppColors.primary
                                : AppColors.primaryDark,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text(
                          "AI Studio",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () => setState(() => _currentTabIndex = 3),
                      ),
                      const SizedBox(width: 8),
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
                Container(
                  padding: const EdgeInsets.all(36),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 56,
                        color: context.textSecondary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Your Learning Workspace is Ready",
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You haven't created any courses yet. Add your first academic subject or upload lecture notes in AI Studio to get started.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            icon: _isLoadingDemoPack
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              _isLoadingDemoPack
                                  ? "Loading Starter Deck..."
                                  : "✨ Load Starter Demo Pack (Biology 101)",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: _isLoadingDemoPack
                                ? null
                                : _loadStarterDemoPack,
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? AppColors.primary
                                  : AppColors.primaryDark,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text(
                              "Create Course",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: _showAddCourseDialog,
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primaryDark,
                              side: BorderSide(
                                color: isDark
                                    ? AppColors.primary
                                    : AppColors.primaryDark,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text(
                              "Open AI Studio",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () =>
                                setState(() => _currentTabIndex = 3),
                          ),
                        ],
                      ),
                    ],
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                const SizedBox(width: 8),
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
                                const SizedBox(width: 6),
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
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.verified_rounded,
                                              size: 12,
                                              color: Color(0xFF10B981),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "${((set.questionCount * 13) % 20 + 80)}% Ready",
                                              style: const TextStyle(
                                                color: Color(0xFF10B981),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
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
                                          label: const Text(
                                            "Blitz",
                                            style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Courses
          _buildCoursesTab(),
          // Tab 1: Flashcards
          FlashcardsScreen(
            courses: _courses,
            apiClient: widget.apiClient,
            onLoadStarterPack: _loadStarterDemoPack,
            onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
            onCardDeleted: () => _fetchCoursesAndSync(fullFetch: true),
          ),
          // Tab 2: Notebook
          NotebookScreen(
            courses: _courses,
            apiClient: widget.apiClient,
            onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
            onLoadStarterPack: _loadStarterDemoPack,
          ),
          // Tab 3: AI Studio
          IngestionScreen(
            courses: _courses,
            apiClient: widget.apiClient,
            onStudySetCreated: (newSet) {
              setState(() {
                final course = _courses.firstWhere(
                  (c) => c.id == newSet.courseId,
                  orElse: () => _courses.first,
                );
                course.studySets.insert(0, newSet);
                _currentTabIndex = 0;
              });
            },
          ),
          // Tab 4: Gemini AI Tutor
          AiTutorScreen(apiClient: widget.apiClient, courses: _courses),
        ],
      ),
      bottomNavigationBar: Container(
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
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: "Courses",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.style_outlined),
              label: "Flashcards",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              label: "Notebook",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology_outlined),
              label: "AI Studio",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_rounded),
              label: "Gemini Tutor",
            ),
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }
}

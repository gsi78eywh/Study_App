import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:uuid/uuid.dart";
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
import "../../sync/services/sync_service.dart";
import "../../ai_tutor/screens/ai_tutor_screen.dart";
import "../../../core/constants/api_constants.dart";
import "../widgets/pomodoro_timer_sheet.dart";

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
              content: Text("✨ Starter Demo Pack loaded! Explore your new Biology 101 flashcards & quizzes."),
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

  Widget _buildWorkflowStep(String title, String desc, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.cardBorderColor),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF6366F1)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(desc, style: TextStyle(color: context.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _syncService = SyncService(
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
    );
    _fetchCoursesAndSync(fullFetch: true);
  }

  Future<void> _fetchCoursesAndSync({bool fullFetch = false, bool showSnackBar = false}) async {
    if (!widget.sessionService.hasValidToken) {
      if (mounted) setState(() => _isLoadingCourses = false);
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.performSync(
      localCourses: _courses,
      fullFetch: fullFetch,
    );
    if (!mounted) return;

    setState(() {
      _isSyncing = false;
      _isLoadingCourses = false;
      if (result.success && result.syncedCourses.isNotEmpty) {
        _courses = result.syncedCourses;
      }
    });

    if (result.message.contains("401") || result.message.toLowerCase().contains("unauthorized")) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Create New Course", style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                style: TextStyle(color: ctx.textPrimary),
                decoration: const InputDecoration(labelText: "Course Code", hintText: "e.g. CS204"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: TextStyle(color: ctx.textPrimary),
                decoration: const InputDecoration(labelText: "Course Name", hintText: "e.g. Algorithms & Data Structures"),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text("Accent: ", style: TextStyle(color: ctx.textSecondary)),
                  ...["#6366F1", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#06B6D4"].map((hex) {
                    final color = Color(int.parse("FF${hex.replaceAll('#', '')}", radix: 16));
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
                            color: selectedColor == hex ? (ctx.isDarkMode ? Colors.white : Colors.black87) : Colors.transparent,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final name = nameController.text.trim();
                if (code.isEmpty || name.isEmpty) return;

                final newCourse = CourseModel(
                  id: const Uuid().v4(),
                  code: code,
                  name: name,
                  colorHex: selectedColor,
                  createdAt: DateTime.now(),
                  studySets: [],
                );

                setState(() {
                  _courses.add(newCourse);
                });
                Navigator.pop(ctx);
                await _syncService.performSync(localCourses: _courses);
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  void _startQuiz(StudySetModel set) {
    final questions = [
      QuestionModel(
        id: "q1",
        studySetId: set.id,
        type: QuestionTypeEnum.multipleChoice,
        prompt: "Review question for: ${set.title}",
        hints: const ["Recall the core concept introduced in this module."],
        explanation: set.description ?? "Active recall practice session.",
        options: [
          QuestionOptionModel(id: "o1", optionText: "Primary verified answer concept", isCorrect: true),
          QuestionOptionModel(id: "o2", optionText: "Secondary distractor alternative", isCorrect: false),
          QuestionOptionModel(id: "o3", optionText: "Tertiary non-applicable option", isCorrect: false),
          QuestionOptionModel(id: "o4", optionText: "Quaternary inverted hypothesis", isCorrect: false),
        ],
      ),
    ];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPlayerScreen(
          studySet: set,
          questions: questions,
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
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
    final totalSets = _courses.fold<int>(0, (sum, c) => sum + c.studySets.length);
    final totalQuestions = _courses.fold<int>(
      0,
      (sum, c) => sum + c.studySets.fold<int>(0, (s, set) => s + set.questionCount),
    );
    final studentName = widget.sessionService.fullName?.trim();
    final displayName = (studentName != null && studentName.isNotEmpty) ? studentName : "Student";

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
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _courses.isEmpty
                          ? "Ready to organize your study workspace"
                          : "Targeting mastery across ${_courses.length} courses",
                      style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  ListenableBuilder(
                    listenable: ThemeController.instance,
                    builder: (context, _) {
                      final currentIsDark = ThemeController.instance.isDarkMode;
                      return IconButton(
                        icon: Icon(
                          currentIsDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                          color: currentIsDark ? const Color(0xFFF59E0B) : AppColors.primaryDark,
                        ),
                        tooltip: currentIsDark ? "Switch to Light Mode" : "Switch to Dark Mode",
                        onPressed: () => ThemeController.instance.toggleTheme(),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6)),
                    tooltip: "Gemini AI Tutor",
                    onPressed: () => setState(() => _currentTabIndex = 4),
                  ),
                  IconButton(
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.sync_rounded, color: AppColors.accent),
                    tooltip: "Sync with Cloud",
                    onPressed: _isSyncing ? null : () => _fetchCoursesAndSync(showSnackBar: true),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout_rounded, color: context.textSecondary),
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
                _buildStatItem("Enrolled", "${_courses.length}", "Courses", Icons.book_rounded, isDark ? AppColors.primaryLight : AppColors.primaryDark),
                Container(height: 36, width: 1, color: context.cardBorderColor),
                _buildStatItem("Active Sets", "$totalSets", "Study Sets", Icons.auto_stories_rounded, AppColors.accent),
                Container(height: 36, width: 1, color: context.cardBorderColor),
                _buildStatItem("Synthesized", "$totalQuestions", "Questions", Icons.psychology_rounded, AppColors.warning),
                Container(height: 36, width: 1, color: context.cardBorderColor),
                InkWell(
                  onTap: () => PomodoroTimerSheet.show(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      children: [
                        const Icon(Icons.timer_outlined, color: Color(0xFFEC4899), size: 20),
                        const SizedBox(height: 4),
                        Text("25:00", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
                        Text("Pomodoro", style: TextStyle(color: context.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3-Step Active Recall Workflow Guide
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.secondaryBg,
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
                        const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "Active Recall Study Workflow",
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      "Instant & Offline-Ready",
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildWorkflowStep(
                        "1. Ingest",
                        "Photos, PDFs, notes",
                        Icons.camera_alt_outlined,
                        () => setState(() => _currentTabIndex = 3),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
                    ),
                    Expanded(
                      child: _buildWorkflowStep(
                        "2. Synthesize",
                        "Cards & drills",
                        Icons.psychology_outlined,
                        () => setState(() => _currentTabIndex = 3),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
                    ),
                    Expanded(
                      child: _buildWorkflowStep(
                        "3. Master",
                        "Spaced practice",
                        Icons.style_outlined,
                        () => setState(() => _currentTabIndex = 1),
                      ),
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
              Text("Your Enrolled Courses", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                      side: BorderSide(color: isDark ? AppColors.primary : AppColors.primaryDark),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text("AI Studio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => setState(() => _currentTabIndex = 3),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text("New Course", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                child: CircularProgressIndicator(color: isDark ? AppColors.primaryLight : AppColors.primaryDark),
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
                  Icon(Icons.school_outlined, size: 56, color: context.textSecondary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  Text(
                    "Your Learning Workspace is Ready",
                    style: GoogleFonts.outfit(fontSize: 18, color: context.textPrimary, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You haven't created any courses yet. Add your first academic subject or upload lecture notes in AI Studio to get started.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
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
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        icon: _isLoadingDemoPack
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(
                          _isLoadingDemoPack ? "Loading Starter Deck..." : "✨ Load Starter Demo Pack (Biology 101)",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _isLoadingDemoPack ? null : _loadStarterDemoPack,
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text("Create Course", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _showAddCourseDialog,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                          side: BorderSide(color: isDark ? AppColors.primary : AppColors.primaryDark),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text("Open AI Studio", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => setState(() => _currentTabIndex = 3),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ..._courses.map((course) {
              final courseColor = Color(int.parse("FF${course.colorHex.replaceAll('#', '')}", radix: 16));

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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: courseColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: courseColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            course.code,
                            style: TextStyle(color: courseColor, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            course.name,
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: context.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.secondaryBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "${course.studySets.length} sets",
                            style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
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
                            const Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "No study sets yet. Ingest notes or lecture slides using AI Studio.",
                                style: TextStyle(color: context.textSecondary, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _currentTabIndex = 3),
                              child: const Text("Ingest Now"),
                            ),
                          ],
                        ),
                      )
                    else
                      ...course.studySets.map((set) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.secondaryBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.cardBorderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      set.title,
                                      style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${set.questionCount} Questions",
                                      style: TextStyle(
                                        color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (set.description != null && set.description!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  set.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: context.textSecondary,
                                      side: BorderSide(color: context.cardBorderColor),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.style_outlined, size: 16),
                                    label: const Text("Flashcards", style: TextStyle(fontSize: 12)),
                                    onPressed: () => setState(() => _currentTabIndex = 1),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                    label: const Text("Start Practice"),
                                    onPressed: () => _startQuiz(set),
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

  Widget _buildStatItem(String label, String value, String sub, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
        Text(label, style: TextStyle(color: context.textSecondary, fontSize: 11)),
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
            onLoadStarterPack: _loadStarterDemoPack,
            onNavigateToStudio: () => setState(() => _currentTabIndex = 3),
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
          AiTutorScreen(
            apiClient: widget.apiClient,
            courses: _courses,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          border: Border(top: BorderSide(color: context.cardBorderColor, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
          unselectedItemColor: context.textSecondary,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _currentTabIndex = 4),
              backgroundColor: const Color(0xFF6366F1),
              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              label: Text(
                "Ask Gemini",
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

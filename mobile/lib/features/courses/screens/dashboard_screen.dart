import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:uuid/uuid.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../models/course_models.dart";
import "../../auth/screens/login_screen.dart";
import "../../flashcards/screens/flashcards_screen.dart";
import "../../ingestion/screens/ingestion_screen.dart";
import "../../notebook/screens/notebook_screen.dart";
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/quiz_player_screen.dart";
import "../../sync/services/sync_service.dart";

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

  @override
  void initState() {
    super.initState();
    _syncService = SyncService(
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
    );
    _initializeDefaultData();
    _runSync(showSnackBar: false);
  }

  void _initializeDefaultData() {
    _courses = [
      CourseModel(
        id: "c1111111-1111-1111-1111-111111111111",
        code: "CS301",
        name: "Distributed Systems & Cloud",
        colorHex: "#6366F1",
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        studySets: [
          StudySetModel(
            id: "s1111111-1111-1111-1111-111111111111",
            courseId: "c1111111-1111-1111-1111-111111111111",
            title: "CAP Theorem & Consensus Protocols",
            description: "Consistency, Availability, Partition Tolerance, Raft, Paxos, and Vector Clocks.",
            questionCount: 8,
            createdAt: DateTime.now().subtract(const Duration(days: 2)),
            bulletPoints: [
              "CAP Theorem states distributed data stores can only guarantee 2 of 3 properties.",
              "Raft uses leader election, log replication, and safety invariants for consensus.",
              "Vector clocks detect causal concurrent updates in distributed key-value stores.",
            ],
          ),
        ],
      ),
      CourseModel(
        id: "c2222222-2222-2222-2222-222222222222",
        code: "BIO102",
        name: "Molecular Genetics & Cellular Biology",
        colorHex: "#10B981",
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        studySets: [
          StudySetModel(
            id: "s2222222-2222-2222-2222-222222222222",
            courseId: "c2222222-2222-2222-2222-222222222222",
            title: "DNA Replication & Transcription",
            description: "Polymerase enzymes, leading/lagging strand synthesis, Okazaki fragments, mRNA processing.",
            questionCount: 6,
            createdAt: DateTime.now().subtract(const Duration(days: 3)),
            bulletPoints: [
              "DNA Polymerase III synthesizes the leading strand continuously 5 prime to 3 prime.",
              "Okazaki fragments on the lagging strand are joined by DNA Ligase.",
              "RNA Splicing removes non-coding introns and connects coding exons.",
            ],
          ),
        ],
      ),
      CourseModel(
        id: "c3333333-3333-3333-3333-333333333333",
        code: "MATH201",
        name: "Linear Algebra & Matrix Analysis",
        colorHex: "#F59E0B",
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
        studySets: [
          StudySetModel(
            id: "s3333333-3333-3333-3333-333333333333",
            courseId: "c3333333-3333-3333-3333-333333333333",
            title: "Eigenvalues, Eigenvectors & Diagonalization",
            description: "Characteristic polynomials, eigenspaces, matrix diagonalization, and Gram-Schmidt process.",
            questionCount: 7,
            createdAt: DateTime.now().subtract(const Duration(days: 4)),
            bulletPoints: [
              "Eigenvector equation Av = lambda v defines invariant directions under matrix transformation.",
              "An n x n matrix is diagonalizable if and only if it has n linearly independent eigenvectors.",
              "Gram-Schmidt transforms an arbitrary basis into an orthonormal basis.",
            ],
          ),
        ],
      ),
    ];
  }

  Future<void> _runSync({bool showSnackBar = false}) async {
    if (!widget.sessionService.hasValidToken) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please sign in to sync with cloud"),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.performSync(localCourses: _courses);
    if (!mounted) return;
    setState(() => _isSyncing = false);

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

    if (showSnackBar) {
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
          backgroundColor: AppColors.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Create New Course", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Course Code", hintText: "e.g. CS204"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Course Name", hintText: "e.g. Algorithms & Data Structures"),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text("Accent: ", style: TextStyle(color: AppColors.darkTextSecondary)),
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
                            color: selectedColor == hex ? Colors.white : Colors.transparent,
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
              onPressed: () {
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
                _runSync(showSnackBar: false);
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
        prompt: "What primary challenge does the CAP theorem address in distributed architecture?",
        hints: const ["Think about network partitions and consistency guarantees."],
        explanation: "The CAP theorem demonstrates that in the presence of a network partition (P), a distributed system must trade off between consistency (C) and availability (A).",
        options: [
          QuestionOptionModel(id: "o1", optionText: "Balancing consistency and availability during network partitions", isCorrect: true),
          QuestionOptionModel(id: "o2", optionText: "Optimizing disk storage for relational databases", isCorrect: false),
          QuestionOptionModel(id: "o3", optionText: "Preventing SQL injection vulnerabilities in web servers", isCorrect: false),
          QuestionOptionModel(id: "o4", optionText: "Minimizing client-side battery consumption", isCorrect: false),
        ],
      ),
      QuestionModel(
        id: "q2",
        studySetId: set.id,
        type: QuestionTypeEnum.multipleChoice,
        prompt: "Which enzyme is responsible for synthesizing leading strand DNA in prokaryotes?",
        hints: const ["It has proofreading capabilities in the 3' to 5' direction."],
        explanation: "DNA Polymerase III is the primary prokaryotic replicative enzyme synthesizing continuously 5' to 3'.",
        options: [
          QuestionOptionModel(id: "o21", optionText: "DNA Polymerase III", isCorrect: true),
          QuestionOptionModel(id: "o22", optionText: "RNA Primase", isCorrect: false),
          QuestionOptionModel(id: "o23", optionText: "DNA Topoisomerase", isCorrect: false),
          QuestionOptionModel(id: "o24", optionText: "Helicase", isCorrect: false),
        ],
      ),
      QuestionModel(
        id: "q3",
        studySetId: set.id,
        type: QuestionTypeEnum.identification,
        prompt: "Name the consensus algorithm designed as an understandable alternative to Paxos.",
        hints: const ["Decomposes consensus into leader election, log replication, and safety."],
        explanation: "Raft decomposes consensus into leader election, log replication, and safety.",
        options: [
          QuestionOptionModel(id: "o31", optionText: "Raft", isCorrect: true),
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
    final totalSets = _courses.fold<int>(0, (sum, c) => sum + c.studySets.length);
    final totalQuestions = _courses.fold<int>(
      0,
      (sum, c) => sum + c.studySets.fold<int>(0, (s, set) => s + set.questionCount),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      widget.sessionService.fullName != null ? "Welcome back, ${widget.sessionService.fullName} 👋" : "Welcome back, Alex 👋",
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Targeting mastery across ${_courses.length} courses",
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.darkTextSecondary),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.sync_rounded, color: AppColors.accent),
                    tooltip: "Sync with Cloud",
                    onPressed: _isSyncing ? null : () => _runSync(showSnackBar: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AppColors.darkTextSecondary),
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
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.darkCard,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("Enrolled", "${_courses.length}", "Courses", Icons.book_rounded, AppColors.primaryLight),
                Container(height: 36, width: 1, color: AppColors.darkCardBorder),
                _buildStatItem("Active Sets", "$totalSets", "Study Sets", Icons.auto_stories_rounded, AppColors.accent),
                Container(height: 36, width: 1, color: AppColors.darkCardBorder),
                _buildStatItem("Synthesized", "$totalQuestions", "Questions", Icons.psychology_rounded, AppColors.warning),
                Container(height: 36, width: 1, color: AppColors.darkCardBorder),
                _buildStatItem("Streak", "5 Days", "Active 🔥", Icons.local_fire_department_rounded, const Color(0xFFF97316)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Enrolled Courses Header & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Your Enrolled Courses", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: const BorderSide(color: AppColors.primary),
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
                      backgroundColor: AppColors.primary,
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

          if (_courses.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: const Text("No courses added yet. Tap '+ New Course' above.", style: TextStyle(color: AppColors.darkTextSecondary)),
            )
          else
            ..._courses.map((course) {
              final courseColor = Color(int.parse("FF${course.colorHex.replaceAll('#', '')}", radix: 16));

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.darkCardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: courseColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: courseColor.withValues(alpha: 0.6)),
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
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.darkBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "${course.studySets.length} study sets",
                            style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (course.studySets.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.darkBg.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "No study sets yet. Use AI Studio to synthesize questions from your lecture files.",
                                style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
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
                            color: AppColors.darkBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.darkCardBorder),
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
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${set.questionCount} Questions",
                                      style: const TextStyle(color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.bold),
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
                                  style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.darkTextSecondary,
                                      side: const BorderSide(color: AppColors.darkCardBorder),
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
                                      backgroundColor: AppColors.primary,
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
    );
  }

  Widget _buildStatItem(String label, String value, String sub, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Courses
          _buildCoursesTab(),
          // Tab 1: Flashcards
          FlashcardsScreen(courses: _courses),
          // Tab 2: Notebook
          NotebookScreen(courses: _courses, apiClient: widget.apiClient),
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
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          border: Border(top: BorderSide(color: AppColors.darkCardBorder, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primaryLight,
          unselectedItemColor: AppColors.darkTextSecondary,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              activeIcon: Icon(Icons.dashboard_rounded, color: AppColors.primaryLight),
              label: "Courses",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.style_outlined),
              activeIcon: Icon(Icons.style_rounded, color: AppColors.primaryLight),
              label: "Flashcards",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book_rounded, color: AppColors.primaryLight),
              label: "Notebook",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome, color: AppColors.primaryLight),
              label: "AI Studio",
            ),
          ],
        ),
      ),
    );
  }
}

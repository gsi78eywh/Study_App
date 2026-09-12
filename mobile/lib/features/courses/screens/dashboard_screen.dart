import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:uuid/uuid.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../models/course_models.dart";
import "../../auth/screens/login_screen.dart";
import "../../ingestion/screens/ingestion_screen.dart";
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
    _runSync();
  }

  void _initializeDefaultData() {
    // Provide sample high-yield courses ready for immediate study and test
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
    ];
  }

  Future<void> _runSync() async {
    setState(() => _isSyncing = true);
    final result = await _syncService.performSync(localCourses: _courses);
    if (!mounted) return;
    setState(() {
      _isSyncing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.accent : AppColors.danger,
        duration: const Duration(seconds: 2),
      ),
    );
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
                  ...["#6366F1", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6"].map((hex) {
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
                          border: selectedColor == hex ? Border.all(color: Colors.white, width: 2) : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                if (codeController.text.trim().isNotEmpty && nameController.text.trim().isNotEmpty) {
                  setState(() {
                    _courses.add(
                      CourseModel(
                        id: const Uuid().v4(),
                        code: codeController.text.trim().toUpperCase(),
                        name: nameController.text.trim(),
                        colorHex: selectedColor,
                        createdAt: DateTime.now(),
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                  _runSync();
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  void _startQuiz(StudySetModel studySet) {
    // Build question bank corresponding to study set
    final questions = [
      QuestionModel(
        id: const Uuid().v4(),
        studySetId: studySet.id,
        type: QuestionTypeEnum.multipleChoice,
        prompt: "Which of the following guarantees does the CAP Theorem state cannot be achieved simultaneously in a partition-prone network?",
        hints: [
          "Think about what 'CAP' stands for.",
          "Network partitions (P) are unavoidable in distributed systems.",
        ],
        explanation: "The CAP theorem states that a distributed data store can simultaneously guarantee at most two out of Consistency, Availability, and Partition Tolerance.",
        options: [
          QuestionOptionModel(id: "1", optionText: "Consistency and Availability", isCorrect: true),
          QuestionOptionModel(id: "2", optionText: "Latency and Throughput", isCorrect: false, distractorRationale: "Latency and throughput are performance metrics, not CAP theorem safety properties."),
          QuestionOptionModel(id: "3", optionText: "Scalability and Elasticity", isCorrect: false, distractorRationale: "Scalability refers to capacity growth, not atomic correctness."),
          QuestionOptionModel(id: "4", optionText: "Durability and Atomicity", isCorrect: false, distractorRationale: "Durability and Atomicity are ACID transactional properties."),
        ],
      ),
      QuestionModel(
        id: const Uuid().v4(),
        studySetId: studySet.id,
        type: QuestionTypeEnum.identification,
        prompt: "What consensus protocol breaks leadership into terms, leader election, and log replication?",
        hints: [
          "It was designed by Stanford researchers as an understandable alternative to Paxos.",
          "Starts with the letter 'R'.",
        ],
        explanation: "Raft is a consensus algorithm designed as an alternative to Multi-Paxos, structured around elected leader terms and log replication.",
        options: [
          QuestionOptionModel(id: "1", optionText: "Raft", isCorrect: true),
        ],
      ),
      QuestionModel(
        id: const Uuid().v4(),
        studySetId: studySet.id,
        type: QuestionTypeEnum.multipleChoice,
        prompt: "In DNA replication, which enzyme is primarily responsible for unwinding the double helix at the replication fork?",
        hints: [
          "It breaks hydrogen bonds between nitrogenous base pairs.",
          "Its name derives from 'helix'.",
        ],
        explanation: "DNA Helicase unwinds and separates the parental double-stranded DNA molecule into single strands ahead of replication.",
        options: [
          QuestionOptionModel(id: "1", optionText: "DNA Helicase", isCorrect: true),
          QuestionOptionModel(id: "2", optionText: "DNA Polymerase I", isCorrect: false, distractorRationale: "Polymerase I removes RNA primers and replaces them with DNA nucleotides."),
          QuestionOptionModel(id: "3", optionText: "DNA Ligase", isCorrect: false, distractorRationale: "DNA Ligase joins phosphodiester bonds between Okazaki fragments."),
          QuestionOptionModel(id: "4", optionText: "Topoisomerase", isCorrect: false, distractorRationale: "Topoisomerase relieves supercoiling tension ahead of the fork."),
        ],
      ),
    ];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPlayerScreen(
          studySet: studySet,
          questions: questions,
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.sessionService.fullName ?? "Scholar";

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("StudyApp Workspace", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
            Text("Welcome back, $userName", style: const TextStyle(fontSize: 12, color: AppColors.darkTextSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.sync_rounded, color: AppColors.accent),
            tooltip: "Sync with C# Backend",
            onPressed: _isSyncing ? null : _runSync,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.darkTextSecondary),
            tooltip: "Sign Out",
            onPressed: () async {
              await widget.sessionService.clear();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(
                    apiClient: widget.apiClient,
                    sessionService: widget.sessionService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text("AI Ingestion", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          final newSet = await Navigator.of(context).push<StudySetModel>(
            MaterialPageRoute(
              builder: (_) => IngestionScreen(
                courses: _courses,
                apiClient: widget.apiClient,
              ),
            ),
          );

          if (newSet != null) {
            setState(() {
              final target = _courses.firstWhere((c) => c.id == newSet.courseId, orElse: () => _courses.first);
              target.studySets.add(newSet);
            });
            _runSync();
          }
        },
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quick Study Stats Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.darkCard],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: AppColors.warning, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Active Recall Mode", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        const Text(
                          "Ready for today's review session across enrolled courses.",
                          style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Enrolled Courses Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Your Enrolled Courses", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("New Course"),
                  onPressed: _showAddCourseDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),

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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(16),
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
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${course.studySets.length} sets",
                            style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
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
                          child: const Row(
                            children: [
                              Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 20),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "No study sets in this course yet. Ingest notes or lecture slides using AI Ingestion.",
                                  style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...course.studySets.map((set) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.darkBg,
                              borderRadius: BorderRadius.circular(12),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
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
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                    label: const Text("Start Practice"),
                                    onPressed: () => _startQuiz(set),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}


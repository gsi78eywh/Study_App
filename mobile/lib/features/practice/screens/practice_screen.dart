import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../flashcards/screens/flashcards_screen.dart";
import "../../ingestion/services/local_pdf_extractor.dart";
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/mistake_bank_screen.dart";
import "../../quiz/screens/quiz_player_screen.dart";
import "../../quiz/screens/rapid_fire_screen.dart";
import "../../quiz/screens/smart_session_player_screen.dart";
import "../models/adaptive_models.dart";

class PracticeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;
  final List<CourseModel> courses;
  final TodayStudyPlanModel? studyPlan;
  final VoidCallback onRefresh;
  final VoidCallback onNavigateToStudio;

  const PracticeScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
    required this.courses,
    this.studyPlan,
    required this.onRefresh,
    required this.onNavigateToStudio,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  String? _selectedCourseId;

  List<StudySetModel> get _availableStudySets {
    if (widget.courses.isEmpty) return [];
    if (_selectedCourseId != null) {
      final c = widget.courses.firstWhere(
        (c) => c.id == _selectedCourseId,
        orElse: () => widget.courses.first,
      );
      return c.studySets;
    }
    return widget.courses.expand((c) => c.studySets).toList();
  }

  int get _totalPracticeQuestions {
    return _availableStudySets.fold(0, (acc, s) => acc + s.questionCount);
  }

  void _showReadinessFormulaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.calculate_rounded, color: Color(0xFF6366F1), size: 22),
            SizedBox(width: 8),
            Text("Readiness & Mastery Formula", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "How Your Readiness is Calculated:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text(
              "Readiness is the weighted average of available evidence: quiz accuracy (50%), flashcard retention (35%), and active-day consistency (15%). Missing quiz or flashcard data is excluded and the remaining weights are normalized. Subtract 1.5 points per unique question missed, then clamp the result to 0–100. No score is shown until an attempt exists.",
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              "Active-day consistency is min(active study days, 5) ÷ 5 × 100. Quiz accuracy, flashcard retention, active days, and missed questions use the selected course's recorded attempts. This version does not apply time decay yet.",
              style: TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  Future<List<QuestionModel>> _resolveQuestionsForSet(StudySetModel set) async {
    if (!set.id.startsWith("local_")) {
      try {
        final res = await widget.apiClient.dio
            .get('/api/v1/studysets/${set.id}/questions')
            .timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200 && res.data is List) {
          final parsed = (res.data as List)
              .map((q) => QuestionModel.fromJson(q as Map<String, dynamic>))
              .toList();
          if (parsed.isNotEmpty) {
            LocalExamSynthesizer.registerQuestions(set.id, parsed);
            return parsed;
          }
        }
      } catch (e) {
        debugPrint("Fallback to local exam synthesizer for set ${set.id}: $e");
      }
    }
    return LocalExamSynthesizer.getQuestionsForSet(set);
  }

  void _showSessionCompositionModal({
    required StudySetModel set,
    required String modeTitle,
    required String modeDescription,
    required ValueChanged<List<QuestionModel>> onProceed,
  }) async {
    BuildContext? loadingDialogCtx;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        loadingDialogCtx = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    final questions = await _resolveQuestionsForSet(set);
    if (loadingDialogCtx != null &&
        loadingDialogCtx!.mounted &&
        Navigator.of(loadingDialogCtx!).canPop()) {
      Navigator.of(loadingDialogCtx!).pop();
    }
    if (!mounted) return;

    if (questions.isEmpty) {
      _showNoQuestionsDialog();
      return;
    }

    final mcCount = questions.where((q) => q.type == QuestionTypeEnum.multipleChoice || q.type == QuestionTypeEnum.scenario).length;
    final tfCount = questions.where((q) => q.type == QuestionTypeEnum.trueFalse).length;
    final idCount = questions.where((q) => q.type == QuestionTypeEnum.identification || q.type == QuestionTypeEnum.cloze).length;
    final otherCount = questions.length - (mcCount + tfCount + idCount);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  modeTitle,
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "${set.title} • $modeDescription",
              style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Session Composition:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Total Practice Questions:"),
                      Text("${questions.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (mcCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("• Multiple Choice:"),
                        Text("$mcCount", style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  if (tfCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("• True / False:"),
                        Text("$tfCount", style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  if (idCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("• Identification / Recall:"),
                        Text("$idCount", style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  if (otherCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("• Short Answer / Other:"),
                        Text("$otherCount", style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                onProceed(questions);
              },
              child: const Text("Start Practice Session", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  void _startSmartQuizSession() {
    final setsWithQuestions = _availableStudySets.where((s) => s.questionCount > 0).toList();
    if (setsWithQuestions.isEmpty) {
      _showNoQuestionsDialog();
      return;
    }

    final targetSet = setsWithQuestions.first;
    _showSessionCompositionModal(
      set: targetSet,
      modeTitle: "Smart Adaptive Practice",
      modeDescription: "Adapts to your recent mistakes and memory curve",
      onProceed: (_) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SmartSessionPlayerScreen(
              apiClient: widget.apiClient,
              initialCourseId: targetSet.courseId,
              onSessionComplete: widget.onRefresh,
            ),
          ),
        ).then((_) => widget.onRefresh());
      },
    );
  }

  void _startStandardQuiz() {
    final setsWithQuestions = _availableStudySets.where((s) => s.questionCount > 0).toList();
    if (setsWithQuestions.isEmpty) {
      _showNoQuestionsDialog();
      return;
    }

    final targetSet = setsWithQuestions.first;
    _showSessionCompositionModal(
      set: targetSet,
      modeTitle: "Standard Quiz",
      modeDescription: "Complete test run with instant explanation and review",
      onProceed: (questions) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuizPlayerScreen(
              studySet: targetSet,
              questions: questions,
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        ).then((_) => widget.onRefresh());
      },
    );
  }

  void _startFlashcards() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashcardsScreen(
          courses: widget.courses,
          apiClient: widget.apiClient,
          onNavigateToStudio: widget.onNavigateToStudio,
          onCardDeleted: widget.onRefresh,
        ),
      ),
    ).then((_) => widget.onRefresh());
  }

  void _startRapidFireBlitz() {
    final setsWithQuestions = _availableStudySets.where((s) => s.questionCount > 0).toList();
    if (setsWithQuestions.isEmpty) {
      _showNoQuestionsDialog();
      return;
    }

    final targetSet = setsWithQuestions.first;
    _showSessionCompositionModal(
      set: targetSet,
      modeTitle: "Rapid-Fire Blitz",
      modeDescription: "Faster, fewer questions (60-second speed drills)",
      onProceed: (questions) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RapidFireScreen(
              studySet: targetSet,
              questions: questions,
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        ).then((_) => widget.onRefresh());
      },
    );
  }

  void _openMistakeBank() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MistakeBankScreen(
          apiClient: widget.apiClient,
          initialCourseId: _selectedCourseId,
          onMistakesChanged: widget.onRefresh,
        ),
      ),
    ).then((_) => widget.onRefresh());
  }

  void _startSimulatedExam() {
    final setsWithQuestions = _availableStudySets.where((s) => s.questionCount > 0).toList();
    if (setsWithQuestions.isEmpty) {
      _showNoQuestionsDialog();
      return;
    }

    final targetSet = setsWithQuestions.first;
    _showSessionCompositionModal(
      set: targetSet,
      modeTitle: "Simulated Exam",
      modeDescription: "Simulates full timed exam conditions without hints",
      onProceed: (questions) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuizPlayerScreen(
              studySet: targetSet,
              questions: questions,
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        ).then((_) => widget.onRefresh());
      },
    );
  }

  void _showNoQuestionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("No Practice Questions Yet"),
        content: const Text(
          "You haven't generated or imported practice questions for this subject yet. Tap '+ Add material' to extract study notes into questions.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onNavigateToStudio();
            },
            child: const Text("+ Add Material"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final readinessScore = widget.studyPlan?.readiness.readinessScore;
    final hasRealData = readinessScore != null && (widget.studyPlan?.readiness.spacingDaysActive ?? 0) > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Practice Hub",
                          style: GoogleFonts.outfit(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Quizzes • Cards • Blitz • Exam",
                          style: TextStyle(fontSize: 12, color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (widget.courses.length > 1)
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedCourseId,
                        hint: const Text("All", style: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text("All", style: TextStyle(fontSize: 12))),
                          ...widget.courses.map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.code, style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) => setState(() => _selectedCourseId = val),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Readiness & Mastery Card (Compact UnionBank-inspired)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), context.surfaceColor]
                        : [const Color(0xFFFFF7ED), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF6B00).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B00).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.insights_rounded, color: Color(0xFFFF6B00), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Exam Readiness",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      hasRealData ? "Live accuracy & retention" : "Take a quiz to track score",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _showReadinessFormulaDialog(context),
                          tooltip: "Formula",
                          icon: const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFFF6B00)),
                        ),
                      ],
                    ),
                    if (hasRealData) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            "${(readinessScore * 100).round()}%",
                            style: GoogleFonts.outfit(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF6B00),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: readinessScore.clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: context.cardBorderColor,
                                valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6B00)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Practice Modes Grid (Clean, Short Labels, Icon-First)
              Text(
                "Practice Modes",
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 10),

              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: [
                  _buildModeCard(
                    context,
                    title: "Smart Quiz",
                    subtitle: "Adaptive recall",
                    badge: "$_totalPracticeQuestions Qs",
                    icon: Icons.psychology_rounded,
                    color: const Color(0xFFFF6B00),
                    onTap: _startSmartQuizSession,
                  ),
                  _buildModeCard(
                    context,
                    title: "Flashcards",
                    subtitle: "Flip & review",
                    badge: "Cards",
                    icon: Icons.style_outlined,
                    color: const Color(0xFF10B981),
                    onTap: _startFlashcards,
                  ),
                  _buildModeCard(
                    context,
                    title: "Blitz",
                    subtitle: "Speed timer",
                    badge: "60s",
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: _startRapidFireBlitz,
                  ),
                  _buildModeCard(
                    context,
                    title: "Mistakes",
                    subtitle: "Fix past errors",
                    badge: "${widget.studyPlan?.unresolvedMistakesCount ?? 0} left",
                    icon: Icons.psychology_alt_outlined,
                    color: const Color(0xFFEF4444),
                    onTap: _openMistakeBank,
                  ),
                  _buildModeCard(
                    context,
                    title: "Mock Exam",
                    subtitle: "Full test run",
                    badge: "Timed",
                    icon: Icons.school_rounded,
                    color: const Color(0xFF6366F1),
                    onTap: _startSimulatedExam,
                  ),
                  _buildModeCard(
                    context,
                    title: "Quick Quiz",
                    subtitle: "Direct Q&A",
                    badge: "Review",
                    icon: Icons.quiz_outlined,
                    color: const Color(0xFF06B6D4),
                    onTap: _startStandardQuiz,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: context.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

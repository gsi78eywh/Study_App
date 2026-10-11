import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/network/api_client.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../models/quiz_models.dart";
import "../../ai_tutor/screens/ai_tutor_screen.dart";
import "quiz_player_screen.dart";

class QuizSummaryScreen extends StatefulWidget {
  final StudySetModel studySet;
  final List<QuestionModel> questions;
  final TestSessionSubmission submission;
  final ApiClient apiClient;
  final SessionService sessionService;
  final int? rapidFireMaxStreak;
  final int? starredCount;

  const QuizSummaryScreen({
    super.key,
    required this.studySet,
    this.questions = const [],
    required this.submission,
    required this.apiClient,
    required this.sessionService,
    this.rapidFireMaxStreak,
    this.starredCount,
  });

  @override
  State<QuizSummaryScreen> createState() => _QuizSummaryScreenState();
}

class _QuizSummaryScreenState extends State<QuizSummaryScreen> {
  bool _isSyncing = false;
  String? _syncStatus;
  int? _authoritativeScore;
  int? _authoritativeTotal;

  @override
  void initState() {
    super.initState();
    _submitForGrading();
  }

  Future<void> _submitForGrading() async {
    if (widget.submission.answers.isEmpty) {
      setState(
        () => _syncStatus = "Recorded locally.",
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.practiceSessions,
        data: widget.submission.toPracticeJson(),
      );
      final data = response.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _authoritativeScore = (data["score"] as num?)?.toInt();
        _authoritativeTotal = (data["totalQuestions"] as num?)?.toInt();
        _isSyncing = false;
        _syncStatus = "Recorded & synced to Mistake Bank";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncStatus = "Saved locally. Server sync pending.";
      });
    }
  }

  List<QuestionModel> get _missedQuestions {
    if (widget.questions.isEmpty) return [];
    final missed = <QuestionModel>[];
    for (final q in widget.questions) {
      final sub = widget.submission.answers.where((a) => a.questionId == q.id).firstOrNull;
      if (sub == null) {
        missed.add(q);
      } else {
        final isCorrect = _isAnswerMatch(q, sub.answer);
        if (!isCorrect) {
          missed.add(q);
        }
      }
    }
    return missed;
  }

  bool _isAnswerMatch(QuestionModel q, String answer) {
    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        final selected = q.options.where((o) => o.id == answer).firstOrNull;
        return selected?.isCorrect == true;
      case QuestionTypeEnum.trueFalse:
        return answer.toLowerCase() == (q.isTrue?.toString().toLowerCase() ?? "");
      case QuestionTypeEnum.identification:
      case QuestionTypeEnum.cloze:
        final entered = answer.trim().toLowerCase();
        if (entered.isEmpty) return false;
        final correctText = (q.correctAnswer ?? "").trim().toLowerCase();
        if (correctText.isNotEmpty && (entered == correctText || correctText.contains(entered))) {
          return true;
        }
        return q.options.where((o) => o.isCorrect).any(
          (o) => o.optionText.trim().toLowerCase() == entered,
        );
      default:
        return answer.trim().length >= 2;
    }
  }

  String _formatStudentAnswer(QuestionModel q) {
    final sub = widget.submission.answers.where((a) => a.questionId == q.id).firstOrNull;
    if (sub == null || sub.answer.isEmpty) return "No answer given";
    if (q.type == QuestionTypeEnum.multipleChoice || q.type == QuestionTypeEnum.scenario) {
      final opt = q.options.where((o) => o.id == sub.answer).firstOrNull;
      return opt?.optionText ?? sub.answer;
    }
    return sub.answer;
  }

  String _formatCorrectAnswer(QuestionModel q) {
    if (q.exactAnswerText.isNotEmpty) return q.exactAnswerText;
    final correctOpts = q.options.where((o) => o.isCorrect).map((o) => o.optionText).toList();
    if (correctOpts.isNotEmpty) return correctOpts.join(", ");
    if (q.correctAnswer != null && q.correctAnswer!.isNotEmpty) return q.correctAnswer!;
    if (q.isTrue != null) return q.isTrue! ? "True" : "False";
    return "See notes snippet";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final score = _authoritativeScore ?? widget.submission.score;
    final totalQuestions = _authoritativeTotal ?? widget.submission.totalQuestions;
    final pct = (score / (totalQuestions > 0 ? totalQuestions : 1)) * 100;
    final minutes = widget.submission.timeSpentSeconds ~/ 60;
    final seconds = widget.submission.timeSpentSeconds % 60;
    final missed = _missedQuestions;

    Color badgeColor;
    String gradeTitle;
    String motivationalMessage;
    IconData headerIcon;

    if (pct >= 85) {
      badgeColor = const Color(0xFF10B981);
      gradeTitle = "Mastery Achieved!";
      motivationalMessage = "Outstanding performance! You have high retention on this material.";
      headerIcon = Icons.stars_rounded;
    } else if (pct >= 60) {
      badgeColor = const Color(0xFF3B82F6);
      gradeTitle = "Solid Progress!";
      motivationalMessage = "Good work! Reviewing your missed questions will get you to mastery.";
      headerIcon = Icons.thumb_up_alt_rounded;
    } else {
      badgeColor = const Color(0xFFF59E0B);
      gradeTitle = "Good Effort — Keep Growing!";
      motivationalMessage = "Mistakes are proof you're learning. Review the concepts below to lock them in.";
      headerIcon = Icons.auto_graph_rounded;
    }

    final previousScorePct = (widget.studySet.masteryScore * 100).toInt();
    final hasPreviousAttempt = widget.studySet.attemptsCount > 0;
    final scoreDelta = pct.toInt() - previousScorePct;

    return Scaffold(
      appBar: AppBar(
        title: Text("Session Results", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Main Encouraging Results Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            headerIcon,
                            color: badgeColor,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          gradeTitle,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          motivationalMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "${pct.toInt()}%",
                          style: GoogleFonts.outfit(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                        Text(
                          "${_isSyncing ? "Evaluating" : score} of $totalQuestions correct",
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Divider(color: context.cardBorderColor),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  "Time Spent",
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${minutes}m ${seconds}s",
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            if (hasPreviousAttempt)
                              Column(
                                children: [
                                  Text(
                                    "vs. Last Attempt",
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "$previousScorePct%",
                                        style: TextStyle(
                                          color: context.textSecondary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (scoreDelta != 0)
                                        Text(
                                          scoreDelta > 0 ? "(+$scoreDelta%)" : "($scoreDelta%)",
                                          style: TextStyle(
                                            color: scoreDelta > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            Column(
                              children: [
                                Text(
                                  "Learning Record",
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (_isSyncing)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 15,
                                        color: Color(0xFF10B981),
                                      ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _syncStatus ?? "Recorded",
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Retry Missed Button (Blueprint requirement)
                  if (missed.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 20),
                      label: Text(
                        "Retry ${missed.length} Missed Question${missed.length > 1 ? 's' : ''}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => QuizPlayerScreen(
                              studySet: widget.studySet,
                              questions: missed,
                              apiClient: widget.apiClient,
                              sessionService: widget.sessionService,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Missed Questions Review Section
                  if (missed.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.fact_check_rounded, color: Color(0xFFF59E0B), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Missed-Question Review (${missed.length})",
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...missed.map((q) {
                      final studentAns = _formatStudentAnswer(q);
                      final correctAns = _formatCorrectAnswer(q);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.cardBorderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.questionText,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Student Answer
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    "Your answer",
                                    style: TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    studentAns,
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Correct Answer
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    "Correct key",
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    correctAns,
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (q.rationale != null && q.rationale!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.18 : 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.school_rounded, size: 16, color: Color(0xFF6366F1)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        q.rationale!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: context.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (q.sourceSnippet != null && q.sourceSnippet!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                "Matches notes: \"${q.sourceSnippet}\"",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],

                  // Action Buttons
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: const Text(
                      "Ask AI Tutor About This Quiz",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AiTutorScreen(
                            apiClient: widget.apiClient,
                            courses: const [],
                            initialPrompt:
                                "I just completed practice for '${widget.studySet.title}' with a score of $score/$totalQuestions. Can you teach me the core concepts for the questions I missed and how to master them?",
                            initialCourseContext: widget.studySet.title,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Return to Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/network/api_client.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../models/quiz_models.dart";
import "../../ai_tutor/screens/ai_tutor_screen.dart";

class QuizSummaryScreen extends StatefulWidget {
  final StudySetModel studySet;
  final TestSessionSubmission submission;
  final ApiClient apiClient;
  final SessionService sessionService;
  final int? rapidFireMaxStreak;
  final int? starredCount;

  const QuizSummaryScreen({
    super.key,
    required this.studySet,
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
        () => _syncStatus = "No answers were available for server grading.",
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
        _authoritativeScore = data["score"] as int?;
        _authoritativeTotal = data["totalQuestions"] as int?;
        _isSyncing = false;
        _syncStatus = "Graded and recorded by the server";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncStatus = "Server grading failed. Please retry this session.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = _authoritativeScore ?? widget.submission.score;
    final totalQuestions =
        _authoritativeTotal ?? widget.submission.totalQuestions;
    final pct = (score / (totalQuestions > 0 ? totalQuestions : 1)) * 100;
    final minutes = widget.submission.timeSpentSeconds ~/ 60;
    final seconds = widget.submission.timeSpentSeconds % 60;

    Color badgeColor = AppColors.accent;
    String gradeTitle = "Mastery Achieved!";
    if (pct < 60) {
      badgeColor = AppColors.danger;
      gradeTitle = "Needs More Practice";
    } else if (pct < 85) {
      badgeColor = AppColors.warning;
      gradeTitle = "Good Progress!";
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Session Results")),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.emoji_events_rounded,
                            color: badgeColor,
                            size: 56,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          gradeTitle,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.studySet.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "${pct.toInt()}%",
                          style: GoogleFonts.outfit(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                        Text(
                          "${_isSyncing ? "Grading" : score} out of $totalQuestions correct",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: AppColors.darkCardBorder),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text(
                                  "Time Spent",
                                  style: TextStyle(
                                    color: AppColors.darkTextSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${minutes}m ${seconds}s",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (widget.rapidFireMaxStreak != null)
                              Column(
                                children: [
                                  const Text(
                                    "Max Streak",
                                    style: TextStyle(
                                      color: AppColors.darkTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "🔥 ${widget.rapidFireMaxStreak}",
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (widget.starredCount != null && widget.starredCount! > 0)
                              Column(
                                children: [
                                  const Text(
                                    "Bookmarked",
                                    style: TextStyle(
                                      color: AppColors.darkTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "⭐ ${widget.starredCount}",
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            Column(
                              children: [
                                const Text(
                                  "Server Sync",
                                  style: TextStyle(
                                    color: AppColors.darkTextSecondary,
                                    fontSize: 12,
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
                                    else if (_authoritativeScore != null)
                                      const Icon(
                                        Icons.cloud_done_rounded,
                                        size: 16,
                                        color: AppColors.accent,
                                      )
                                    else
                                      const Icon(
                                        Icons.cloud_off_rounded,
                                        size: 16,
                                        color: AppColors.warning,
                                      ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _syncStatus ?? "Syncing...",
                                      style: const TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 11,
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
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: const Text(
                      "Ask Gemini Tutor About This Quiz",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AiTutorScreen(
                            apiClient: widget.apiClient,
                            courses: const [],
                            initialPrompt:
                                "I just completed practice for '${widget.studySet.title}' with a score of $score/$totalQuestions. Can you explain the core concepts of this topic and give me advice on how to master it?",
                            initialCourseContext: widget.studySet.title,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Return to Dashboard"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

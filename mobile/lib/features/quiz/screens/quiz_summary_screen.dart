import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../models/quiz_models.dart";
import "../../sync/services/sync_service.dart";

class QuizSummaryScreen extends StatefulWidget {
  final StudySetModel studySet;
  final TestSessionSubmission submission;
  final ApiClient apiClient;
  final SessionService sessionService;

  const QuizSummaryScreen({
    super.key,
    required this.studySet,
    required this.submission,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<QuizSummaryScreen> createState() => _QuizSummaryScreenState();
}

class _QuizSummaryScreenState extends State<QuizSummaryScreen> {
  bool _isSyncing = false;
  String? _syncStatus;

  @override
  void initState() {
    super.initState();
    _syncResults();
  }

  Future<void> _syncResults() async {
    setState(() => _isSyncing = true);
    final syncService = SyncService(
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
    );

    final res = await syncService.performSync(pendingSessions: [widget.submission]);
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncStatus = res.success ? "Scores synced to server database" : "Stored locally (will sync later)";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.submission.score / (widget.submission.totalQuestions > 0 ? widget.submission.totalQuestions : 1)) * 100;
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
                      border: Border.all(color: badgeColor.withOpacity(0.5), width: 2),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.emoji_events_rounded, color: badgeColor, size: 56),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          gradeTitle,
                          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.studySet.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "${pct.toInt()}%",
                          style: GoogleFonts.outfit(fontSize: 56, fontWeight: FontWeight.bold, color: badgeColor),
                        ),
                        Text(
                          "${widget.submission.score} out of ${widget.submission.totalQuestions} correct",
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: AppColors.darkCardBorder),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text("Time Spent", style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text("${minutes}m ${seconds}s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text("Server Sync", style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (_isSyncing)
                                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                                    else
                                      const Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.accent),
                                    const SizedBox(width: 4),
                                    Text(_syncStatus ?? "Syncing...", style: const TextStyle(color: AppColors.accent, fontSize: 11)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
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

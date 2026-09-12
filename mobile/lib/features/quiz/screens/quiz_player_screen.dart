import "dart:async";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:uuid/uuid.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../models/quiz_models.dart";
import "quiz_summary_screen.dart";

class QuizPlayerScreen extends StatefulWidget {
  final StudySetModel studySet;
  final List<QuestionModel> questions;
  final ApiClient apiClient;
  final SessionService sessionService;

  const QuizPlayerScreen({
    super.key,
    required this.studySet,
    required this.questions,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  int _currentIndex = 0;
  int _score = 0;
  int _secondsElapsed = 0;
  Timer? _timer;

  String? _selectedOptionId;
  final _identificationController = TextEditingController();
  bool _hasSubmittedCurrent = false;
  int _revealedHintsCount = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _identificationController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  void _submitAnswer() {
    final currentQ = widget.questions[_currentIndex];
    bool isCorrect = false;

    if (currentQ.type == QuestionTypeEnum.multipleChoice) {
      if (_selectedOptionId == null) return;
      final selectedOpt = currentQ.options.firstWhere((o) => o.id == _selectedOptionId);
      isCorrect = selectedOpt.isCorrect;
    } else {
      final userText = _identificationController.text.trim().toLowerCase();
      if (userText.isEmpty) return;
      final correctOpt = currentQ.options.firstWhere(
        (o) => o.isCorrect,
        orElse: () => QuestionOptionModel(id: "", optionText: "", isCorrect: true),
      );
      isCorrect = userText == correctOpt.optionText.trim().toLowerCase();
    }

    if (isCorrect) _score++;
    setState(() => _hasSubmittedCurrent = true);
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionId = null;
        _identificationController.clear();
        _hasSubmittedCurrent = false;
        _revealedHintsCount = 0;
      });
    } else {
      _timer?.cancel();
      final submission = TestSessionSubmission(
        id: const Uuid().v4(),
        studySetId: widget.studySet.id,
        mode: 1, // PracticeQuiz
        score: _score,
        totalQuestions: widget.questions.length,
        timeSpentSeconds: _secondsElapsed,
        completedAt: DateTime.now(),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuizSummaryScreen(
            studySet: widget.studySet,
            submission: submission,
            apiClient: widget.apiClient,
            sessionService: widget.sessionService,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Quiz Practice")),
        body: const Center(child: Text("No questions found in this study set.")),
      );
    }

    final currentQ = widget.questions[_currentIndex];
    final progress = (_currentIndex + 1) / widget.questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studySet.title, style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.darkCardBorder,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: AppColors.darkTextSecondary),
                  const SizedBox(width: 4),
                  Text(
                    "${_secondsElapsed ~/ 60}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}",
                    style: const TextStyle(color: AppColors.darkTextSecondary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Question Tracker & Type
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Question ${_currentIndex + 1} of ${widget.questions.length}",
                    style: const TextStyle(color: AppColors.darkTextSecondary, fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentQ.type == QuestionTypeEnum.multipleChoice ? "Multiple Choice" : "Identification",
                      style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Question Prompt Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.darkCardBorder),
                ),
                child: Text(
                  currentQ.prompt,
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4),
                ),
              ),
              const SizedBox(height: 20),

              // Multiple Choice Options
              if (currentQ.type == QuestionTypeEnum.multipleChoice) ...[
                ...currentQ.options.map((opt) {
                  final isSelected = _selectedOptionId == opt.id;
                  Color borderColor = AppColors.darkCardBorder;
                  Color bgColor = AppColors.darkCard;

                  if (_hasSubmittedCurrent) {
                    if (opt.isCorrect) {
                      borderColor = AppColors.accent;
                      bgColor = AppColors.accent.withValues(alpha: 0.15);
                    } else if (isSelected && !opt.isCorrect) {
                      borderColor = AppColors.danger;
                      bgColor = AppColors.danger.withValues(alpha: 0.15);
                    }
                  } else if (isSelected) {
                    borderColor = AppColors.primary;
                    bgColor = AppColors.primary.withValues(alpha: 0.12);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: _hasSubmittedCurrent ? null : () => setState(() => _selectedOptionId = opt.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: isSelected || (_hasSubmittedCurrent && opt.isCorrect) ? 2 : 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _hasSubmittedCurrent && opt.isCorrect
                                  ? Icons.check_circle_rounded
                                  : (_hasSubmittedCurrent && isSelected && !opt.isCorrect
                                      ? Icons.cancel_rounded
                                      : (isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked)),
                              color: _hasSubmittedCurrent && opt.isCorrect
                                  ? AppColors.accent
                                  : (_hasSubmittedCurrent && isSelected && !opt.isCorrect
                                      ? AppColors.danger
                                      : (isSelected ? AppColors.primary : AppColors.darkTextSecondary)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                opt.optionText,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ] else ...[
                // Identification input
                TextField(
                  controller: _identificationController,
                  enabled: !_hasSubmittedCurrent,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Your Answer",
                    hintText: "Type key term or concept...",
                  ),
                ),
              ],

              // Hints Section
              if (currentQ.hints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(_revealedHintsCount < currentQ.hints.length
                          ? "Need a hint? ($_revealedHintsCount/${currentQ.hints.length})"
                          : "All hints revealed"),
                      onPressed: _revealedHintsCount < currentQ.hints.length
                          ? () => setState(() => _revealedHintsCount++)
                          : null,
                    ),
                  ],
                ),
                for (int i = 0; i < _revealedHintsCount; i++) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates_rounded, color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Hint ${i + 1}: ${currentQ.hints[i]}",
                            style: const TextStyle(color: AppColors.warning, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Post-Submission Explanation & Distractor Rationale
              if (_hasSubmittedCurrent) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.darkCardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.psychology_outlined, color: AppColors.accent, size: 20),
                          const SizedBox(width: 8),
                          Text("AI Explanation", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentQ.explanation ?? "No explanation provided for this question.",
                        style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Button (Check Answer vs Next Question)
              if (!_hasSubmittedCurrent)
                ElevatedButton(
                  onPressed: (_selectedOptionId != null || _identificationController.text.trim().isNotEmpty)
                      ? _submitAnswer
                      : null,
                  child: const Text("Check Answer"),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(_currentIndex < widget.questions.length - 1 ? "Next Question" : "View Results"),
                  onPressed: _nextQuestion,
                ),
            ],
          ),
        ),
      ),
    );
  }
}



import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/session_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../courses/models/course_models.dart';
import '../models/quiz_models.dart';
import 'quiz_summary_screen.dart';

class RapidFireScreen extends StatefulWidget {
  final StudySetModel studySet;
  final List<QuestionModel> questions;
  final ApiClient apiClient;
  final SessionService sessionService;
  final int secondsPerQuestion;

  const RapidFireScreen({
    super.key,
    required this.studySet,
    required this.questions,
    required this.apiClient,
    required this.sessionService,
    this.secondsPerQuestion = 10,
  });

  @override
  State<RapidFireScreen> createState() => _RapidFireScreenState();
}

class _RapidFireScreenState extends State<RapidFireScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _timeLeft = 10;
  int _totalElapsed = 0;
  bool _hasAnswered = false;
  String? _selectedOptionId;
  bool? _selectedTrueFalse;
  final _textController = TextEditingController();
  Timer? _questionTimer;
  Timer? _elapsedTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final List<PracticeAnswerSubmission> _answers = [];

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.secondsPerQuestion;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnim = Tween<double>(
      begin: 1,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _startTimers();
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    _elapsedTimer?.cancel();
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _startTimers() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _totalElapsed++);
    });
    _startQuestionTimer();
  }

  void _startQuestionTimer() {
    _questionTimer?.cancel();
    _timeLeft = widget.secondsPerQuestion;
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _hasAnswered) return;
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        _questionTimer?.cancel();
        _onTimeout();
      }
    });
  }

  void _onTimeout() {
    final question = widget.questions[_currentIndex];
    setState(() {
      _hasAnswered = true;
      _answers.add(
        PracticeAnswerSubmission(questionId: question.id, answer: ''),
      );
    });
    Future.delayed(const Duration(milliseconds: 1200), _advance);
  }

  void _submitAnswer() {
    if (_hasAnswered) return;
    _questionTimer?.cancel();
    final q = widget.questions[_currentIndex];
    String? answer;

    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        if (_selectedOptionId == null) return;
        answer = _selectedOptionId;
        break;
      case QuestionTypeEnum.trueFalse:
        if (_selectedTrueFalse == null) return;
        answer = _selectedTrueFalse.toString();
        break;
      default:
        final ans = _textController.text.trim();
        if (ans.isEmpty) return;
        answer = q.type == QuestionTypeEnum.matching ? jsonEncode({}) : ans;
    }

    _answers.add(PracticeAnswerSubmission(questionId: q.id, answer: answer!));
    _pulseController.forward(from: 0);

    setState(() {
      _hasAnswered = true;
    });

    Future.delayed(const Duration(milliseconds: 900), _advance);
  }

  void _advance() {
    if (!mounted) return;
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _hasAnswered = false;
        _selectedOptionId = null;
        _selectedTrueFalse = null;
        _textController.clear();
      });
      _startQuestionTimer();
    } else {
      _finish();
    }
  }

  void _finish() {
    _questionTimer?.cancel();
    _elapsedTimer?.cancel();
    final sub = TestSessionSubmission(
      id: const Uuid().v4(),
      studySetId: widget.studySet.id,
      mode: StudyModeValue.rapidFireBlitz,
      score: 0,
      totalQuestions: widget.questions.length,
      timeSpentSeconds: _totalElapsed,
      completedAt: DateTime.now(),
      answers: _answers,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuizSummaryScreen(
          studySet: widget.studySet,
          submission: sub,
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('⚡ Rapid-Fire Blitz')),
        body: const Center(child: Text('No questions available.')),
      );
    }

    final q = widget.questions[_currentIndex];
    final progress = (_currentIndex + 1) / widget.questions.length;
    final timerPct = _timeLeft / widget.secondsPerQuestion;
    final isDark = context.isDarkMode;

    Color timerColor = AppColors.accent;
    if (timerPct < 0.4) timerColor = AppColors.warning;
    if (timerPct < 0.2) timerColor = AppColors.danger;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with close + score + streak
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: context.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      '⚡ Rapid-Fire Blitz',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: context.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_answers.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Server graded',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_answers.length} answered',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Progress bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: context.cardBorderColor,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6366F1),
              ),
              minHeight: 3,
            ),
            // Timer countdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_currentIndex + 1}/${widget.questions.length}',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      '0:${_timeLeft.toString().padLeft(2, '0')}',
                      key: ValueKey(_timeLeft),
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: timerColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: timerPct.clamp(0, 1),
                        backgroundColor: context.cardBorderColor,
                        valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        // Result flash
                        if (_hasAnswered)
                          ScaleTransition(
                            scale: _pulseAnim,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Answer recorded — server grading follows the round.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        // Question prompt
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.cardBorderColor),
                          ),
                          child: Text(
                            q.prompt,
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Input
                        _buildInput(q, isDark),
                        const SizedBox(height: 16),
                        if (!_hasAnswered)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? AppColors.primary
                                  : AppColors.primaryDark,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _canSubmit ? _submitAnswer : null,
                            child: Text(
                              'Submit ⚡',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit {
    final q = widget.questions[_currentIndex];
    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        return _selectedOptionId != null;
      case QuestionTypeEnum.trueFalse:
        return _selectedTrueFalse != null;
      default:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Widget _buildInput(QuestionModel q, bool isDark) {
    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        return Column(
          children: q.options.map((opt) {
            final isSelected = _selectedOptionId == opt.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _hasAnswered
                    ? null
                    : () => setState(() => _selectedOptionId = opt.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : context.surfaceColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryLight
                          : context.cardBorderColor,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    opt.optionText,
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case QuestionTypeEnum.trueFalse:
        return Row(
          children: [
            Expanded(child: _rfTfButton('TRUE', true)),
            const SizedBox(width: 12),
            Expanded(child: _rfTfButton('FALSE', false)),
          ],
        );

      default:
        return TextField(
          controller: _textController,
          enabled: !_hasAnswered,
          autofocus: true,
          style: TextStyle(color: context.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Quick! Type your answer...',
            hintStyle: TextStyle(color: context.textSecondary),
          ),
          onSubmitted: (_) {
            if (_canSubmit && !_hasAnswered) _submitAnswer();
          },
        );
    }
  }

  Widget _rfTfButton(String label, bool value) {
    final isSelected = _selectedTrueFalse == value;
    return GestureDetector(
      onTap: _hasAnswered
          ? null
          : () => setState(() => _selectedTrueFalse = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight
                : context.cardBorderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }
}

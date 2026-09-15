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

class QuizPlayerScreen extends StatefulWidget {
  final StudySetModel studySet;
  final List<QuestionModel> questions;
  final ApiClient apiClient;
  final SessionService sessionService;
  final int initialMode;
  final bool instantFeedback;
  final bool shuffleOptions;

  const QuizPlayerScreen({
    super.key,
    required this.studySet,
    required this.questions,
    required this.apiClient,
    required this.sessionService,
    this.initialMode = StudyModeValue.simulatedExam,
    this.instantFeedback = true,
    this.shuffleOptions = true,
  });

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  int _currentIndex = 0;
  int _secondsElapsed = 0;
  Timer? _timer;

  String? _selectedOptionId;
  final _textController = TextEditingController();
  bool? _selectedTrueFalse;
  Map<String, String?> _matchingSelections = {};
  List<String> _matchingDefinitions = [];

  bool _hasSubmittedCurrent = false;
  int _revealedHintsCount = 0;
  final List<PracticeAnswerSubmission> _answers = [];
  final Set<String> _starredQuestionIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.shuffleOptions) {
      for (final q in widget.questions) {
        q.options.shuffle();
      }
    }
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  void _resetQuestionState() {
    _selectedOptionId = null;
    _textController.clear();
    _selectedTrueFalse = null;
    _matchingSelections = {};
    _matchingDefinitions = [];
    _hasSubmittedCurrent = false;
    _revealedHintsCount = 0;
  }

  void _submitAnswer() {
    if (_hasSubmittedCurrent) return;
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
      case QuestionTypeEnum.matching:
        if (_matchingSelections.isEmpty) return;
        answer = jsonEncode(_matchingSelections);
        break;
      default:
        answer = _textController.text.trim();
        if (answer.isEmpty) return;
    }

    setState(() {
      _answers.removeWhere((a) => a.questionId == q.id);
      _answers.add(PracticeAnswerSubmission(questionId: q.id, answer: answer!));
      _hasSubmittedCurrent = true;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _resetQuestionState();
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() {
    _timer?.cancel();
    final submission = TestSessionSubmission(
      id: const Uuid().v4(),
      studySetId: widget.studySet.id,
      mode: widget.initialMode,
      score: 0,
      totalQuestions: widget.questions.length,
      timeSpentSeconds: _secondsElapsed,
      completedAt: DateTime.now(),
      answers: _answers,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuizSummaryScreen(
          studySet: widget.studySet,
          submission: submission,
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
          starredCount: _starredQuestionIds.length,
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
      case QuestionTypeEnum.matching:
        return _matchingSelections.isNotEmpty;
      default:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Color _typeColor(QuestionTypeEnum type) {
    switch (type) {
      case QuestionTypeEnum.multipleChoice:
        return const Color(0xFF6366F1);
      case QuestionTypeEnum.identification:
        return const Color(0xFF10B981);
      case QuestionTypeEnum.enumeration:
      case QuestionTypeEnum.bulletPoints:
        return const Color(0xFFF59E0B);
      case QuestionTypeEnum.cloze:
        return const Color(0xFF06B6D4);
      case QuestionTypeEnum.trueFalse:
        return const Color(0xFF8B5CF6);
      case QuestionTypeEnum.matching:
        return const Color(0xFFEC4899);
      case QuestionTypeEnum.shortAnswer:
        return const Color(0xFFEF4444);
      case QuestionTypeEnum.scenario:
      case QuestionTypeEnum.logicalThinking:
        return const Color(0xFFFF7849);
    }
  }

  IconData _typeIcon(QuestionTypeEnum type) {
    switch (type) {
      case QuestionTypeEnum.multipleChoice:
        return Icons.quiz_rounded;
      case QuestionTypeEnum.identification:
        return Icons.text_fields_rounded;
      case QuestionTypeEnum.enumeration:
      case QuestionTypeEnum.bulletPoints:
        return Icons.format_list_numbered;
      case QuestionTypeEnum.cloze:
        return Icons.text_snippet_rounded;
      case QuestionTypeEnum.trueFalse:
        return Icons.check_circle_outline_rounded;
      case QuestionTypeEnum.matching:
        return Icons.compare_arrows_rounded;
      case QuestionTypeEnum.shortAnswer:
        return Icons.edit_note_rounded;
      case QuestionTypeEnum.scenario:
      case QuestionTypeEnum.logicalThinking:
        return Icons.lightbulb_outline_rounded;
    }
  }

  String _typeLabel(QuestionTypeEnum type) {
    switch (type) {
      case QuestionTypeEnum.multipleChoice:
        return 'Multiple Choice';
      case QuestionTypeEnum.identification:
        return 'Identification';
      case QuestionTypeEnum.enumeration:
        return 'Enumeration';
      case QuestionTypeEnum.bulletPoints:
        return 'Bullet Points';
      case QuestionTypeEnum.cloze:
        return 'Cloze / Fill-in';
      case QuestionTypeEnum.trueFalse:
        return 'True / False';
      case QuestionTypeEnum.matching:
        return 'Matching Type';
      case QuestionTypeEnum.shortAnswer:
        return 'Short Answer';
      case QuestionTypeEnum.scenario:
        return 'Scenario Drill';
      case QuestionTypeEnum.logicalThinking:
        return 'Logical Thinking';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.studySet.title)),
        body: const Center(
          child: Text('No questions available for this study set.'),
        ),
      );
    }

    final q = widget.questions[_currentIndex];
    final progress = (_currentIndex + 1) / widget.questions.length;
    final isDark = context.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.studySet.title,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _starredQuestionIds.contains(q.id)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: _starredQuestionIds.contains(q.id)
                  ? const Color(0xFFF59E0B)
                  : context.textSecondary,
            ),
            tooltip: _starredQuestionIds.contains(q.id)
                ? 'Bookmarked (tap to remove)'
                : 'Star question for cram review',
            onPressed: () {
              setState(() {
                if (_starredQuestionIds.contains(q.id)) {
                  _starredQuestionIds.remove(q.id);
                } else {
                  _starredQuestionIds.add(q.id);
                }
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_secondsElapsed ~/ 60}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: context.cardBorderColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? AppColors.primaryLight : AppColors.primaryDark,
            ),
            minHeight: 4,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question ${_currentIndex + 1} of ${widget.questions.length}',
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Answered: ${_answers.length}',
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Type badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _typeColor(q.type).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _typeColor(q.type)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _typeIcon(q.type),
                                  size: 14,
                                  color: _typeColor(q.type),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _typeLabel(q.type),
                                  style: TextStyle(
                                    color: _typeColor(q.type),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Prompt
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.cardBorderColor),
                        ),
                        child: Text(
                          q.prompt,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Input for this type
                      _buildInput(q, isDark),
                      // Hints
                      if (q.hints.isNotEmpty &&
                          q.type != QuestionTypeEnum.shortAnswer) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.lightbulb_outline, size: 16),
                          label: Text(
                            _revealedHintsCount < q.hints.length
                                ? 'Hint ($_revealedHintsCount/${q.hints.length})'
                                : 'All hints shown',
                          ),
                          onPressed:
                              _revealedHintsCount < q.hints.length &&
                                  !_hasSubmittedCurrent
                              ? () => setState(() => _revealedHintsCount++)
                              : null,
                        ),
                        for (int i = 0; i < _revealedHintsCount; i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.tips_and_updates_rounded,
                                  color: AppColors.warning,
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Hint ${i + 1}: ${q.hints[i]}',
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      // Short answer rubric
                      if (_hasSubmittedCurrent &&
                          q.type == QuestionTypeEnum.shortAnswer &&
                          q.hints.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rubric Keywords:',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryLight,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: q.hints.map((kw) {
                                  final mentioned = _textController.text
                                      .toLowerCase()
                                      .contains(kw.toLowerCase());
                                  return Chip(
                                    label: Text(
                                      kw,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: mentioned
                                            ? Colors.white
                                            : context.textPrimary,
                                      ),
                                    ),
                                    backgroundColor: mentioned
                                        ? AppColors.accent
                                        : context.cardBorderColor.withValues(
                                            alpha: 0.3,
                                          ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_hasSubmittedCurrent) ...[
                        const SizedBox(height: 14),
                        _buildRealtimeAnswerFeedbackBanner(q),
                        if (q.explanation != null &&
                            q.explanation!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _buildAiExplanationCard(q),
                        ],
                      ],
                      const SizedBox(height: 18),
                      if (!_hasSubmittedCurrent)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? AppColors.primary
                                : AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _canSubmit ? _submitAnswer : null,
                          child: Text(
                            'Check Answer',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _currentIndex < widget.questions.length - 1
                                ? 'Next Question'
                                : 'View Results',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          onPressed: _nextQuestion,
                        ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(QuestionModel q, bool isDark) {
    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        // Deduplicate options by text to guarantee distinct choices
        final seenOptionTexts = <String>{};
        final distinctOptions = q.options.where((opt) {
          final trimmed = opt.optionText.trim().toLowerCase();
          return trimmed.isNotEmpty && seenOptionTexts.add(trimmed);
        }).toList();

        return Column(
          children: distinctOptions.asMap().entries.map((entry) {
            final idx = entry.key;
            final opt = entry.value;
            final letter = String.fromCharCode(65 + idx); // A, B, C, D
            final isSelected = _selectedOptionId == opt.id;
            final isCorrect = opt.isCorrect;

            Color borderColor = context.cardBorderColor;
            Color bgColor = context.surfaceColor;
            Color letterBg = isSelected
                ? (isDark
                    ? AppColors.primaryLight.withValues(alpha: 0.25)
                    : AppColors.primaryDark.withValues(alpha: 0.2))
                : context.secondaryBg;
            Color letterColor = isSelected
                ? (isDark ? AppColors.primaryLight : AppColors.primaryDark)
                : context.textPrimary;
            Widget? trailingBadge;

            if (_hasSubmittedCurrent) {
              if (isCorrect) {
                // 100% Verified Correct Option
                borderColor = const Color(0xFF10B981);
                bgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
                letterBg = const Color(0xFF10B981);
                letterColor = Colors.white;
                trailingBadge = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        '100% Correct',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              } else if (isSelected) {
                // User's Incorrect Selection
                borderColor = const Color(0xFFEF4444);
                bgColor = const Color(0xFFEF4444).withValues(alpha: 0.12);
                letterBg = const Color(0xFFEF4444);
                letterColor = Colors.white;
                trailingBadge = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Your Choice (Incorrect)',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                // Unselected Distractors
                borderColor = context.cardBorderColor.withValues(alpha: 0.35);
                bgColor = context.surfaceColor.withValues(alpha: 0.35);
                letterBg = context.secondaryBg.withValues(alpha: 0.4);
                letterColor = context.textSecondary.withValues(alpha: 0.5);
              }
            } else if (isSelected) {
              borderColor = isDark ? AppColors.primaryLight : AppColors.primaryDark;
              bgColor = AppColors.primary.withValues(alpha: 0.1);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: _hasSubmittedCurrent
                        ? null
                        : () => setState(() => _selectedOptionId = opt.id),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor,
                          width: (_hasSubmittedCurrent && (isCorrect || isSelected)) || isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: letterBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (_hasSubmittedCurrent && (isCorrect || isSelected)) || isSelected
                                    ? borderColor
                                    : context.cardBorderColor,
                              ),
                            ),
                            child: Text(
                              letter,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: letterColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              opt.optionText,
                              style: TextStyle(
                                color: _hasSubmittedCurrent && !isCorrect && !isSelected
                                    ? context.textSecondary
                                    : context.textPrimary,
                                fontSize: 15,
                                fontWeight: (_hasSubmittedCurrent && isCorrect) || isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (trailingBadge != null) ...[
                            const SizedBox(width: 8),
                            trailingBadge,
                          ] else if (isSelected && !_hasSubmittedCurrent) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle_rounded,
                              color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_hasSubmittedCurrent &&
                      isSelected &&
                      !isCorrect &&
                      opt.distractorRationale != null &&
                      opt.distractorRationale!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              opt.distractorRationale!,
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );

      case QuestionTypeEnum.trueFalse:
        return Row(
          children: [
            _tfButton('TRUE', true, Icons.check_circle_rounded),
            const SizedBox(width: 12),
            _tfButton('FALSE', false, Icons.cancel_rounded),
          ],
        );

      case QuestionTypeEnum.matching:
        return _buildMatchingWidget(q);

      case QuestionTypeEnum.enumeration:
      case QuestionTypeEnum.bulletPoints:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              enabled: !_hasSubmittedCurrent,
              style: TextStyle(color: context.textPrimary),
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'List each item on a new line or separated by commas...',
                hintStyle: TextStyle(color: context.textSecondary),
                alignLabelWithHint: true,
              ),
            ),
            if (_hasSubmittedCurrent) ...[
              const SizedBox(height: 12),
              _buildExactAnswerKeyCard(q),
            ],
          ],
        );

      case QuestionTypeEnum.shortAnswer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              enabled: !_hasSubmittedCurrent,
              style: TextStyle(color: context.textPrimary),
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Write your conceptual explanation in your own words...',
                hintStyle: TextStyle(color: context.textSecondary),
                alignLabelWithHint: true,
              ),
            ),
            if (_hasSubmittedCurrent) ...[
              const SizedBox(height: 12),
              _buildExactAnswerKeyCard(q),
            ],
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              enabled: !_hasSubmittedCurrent,
              autofocus: true,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: q.type == QuestionTypeEnum.cloze
                    ? 'Type the missing word that fills the ____...'
                    : 'Type the key term or concept...',
                hintStyle: TextStyle(color: context.textSecondary),
              ),
              onSubmitted: (_) {
                if (_canSubmit && !_hasSubmittedCurrent) _submitAnswer();
              },
            ),
            if (_hasSubmittedCurrent) ...[
              const SizedBox(height: 12),
              _buildExactAnswerKeyCard(q),
            ],
          ],
        );
    }
  }

  Widget _tfButton(String label, bool value, IconData icon) {
    final isSelected = _selectedTrueFalse == value;
    final q = widget.questions[_currentIndex];
    final isCorrectAnswer = q.isTrue == value;

    Color bg = context.surfaceColor;
    Color border = context.cardBorderColor;
    Color iconColor = context.textSecondary;
    Widget? statusBadge;

    if (_hasSubmittedCurrent) {
      if (isCorrectAnswer) {
        bg = const Color(0xFF10B981).withValues(alpha: 0.16);
        border = const Color(0xFF10B981);
        iconColor = const Color(0xFF10B981);
        statusBadge = Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '100% Correct',
            style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        );
      } else if (isSelected) {
        bg = const Color(0xFFEF4444).withValues(alpha: 0.14);
        border = const Color(0xFFEF4444);
        iconColor = const Color(0xFFEF4444);
        statusBadge = Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFEF4444)),
          ),
          child: const Text(
            'Incorrect',
            style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        );
      } else {
        bg = context.surfaceColor.withValues(alpha: 0.4);
        border = context.cardBorderColor.withValues(alpha: 0.3);
        iconColor = context.textSecondary.withValues(alpha: 0.4);
      }
    } else if (isSelected) {
      bg = AppColors.primary.withValues(alpha: 0.15);
      border = AppColors.primaryLight;
      iconColor = AppColors.primaryLight;
    }

    return Expanded(
      child: GestureDetector(
        onTap: _hasSubmittedCurrent
            ? null
            : () => setState(() => _selectedTrueFalse = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: (_hasSubmittedCurrent &&
                          (isCorrectAnswer || isSelected)) ||
                      isSelected
                  ? 2
                  : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 36, color: iconColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: context.textPrimary,
                ),
              ),
              ?statusBadge,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchingWidget(QuestionModel q) {
    if (q.matchingTerms.isEmpty || q.matchingDefinitions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textController,
            enabled: !_hasSubmittedCurrent,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'Type the matching answer...',
              hintStyle: TextStyle(color: context.textSecondary),
            ),
          ),
          if (_hasSubmittedCurrent) ...[
            const SizedBox(height: 12),
            _buildExactAnswerKeyCard(q),
          ],
        ],
      );
    }
    if (_matchingDefinitions.isEmpty) {
      _matchingDefinitions = List<String>.from(q.matchingDefinitions)..shuffle();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Match each term to its definition:',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        ...q.matchingTerms.map((term) {
          final selectedDef = _matchingSelections[term];
          final expectedDef = q.matchingPairs?.firstWhere(
            (p) => p["term"]?.trim().toLowerCase() == term.trim().toLowerCase(),
            orElse: () => const {},
          )["definition"];

          final isMatched = _hasSubmittedCurrent &&
              expectedDef != null &&
              selectedDef != null &&
              selectedDef.trim().toLowerCase() == expectedDef.trim().toLowerCase();

          Color borderColor = context.cardBorderColor;
          Color bgColor = context.surfaceColor;

          if (_hasSubmittedCurrent) {
            if (isMatched) {
              borderColor = const Color(0xFF10B981);
              bgColor = const Color(0xFF10B981).withValues(alpha: 0.1);
            } else {
              borderColor = const Color(0xFFEF4444);
              bgColor = const Color(0xFFEF4444).withValues(alpha: 0.08);
            }
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: _hasSubmittedCurrent ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        term,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _hasSubmittedCurrent
                          ? Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedDef ?? '(none)',
                                    style: TextStyle(
                                      color: isMatched
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Icon(
                                  isMatched
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: isMatched
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                  size: 16,
                                ),
                              ],
                            )
                          : DropdownButton<String>(
                              value: selectedDef,
                              hint: const Text('Select...'),
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: _matchingDefinitions
                                  .map(
                                    (def) => DropdownMenuItem(
                                      value: def,
                                      child: Text(
                                        def,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _matchingSelections[term] = val),
                            ),
                    ),
                  ],
                ),
                if (_hasSubmittedCurrent &&
                    !isMatched &&
                    expectedDef != null &&
                    expectedDef.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '100% Match: $expectedDef',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  bool get _isCurrentCorrect {
    final q = widget.questions[_currentIndex];
    switch (q.type) {
      case QuestionTypeEnum.multipleChoice:
      case QuestionTypeEnum.scenario:
        if (_selectedOptionId == null) return false;
        final selected =
            q.options.where((o) => o.id == _selectedOptionId).firstOrNull;
        return selected?.isCorrect == true;
      case QuestionTypeEnum.trueFalse:
        if (_selectedTrueFalse == null || q.isTrue == null) return false;
        return _selectedTrueFalse == q.isTrue;
      case QuestionTypeEnum.matching:
        if (_matchingSelections.isEmpty ||
            (q.matchingPairs == null || q.matchingPairs!.isEmpty)) {
          return false;
        }
        for (final pair in q.matchingPairs!) {
          final term = pair["term"] ?? "";
          final def = pair["definition"] ?? "";
          if (_matchingSelections[term]?.trim().toLowerCase() !=
              def.trim().toLowerCase()) {
            return false;
          }
        }
        return true;
      case QuestionTypeEnum.identification:
      case QuestionTypeEnum.cloze:
        final entered = _textController.text.trim().toLowerCase();
        if (entered.isEmpty) return false;
        final candidates = <String>[];
        if (q.correctAnswer != null && q.correctAnswer!.isNotEmpty) {
          candidates.add(q.correctAnswer!.trim().toLowerCase());
        }
        for (final opt in q.options.where((o) => o.isCorrect)) {
          candidates.add(opt.optionText.trim().toLowerCase());
        }
        return candidates.any((c) => _isFuzzyMatch(entered, c));
      case QuestionTypeEnum.enumeration:
      case QuestionTypeEnum.bulletPoints:
        final entered = _textController.text.trim().toLowerCase();
        if (entered.isEmpty) return false;
        final accepted = q.options
            .where((o) => o.isCorrect)
            .map((o) => o.optionText.trim().toLowerCase())
            .toList();
        if (accepted.isEmpty && q.correctAnswer != null) {
          accepted.addAll(q.correctAnswer!
              .toLowerCase()
              .split(RegExp(r'[,;\n]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty));
        }
        return accepted.any((item) => entered.contains(item));
      default:
        final entered = _textController.text.trim().toLowerCase();
        return entered.isNotEmpty;
    }
  }

  static bool _isFuzzyMatch(String a, String b) {
    if (a == b) return true;
    final cleanA = a.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanB = b.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (cleanA == cleanB && cleanA.isNotEmpty) return true;
    if (cleanB.contains(cleanA) && cleanA.length >= 3) return true;
    return false;
  }

  Widget _buildRealtimeAnswerFeedbackBanner(QuestionModel q) {
    final isCorrect = _isCurrentCorrect;
    final primaryColor =
        isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final iconData =
        isCorrect ? Icons.check_circle_rounded : Icons.highlight_off_rounded;
    final title =
        isCorrect ? '100% Correct Recall!' : 'Answer Revealed: Review Key';
    final subtitle = isCorrect
        ? 'Spot on! You selected the verified 100% accurate solution.'
        : 'The exact 100% correct answer is highlighted in green below.';
    final badgeLabel = isCorrect ? '100% Accurate' : 'Exact Answer Revealed';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: primaryColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badgeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiExplanationCard(QuestionModel q) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Pedagogical Explanation & Rationale',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q.explanation!,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExactAnswerKeyCard(QuestionModel q) {
    final answerText = q.exactAnswerText.isNotEmpty
        ? q.exactAnswerText
        : (q.options
                .where((o) => o.isCorrect)
                .map((o) => o.optionText)
                .join(', ')
                .isNotEmpty
            ? q.options
                .where((o) => o.isCorrect)
                .map((o) => o.optionText)
                .join(', ')
            : (q.correctAnswer ?? ''));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.14),
            const Color(0xFF059669).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exact 100% Answer Key',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '100% Accuracy',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              answerText,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: context.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

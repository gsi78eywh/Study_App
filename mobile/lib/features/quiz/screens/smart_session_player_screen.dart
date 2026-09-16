import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../practice/models/adaptive_models.dart";

class SmartSessionPlayerScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SmartSessionPayloadModel? payload;
  final String? initialCourseId;
  final VoidCallback onSessionComplete;

  const SmartSessionPlayerScreen({
    super.key,
    required this.apiClient,
    this.payload,
    this.initialCourseId,
    required this.onSessionComplete,
  });

  @override
  State<SmartSessionPlayerScreen> createState() => _SmartSessionPlayerScreenState();
}

class _SmartSessionPlayerScreenState extends State<SmartSessionPlayerScreen> {
  // Current stage: 0 = Flashcards, 1 = Retrieval Practice, 2 = Mistake Drill, 3 = Summary
  int _currentStage = 0;
  int _flashcardIndex = 0;
  bool _isCardFlipped = false;

  int _retrievalIndex = 0;
  String? _selectedOption;
  bool _isQuestionSubmitted = false;

  int _mistakeIndex = 0;
  String? _mistakeSelectedOption;
  bool _isMistakeSubmitted = false;

  int _correctRetrievalCount = 0;
  int _resolvedMistakesCount = 0;
  int _flashcardsReviewedCount = 0;

  SmartSessionPayloadModel? _sessionPayload;
  bool _isLoadingPayload = false;

  SmartSessionPayloadModel get payload => _sessionPayload!;

  @override
  void initState() {
    super.initState();
    if (widget.payload != null) {
      _sessionPayload = widget.payload;
    } else {
      _loadSessionPayload();
    }
  }

  Future<void> _loadSessionPayload() async {
    setState(() => _isLoadingPayload = true);
    try {
      final res = await widget.apiClient.getSmartSession(courseId: widget.initialCourseId);
      if (mounted) {
        setState(() {
          _sessionPayload = res ??
              SmartSessionPayloadModel(
                sessionTitle: "Personalized Smart Session",
                estimatedMinutes: 25,
                flashcards: [],
                retrievalQuestions: [],
                mistakeDrillQuestions: [],
              );
          _isLoadingPayload = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sessionPayload = SmartSessionPayloadModel(
            sessionTitle: "Personalized Smart Session",
            estimatedMinutes: 25,
            flashcards: [],
            retrievalQuestions: [],
            mistakeDrillQuestions: [],
          );
          _isLoadingPayload = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    if (_isLoadingPayload || _sessionPayload == null) {
      return Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: AppBar(title: const Text("⚡ Smart Study Session")),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF6366F1)),
              SizedBox(height: 16),
              Text("Synthesizing interleaved study session..."),
            ],
          ),
        ),
      );
    }

    if (_currentStage == 3) {
      return _buildSummaryScreen(context, isDark);
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "⚡ Smart Study Session",
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _stageTitle(),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _stageColor(),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: "Exit Session",
            onPressed: () => _confirmExit(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _calculateOverallProgress(),
            backgroundColor: context.cardBorderColor,
            valueColor: AlwaysStoppedAnimation<Color>(_stageColor()),
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _buildCurrentStageView(context, isDark),
        ),
      ),
    );
  }

  String _stageTitle() {
    switch (_currentStage) {
      case 0:
        return "Stage 1 of 3: Spaced Flashcard Recall (${_flashcardIndex + 1}/${payload.flashcards.length})";
      case 1:
        return "Stage 2 of 3: Weak-Topic Retrieval (${_retrievalIndex + 1}/${payload.retrievalQuestions.length})";
      case 2:
        return "Stage 3 of 3: Mistake Bank Drill (${_mistakeIndex + 1}/${payload.mistakeDrillQuestions.length})";
      default:
        return "Complete";
    }
  }

  Color _stageColor() {
    switch (_currentStage) {
      case 0:
        return const Color(0xFF10B981);
      case 1:
        return const Color(0xFF6366F1);
      case 2:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  double _calculateOverallProgress() {
    final totalStages = 3;
    final stageProgress = _currentStage / totalStages;
    double innerProgress = 0.0;
    if (_currentStage == 0 && payload.flashcards.isNotEmpty) {
      innerProgress = _flashcardIndex / (payload.flashcards.length * totalStages);
    } else if (_currentStage == 1 && payload.retrievalQuestions.isNotEmpty) {
      innerProgress = _retrievalIndex / (payload.retrievalQuestions.length * totalStages);
    } else if (_currentStage == 2 && payload.mistakeDrillQuestions.isNotEmpty) {
      innerProgress = _mistakeIndex / (payload.mistakeDrillQuestions.length * totalStages);
    }
    return (stageProgress + innerProgress).clamp(0.0, 1.0);
  }

  Widget _buildCurrentStageView(BuildContext context, bool isDark) {
    if (_currentStage == 0) {
      if (payload.flashcards.isEmpty) {
        return _buildSkipStagePrompt("No flashcards due", () => setState(() => _currentStage = 1));
      }
      return _buildFlashcardStage(context, isDark);
    } else if (_currentStage == 1) {
      if (payload.retrievalQuestions.isEmpty) {
        return _buildSkipStagePrompt("No retrieval questions", () => setState(() => _currentStage = 2));
      }
      return _buildRetrievalStage(context, isDark);
    } else {
      if (payload.mistakeDrillQuestions.isEmpty) {
        return _buildSkipStagePrompt("No mistakes to drill", () => setState(() => _currentStage = 3));
      }
      return _buildMistakeStage(context, isDark);
    }
  }

  Widget _buildSkipStagePrompt(String message, VoidCallback onSkip) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF10B981)),
          const SizedBox(height: 12),
          Text(message, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onSkip, child: const Text("Continue to Next Stage")),
        ],
      ),
    );
  }

  // --- Stage 1: Flashcards ---
  Widget _buildFlashcardStage(BuildContext context, bool isDark) {
    final card = payload.flashcards[_flashcardIndex];

    return Column(
      children: [
        // Cognitive Dimension Tag & Why Reason
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                card.dimensionTag,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF10B981),
                ),
              ),
            ),
            Text(
              card.reasonWhy,
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Flippable Flashcard
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isCardFlipped = !_isCardFlipped),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isCardFlipped ? const Color(0xFF10B981) : context.cardBorderColor,
                  width: _isCardFlipped ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isCardFlipped ? "EXPLANATION / ANSWER" : "FRONT / CONCEPT",
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: _isCardFlipped ? const Color(0xFF10B981) : context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isCardFlipped ? card.answer : card.prompt,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_outlined, size: 14, color: context.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        _isCardFlipped ? "Tap to flip back" : "Tap card to reveal answer",
                        style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Rating / Recall Actions
        if (_isCardFlipped)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _advanceFlashcard(1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Again (<1d)"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _advanceFlashcard(3),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Good (7d)"),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _isCardFlipped = true),
              icon: const Icon(Icons.flip_rounded),
              label: const Text("Show Answer"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  void _advanceFlashcard(int rating) {
    _flashcardsReviewedCount++;
    if (_flashcardIndex + 1 < payload.flashcards.length) {
      setState(() {
        _flashcardIndex++;
        _isCardFlipped = false;
      });
    } else {
      _showStageCompleteModal(
        "🎉 Stage 1 Complete!",
        "You reviewed $_flashcardsReviewedCount flashcards.",
        "Proceed to Stage 2: Weak-Topic Retrieval Practice",
        () {
          setState(() {
            _currentStage = 1;
            _retrievalIndex = 0;
            _selectedOption = null;
            _isQuestionSubmitted = false;
          });
        },
      );
    }
  }

  // --- Stage 2: Retrieval Practice ---
  Widget _buildRetrievalStage(BuildContext context, bool isDark) {
    final q = payload.retrievalQuestions[_retrievalIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                q.stageName,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6366F1),
                ),
              ),
            ),
            Text(
              "Adaptive Drill",
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Text(
          q.prompt,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: ListView(
            children: q.options.map((opt) {
              final isSelected = _selectedOption == opt.text;
              Color border = context.cardBorderColor;
              Color bg = context.surfaceColor;

              if (_isQuestionSubmitted) {
                if (opt.isCorrect) {
                  border = const Color(0xFF10B981);
                  bg = const Color(0xFF10B981).withValues(alpha: 0.12);
                } else if (isSelected && !opt.isCorrect) {
                  border = const Color(0xFFEF4444);
                  bg = const Color(0xFFEF4444).withValues(alpha: 0.12);
                }
              } else if (isSelected) {
                border = const Color(0xFF6366F1);
                bg = const Color(0xFF6366F1).withValues(alpha: 0.1);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: isSelected ? 2 : 1),
                ),
                child: ListTile(
                  onTap: _isQuestionSubmitted
                      ? null
                      : () => setState(() => _selectedOption = opt.text),
                  title: Text(
                    opt.text,
                    style: GoogleFonts.inter(fontSize: 14, color: context.textPrimary),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        if (_isQuestionSubmitted) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Explanation",
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1)),
                ),
                const SizedBox(height: 4),
                Text(q.explanation, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _advanceRetrieval,
              child: const Text("Next Question"),
            ),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _selectedOption == null
                  ? null
                  : () {
                      final correct = q.options.any((o) => o.text == _selectedOption && o.isCorrect);
                      if (correct) _correctRetrievalCount++;
                      setState(() => _isQuestionSubmitted = true);
                    },
              child: const Text("Submit Answer"),
            ),
          ),
      ],
    );
  }

  void _advanceRetrieval() {
    if (_retrievalIndex + 1 < payload.retrievalQuestions.length) {
      setState(() {
        _retrievalIndex++;
        _selectedOption = null;
        _isQuestionSubmitted = false;
      });
    } else {
      _showStageCompleteModal(
        "🎯 Stage 2 Complete!",
        "Score: $_correctRetrievalCount/${payload.retrievalQuestions.length} correct in retrieval practice.",
        "Proceed to Stage 3: Mistake Bank Drill",
        () {
          setState(() {
            _currentStage = 2;
            _mistakeIndex = 0;
            _mistakeSelectedOption = null;
            _isMistakeSubmitted = false;
          });
        },
      );
    }
  }

  // --- Stage 3: Mistake Bank Drill ---
  Widget _buildMistakeStage(BuildContext context, bool isDark) {
    final q = payload.mistakeDrillQuestions[_mistakeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.replay_rounded, size: 13, color: Color(0xFFEF4444)),
                  const SizedBox(width: 4),
                  Text(
                    "MISTAKE BANK RETRY",
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              q.reasonWhy,
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Text(
          q.prompt,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: ListView(
            children: q.options.map((opt) {
              final isSelected = _mistakeSelectedOption == opt.text;
              Color border = context.cardBorderColor;
              Color bg = context.surfaceColor;

              if (_isMistakeSubmitted) {
                if (opt.isCorrect) {
                  border = const Color(0xFF10B981);
                  bg = const Color(0xFF10B981).withValues(alpha: 0.12);
                } else if (isSelected && !opt.isCorrect) {
                  border = const Color(0xFFEF4444);
                  bg = const Color(0xFFEF4444).withValues(alpha: 0.12);
                }
              } else if (isSelected) {
                border = const Color(0xFFEF4444);
                bg = const Color(0xFFEF4444).withValues(alpha: 0.08);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: isSelected ? 2 : 1),
                ),
                child: ListTile(
                  onTap: _isMistakeSubmitted
                      ? null
                      : () => setState(() => _mistakeSelectedOption = opt.text),
                  title: Text(
                    opt.text,
                    style: GoogleFonts.inter(fontSize: 14, color: context.textPrimary),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        if (_isMistakeSubmitted) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Why This Answer Matters",
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                ),
                const SizedBox(height: 4),
                Text(q.explanation, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _advanceMistake,
              child: const Text("Next"),
            ),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _mistakeSelectedOption == null
                  ? null
                  : () {
                      final correct = q.options.any((o) => o.text == _mistakeSelectedOption && o.isCorrect);
                      if (correct) {
                        _resolvedMistakesCount++;
                        widget.apiClient.resolveMistake(q.questionId, isResolved: true);
                      }
                      setState(() => _isMistakeSubmitted = true);
                    },
              child: const Text("Submit Mistake Retry"),
            ),
          ),
      ],
    );
  }

  void _advanceMistake() {
    if (_mistakeIndex + 1 < payload.mistakeDrillQuestions.length) {
      setState(() {
        _mistakeIndex++;
        _mistakeSelectedOption = null;
        _isMistakeSubmitted = false;
      });
    } else {
      setState(() => _currentStage = 3);
    }
  }

  void _showStageCompleteModal(String title, String subtitle, String buttonLabel, VoidCallback onNext) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 52, color: Color(0xFF10B981)),
            const SizedBox(height: 12),
            Text(title, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onNext();
                },
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Final Summary & Mastery Delta Screen ---
  Widget _buildSummaryScreen(BuildContext context, bool isDark) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF10B981)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_rounded, size: 64, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                "⚡ Smart Session Complete!",
                style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                "You reinforced critical concepts across 3 cognitive stages without study fatigue.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 28),

              // Metrics Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricCol("Cards Recalled", "$_flashcardsReviewedCount", const Color(0xFF10B981)),
                    Container(height: 36, width: 1, color: context.cardBorderColor),
                    _buildMetricCol("Retrieval Correct", "$_correctRetrievalCount", const Color(0xFF6366F1)),
                    Container(height: 36, width: 1, color: context.cardBorderColor),
                    _buildMetricCol("Mistakes Resolved", "$_resolvedMistakesCount", const Color(0xFFEF4444)),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Mastery Delta Badge
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, color: Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Estimated Topic Mastery: +8% gain recorded from today's retrieval practice!",
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onSessionComplete();
                    Navigator.pop(context);
                  },
                  child: const Text("Return to Dashboard"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Exit Smart Session?"),
        content: const Text("Progress in completed stages has been saved to your learning profile."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Stay")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("Exit", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

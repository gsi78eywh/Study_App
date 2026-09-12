import "dart:math" as math;
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../quiz/models/quiz_models.dart";

class FlashcardItem {
  final String id;
  final String courseCode;
  final String studySetId;
  final String studySetTitle;
  final String front;
  final String back;
  final String? category;
  final String? hint;
  String interval; // "1d", "3d", "7d", "14d"
  bool isMastered;

  FlashcardItem({
    required this.id,
    required this.courseCode,
    required this.studySetId,
    required this.studySetTitle,
    required this.front,
    required this.back,
    this.category,
    this.hint,
    this.interval = "1d",
    this.isMastered = false,
  });
}

class FlashcardsScreen extends StatefulWidget {
  final List<CourseModel> courses;
  final String? initialStudySetId;
  final ApiClient? apiClient;
  final VoidCallback? onLoadStarterPack;
  final VoidCallback? onNavigateToStudio;

  const FlashcardsScreen({
    super.key,
    required this.courses,
    this.initialStudySetId,
    this.apiClient,
    this.onLoadStarterPack,
    this.onNavigateToStudio,
  });

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  final String _selectedCourseFilter = "ALL";
  String _selectedSetFilter = "ALL";
  int _currentIndex = 0;
  bool _showBack = false;

  final List<FlashcardItem> _allCards = [];
  List<FlashcardItem> _filteredCards = [];

  final Set<String> _masteredIds = {};
  final Set<String> _learningIds = {};
  final Set<String> _highRiskIds = {};

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    )..addListener(() {
        if (_flipAnimation.value >= 0.5 && !_showBack) {
          setState(() => _showBack = true);
        } else if (_flipAnimation.value < 0.5 && _showBack) {
          setState(() => _showBack = false);
        }
      });

    if (widget.initialStudySetId != null) {
      _selectedSetFilter = widget.initialStudySetId!;
    }

    _initializeCards();
    _fetchRealQuestionsIfAvailable();
  }

  @override
  void didUpdateWidget(FlashcardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.courses.length != oldWidget.courses.length ||
        widget.initialStudySetId != oldWidget.initialStudySetId) {
      if (widget.initialStudySetId != null) {
        _selectedSetFilter = widget.initialStudySetId!;
      }
      _initializeCards();
      _fetchRealQuestionsIfAvailable();
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _fetchRealQuestionsIfAvailable() async {
    if (widget.apiClient == null) return;

    // Fetch questions for target study sets
    final setsToFetch = <StudySetModel>[];
    for (final c in widget.courses) {
      for (final s in c.studySets) {
        if (_selectedSetFilter == "ALL" || _selectedSetFilter == s.id) {
          setsToFetch.add(s);
        }
      }
    }

    bool hasNewCards = false;
    for (final set in setsToFetch) {
      try {
        final response = await widget.apiClient!.dio.get("/api/v1/studysets/${set.id}/questions");
        if (response.statusCode == 200 && response.data is List) {
          final List list = response.data;
          final questions = list.map((item) => QuestionModel.fromJson(item as Map<String, dynamic>)).toList();

          if (questions.isNotEmpty) {
            // Remove any placeholder cards for this set
            _allCards.removeWhere((c) => c.studySetId == set.id);

            final course = widget.courses.firstWhere(
              (c) => c.studySets.any((s) => s.id == set.id),
              orElse: () => widget.courses.first,
            );

            for (final q in questions) {
              final correctOpt = q.options.firstWhere(
                (o) => o.isCorrect,
                orElse: () => q.options.isNotEmpty
                    ? q.options.first
                    : QuestionOptionModel(id: "none", optionText: "Verified Concept", isCorrect: true),
              );

              final backText = StringBuffer();
              backText.writeln(correctOpt.optionText);
              if (q.explanation != null && q.explanation!.trim().isNotEmpty) {
                backText.writeln("\n💡 ${q.explanation!.trim()}");
              }

              _allCards.add(FlashcardItem(
                id: "card-${q.id}",
                courseCode: course.code,
                studySetId: set.id,
                studySetTitle: set.title,
                front: q.prompt,
                back: backText.toString().trim(),
                category: set.title,
                hint: q.hints.isNotEmpty ? q.hints.first : null,
              ));
            }
            hasNewCards = true;
          }
        }
      } catch (_) {}
    }

    if (hasNewCards && mounted) {
      _applyFilter();
    }
  }

  void _initializeCards() {
    _allCards.clear();

    for (final course in widget.courses) {
      for (final studySet in course.studySets) {
        if (studySet.bulletPoints.isNotEmpty) {
          for (int i = 0; i < studySet.bulletPoints.length; i++) {
            final bullet = studySet.bulletPoints[i];
            if (bullet.contains(":") || bullet.contains("—") || bullet.contains(" states ")) {
              final parts = bullet.split(RegExp(r"[:—]|(?<=\bstates\b)"));
              if (parts.length >= 2) {
                final q = parts[0].trim();
                final a = parts.sublist(1).join(" ").trim();
                if (q.length > 4 && a.length > 4) {
                  _allCards.add(FlashcardItem(
                    id: "card-${course.code}-$i-${studySet.id.substring(0, math.min(6, studySet.id.length))}",
                    courseCode: course.code,
                    studySetId: studySet.id,
                    studySetTitle: studySet.title,
                    front: q,
                    back: a,
                    category: studySet.title,
                  ));
                }
              }
            } else if (bullet.length > 20) {
              _allCards.add(FlashcardItem(
                id: "card-${course.code}-$i-${studySet.id.substring(0, math.min(6, studySet.id.length))}",
                courseCode: course.code,
                studySetId: studySet.id,
                studySetTitle: studySet.title,
                front: "Core Concept (${studySet.title})",
                back: bullet,
                category: studySet.title,
              ));
            }
          }
        } else if (studySet.description != null && studySet.description!.isNotEmpty) {
          _allCards.add(FlashcardItem(
            id: "card-${course.code}-${studySet.id}",
            courseCode: course.code,
            studySetId: studySet.id,
            studySetTitle: studySet.title,
            front: "Overview of '${studySet.title}'",
            back: studySet.description!,
            category: course.name,
          ));
        }
      }
    }
    _applyFilter();
  }

  void _applyFilter() {
    setState(() {
      _filteredCards = _allCards.where((c) {
        final matchesCourse = _selectedCourseFilter == "ALL" || c.courseCode == _selectedCourseFilter;
        final matchesSet = _selectedSetFilter == "ALL" || c.studySetId == _selectedSetFilter;
        return matchesCourse && matchesSet;
      }).toList();

      _currentIndex = 0;
      _resetCardFlip();
    });
  }

  void _resetCardFlip() {
    _showBack = false;
    _flipController.reset();
  }

  void _toggleFlip() {
    if (_flipController.isAnimating) return;
    if (_flipController.isCompleted) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
  }

  void _rateCard(String rating, String interval) {
    if (_filteredCards.isEmpty) return;
    final currentCard = _filteredCards[_currentIndex];
    currentCard.interval = interval;

    setState(() {
      if (rating == "again" || rating == "hard") {
        _learningIds.add(currentCard.id);
        _highRiskIds.add(currentCard.id);
        _masteredIds.remove(currentCard.id);
        currentCard.isMastered = false;
      } else {
        _learningIds.remove(currentCard.id);
        _highRiskIds.remove(currentCard.id);
        _masteredIds.add(currentCard.id);
        currentCard.isMastered = true;
      }

      if (_currentIndex < _filteredCards.length - 1) {
        _currentIndex++;
        _resetCardFlip();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🎉 Completed study session! ${_masteredIds.length} cards mastered."),
            backgroundColor: AppColors.accent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _shuffleCards() {
    setState(() {
      _filteredCards.shuffle();
      _currentIndex = 0;
      _resetCardFlip();
    });
  }

  void _resetDeck() {
    setState(() {
      _masteredIds.clear();
      _learningIds.clear();
      _highRiskIds.clear();
      _currentIndex = 0;
      _resetCardFlip();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Flashcard deck progress reset"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final canPop = Navigator.of(context).canPop();
    

    final allStudySets = <StudySetModel>[];
    for (final c in widget.courses) {
      allStudySets.addAll(c.studySets);
    }

    final totalCards = _filteredCards.length;
    final masteredCount = _filteredCards.where((c) => _masteredIds.contains(c.id)).length;
    final learningCount = _filteredCards.where((c) => _learningIds.contains(c.id)).length;
    final progress = totalCards > 0 ? (masteredCount / totalCards) : 0.0;

    String currentSetTitle = "All Study Sets";
    if (_selectedSetFilter != "ALL") {
      final match = allStudySets.where((s) => s.id == _selectedSetFilter).firstOrNull;
      if (match != null) currentSetTitle = match.title;
    }

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: Text(currentSetTitle, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Screen Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            canPop ? "Study Set Practice" : "Spaced Recall Flashcards",
                            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedSetFilter != "ALL"
                                ? "Practicing: $currentSetTitle"
                                : "Active recall intervals strengthen long-term retention",
                            style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
                          ),
                        ],
                      ),
                      if (totalCards > 0)
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.refresh_rounded, color: context.textSecondary),
                              tooltip: "Reset Deck Progress",
                              onPressed: _resetDeck,
                            ),
                            IconButton(
                              icon: Icon(Icons.shuffle_rounded, color: isDark ? AppColors.primaryLight : AppColors.primaryDark),
                              tooltip: "Shuffle Deck",
                              onPressed: _shuffleCards,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Study Set Selector if multiple study sets exist
                  if (allStudySets.length > 1 && !canPop) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSetFilter,
                          isExpanded: true,
                          dropdownColor: context.surfaceColor,
                          items: [
                            const DropdownMenuItem(value: "ALL", child: Text("📚 All Study Sets (Combined Deck)")),
                            ...allStudySets.map((s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text("📖 ${s.title} (${s.questionCount} Qs)"),
                                )),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSetFilter = val);
                              _applyFilter();
                              _fetchRealQuestionsIfAvailable();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Visual Mastery Meter
                  if (totalCards > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.insights_rounded, size: 18, color: AppColors.accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Visual Mastery Meter",
                                    style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Text(
                                "${(progress * 100).toInt()}% Mastered",
                                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: context.secondaryBg,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("🟢 Mastered: $masteredCount", style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                              Text("🟡 Learning: $learningCount", style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                              Text("🔴 High-Risk: ${_highRiskIds.length}", style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                              Text("Total Cards: $totalCards", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Empty State with Direct Action Buttons
                  if (totalCards == 0)
                    Container(
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.style_outlined, size: 48, color: isDark ? AppColors.primaryLight : AppColors.primaryDark),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            "No Flashcards in this Deck",
                            style: GoogleFonts.outfit(fontSize: 20, color: context.textPrimary, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Upload lecture notes, whiteboard photos, or PDFs in the AI Studio to generate active recall flashcards.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (widget.onLoadStarterPack != null && widget.courses.isEmpty)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                  label: const Text("✨ Load Biology 101 Starter Pack", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: widget.onLoadStarterPack,
                                ),
                              if (widget.onNavigateToStudio != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.textPrimary,
                                    side: BorderSide(color: context.cardBorderColor),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                  label: const Text("⚡ Open AI Studio Ingestion"),
                                  onPressed: widget.onNavigateToStudio,
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // Card Navigation Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Card ${_currentIndex + 1} of $totalCards",
                          style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back_ios_rounded, size: 16, color: context.textPrimary.withValues(alpha: 0.7)),
                              onPressed: _currentIndex > 0
                                  ? () {
                                      setState(() {
                                        _currentIndex--;
                                        _resetCardFlip();
                                      });
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: context.textPrimary.withValues(alpha: 0.7)),
                              onPressed: _currentIndex < totalCards - 1
                                  ? () {
                                      setState(() {
                                        _currentIndex++;
                                        _resetCardFlip();
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Flip Card Interactive Widget
                    GestureDetector(
                      onTap: _toggleFlip,
                      child: AnimatedBuilder(
                        animation: _flipAnimation,
                        builder: (context, child) {
                          final angle = _flipAnimation.value * math.pi;
                          final isUnder = _flipAnimation.value >= 0.5;
                          final card = _filteredCards[_currentIndex];

                          return Transform(
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateY(angle),
                            alignment: Alignment.center,
                            child: Transform(
                              transform: Matrix4.identity()..rotateY(isUnder ? math.pi : 0),
                              alignment: Alignment.center,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 280),
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: context.surfaceColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isUnder ? AppColors.accent.withValues(alpha: 0.5) : context.cardBorderColor,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            card.studySetTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isUnder ? AppColors.accent.withValues(alpha: 0.15) : context.secondaryBg,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isUnder ? "ANSWER / EXPLANATION" : "QUESTION / PROMPT",
                                            style: TextStyle(
                                              color: isUnder ? AppColors.accent : context.textSecondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),

                                    Center(
                                      child: Text(
                                        isUnder ? card.back : card.front,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: isUnder ? 16 : 19,
                                          fontWeight: isUnder ? FontWeight.w500 : FontWeight.w600,
                                          color: context.textPrimary,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.touch_app_outlined, size: 15, color: context.textSecondary.withValues(alpha: 0.7)),
                                          const SizedBox(width: 6),
                                          Text(
                                            isUnder ? "Tap to view question" : "Tap card to reveal verified answer",
                                            style: TextStyle(color: context.textSecondary.withValues(alpha: 0.7), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Spaced Repetition 4-Button Grading Controls
                    Text(
                      "Rate Retention (Spaced Repetition Interval)",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Again (1d)
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _rateCard("again", "1d"),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text("Again", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                SizedBox(height: 2),
                                Text("< 1 Day", style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Hard (3d)
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFFF59E0B),
                              side: const BorderSide(color: Color(0xFFF59E0B), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _rateCard("hard", "3d"),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text("Hard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                SizedBox(height: 2),
                                Text("3 Days", style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Good (7d)
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _rateCard("good", "7d"),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text("Good", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                SizedBox(height: 2),
                                Text("7 Days", style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Easy (14d)
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFF6366F1),
                              side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _rateCard("easy", "14d"),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text("Easy", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                SizedBox(height: 2),
                                Text("14 Days", style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

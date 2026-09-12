import "dart:math" as math;
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

class FlashcardItem {
  final String id;
  final String courseCode;
  final String front;
  final String back;
  final String? category;
  final String? hint;
  bool isMastered;

  FlashcardItem({
    required this.id,
    required this.courseCode,
    required this.front,
    required this.back,
    this.category,
    this.hint,
    this.isMastered = false,
  });
}

class FlashcardsScreen extends StatefulWidget {
  final List<CourseModel> courses;

  const FlashcardsScreen({
    super.key,
    required this.courses,
  });

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  String _selectedCourseFilter = "ALL";
  int _currentIndex = 0;
  bool _showBack = false;
  bool _showHint = false;

  final List<FlashcardItem> _allCards = [];
  List<FlashcardItem> _filteredCards = [];

  final Set<String> _masteredIds = {};
  final Set<String> _learningIds = {};

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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

    _initializeCards();
    _applyFilter();
  }

  @override
  void didUpdateWidget(FlashcardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.courses.length != oldWidget.courses.length) {
      _initializeCards();
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _initializeCards() {
    _allCards.clear();

    // Dynamically generate flashcards exclusively from real courses and study sets
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
                front: "Key Concept (${studySet.title})",
                back: bullet,
                category: studySet.title,
              ));
            }
          }
        } else if (studySet.description != null && studySet.description!.isNotEmpty) {
          _allCards.add(FlashcardItem(
            id: "card-${course.code}-${studySet.id}",
            courseCode: course.code,
            front: "What is covered in '${studySet.title}'?",
            back: studySet.description!,
            category: course.name,
          ));
        }
      }
    }
  }

  void _applyFilter() {
    setState(() {
      if (_selectedCourseFilter == "ALL") {
        _filteredCards = List.from(_allCards);
      } else {
        _filteredCards = _allCards.where((c) => c.courseCode == _selectedCourseFilter).toList();
      }
      _currentIndex = 0;
      _resetCardFlip();
    });
  }

  void _resetCardFlip() {
    _showBack = false;
    _showHint = false;
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

  void _markCard(bool mastered) {
    if (_filteredCards.isEmpty) return;
    final currentCard = _filteredCards[_currentIndex];

    setState(() {
      if (mastered) {
        _masteredIds.add(currentCard.id);
        _learningIds.remove(currentCard.id);
      } else {
        _learningIds.add(currentCard.id);
        _masteredIds.remove(currentCard.id);
      }

      if (_currentIndex < _filteredCards.length - 1) {
        _currentIndex++;
        _resetCardFlip();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🎉 Completed all ${_filteredCards.length} flashcards in this deck!"),
            backgroundColor: AppColors.accent,
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
    final availableCourses = <String>["ALL", ...widget.courses.map((c) => c.code).toSet()];
    final totalCards = _filteredCards.length;
    final masteredCount = _filteredCards.where((c) => _masteredIds.contains(c.id)).length;
    final progress = totalCards > 0 ? (masteredCount / totalCards) : 0.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Spaced Recall Flashcards",
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Active recall strengthens neural retention",
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

              if (availableCourses.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: availableCourses.map((code) {
                      final isSelected = _selectedCourseFilter == code;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(code == "ALL" ? "All Subjects" : code),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                          selectedColor: isDark ? AppColors.primary : AppColors.primaryDark,
                          backgroundColor: context.surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? (isDark ? AppColors.primary : AppColors.primaryDark)
                                  : context.cardBorderColor,
                            ),
                          ),
                          onSelected: (_) {
                            _selectedCourseFilter = code;
                            _applyFilter();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (totalCards > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Deck Progress ($masteredCount of $totalCards Mastered)",
                            style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            "${(progress * 100).toInt()}%",
                            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: context.secondaryBg,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (totalCards == 0)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.style_outlined, size: 56, color: context.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      Text(
                        "No Flashcards Available",
                        style: GoogleFonts.outfit(fontSize: 18, color: context.textPrimary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Upload documents in AI Studio or add a study set with key definitions to generate spaced-recall cards.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                )
              else ...[
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

                GestureDetector(
                  onTap: _toggleFlip,
                  child: AnimatedBuilder(
                    animation: _flipAnimation,
                    builder: (context, child) {
                      final angle = _flipAnimation.value * math.pi;
                      final isUnder = (angle > (math.pi / 2));
                      final card = _filteredCards[_currentIndex];

                      return Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        alignment: Alignment.center,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 320),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isUnder ? context.secondaryBg : context.surfaceColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isUnder
                                  ? AppColors.accent.withValues(alpha: 0.6)
                                  : (isDark ? AppColors.primary.withValues(alpha: 0.5) : AppColors.primaryDark.withValues(alpha: 0.3)),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isUnder ? AppColors.accent : AppColors.primary).withValues(alpha: isDark ? 0.12 : 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Transform(
                            transform: Matrix4.identity()..rotateY(isUnder ? math.pi : 0),
                            alignment: Alignment.center,
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
                                        card.courseCode,
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
                                        isUnder ? "ANSWER / KEY CONCEPT" : "QUESTION / PROMPT",
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

                                if (!isUnder && card.hint != null) ...[
                                  if (_showHint)
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.warning),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              card.hint!,
                                              style: const TextStyle(color: AppColors.warning, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Center(
                                      child: TextButton.icon(
                                        icon: Icon(Icons.help_outline_rounded, size: 16, color: context.textSecondary),
                                        label: Text("Show Hint", style: TextStyle(color: context.textSecondary, fontSize: 12)),
                                        onPressed: () => setState(() => _showHint = true),
                                      ),
                                    ),
                                ],

                                Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app_outlined, size: 15, color: context.textSecondary.withValues(alpha: 0.7)),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Tap card to flip",
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

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text("Still Learning", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _markCard(false),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text("Mastered", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _markCard(true),
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
    );
  }
}

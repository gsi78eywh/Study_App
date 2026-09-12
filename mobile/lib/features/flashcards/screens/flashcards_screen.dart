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

  late List<FlashcardItem> _allCards;
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
    _allCards = [
      FlashcardItem(
        id: "fc-1",
        courseCode: "CS301",
        front: "What is the core premise of the CAP Theorem in distributed databases?",
        back: "A distributed data store can simultaneously guarantee at most TWO out of three properties:\n\n• Consistency (Every read receives the most recent write)\n• Availability (Every non-failing node returns a response)\n• Partition Tolerance (System sustains network splits/partitions)",
        category: "Distributed Systems",
        hint: "Formulated by Eric Brewer in 2000.",
      ),
      FlashcardItem(
        id: "fc-2",
        courseCode: "CS301",
        front: "In the Raft consensus algorithm, how does leader election resolve split votes?",
        back: "Raft utilizes Randomized Election Timeouts (typically 150ms - 300ms).\n\nBy staggering timeouts across candidate nodes, one node times out first, increments the term, and gathers majority votes before rivals initiate competing elections.",
        category: "Consensus Protocols",
        hint: "Think about timing jitter.",
      ),
      FlashcardItem(
        id: "fc-3",
        courseCode: "BIO102",
        front: "What is the primary function of DNA Polymerase III during replication?",
        back: "DNA Polymerase III is the primary prokaryotic replicative enzyme.\n\nIt synthesizes new DNA by polymerizing deoxyribonucleotides in the 5' to 3' direction along the template strand, and performs 3' to 5' exonuclease proofreading.",
        category: "Molecular Genetics",
        hint: "Synthesizes leading strand continuously.",
      ),
      FlashcardItem(
        id: "fc-4",
        courseCode: "BIO102",
        front: "Why are Okazaki fragments formed on the lagging strand during DNA replication?",
        back: "Because DNA polymerase can only synthesize in the 5' to 3' direction, while the replication fork unzips antiparallel (3' to 5').\n\nThe lagging strand must be synthesized discontinuously in short segments, which are later joined by DNA ligase.",
        category: "Molecular Genetics",
        hint: "Antiparallel nature of DNA double helix.",
      ),
      FlashcardItem(
        id: "fc-5",
        courseCode: "MATH201",
        front: "What does it mean for an n×n square matrix A to be invertible?",
        back: "Matrix A is invertible if and only if:\n\n• Determinant det(A) ≠ 0\n• Columns (and rows) of A form a linearly independent basis for R^n\n• Rank(A) = n (Full rank)\n• Zero is not an eigenvalue of A (λ = 0 has no non-trivial eigenvector)",
        category: "Linear Algebra",
        hint: "Invertible Matrix Theorem.",
      ),
      FlashcardItem(
        id: "fc-6",
        courseCode: "MATH201",
        front: "Define an Eigenvector and Eigenvalue of a linear transformation matrix A.",
        back: "A non-zero vector v is an eigenvector with eigenvalue λ if applying transformation A results in scaling v without changing its span direction:\n\nAv = λv  where  v ≠ 0\n\nComputed via characteristic equation det(A - λI) = 0.",
        category: "Linear Algebra",
        hint: "Av = λv",
      ),
    ];

    for (final course in widget.courses) {
      for (final studySet in course.studySets) {
        for (int i = 0; i < studySet.bulletPoints.length; i++) {
          final bullet = studySet.bulletPoints[i];
          if (bullet.contains(":") || bullet.contains("—") || bullet.contains(" states ")) {
            final parts = bullet.split(RegExp(r"[:—]|(?<=\bstates\b)"));
            if (parts.length >= 2) {
              final q = parts[0].trim();
              final a = parts.sublist(1).join(" ").trim();
              if (q.length > 5 && a.length > 5) {
                _allCards.add(FlashcardItem(
                  id: "gen-${course.code}-$i",
                  courseCode: course.code,
                  front: "Key Concept: $q",
                  back: a,
                  category: studySet.title,
                ));
              }
            }
          }
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
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Active recall strengthens neural pathways",
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.darkTextSecondary),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: AppColors.darkTextSecondary),
                        tooltip: "Reset Deck Progress",
                        onPressed: totalCards > 0 ? _resetDeck : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded, color: AppColors.primaryLight),
                        tooltip: "Shuffle Deck",
                        onPressed: totalCards > 0 ? _shuffleCards : null,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

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
                          color: isSelected ? Colors.white : AppColors.darkTextSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.darkCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : AppColors.darkCardBorder,
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

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.darkCardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Deck Progress ($masteredCount of $totalCards Mastered)",
                          style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, fontWeight: FontWeight.w600),
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
                        backgroundColor: AppColors.darkBg,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (totalCards == 0)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkCardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.style_outlined, size: 56, color: AppColors.darkTextSecondary),
                      const SizedBox(height: 16),
                      Text("No Flashcards for $_selectedCourseFilter", style: GoogleFonts.outfit(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text("Upload lecture notes in AI Studio to automatically generate flashcards.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.darkTextSecondary)),
                    ],
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Card ${_currentIndex + 1} of $totalCards",
                      style: const TextStyle(color: AppColors.darkTextSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, size: 16, color: Colors.white70),
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
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
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
                            color: isUnder ? const Color(0xFF1E2433) : AppColors.darkCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isUnder ? AppColors.accent.withValues(alpha: 0.6) : AppColors.primary.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isUnder ? AppColors.accent : AppColors.primary).withValues(alpha: 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
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
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        card.courseCode,
                                        style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isUnder ? AppColors.accent.withValues(alpha: 0.2) : Colors.white12,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isUnder ? "ANSWER / BREAKDOWN" : "QUESTION / PROMPT",
                                        style: TextStyle(
                                          color: isUnder ? AppColors.accent : AppColors.darkTextSecondary,
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
                                      color: Colors.white,
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
                                        icon: const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.darkTextSecondary),
                                        label: const Text("Show Hint", style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                                        onPressed: () => setState(() => _showHint = true),
                                      ),
                                    ),
                                ],

                                Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app_outlined, size: 15, color: AppColors.darkTextSecondary.withValues(alpha: 0.7)),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Tap card to flip",
                                        style: TextStyle(color: AppColors.darkTextSecondary.withValues(alpha: 0.7), fontSize: 12),
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
                          backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.15),
                          foregroundColor: const Color(0xFFF87171),
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
                          backgroundColor: AppColors.accent.withValues(alpha: 0.15),
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

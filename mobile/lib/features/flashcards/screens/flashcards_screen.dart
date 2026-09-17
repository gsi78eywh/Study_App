import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../quiz/models/quiz_models.dart";
import "../utils/flashcard_text_sanitizer.dart";

enum FlashcardStudyMode {
  remix("🔀 Academic Remix"),
  standard("📖 Standard"),
  reverseRecall("🎯 Reverse Recall");

  final String label;
  const FlashcardStudyMode(this.label);
}

class FlashcardItem {
  final String id;
  final String? questionId;
  final String courseCode;
  final String studySetId;
  final String studySetTitle;
  final String front;
  final String back;
  final String? category;
  final String? hint;
  final String? dimensionTag;
  String interval; // "1d", "3d", "7d", "14d"
  bool isMastered;

  FlashcardItem({
    required this.id,
    this.questionId,
    required this.courseCode,
    required this.studySetId,
    required this.studySetTitle,
    required this.front,
    required this.back,
    this.category,
    this.hint,
    this.dimensionTag,
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
  final VoidCallback? onCardDeleted;

  const FlashcardsScreen({
    super.key,
    required this.courses,
    this.initialStudySetId,
    this.apiClient,
    this.onLoadStarterPack,
    this.onNavigateToStudio,
    this.onCardDeleted,
  });


  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  late FocusNode _focusNode;

  final String _selectedCourseFilter = "ALL";
  String _selectedSetFilter = "ALL";
  String _cardFilter = "ALL"; // "ALL", "HIGH_RISK", "MASTERED"
  FlashcardStudyMode _studyMode = FlashcardStudyMode.remix;
  int _currentIndex = 0;
  bool _showBack = false;
  bool _isRefreshing = false;
  bool _showHint = false;

  final List<FlashcardItem> _allCards = [];
  List<FlashcardItem> _filteredCards = [];

  final Set<String> _masteredIds = {};
  final Set<String> _learningIds = {};
  final Set<String> _highRiskIds = {};

  String _resolveDimensionTag(FlashcardItem card) {
    if (card.dimensionTag != null && card.dimensionTag!.trim().isNotEmpty) {
      return card.dimensionTag!.trim();
    }
    final frontLower = card.front.toLowerCase();
    if (frontLower.contains("role") || frontLower.contains("definition") || frontLower.startsWith("what is")) {
      return "CORE CONCEPT";
    }
    if (frontLower.contains("which core concept") || frontLower.contains("characterized by") || frontLower.contains("corresponds to")) {
      return "REVERSE RECALL";
    }
    if (frontLower.contains("consequence") || frontLower.contains("outcome") || frontLower.contains("effect") || frontLower.contains("govern")) {
      return "CAUSE & EFFECT";
    }
    if (frontLower.contains("distinguish") || frontLower.contains("differ") || frontLower.contains("uniquely")) {
      return "KEY DISTINCTION";
    }
    if (frontLower.contains("applied") || frontLower.contains("practical") || frontLower.contains("utilize")) {
      return "APPLICATION DRILL";
    }
    if (frontLower.contains("________") || frontLower.contains("complete the") || frontLower.contains("[ ______ ]")) {
      return "CONTEXTUAL CLOZE";
    }
    return "ACTIVE RECALL";
  }

  Color _dimensionColor(String tag) {
    switch (tag.toUpperCase()) {
      case "CORE CONCEPT":
        return const Color(0xFF3B82F6); // Blue
      case "REVERSE RECALL":
        return const Color(0xFFEC4899); // Pink
      case "CAUSE & EFFECT":
        return const Color(0xFFF59E0B); // Amber/Orange
      case "KEY DISTINCTION":
        return const Color(0xFF06B6D4); // Cyan
      case "APPLICATION DRILL":
        return const Color(0xFF10B981); // Emerald
      case "CONTEXTUAL CLOZE":
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF6366F1); // Indigo
    }
  }

  void _remixDeck() {
    if (_allCards.isEmpty) return;
    setState(() {
      _allCards.shuffle();
      _applyFilter();
      _currentIndex = 0;
      _resetCardFlip();
    });
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.shuffle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Deck remixed! Active recall cards randomized across all 6 cognitive dimensions.",
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
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

    final oldSetsCount = oldWidget.courses.fold<int>(0, (sum, c) => sum + c.studySets.length);
    final newSetsCount = widget.courses.fold<int>(0, (sum, c) => sum + c.studySets.length);
    final oldQuestionsCount = oldWidget.courses.fold<int>(0, (sum, c) => sum + c.studySets.fold<int>(0, (sSum, s) => sSum + s.questionCount));
    final newQuestionsCount = widget.courses.fold<int>(0, (sum, c) => sum + c.studySets.fold<int>(0, (sSum, s) => sSum + s.questionCount));

    if (widget.courses.length != oldWidget.courses.length ||
        oldSetsCount != newSetsCount ||
        oldQuestionsCount != newQuestionsCount ||
        widget.initialStudySetId != oldWidget.initialStudySetId) {
      if (widget.initialStudySetId != null) {
        _selectedSetFilter = widget.initialStudySetId!;
      }
      _initializeCards();
      _fetchRealQuestionsIfAvailable(force: true);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _flipController.dispose();
    super.dispose();
  }

  static String _cleanFlashcardFront(String raw) => FlashcardTextSanitizer.cleanFront(raw);
  static String _cleanOptionAnswer(String raw) => FlashcardTextSanitizer.cleanAnswer(raw);
  static String _cleanExplanation(String raw) => FlashcardTextSanitizer.cleanExplanation(raw);

  Future<void> _refreshDeckFromServer({bool showToast = true}) async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      _initializeCards();
      await _fetchRealQuestionsIfAvailable(force: true);

      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  "Deck updated: ${_filteredCards.length} flashcards loaded from cloud",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Could not sync with server. Showing cached cards."),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _fetchRealQuestionsIfAvailable({bool force = false}) async {
    if (widget.apiClient == null) return;

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
        final response = await widget.apiClient!.dio.get(
          "/api/v1/studysets/${set.id}/questions",
          queryParameters: force ? {"_t": DateTime.now().millisecondsSinceEpoch} : null,
        );
        if (response.statusCode == 200 && response.data is List) {
          final List list = response.data;
          final questions = list.map((item) => QuestionModel.fromJson(item as Map<String, dynamic>)).toList();

          if (questions.isNotEmpty) {
            _allCards.removeWhere((c) => c.studySetId == set.id);

            final course = widget.courses.isNotEmpty
                ? widget.courses.firstWhere(
                    (c) => c.studySets.any((s) => s.id == set.id),
                    orElse: () => widget.courses.first,
                  )
                : CourseModel(
                    id: set.courseId,
                    code: "GEN-101",
                    name: "General Studies",
                    colorHex: "#6366F1",
                    createdAt: DateTime.now(),
                    studySets: [set],
                  );

            for (final q in questions) {
              final correctOpt = q.options.firstWhere(
                (o) => o.isCorrect,
                orElse: () => q.options.isNotEmpty
                    ? q.options.first
                    : QuestionOptionModel(id: "none", optionText: "Verified Concept", isCorrect: true),
              );

              final cleanFront = _cleanFlashcardFront(q.prompt);
              final cleanBackAnswer = _cleanOptionAnswer(correctOpt.optionText);

              final backText = StringBuffer();
              backText.writeln(cleanBackAnswer);
              if (q.explanation != null && q.explanation!.trim().isNotEmpty) {
                final cleanExpl = _cleanExplanation(q.explanation!.trim());
                backText.writeln("\n💡 $cleanExpl");
              }

              _allCards.add(FlashcardItem(
                id: "card-${q.id}",
                questionId: q.id,
                courseCode: course.code,
                studySetId: set.id,
                studySetTitle: set.title,
                front: cleanFront,
                back: backText.toString().trim(),
                category: set.title,
                hint: q.hints.isNotEmpty ? q.hints.first : null,
                dimensionTag: q.dimensionTag,
              ));
            }
            hasNewCards = true;
          }
        }
      } catch (_) {}
    }

    if ((hasNewCards || force) && mounted) {
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
                    front: _cleanFlashcardFront(q),
                    back: _cleanOptionAnswer(a),
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
      final inDeck = _allCards.where((c) {
        final matchesCourse = _selectedCourseFilter == "ALL" || c.courseCode == _selectedCourseFilter;
        final matchesSet = _selectedSetFilter == "ALL" || c.studySetId == _selectedSetFilter;
        return matchesCourse && matchesSet;
      }).toList();

      if (_cardFilter == "HIGH_RISK") {
        _filteredCards = inDeck.where((c) => _highRiskIds.contains(c.id)).toList();
      } else if (_cardFilter == "MASTERED") {
        _filteredCards = inDeck.where((c) => _masteredIds.contains(c.id)).toList();
      } else {
        _filteredCards = inDeck;
      }

      if (_currentIndex >= _filteredCards.length) {
        _currentIndex = _filteredCards.isNotEmpty ? _filteredCards.length - 1 : 0;
      }
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
        _showSessionCompletedDialog();
      }
    });
  }

  void _nextCard() {
    if (_currentIndex < _filteredCards.length - 1) {
      setState(() {
        _currentIndex++;
        _resetCardFlip();
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _resetCardFlip();
      });
    }
  }

  void _shuffleCards() {
    setState(() {
      _filteredCards.shuffle();
      _currentIndex = 0;
      _resetCardFlip();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🔀 Flashcard deck shuffled"),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
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
        content: Text("Retention grading progress reset for this deck"),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDeleteCard(FlashcardItem card) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              "Delete Flashcard?",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete this flashcard from '${card.studySetTitle}'?",
              style: TextStyle(
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.grey.shade100).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              child: Text(
                card.front,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "This removes the question to prevent confusion and errors in future study sessions.",
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key("cancel_delete_card_button"),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              "Cancel",
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
            ),
          ),
          ElevatedButton.icon(
            key: const Key("confirm_delete_card_button"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteCard(card);
    }
  }

  Future<void> _deleteCard(FlashcardItem card) async {
    final deletedQuestionId = card.questionId;
    final deletedCardId = card.id;

    if (deletedQuestionId != null && widget.apiClient != null) {
      try {
        await widget.apiClient!.dio.delete("/api/v1/questions/$deletedQuestionId");
      } catch (e) {
        debugPrint("Error deleting question from server: $e");
      }
    }

    setState(() {
      _allCards.removeWhere((c) => c.id == deletedCardId);
      _filteredCards.removeWhere((c) => c.id == deletedCardId);
      _masteredIds.remove(deletedCardId);
      _learningIds.remove(deletedCardId);
      _highRiskIds.remove(deletedCardId);

      if (_currentIndex >= _filteredCards.length) {
        _currentIndex = _filteredCards.isNotEmpty ? _filteredCards.length - 1 : 0;
      }
      _resetCardFlip();
    });

    widget.onCardDeleted?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text("Flashcard deleted successfully.", style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }


  void _showSessionCompletedDialog() {
    final totalInFilter = _filteredCards.length;
    final masteredCount = _filteredCards.where((c) => _masteredIds.contains(c.id)).length;
    final highRiskCount = _filteredCards.where((c) => _highRiskIds.contains(c.id)).length;
    final pct = totalInFilter > 0 ? ((masteredCount / totalInFilter) * 100).toInt() : 100;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: context.surfaceColor,
        title: Row(
          children: [
            const Text("🎉", style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Text(
              "Deck Completed!",
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: context.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Great work! You reviewed $totalInFilter active recall flashcards.",
              style: TextStyle(color: context.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.secondaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text("$pct%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.accent)),
                      const Text("Mastery", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  Column(
                    children: [
                      Text("$masteredCount", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF10B981))),
                      const Text("Mastered", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  Column(
                    children: [
                      Text("$highRiskCount", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFFEF4444))),
                      const Text("Needs Practice", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (highRiskCount > 0)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.repeat_rounded, size: 16),
              label: Text("Drill Needs Practice ($highRiskCount)"),
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _cardFilter = "HIGH_RISK";
                  _applyFilter();
                });
              },
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _currentIndex = 0;
                _resetCardFlip();
              });
            },
            child: const Text("Restart Deck"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Done"),
          ),
        ],
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

    final inDeckCards = _allCards.where((c) {
      final matchesCourse = _selectedCourseFilter == "ALL" || c.courseCode == _selectedCourseFilter;
      final matchesSet = _selectedSetFilter == "ALL" || c.studySetId == _selectedSetFilter;
      return matchesCourse && matchesSet;
    }).toList();

    final totalDeckCards = inDeckCards.length;
    final totalFilteredCards = _filteredCards.length;
    final masteredCount = inDeckCards.where((c) => _masteredIds.contains(c.id)).length;
    final learningCount = inDeckCards.where((c) => _learningIds.contains(c.id)).length;
    final highRiskCount = inDeckCards.where((c) => _highRiskIds.contains(c.id)).length;
    final progress = totalDeckCards > 0 ? (masteredCount / totalDeckCards) : 0.0;

    String currentSetTitle = "All Study Sets";
    if (_selectedSetFilter != "ALL") {
      final match = allStudySets.where((s) => s.id == _selectedSetFilter).firstOrNull;
      if (match != null) currentSetTitle = match.title;
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _toggleFlip();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nextCard();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _prevCard();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.digit1) {
            _rateCard("again", "1d");
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.digit2) {
            _rateCard("hard", "3d");
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.digit3) {
            _rateCard("good", "7d");
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.digit4) {
            _rateCard("easy", "14d");
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                    // Screen Header with True Cloud Sync Button & Menu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
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
                        ),
                        Row(
                          children: [
                            // Authentic Cloud Sync & Refresher
                            IconButton(
                              icon: _isRefreshing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                    )
                                  : Icon(Icons.cloud_sync_rounded, color: context.textPrimary),
                              tooltip: "Reload & Sync Deck from Cloud",
                              onPressed: _isRefreshing ? null : () => _refreshDeckFromServer(showToast: true),
                            ),
                            // Shuffle
                            IconButton(
                              icon: Icon(Icons.shuffle_rounded, color: isDark ? AppColors.primaryLight : AppColors.primaryDark),
                              tooltip: "Shuffle Deck",
                              onPressed: totalFilteredCards > 1 ? _shuffleCards : null,
                            ),
                            // More Options Menu
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
                              tooltip: "Deck Options",
                              color: context.surfaceColor,
                              onSelected: (action) {
                                if (action == "reset_progress") {
                                  _resetDeck();
                                } else if (action == "reload_all") {
                                  _refreshDeckFromServer(showToast: true);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: "reload_all",
                                  child: Row(
                                    children: [
                                      Icon(Icons.refresh_rounded, size: 18, color: AppColors.accent),
                                      SizedBox(width: 10),
                                      Text("Force Reload from Cloud"),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: "reset_progress",
                                  child: Row(
                                    children: [
                                      Icon(Icons.restart_alt_rounded, size: 18, color: Colors.orange),
                                      SizedBox(width: 10),
                                      Text("Reset Retention Progress"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Study Set Selector if multiple sets exist
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
                              DropdownMenuItem(
                                value: "ALL",
                                child: Text("📚 All Study Sets (${_allCards.length} Cards)"),
                              ),
                              ...allStudySets.map((s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text("📖 ${s.title} (${s.questionCount} Questions)"),
                                  )),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedSetFilter = val;
                                  _cardFilter = "ALL";
                                });
                                _applyFilter();
                                _fetchRealQuestionsIfAvailable(force: true);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Visual Mastery Meter
                    if (totalDeckCards > 0) ...[
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
                                const Row(
                                  children: [
                                    Icon(Icons.insights_rounded, size: 18, color: AppColors.accent),
                                    SizedBox(width: 8),
                                    Text(
                                      "Visual Mastery Meter",
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                                Text("🔴 High-Risk: $highRiskCount", style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                                Text("Total Cards: $totalDeckCards", style: TextStyle(fontSize: 12, color: context.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Filter Chips: All, Needs Practice, Mastered
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text("All Cards ($totalDeckCards)"),
                              selected: _cardFilter == "ALL",
                              onSelected: (_) {
                                setState(() {
                                  _cardFilter = "ALL";
                                  _applyFilter();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                                  const SizedBox(width: 4),
                                  Text("Needs Practice ($highRiskCount)"),
                                ],
                              ),
                              selected: _cardFilter == "HIGH_RISK",
                              onSelected: (_) {
                                setState(() {
                                  _cardFilter = "HIGH_RISK";
                                  _applyFilter();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Text("Mastered ($masteredCount)"),
                                ],
                              ),
                              selected: _cardFilter == "MASTERED",
                              onSelected: (_) {
                                setState(() {
                                  _cardFilter = "MASTERED";
                                  _applyFilter();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Study Mode Switcher & Remix Deck Button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.cardBorderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: FlashcardStudyMode.values.map((mode) {
                                    final isSelected = (_studyMode == mode);
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          setState(() {
                                            _studyMode = mode;
                                            _resetCardFlip();
                                          });
                                          if (mode == FlashcardStudyMode.remix) {
                                            _remixDeck();
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 180),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected ? AppColors.primary : Colors.transparent,
                                            ),
                                          ),
                                          child: Text(
                                            mode.label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? (isDark ? AppColors.primaryLight : AppColors.primaryDark) : context.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: "Remix deck order across all active-recall angles",
                              child: ElevatedButton.icon(
                                onPressed: totalDeckCards > 1 ? _remixDeck : null,
                                icon: const Icon(Icons.shuffle_rounded, size: 14),
                                label: const Text("Remix Deck", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Empty State with Direct Action Buttons
                    if (totalFilteredCards == 0)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                            decoration: BoxDecoration(
                              color: context.surfaceColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: context.cardBorderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
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
                                  _cardFilter != "ALL" ? "No Cards in this Filter" : "No Flashcards in this Deck",
                                  style: GoogleFonts.outfit(fontSize: 20, color: context.textPrimary, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _cardFilter != "ALL"
                                      ? "You have no cards marked under '${_cardFilter == 'HIGH_RISK' ? 'Needs Practice' : 'Mastered'}'. Keep up the great studying!"
                                      : "Upload lecture notes, whiteboard photos, or PDFs in the AI Studio to generate active recall flashcards.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    if (_cardFilter != "ALL")
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                                        label: const Text("Show All Cards", style: TextStyle(fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          setState(() {
                                            _cardFilter = "ALL";
                                            _applyFilter();
                                          });
                                        },
                                      ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                                      label: const Text("Sync Deck from Cloud", style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () => _refreshDeckFromServer(showToast: true),
                                    ),
                                    if (widget.onNavigateToStudio != null)
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: context.textPrimary,
                                          side: BorderSide(color: context.cardBorderColor),
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                          ),
                        ),
                      )
                    else ...[
                      // Card Navigation Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Card ${_currentIndex + 1} of $totalFilteredCards",
                            style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back_ios_rounded, size: 16, color: context.textPrimary.withValues(alpha: 0.7)),
                                onPressed: _currentIndex > 0 ? _prevCard : null,
                              ),
                              IconButton(
                                icon: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: context.textPrimary.withValues(alpha: 0.7)),
                                onPressed: _currentIndex < totalFilteredCards - 1 ? _nextCard : null,
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
                                  padding: const EdgeInsets.all(26),
                                  decoration: BoxDecoration(
                                    color: context.surfaceColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isUnder ? AppColors.accent.withValues(alpha: 0.6) : context.cardBorderColor,
                                      width: isUnder ? 1.8 : 1.2,
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
                                      () {
                                        final dimTag = _resolveDimensionTag(card);
                                        final dimColor = _dimensionColor(dimTag);
                                        final isReverseRecall = (_studyMode == FlashcardStudyMode.reverseRecall);

                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Flexible(
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
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
                                                      color: dimColor.withValues(alpha: 0.14),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: dimColor.withValues(alpha: 0.35)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.psychology_outlined, size: 12, color: dimColor),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          dimTag,
                                                          style: TextStyle(
                                                            color: dimColor,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            letterSpacing: 0.4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!isUnder && card.hint != null && card.hint!.isNotEmpty) ...[
                                                  IconButton(
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    icon: Icon(
                                                      _showHint ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                                                      size: 18,
                                                      color: _showHint ? Colors.amber : context.textSecondary,
                                                    ),
                                                    tooltip: "Toggle Hint",
                                                    onPressed: () => setState(() => _showHint = !_showHint),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isUnder ? AppColors.accent.withValues(alpha: 0.15) : context.secondaryBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    isUnder
                                                        ? (isReverseRecall ? "TARGET CONCEPT" : "VERIFIED ANSWER")
                                                        : (isReverseRecall ? "REVERSE RECALL CUE" : "ACTIVE RECALL PROMPT"),
                                                    style: TextStyle(
                                                      color: isUnder ? AppColors.accent : context.textSecondary,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                IconButton(
                                                  key: const Key("delete_flashcard_icon"),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                  icon: Icon(
                                                    Icons.delete_outline_rounded,
                                                    size: 18,
                                                    color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                                                  ),
                                                  tooltip: "Delete Flashcard",
                                                  onPressed: () => _confirmDeleteCard(card),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }(),
                                      const SizedBox(height: 20),

                                      // Main Prompt / Answer Center Content
                                      () {
                                        final isReverseRecall = (_studyMode == FlashcardStudyMode.reverseRecall);
                                        final displayedText = isUnder
                                            ? (isReverseRecall ? card.front : card.back)
                                            : (isReverseRecall ? card.back : card.front);

                                        return Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isReverseRecall && !isUnder) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  margin: const EdgeInsets.only(bottom: 12),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEC4899).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text(
                                                    "🎯 Reverse Active Recall: Name this concept",
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEC4899)),
                                                  ),
                                                ),
                                              ],
                                              Text(
                                                displayedText,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.outfit(
                                                  fontSize: isUnder ? 17 : 20,
                                                  fontWeight: isUnder ? FontWeight.w500 : FontWeight.w600,
                                                  color: context.textPrimary,
                                                  height: 1.5,
                                                ),
                                              ),
                                              if (!isUnder && _showHint && card.hint != null) ...[
                                                const SizedBox(height: 16),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.lightbulb_rounded, size: 16, color: Colors.amber),
                                                      const SizedBox(width: 6),
                                                      Flexible(
                                                        child: Text(
                                                          "Hint: ${card.hint!}",
                                                          style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }(),
                                      const SizedBox(height: 20),

                                      Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.touch_app_outlined, size: 15, color: context.textSecondary.withValues(alpha: 0.7)),
                                            const SizedBox(width: 6),
                                            Text(
                                              isUnder ? "Tap to flip back to prompt" : "Tap card or press Space to reveal answer",
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
                      const SizedBox(height: 22),

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
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("Easy", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  SizedBox(height: 2),
                                  Text("14 Days", style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Keyboard Shortcuts Helper Bar (Desktop / Web)
                      Center(
                        child: Text(
                          "⌨ Shortcuts: [Space] Flip • [← / →] Prev / Next • [1 - 4] Rate Retention",
                          style: TextStyle(fontSize: 11, color: context.textSecondary.withValues(alpha: 0.6)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

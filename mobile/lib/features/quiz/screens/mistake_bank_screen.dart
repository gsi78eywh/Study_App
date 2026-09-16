import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../practice/models/adaptive_models.dart";
import "quiz_player_screen.dart";
import "../models/quiz_models.dart";

class MistakeBankScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String? initialCourseId;
  final VoidCallback? onMistakesChanged;

  const MistakeBankScreen({
    super.key,
    required this.apiClient,
    this.initialCourseId,
    this.onMistakesChanged,
  });

  @override
  State<MistakeBankScreen> createState() => _MistakeBankScreenState();
}

class _MistakeBankScreenState extends State<MistakeBankScreen> {
  bool _isLoading = true;
  List<MistakeBankItemModel> _mistakes = [];
  String _filter = "unresolved"; // "unresolved", "resolved", "all"

  @override
  void initState() {
    super.initState();
    _loadMistakeBank();
  }

  Future<void> _loadMistakeBank() async {
    setState(() => _isLoading = true);
    final items = await widget.apiClient.getMistakeBank(courseId: widget.initialCourseId);
    if (mounted) {
      setState(() {
        _mistakes = items;
        _isLoading = false;
      });
    }
  }

  List<MistakeBankItemModel> get _filteredMistakes {
    if (_filter == "unresolved") {
      return _mistakes.where((m) => !m.isResolved).toList();
    } else if (_filter == "resolved") {
      return _mistakes.where((m) => m.isResolved).toList();
    }
    return _mistakes;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final unresolvedCount = _mistakes.count((m) => !m.isResolved);
    final resolvedCount = _mistakes.count((m) => m.isResolved);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "🧠 My Mistakes Bank",
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              "$unresolvedCount active misconception patterns",
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Mistakes",
            onPressed: _loadMistakeBank,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter Tabs Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: context.surfaceColor,
                  child: Row(
                    children: [
                      _buildFilterChip("Unresolved ($unresolvedCount)", "unresolved"),
                      const SizedBox(width: 8),
                      _buildFilterChip("Resolved ($resolvedCount)", "resolved"),
                      const SizedBox(width: 8),
                      _buildFilterChip("All (${_mistakes.length})", "all"),
                    ],
                  ),
                ),

                // Main Content List
                Expanded(
                  child: _filteredMistakes.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredMistakes.length,
                          itemBuilder: (ctx, i) => _buildMistakeCard(ctx, _filteredMistakes[i], isDark),
                        ),
                ),

                // Bottom CTA: Practice My Mistakes
                if (unresolvedCount > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      border: Border(top: BorderSide(color: context.cardBorderColor)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _startMistakePracticeSession,
                        icon: const Icon(Icons.replay_rounded, color: Colors.white),
                        label: Text(
                          "Practice My Mistakes ($unresolvedCount)",
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, String key) {
    final isSelected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _filter = key),
      selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFF6366F1) : context.textSecondary,
      ),
    );
  }

  Widget _buildMistakeCard(BuildContext context, MistakeBankItemModel item, bool isDark) {
    final missColor = item.missCount >= 3
        ? const Color(0xFFEF4444)
        : item.missCount >= 2
            ? const Color(0xFFF59E0B)
            : const Color(0xFF6366F1);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.isResolved
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : missColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Course + Miss Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.cardBorderColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${item.courseCode} • ${item.studySetTitle}",
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.isResolved
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : missColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.isResolved ? "✓ Resolved" : "${item.missCount} Mistakes",
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.isResolved ? const Color(0xFF10B981) : missColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question Prompt
          Text(
            item.prompt,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 10),

          // Misconception Pattern Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 14, color: missColor),
                    const SizedBox(width: 6),
                    Text(
                      "Why was this missed?",
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: missColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.explanation,
                  style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary, height: 1.4),
                ),
                if (item.lastSubmittedAnswer != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Last answer: '${item.lastSubmittedAnswer}' → Correct: '${item.correctAnswer}'",
                    style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Toggle Resolve / Practice Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final newStatus = !item.isResolved;
                  await widget.apiClient.resolveMistake(item.questionId, isResolved: newStatus);
                  _loadMistakeBank();
                  widget.onMistakesChanged?.call();
                },
                icon: Icon(
                  item.isResolved ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
                  size: 15,
                  color: item.isResolved ? Colors.grey : const Color(0xFF10B981),
                ),
                label: Text(
                  item.isResolved ? "Reopen Mistake" : "Mark Resolved",
                  style: TextStyle(fontSize: 12, color: item.isResolved ? Colors.grey : const Color(0xFF10B981)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_very_satisfied_rounded, size: 64, color: Color(0xFF10B981)),
            const SizedBox(height: 16),
            Text(
              "No Active Mistakes!",
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _filter == "resolved"
                  ? "You haven't resolved any mistakes yet."
                  : "Excellent job! You have zero unresolved misconception patterns.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _startMistakePracticeSession() {
    final unresolved = _mistakes.where((m) => !m.isResolved).toList();
    if (unresolved.isEmpty) return;

    final questions = unresolved.map((m) {
      QuestionTypeEnum qType = QuestionTypeEnum.multipleChoice;
      final typeStr = m.type.toLowerCase();
      if (typeStr.contains("true")) {
        qType = QuestionTypeEnum.trueFalse;
      } else if (typeStr.contains("ident")) {
        qType = QuestionTypeEnum.identification;
      }

      return QuestionModel(
        id: m.questionId,
        studySetId: m.studySetId,
        type: qType,
        prompt: m.prompt,
        hints: const [],
        options: m.options
            .map((optText) => QuestionOptionModel(
                  id: optText,
                  optionText: optText,
                  isCorrect: optText == m.correctAnswer,
                ))
            .toList(),
        correctAnswer: m.correctAnswer,
        explanation: m.explanation,
      );
    }).toList();

    final setModel = StudySetModel(
      id: unresolved.first.studySetId,
      courseId: widget.initialCourseId ?? "",
      title: "🧠 Targeted Mistake Bank Drill",
      description: "Custom practice session addressing personal misconception patterns",
      questionCount: questions.length,
      createdAt: DateTime.now(),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPlayerScreen(
          apiClient: widget.apiClient,
          sessionService: widget.apiClient.sessionService,
          studySet: setModel,
          questions: questions,
        ),
      ),
    ).then((_) {
      _loadMistakeBank();
      widget.onMistakesChanged?.call();
    });
  }
}

extension _CountExtension<T> on Iterable<T> {
  int count(bool Function(T element) predicate) {
    var c = 0;
    for (var element in this) {
      if (predicate(element)) c++;
    }
    return c;
  }
}

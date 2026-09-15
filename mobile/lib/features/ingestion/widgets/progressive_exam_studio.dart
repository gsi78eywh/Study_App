import "dart:async";
import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../quiz/models/quiz_models.dart";
import "../../quiz/screens/quiz_player_screen.dart";

class ProgressiveExamStudio extends StatefulWidget {
  final String courseId;
  final String courseName;
  final String initialTitle;
  final String sourceText;
  final ApiClient apiClient;
  final bool enableStageTimer;
  final bool autoStart;
  final List<QuestionModel>? initialQuestions;
  final void Function(StudySetModel createdSet) onExamSaved;
  final void Function(StudySetModel createdSet, List<QuestionModel> questions)? onLaunchQuiz;
  final void Function(StudySetModel createdSet, List<QuestionModel> questions)? onPracticeFlashcards;

  const ProgressiveExamStudio({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.initialTitle,
    required this.sourceText,
    required this.apiClient,
    this.enableStageTimer = true,
    this.autoStart = true,
    this.initialQuestions,
    required this.onExamSaved,
    this.onLaunchQuiz,
    this.onPracticeFlashcards,
  });

  static Future<void> show(
    BuildContext context, {
    required String courseId,
    required String courseName,
    required String initialTitle,
    required String sourceText,
    required ApiClient apiClient,
    bool enableStageTimer = true,
    bool autoStart = true,
    List<QuestionModel>? initialQuestions,
    required void Function(StudySetModel createdSet) onExamSaved,
    void Function(StudySetModel createdSet, List<QuestionModel> questions)? onLaunchQuiz,
    void Function(StudySetModel createdSet, List<QuestionModel> questions)? onPracticeFlashcards,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ProgressiveExamStudio(
          courseId: courseId,
          courseName: courseName,
          initialTitle: initialTitle,
          sourceText: sourceText,
          apiClient: apiClient,
          enableStageTimer: enableStageTimer,
          autoStart: autoStart,
          initialQuestions: initialQuestions,
          onExamSaved: onExamSaved,
          onLaunchQuiz: onLaunchQuiz,
          onPracticeFlashcards: onPracticeFlashcards,
        ),
      ),
    );
  }

  @override
  State<ProgressiveExamStudio> createState() => _ProgressiveExamStudioState();
}

class _ProgressiveExamStudioState extends State<ProgressiveExamStudio> {
  final CancelToken _cancelToken = CancelToken();
  Timer? _stageTimer;

  bool _isApiLoading = true;
  bool _isSynthesisComplete = false;
  String? _errorMessage;

  // Staged synthesis tracking
  int _currentStageIndex = 0;
  double _displayProgress = 0.05;

  static const List<Map<String, dynamic>> _synthesisStages = [
    {
      "key": "concepts",
      "kind": "Foundational Concepts",
      "icon": Icons.search_rounded,
      "color": Color(0xFF6366F1),
      "desc": "Parsing scanned notes & isolating core definitions...",
      "targetProgress": 0.15,
    },
    {
      "key": "mcq",
      "kind": "Multiple Choice Drills",
      "icon": Icons.check_circle_outline_rounded,
      "color": Color(0xFF4F46E5),
      "desc": "Sculpting 4-option questions with distractor rationales (A, B, C, D)...",
      "targetProgress": 0.35,
    },
    {
      "key": "identification",
      "kind": "Identification & Vocabulary",
      "icon": Icons.label_important_outline_rounded,
      "color": Color(0xFF10B981),
      "desc": "Generating direct-recall terminology and keyword prompts...",
      "targetProgress": 0.55,
    },
    {
      "key": "true_false",
      "kind": "True / False Analysis",
      "icon": Icons.rule_rounded,
      "color": Color(0xFFF59E0B),
      "desc": "Engineering analytical scenarios and factual validations...",
      "targetProgress": 0.75,
    },
    {
      "key": "cloze",
      "kind": "Cloze / Fill-in-the-Blank",
      "icon": Icons.space_bar_rounded,
      "color": Color(0xFF06B6D4),
      "desc": "Crafting contextual sentence completion tests...",
      "targetProgress": 0.90,
    },
    {
      "key": "flashcard",
      "kind": "High-Yield Flashcards",
      "icon": Icons.style_rounded,
      "color": Color(0xFF8B5CF6),
      "desc": "Finalizing spaced-repetition term ↔ definition flashcard deck...",
      "targetProgress": 1.00,
    },
  ];

  StudySetModel? _createdStudySet;
  List<QuestionModel> _allQuestions = [];
  List<QuestionModel> _visibleQuestions = [];
  String _selectedKindFilter = "all";

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestions != null && widget.initialQuestions!.isNotEmpty) {
      _allQuestions = List.from(widget.initialQuestions!);
      _isApiLoading = false;
      _displayProgress = 1.0;
      _isSynthesisComplete = true;
      _updateVisibleQuestions();
    } else if (widget.autoStart) {
      _startProgressiveSynthesis();
    } else {
      _isApiLoading = false;
    }
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _startProgressiveSynthesis() async {
    // 1. Kick off progressive timer animation
    if (widget.enableStageTimer) {
      _currentStageIndex = 0;
      _displayProgress = 0.08;
      _stageTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_currentStageIndex < _synthesisStages.length - 1) {
          setState(() {
            _currentStageIndex++;
            _displayProgress = _synthesisStages[_currentStageIndex]["targetProgress"] as double;
            _updateVisibleQuestions();
          });
        } else {
          timer.cancel();
          if (!_isApiLoading) {
            setState(() {
              _displayProgress = 1.0;
              _isSynthesisComplete = true;
              _updateVisibleQuestions();
            });
          }
        }
      });
    }

    // 2. Call backend multi-kind ingestion endpoint
    try {
      final geminiKey = widget.apiClient.sessionService.geminiApiKey;
      final payload = <String, dynamic>{
        "courseId": widget.courseId,
        "title": widget.initialTitle,
        "content": widget.sourceText,
        "questionTypes": [
          "multiple_choice",
          "identification",
          "true_false",
          "cloze",
          "flashcard"
        ],
        "targetCount": 15,
        "setIndex": 0,
      };

      final options = Options();
      if (geminiKey != null && geminiKey.isNotEmpty) {
        options.headers = {"X-Gemini-ApiKey": geminiKey};
      }

      final response = await widget.apiClient.dio.post(
        ApiConstants.ingestText,
        data: payload,
        options: options,
        cancelToken: _cancelToken,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);

        final studySet = StudySetModel(
          id: data["id"]?.toString() ?? "",
          courseId: data["courseId"]?.toString() ?? widget.courseId,
          title: data["title"] ?? widget.initialTitle,
          description: data["description"] ?? "",
          questionCount: data["questionCount"] ?? 0,
          createdAt: DateTime.now(),
          bulletPoints: (data["highYieldBulletPoints"] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
        );

        List<QuestionModel> loadedQuestions = [];
        if (data["questions"] is List) {
          loadedQuestions = (data["questions"] as List)
              .map((q) => QuestionModel.fromJson(Map<String, dynamic>.from(q as Map)))
              .toList();
        } else {
          // Fallback: fetch directly from study set questions endpoint
          final qResp = await widget.apiClient.dio.get(
            ApiConstants.studySetQuestions(studySet.id),
          );
          if (qResp.statusCode == 200 && qResp.data is List) {
            loadedQuestions = (qResp.data as List)
                .map((q) => QuestionModel.fromJson(Map<String, dynamic>.from(q as Map)))
                .toList();
          }
        }

        if (mounted) {
          _stageTimer?.cancel();
          setState(() {
            _createdStudySet = studySet;
            _allQuestions = loadedQuestions;
            _isApiLoading = false;
            _currentStageIndex = _synthesisStages.length - 1;
            _displayProgress = 1.0;
            _isSynthesisComplete = true;
            _updateVisibleQuestions();
          });
          widget.onExamSaved(studySet);
        }
      }
    } on DioException catch (e) {
      _stageTimer?.cancel();
      if (mounted) {
        setState(() {
          _isApiLoading = false;
          _errorMessage = e.error?.toString() ?? e.message ?? "Exam synthesis failed.";
        });
      }
    } catch (e) {
      _stageTimer?.cancel();
      if (mounted) {
        setState(() {
          _isApiLoading = false;
          _errorMessage = "Synthesis error: $e";
        });
      }
    }
  }

  void _instantRevealAll() {
    _stageTimer?.cancel();
    setState(() {
      _currentStageIndex = _synthesisStages.length - 1;
      _displayProgress = 1.0;
      _isSynthesisComplete = true;
      _updateVisibleQuestions();
    });
  }

  void _updateVisibleQuestions() {
    if (_allQuestions.isEmpty) {
      _visibleQuestions = [];
      return;
    }

    // Determine how many questions are revealed according to current progress
    final revealRatio = _isSynthesisComplete ? 1.0 : (_currentStageIndex + 1) / _synthesisStages.length;
    final maxAllowed = (_allQuestions.length * revealRatio).ceil().clamp(0, _allQuestions.length);
    final currentPool = _allQuestions.take(maxAllowed).toList();

    if (_selectedKindFilter == "all") {
      _visibleQuestions = currentPool;
    } else {
      _visibleQuestions = currentPool.where((q) {
        final typeStr = q.type.name.toLowerCase();
        return typeStr.contains(_selectedKindFilter.toLowerCase());
      }).toList();
    }
  }

  void _filterByKind(String filter) {
    setState(() {
      _selectedKindFilter = filter;
      _updateVisibleQuestions();
    });
  }

  void _launchQuizExam() {
    if (_createdStudySet == null || _allQuestions.isEmpty) return;
    if (widget.onLaunchQuiz != null) {
      widget.onLaunchQuiz!(_createdStudySet!, _allQuestions);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => QuizPlayerScreen(
            studySet: _createdStudySet!,
            questions: _allQuestions,
            apiClient: widget.apiClient,
            sessionService: widget.apiClient.sessionService,
          ),
        ),
      );
    }
  }

  void _launchFlashcards() {
    if (_createdStudySet == null || _allQuestions.isEmpty) return;
    if (widget.onPracticeFlashcards != null) {
      widget.onPracticeFlashcards!(_createdStudySet!, _allQuestions);
    } else {
      Navigator.of(context).pop();
    }
  }

  Color _getKindColor(QuestionTypeEnum type) {
    switch (type) {
      case QuestionTypeEnum.multipleChoice:
        return const Color(0xFF6366F1);
      case QuestionTypeEnum.identification:
        return const Color(0xFF10B981);
      case QuestionTypeEnum.trueFalse:
        return const Color(0xFFF59E0B);
      case QuestionTypeEnum.cloze:
        return const Color(0xFF06B6D4);
      case QuestionTypeEnum.enumeration:
        return const Color(0xFFEC4899);
      case QuestionTypeEnum.matching:
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String _getKindDisplayName(QuestionTypeEnum type) {
    switch (type) {
      case QuestionTypeEnum.multipleChoice:
        return "Multiple Choice";
      case QuestionTypeEnum.identification:
        return "Identification";
      case QuestionTypeEnum.trueFalse:
        return "True / False";
      case QuestionTypeEnum.cloze:
        return "Cloze Blank";
      case QuestionTypeEnum.enumeration:
        return "Enumeration";
      case QuestionTypeEnum.matching:
        return "Matching Type";
      default:
        return "Active Recall";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final currentStage = _synthesisStages[_currentStageIndex];

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Progressive Exam Studio",
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "${widget.courseName} • ${widget.initialTitle}",
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        actions: [
          if (!_isSynthesisComplete && !_isApiLoading)
            TextButton.icon(
              icon: const Icon(Icons.fast_forward_rounded, size: 16),
              label: const Text("Reveal All", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _instantRevealAll,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progressive Synthesis Status Banner
          _buildSynthesisProgressHeader(context, isDark, currentStage),

          // Error Banner if any
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Exam Kind Filter Chips Bar
          if (_allQuestions.isNotEmpty)
            _buildKindFilterBar(context, isDark),

          // Questions Feed (Cards popping in as synthesized)
          Expanded(
            child: _visibleQuestions.isEmpty && _isApiLoading
                ? _buildInitialLoadingPlaceholder(context, isDark, currentStage)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: _visibleQuestions.length,
                    itemBuilder: (context, index) {
                      final question = _visibleQuestions[index];
                      return _buildQuestionCard(context, isDark, question, index + 1);
                    },
                  ),
          ),
        ],
      ),

      // Bottom Action Hub
      bottomSheet: _allQuestions.isNotEmpty
          ? _buildBottomActionHub(context, isDark)
          : null,
    );
  }

  Widget _buildSynthesisProgressHeader(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> stage,
  ) {
    final stageColor = stage["color"] as Color;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(bottom: BorderSide(color: context.cardBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  stage["icon"] as IconData,
                  color: stageColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isSynthesisComplete
                              ? "✨ Exam Synthesis Complete"
                              : "Synthesizing ${stage["kind"]}...",
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "${(_displayProgress * 100).toInt()}%",
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: stageColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isSynthesisComplete
                          ? "${_allQuestions.length} multi-kind active recall items ready for study"
                          : stage["desc"] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _displayProgress,
              minHeight: 6,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(stageColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKindFilterBar(BuildContext context, bool isDark) {
    final kinds = [
      {"id": "all", "label": "All Kinds (${_allQuestions.length})", "icon": Icons.apps_rounded},
      {"id": "multiplechoice", "label": "Multiple Choice", "icon": Icons.check_circle_outline},
      {"id": "identification", "label": "Identification", "icon": Icons.label_outline},
      {"id": "truefalse", "label": "True / False", "icon": Icons.rule_rounded},
      {"id": "cloze", "label": "Cloze", "icon": Icons.space_bar_rounded},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: kinds.map((k) {
            final isSelected = _selectedKindFilter == k["id"];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                label: Text(k["label"] as String),
                avatar: Icon(
                  k["icon"] as IconData,
                  size: 14,
                  color: isSelected ? Colors.white : context.textSecondary,
                ),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : context.textPrimary,
                ),
                selectedColor: const Color(0xFF6366F1),
                backgroundColor: context.secondaryBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF6366F1) : context.cardBorderColor,
                  ),
                ),
                onSelected: (_) => _filterByKind(k["id"] as String),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInitialLoadingPlaceholder(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> stage,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (stage["color"] as Color).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: stage["color"] as Color,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Sculpting Exam Questions...",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Our multimodal synthesis engine is analyzing the transcribed notes and generating comprehensive test items across all 5 exam kinds.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    bool isDark,
    QuestionModel question,
    int index,
  ) {
    final kindColor = _getKindColor(question.type);
    final kindName = _getKindDisplayName(question.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header: Question Number & Kind Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Q$index",
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kindColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kindColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: kindColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      kindName,
                      style: TextStyle(
                        color: kindColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question Prompt
          Text(
            question.prompt,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Options / Answer Breakdown
          if (question.options.isNotEmpty) ...[
            ...question.options.map((opt) {
              final isCorrect = opt.isCorrect;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : context.secondaryBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCorrect
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : context.cardBorderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 15,
                      color: isCorrect ? const Color(0xFF10B981) : context.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        opt.optionText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                          color: isCorrect ? const Color(0xFF10B981) : context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else if (question.correctAnswer != null && question.correctAnswer!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key_rounded, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Key Answer: ${question.correctAnswer}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Explanation / Note Citation if present
          if (question.explanation != null && question.explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "💡 ${question.explanation}",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: context.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActionHub(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(top: BorderSide(color: context.cardBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  "Launch Quiz Exam (${_allQuestions.length})",
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: _launchQuizExam,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textPrimary,
                  side: BorderSide(color: context.cardBorderColor),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.style_outlined, size: 16),
                label: const Text("Flashcards", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: _launchFlashcards,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

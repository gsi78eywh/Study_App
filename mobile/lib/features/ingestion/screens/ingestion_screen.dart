import "dart:async";
import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:file_picker/file_picker.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

class IngestionScreen extends StatefulWidget {
  final List<CourseModel> courses;
  final ApiClient apiClient;
  final void Function(StudySetModel)? onStudySetCreated;

  const IngestionScreen({
    super.key,
    required this.courses,
    required this.apiClient,
    this.onStudySetCreated,
  });

  @override
  State<IngestionScreen> createState() => _IngestionScreenState();
}

class _IngestionScreenState extends State<IngestionScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String _selectedCourseId;
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _urlController = TextEditingController();

  PlatformFile? _selectedFile;
  int _fileSizeBytes = 0;
  int _targetCount = 10;
  bool _isLoading = false;
  bool _fastMode = false;
  int _loadingStep = 0;
  Timer? _stepTimer;
  String? _errorMessage;

  final Set<String> _selectedModes = {"Multiple Choice", "Identification", "Enumeration"};

  final List<String> _loadingSteps = [
    "Reading notes & extracting handwriting/document text...",
    "Parsing questions, answers & active-recall prompts...",
    "Structuring multiple-choice drills (A, B, C, D) & flashcards...",
    "Finalizing high-yield study set and saving locally...",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedCourseId = widget.courses.isNotEmpty ? widget.courses.first.id : "";
  }

  @override
  void didUpdateWidget(IngestionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedCourseId.isEmpty && widget.courses.isNotEmpty) {
      _selectedCourseId = widget.courses.first.id;
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _tabController.dispose();
    _titleController.dispose();
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool _isImageFile(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".webp");
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["pdf", "docx", "txt", "md", "png", "jpg", "jpeg", "webp"],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final size = file.lengthSync() ?? await file.length();
        setState(() {
          _selectedFile = file;
          _fileSizeBytes = size;
          _errorMessage = null;
          if (_titleController.text.isEmpty) {
            _titleController.text = file.name.split('.').first;
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = "Error picking file: $e");
    }
  }

  void _startStepAnimation() {
    _loadingStep = 0;
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!mounted || !_isLoading) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_loadingStep < _loadingSteps.length - 1) {
          _loadingStep++;
        }
      });
    });
  }

  Future<void> _handleGenerate() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Please enter a title for the study set.");
      return;
    }

    if (_selectedCourseId.isEmpty && widget.courses.isNotEmpty) {
      _selectedCourseId = widget.courses.first.id;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _startStepAnimation();

    try {
      Response response;

      if (_tabController.index == 0) {
        // Text Ingestion
        if (_textController.text.trim().isEmpty) {
          setState(() => _errorMessage = "Please enter or paste your study notes.");
          return;
        }

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestText,
          data: {
            "courseId": _selectedCourseId,
            "title": _titleController.text.trim(),
            "content": _textController.text.trim(),
            "targetCount": _targetCount,
            "questionTypes": _selectedModes.map((m) {
              return switch (m) {
                "Multiple Choice" => "multiple_choice",
                "Identification" => "identification",
                "Enumeration" => "enumeration",
                "Cloze / Fill-in" => "cloze",
                "True / False" => "true_false",
                "Matching Type" => "matching",
                "Short Answer" => "short_answer",
                "Scenario Drills" => "scenario",
                "Flashcards" => "flashcards",
                "Summary" => "summary",
                _ => m.toLowerCase().replaceAll(" ", "_").replaceAll("/", "").replaceAll("  ", "_")
              };
            }).toList(),
            "fastMode": _fastMode,
          },
        );
      } else if (_tabController.index == 1) {
        // File / Photo Upload Ingestion
        if (_selectedFile == null) {
          setState(() => _errorMessage = "Please select a document or whiteboard photo (.pdf, .png, .jpg, .docx, .txt).");
          return;
        }

        final fileBytes = await _selectedFile!.readAsBytes();

        if (fileBytes.isEmpty) {
          setState(() => _errorMessage = "Could not read file data. Please re-select the file.");
          return;
        }

        final multipartFile = MultipartFile.fromBytes(
          fileBytes,
          filename: _selectedFile!.name,
        );

        final formData = FormData.fromMap({
          "file": multipartFile,
          "courseId": _selectedCourseId,
          "title": _titleController.text.trim(),
          "questionTypes": _selectedModes.map((m) {
              return switch (m) {
                "Multiple Choice" => "multiple_choice",
                "Identification" => "identification",
                "Enumeration" => "enumeration",
                "Cloze / Fill-in" => "cloze",
                "True / False" => "true_false",
                "Matching Type" => "matching",
                "Short Answer" => "short_answer",
                "Scenario Drills" => "scenario",
                "Flashcards" => "flashcards",
                "Summary" => "summary",
                _ => m.toLowerCase().replaceAll(" ", "_").replaceAll("/", "").replaceAll("  ", "_")
              };
            }).join(","),
          "targetCount": _targetCount,
          "fastMode": _fastMode.toString(),
        });

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestFile,
          data: formData,
        );
      } else {
        // URL Ingestion
        if (_urlController.text.trim().isEmpty) {
          setState(() => _errorMessage = "Please provide an article or documentation URL.");
          return;
        }

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestUrl,
          data: {
            "courseId": _selectedCourseId,
            "title": _titleController.text.trim(),
            "url": _urlController.text.trim(),
            "targetCount": _targetCount,
            "fastMode": _fastMode,
          },
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final newSet = StudySetModel.fromJson(response.data);
        setState(() {
        });

        widget.onStudySetCreated?.call(newSet);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✨ Successfully synthesized '${newSet.title}' with ${newSet.questionCount} questions!"),
              backgroundColor: AppColors.accent,
              duration: const Duration(seconds: 4),
            ),
          );

          if (Navigator.of(context).canPop()) {
            Navigator.pop(context, newSet);
          }
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "AI generation failed. Check server status.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error: $e";
      });
    } finally {
      _stepTimer?.cancel();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text("Study Notes Extractor & Studio", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.textPrimary)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
          labelColor: isDark ? Colors.white : AppColors.primaryDark,
          unselectedLabelColor: context.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.notes_rounded), text: "Paste Text"),
            Tab(icon: Icon(Icons.photo_camera_back_rounded), text: "Upload File / Photo"),
            Tab(icon: Icon(Icons.link_rounded), text: "Article URL"),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Direct extraction banner
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1E1B4B), const Color(0xFF2E1065)]
                            : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF818CF8).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Direct Note & Document Extractor",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : const Color(0xFF312E81),
                                ),
                              ),
                              Text(
                                "Directly extracts questions, answers, and concepts from notes, handwritten whiteboard photos, and documents without AI hallucinations.",
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF4338CA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Fast Mode & Offline Synthesis Toggle Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _fastMode ? AppColors.accent.withValues(alpha: 0.6) : context.cardBorderColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _fastMode ? AppColors.accent.withValues(alpha: 0.15) : context.secondaryBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.bolt_rounded,
                            color: _fastMode ? AppColors.accent : context.textSecondary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "⚡ Instant Fast Mode (<100ms)",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "LOW LATENCY",
                                      style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Instant local active-recall synthesis. Zero waiting for slow networks.",
                                style: TextStyle(color: context.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _fastMode,
                          activeTrackColor: AppColors.accent,
                          onChanged: (val) => setState(() => _fastMode = val),
                        ),
                      ],
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Course Selector
                  Text("Assign to Course", style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  const SizedBox(height: 8),
                  if (widget.courses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "No courses found. Study set will be created in default space.",
                              style: TextStyle(color: context.textSecondary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: widget.courses.any((c) => c.id == _selectedCourseId) ? _selectedCourseId : widget.courses.first.id,
                          isExpanded: true,
                          dropdownColor: context.surfaceColor,
                          items: widget.courses.map((c) {
                            return DropdownMenuItem(
                              value: c.id,
                              child: Text("${c.code} - ${c.name}", style: TextStyle(color: context.textPrimary)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCourseId = val);
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Title input
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: context.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Study Set Title",
                      hintText: "e.g. Chapter 4: Cellular Respiration & Krebs Cycle",
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tab View Content
                  SizedBox(
                    height: 240,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Text
                        TextField(
                          controller: _textController,
                          maxLines: 9,
                          style: TextStyle(color: context.textPrimary),
                          decoration: const InputDecoration(
                            labelText: "Lecture Notes or Text Content",
                            hintText: "Paste textbook paragraphs, slide bullet points, or formulas here...",
                          ),
                        ),

                        // Tab 2: File / Photo Picker
                        InkWell(
                          onTap: _pickFile,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _selectedFile != null
                                    ? AppColors.accent
                                    : (isDark ? AppColors.primary.withValues(alpha: 0.5) : AppColors.primaryDark.withValues(alpha: 0.3)),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _selectedFile != null
                                      ? (_isImageFile(_selectedFile!.name) ? Icons.photo_size_select_actual_rounded : Icons.check_circle_rounded)
                                      : Icons.add_photo_alternate_outlined,
                                  size: 48,
                                  color: _selectedFile != null
                                      ? AppColors.accent
                                      : (isDark ? AppColors.primaryLight : AppColors.primaryDark),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedFile != null
                                      ? _selectedFile!.name
                                      : "Tap to browse Whiteboard Photo, PDF, Word (DOCX), or TXT",
                                  style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                if (_selectedFile != null && _isImageFile(_selectedFile!.name))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "📸 Whiteboard / Diagram detected - Direct Note Text Extraction",
                                      style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  )
                                else
                                  Text(
                                    _selectedFile != null
                                        ? "${(_fileSizeBytes / 1024).toStringAsFixed(1)} KB ready for extraction"
                                        : "Supports handwritten captures, slides, handouts, and textbooks up to 30MB",
                                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Tab 3: URL
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _urlController,
                              keyboardType: TextInputType.url,
                              style: TextStyle(color: context.textPrimary),
                              decoration: InputDecoration(
                                labelText: "Web Article or Documentation URL",
                                hintText: "https://en.wikipedia.org/wiki/...",
                                prefixIcon: Icon(Icons.language_rounded, color: context.textSecondary),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "The backend scrapes clean instructional sections and synthesizes active recall drills.",
                              style: TextStyle(color: context.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Exam Modes & Quick Preset Selectors
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Exam Modes & Question Types", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary)),
                      Text("${_selectedModes.length} modes active", style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                          label: const Text("🎯 All Types (Simulated Exam)"),
                          backgroundColor: const Color(0xFF6366F1),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          onPressed: () {
                            setState(() {
                              _selectedModes.addAll([
                                "Multiple Choice",
                                "Identification",
                                "Enumeration",
                                "Cloze / Fill-in",
                                "True / False",
                                "Matching Type",
                                "Short Answer",
                                "Scenario Drills",
                              ]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.check_circle_outline, size: 14, color: Colors.white),
                          label: const Text("📚 Objective (MCQ + T/F)"),
                          backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          onPressed: () {
                            setState(() {
                              _selectedModes.clear();
                              _selectedModes.addAll(["Multiple Choice", "True / False"]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.edit_note_rounded, size: 14, color: Colors.white),
                          label: const Text("✍️ Active Recall (ID + Cloze + Enum)"),
                          backgroundColor: const Color(0xFF10B981),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          onPressed: () {
                            setState(() {
                              _selectedModes.clear();
                              _selectedModes.addAll(["Identification", "Cloze / Fill-in", "Enumeration"]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.hub_rounded, size: 14, color: Colors.white),
                          label: const Text("🧩 Drills (Matching + Scenario)"),
                          backgroundColor: const Color(0xFFF59E0B),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          onPressed: () {
                            setState(() {
                              _selectedModes.clear();
                              _selectedModes.addAll(["Matching Type", "Scenario Drills"]);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      "Multiple Choice",
                      "Identification",
                      "Enumeration",
                      "Cloze / Fill-in",
                      "True / False",
                      "Matching Type",
                      "Short Answer",
                      "Scenario Drills",
                      "Flashcards",
                      "Summary",
                    ].map((mode) {
                      final isSelected = _selectedModes.contains(mode);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(mode),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : context.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        selectedColor: isDark ? AppColors.primary : AppColors.primaryDark,
                        backgroundColor: context.surfaceColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected ? (isDark ? AppColors.primary : AppColors.primaryDark) : context.cardBorderColor,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedModes.add(mode);
                            } else if (_selectedModes.length > 1) {
                              _selectedModes.remove(mode);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Target questions slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Target Questions:", style: TextStyle(color: context.textSecondary)),
                      Text("$_targetCount Questions", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _targetCount.toDouble(),
                    min: 5,
                    max: 20,
                    divisions: 3,
                    activeColor: isDark ? AppColors.primary : AppColors.primaryDark,
                    onChanged: (val) => setState(() => _targetCount = val.toInt()),
                  ),

                  // Stepped Progress Indicator Card while loading
                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Synthesizing (${_loadingStep + 1}/${_loadingSteps.length})",
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _loadingSteps[_loadingStep],
                            style: TextStyle(color: context.textPrimary, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_loadingStep + 1) / _loadingSteps.length,
                            backgroundColor: context.secondaryBg,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.menu_book_rounded),
                    label: Text(
                      _isLoading
                          ? "Extracting & Synthesizing Study Set..."
                          : (_fastMode ? "⚡ Instant Extraction (<100ms)" : "Generate Study Set from Notes"),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: _isLoading ? null : _handleGenerate,
                  ),
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

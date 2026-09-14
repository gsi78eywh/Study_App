import "dart:async";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:dio/dio.dart";
import "package:file_picker/file_picker.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../quiz/models/quiz_models.dart";

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
  Uint8List? _selectedFileBytes;
  int _fileSizeBytes = 0;
  int _targetCount = 10;
  bool _isLoading = false;
  bool _fastMode = false;
  bool _isScanning = false;
  bool _isExtractingTextToEditor = false;
  Map<String, dynamic>? _scannedResult;
  int _loadingStep = 0;
  Timer? _stepTimer;
  String? _errorMessage;

  final Set<String> _selectedModes = {"Multiple Choice", "Identification", "Enumeration"};
  int _selectedSetIndex = 0;

  static const List<Map<String, dynamic>> _questionSetVariants = [
    {
      "id": "set_a",
      "index": 0,
      "name": "Set A: Core Concepts",
      "badge": "Set A (Core)",
      "desc": "Foundational definitions, primary terminology, and key principles.",
      "color": Color(0xFF6366F1),
    },
    {
      "id": "set_b",
      "index": 1,
      "name": "Set B: Reverse & Cloze",
      "badge": "Set B (Reverse)",
      "desc": "Inverted recall (definition ➔ term), fill-in blanks, and concept matching.",
      "color": Color(0xFF10B981),
    },
    {
      "id": "set_c",
      "index": 2,
      "name": "Set C: Scenarios & Applied",
      "badge": "Set C (Scenarios)",
      "desc": "Real-world problem-solving scenarios and True/False contrast analysis.",
      "color": Color(0xFFF59E0B),
    },
    {
      "id": "set_d",
      "index": 3,
      "name": "Set D: Simulated Exam",
      "badge": "Set D (Simulated)",
      "desc": "Comprehensive balanced active recall across all question modes.",
      "color": Color(0xFF8B5CF6),
    },
    {
      "id": "shuffle",
      "index": 999,
      "name": "🎲 Fresh Shuffled Set",
      "badge": "🎲 Fresh Shuffle",
      "desc": "Generates a randomized seed ensuring novel question angles and fresh distractors.",
      "color": Color(0xFFEC4899),
    },
  ];

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
    return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".webp") || lower.endsWith(".bmp");
  }

  void _clearFile() {
    setState(() {
      _selectedFile = null;
      _selectedFileBytes = null;
      _fileSizeBytes = 0;
      _scannedResult = null;
      _isScanning = false;
      _errorMessage = null;
    });
  }

  void _resetForm() {
    setState(() {
      _selectedFile = null;
      _selectedFileBytes = null;
      _fileSizeBytes = 0;
      _scannedResult = null;
      _isScanning = false;
      _titleController.clear();
      _textController.clear();
      _urlController.clear();
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✨ Form refreshed. Ready for your next study notes or upload!"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["pdf", "docx", "txt", "md", "png", "jpg", "jpeg", "webp", "bmp"],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final size = await file.length();
        final bytes = await file.readAsBytes();
        setState(() {
          _selectedFile = file;
          _selectedFileBytes = bytes;
          _fileSizeBytes = size;
          _scannedResult = null;
          _isScanning = false;
          _errorMessage = null;
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = file.name.split('.').first;
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = "Error picking file: $e");
    }
  }

  Future<void> _scanAndInspectContent() async {
    if (_selectedFile == null || _selectedFileBytes == null) return;

    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final multipartFile = MultipartFile.fromBytes(
        _selectedFileBytes!,
        filename: _selectedFile!.name,
      );

      final geminiKey = widget.apiClient.sessionService.geminiApiKey;
      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };
      if (geminiKey != null && geminiKey.isNotEmpty) {
        formDataMap["apiKey"] = geminiKey;
      }

      final response = await widget.apiClient.dio.post(
        ApiConstants.scanContent,
        data: FormData.fromMap(formDataMap),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        setState(() {
          _scannedResult = data;
        });

        if (mounted) {
          _showScannedContentSheet(data);
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "Scan failed. Ensure backend is running.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Scan error: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _extractCleanTextFromImageOrFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["png", "jpg", "jpeg", "webp", "bmp", "pdf", "docx", "txt", "md"],
      );

      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _errorMessage = "Could not read the selected file data.");
        return;
      }

      setState(() {
        _isExtractingTextToEditor = true;
        _errorMessage = null;
      });

      final multipartFile = MultipartFile.fromBytes(bytes, filename: file.name);
      final geminiKey = widget.apiClient.sessionService.geminiApiKey;
      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };
      if (geminiKey != null && geminiKey.isNotEmpty) {
        formDataMap["apiKey"] = geminiKey;
      }

      final response = await widget.apiClient.dio.post(
        ApiConstants.scanContent,
        data: FormData.fromMap(formDataMap),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final cleanText = (data["extractedText"] ?? "") as String;
        final charCount = data["charCount"] ?? cleanText.length;
        final ocrEngine = (data["ocrEngine"] ?? "Document Scanner") as String;

        if (cleanText.trim().isEmpty) {
          setState(() {
            _errorMessage = "No readable text could be recognized from '${file.name}'. Please ensure the image is clear and well-lit.";
          });
          return;
        }

        setState(() {
          _textController.text = cleanText.trim();
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = file.name.split('.').first;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✨ Extracted $charCount characters of clean, readable text via $ocrEngine! Review and edit as needed."),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "Scan failed. Ensure backend server is running.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Extraction error: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isExtractingTextToEditor = false);
      }
    }
  }

  Future<void> _showExtractFromModulesDialog() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final availableModules = <Map<String, dynamic>>[];
    for (final c in widget.courses) {
      for (final s in c.studySets) {
        availableModules.add({
          "course": c,
          "studySet": s,
        });
      }
    }

    if (availableModules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No course modules found. You can paste notes or upload a file above."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.88,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.menu_book_rounded, color: Color(0xFF6366F1), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Extract Text from Course Modules",
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Select any study module below to extract its key concepts, summaries, and structured notes directly into your editor based on your selected question types (${_selectedModes.join(', ')}).",
                    style: TextStyle(fontSize: 12.5, color: context.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: availableModules.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final item = availableModules[idx];
                        final CourseModel course = item["course"];
                        final StudySetModel studySet = item["studySet"];

                        final isCurrentCourse = course.id == _selectedCourseId;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(bottomSheetContext).pop();
                              _extractTextFromStudySet(studySet, course, setVariant: _selectedSetIndex);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrentCourse ? const Color(0xFF6366F1) : context.cardBorderColor,
                                  width: isCurrentCourse ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF6366F1), size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    studySet.title,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: context.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isCurrentCourse)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      "CURRENT COURSE",
                                                      style: TextStyle(
                                                        color: Color(0xFF6366F1),
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${course.code} • ${course.name} • ${studySet.questionCount} Questions",
                                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6366F1)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _questionSetVariants.map((v) {
                                      final int idx = v["index"] as int;
                                      final String badge = v["badge"] as String;
                                      final Color color = v["color"] as Color;
                                      final isSelected = _selectedSetIndex == idx;

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          Navigator.of(bottomSheetContext).pop();
                                          _extractTextFromStudySet(studySet, course, setVariant: idx);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                          decoration: BoxDecoration(
                                            color: isSelected ? color.withValues(alpha: 0.18) : context.secondaryBg,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected ? color : context.cardBorderColor.withValues(alpha: 0.8),
                                              width: isSelected ? 1.2 : 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            badge,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? color : context.textSecondary,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _extractTextFromStudySet(
    StudySetModel studySet,
    CourseModel course, {
    int setVariant = 0,
  }) async {
    setState(() {
      _isExtractingTextToEditor = true;
      _selectedSetIndex = setVariant;
    });

    try {
      final buffer = StringBuffer();
      buffer.writeln("# ${studySet.title}");
      buffer.writeln("Course: ${course.code} - ${course.name}");
      if (studySet.description != null && studySet.description!.trim().isNotEmpty) {
        buffer.writeln("Overview: ${studySet.description!.trim()}");
      }
      buffer.writeln();

      if (studySet.bulletPoints.isNotEmpty) {
        buffer.writeln("## Core Key Takeaways & Facts");
        for (final bullet in studySet.bulletPoints) {
          buffer.writeln("• $bullet");
        }
        buffer.writeln();
      }

      // Fetch server questions to structure notes based on active question types and setVariant
      try {
        final response = await widget.apiClient.dio.get(
          "/api/v1/studysets/${studySet.id}/questions",
        );
        if (response.statusCode == 200 && response.data is List) {
          final List list = response.data;
          final questions = list.map((item) => QuestionModel.fromJson(item as Map<String, dynamic>)).toList();

          if (questions.isNotEmpty) {
            // Re-order questions based on setVariant so different sets focus on different concepts first
            final rotated = List<QuestionModel>.from(questions);
            if (setVariant > 0 && rotated.length > 1) {
              final shift = (setVariant * 3) % rotated.length;
              final head = rotated.sublist(shift);
              final tail = rotated.sublist(0, shift);
              rotated.clear();
              rotated.addAll(head);
              rotated.addAll(tail);
            }

            final variantName = _questionSetVariants.firstWhere(
              (v) => v["index"] == setVariant,
              orElse: () => _questionSetVariants.first,
            )["name"] as String;

            buffer.writeln("## Extracted Module Concepts & Knowledge Points ($variantName)");
            for (int i = 0; i < rotated.length; i++) {
              final q = rotated[i];
              final correctOpts = q.options.where((o) => o.isCorrect).map((o) => o.optionText).toList();
              final answer = correctOpts.isNotEmpty ? correctOpts.first : "";

              if (setVariant == 1) {
                // Set B: Reverse Recall & Cloze drills
                if (answer.isNotEmpty) {
                  buffer.writeln("• Key Concept (${answer}): ${q.explanation ?? q.prompt}");
                } else {
                  buffer.writeln("• Concept Prompt: ${q.prompt}");
                }
              } else if (setVariant == 2) {
                // Set C: Scenarios & Applied
                buffer.writeln("• Application & Principle: ${q.prompt}${answer.isNotEmpty ? ' ➔ Correct Principle: $answer' : ''}");
                if (q.explanation != null && q.explanation!.trim().isNotEmpty) {
                  buffer.writeln("  Context / Rationale: ${q.explanation!.trim()}");
                }
              } else {
                // Set A / Set D / Shuffled: Clean Term-Definition notes
                if (answer.isNotEmpty) {
                  buffer.writeln("• $answer: ${q.explanation ?? q.prompt}");
                } else {
                  buffer.writeln("• ${q.prompt}");
                }
                if (q.hints.isNotEmpty) {
                  buffer.writeln("  Hint: ${q.hints.first}");
                }
              }
            }
          }
        }
      } catch (_) {}

      final resultText = buffer.toString().trim();
      final setSuffix = setVariant == 0
          ? "(Extracted Notes)"
          : setVariant == 1
              ? "Set B (Reverse & Cloze)"
              : setVariant == 2
                  ? "Set C (Scenarios & Applied)"
                  : setVariant == 3
                      ? "Set D (Simulated Exam)"
                      : "Shuffled Set";

      setState(() {
        _textController.text = resultText;
        _titleController.text = setVariant == 0
            ? "${studySet.title} (Extracted Notes)"
            : "${studySet.title} - $setSuffix";
        _selectedCourseId = course.id;
        _selectedSetIndex = setVariant;
        _tabController.index = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Extracted ${resultText.length} characters from '${studySet.title}' [$setSuffix] into Note Editor!",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExtractingTextToEditor = false);
      }
    }
  }

  Future<void> _scanAndTransferToEditor() async {
    if (_selectedFile == null || _selectedFileBytes == null) return;

    if (_scannedResult != null && (_scannedResult!['extractedText'] ?? "").toString().trim().isNotEmpty) {
      _textController.text = (_scannedResult!['extractedText'] as String).trim();
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✏️ Clean text transferred to editor! You can now review, edit, and synthesize."),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final multipartFile = MultipartFile.fromBytes(
        _selectedFileBytes!,
        filename: _selectedFile!.name,
      );

      final geminiKey = widget.apiClient.sessionService.geminiApiKey;
      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };
      if (geminiKey != null && geminiKey.isNotEmpty) {
        formDataMap["apiKey"] = geminiKey;
      }

      final response = await widget.apiClient.dio.post(
        ApiConstants.scanContent,
        data: FormData.fromMap(formDataMap),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final cleanText = (data["extractedText"] ?? "") as String;
        setState(() {
          _scannedResult = data;
          if (cleanText.trim().isNotEmpty) {
            _textController.text = cleanText.trim();
          }
        });

        if (cleanText.trim().isNotEmpty) {
          _tabController.animateTo(0);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("✏️ Clean text extracted and loaded into the Note Editor!"),
                backgroundColor: Color(0xFF10B981),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = "No readable text could be recognized from '${_selectedFile!.name}'.";
          });
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "Scan failed.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Extraction error: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _showScannedContentSheet(Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extractedText = (data["extractedText"] ?? "") as String;
    final fileName = (data["fileName"] ?? "Scanned File") as String;
    final ocrEngine = (data["ocrEngine"] ?? "Native Scanner") as String;
    final wordCount = data["wordCount"] ?? 0;
    final charCount = data["charCount"] ?? 0;
    final lineCount = data["lineCount"] ?? 0;
    final hasContent = data["hasContent"] == true && extractedText.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF6366F1), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Scanned Content Inspector",
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              fileName,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                              ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.12)
                              : const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : const Color(0xFF6366F1).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                                  ? Icons.bolt_rounded
                                  : Icons.auto_awesome,
                              size: 14,
                              color: (ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF6366F1),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ocrEngine,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? ((ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFA5B4FC))
                                    : ((ocrEngine.contains("Windows") || ocrEngine.contains("Offline"))
                                        ? const Color(0xFF065F46)
                                        : const Color(0xFF4338CA)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: context.cardBorderColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "🔤 $charCount characters",
                          style: TextStyle(fontSize: 11.5, color: context.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: context.cardBorderColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "📝 $wordCount words",
                          style: TextStyle(fontSize: 11.5, color: context.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: context.cardBorderColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "📑 $lineCount lines",
                          style: TextStyle(fontSize: 11.5, color: context.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: hasContent
                          ? SingleChildScrollView(
                              controller: scrollController,
                              child: SelectableText(
                                extractedText,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: context.textPrimary,
                                  fontFamily: "monospace",
                                ),
                              ),
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.warning),
                                  const SizedBox(height: 12),
                                  Text(
                                    "No Text Extracted",
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    data["message"] ?? "Please verify the image is clear and well-lit.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (hasContent) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text("Copy Scanned Text"),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: extractedText));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("📋 Scanned text copied to clipboard!"),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8B5CF6),
                            side: const BorderSide(color: Color(0xFF8B5CF6)),
                          ),
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                          label: const Text("Transfer to Note Editor"),
                          onPressed: () {
                            _textController.text = extractedText;
                            _tabController.animateTo(0);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("✏️ Scanned text loaded into the Paste Text editor!"),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                        ),
                      ],
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text("Synthesize Study Set Now"),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleGenerate();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showGeminiKeyDialog() {
    final controller = TextEditingController(text: widget.apiClient.sessionService.geminiApiKey ?? "");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            Text("Gemini Vision OCR Key", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: ctx.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "To transcribe handwritten notes or text from screenshots, enter a free Google Gemini API Key. (Get one free at aistudio.google.com)",
              style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: TextStyle(color: ctx.textPrimary, fontFamily: "monospace"),
              decoration: const InputDecoration(
                labelText: "Google Gemini API Key",
                hintText: "AIzaSy...",
                prefixIcon: Icon(Icons.key_rounded, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () async {
              await widget.apiClient.sessionService.setGeminiApiKey(controller.text.trim());
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("✨ Gemini API Key saved! Vision OCR enabled for screenshots."),
                    backgroundColor: AppColors.accent,
                  ),
                );
              }
            },
            child: const Text("Save Key"),
          ),
        ],
      ),
    );
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
            "setIndex": _selectedSetIndex == 999
                ? (DateTime.now().millisecondsSinceEpoch % 1000) + 10
                : _selectedSetIndex,
            "variant": _questionSetVariants.firstWhere(
                (v) => v["index"] == _selectedSetIndex,
                orElse: () => _questionSetVariants.first,
            )["id"] as String,
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

        final fileBytes = _selectedFileBytes ?? await _selectedFile!.readAsBytes();

        if (fileBytes.isEmpty) {
          setState(() => _errorMessage = "Could not read file data. Please re-select the file.");
          return;
        }

        final multipartFile = MultipartFile.fromBytes(
          fileBytes,
          filename: _selectedFile!.name,
        );

        final formDataMap = <String, dynamic>{
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
          "setIndex": (_selectedSetIndex == 999
              ? (DateTime.now().millisecondsSinceEpoch % 1000) + 10
              : _selectedSetIndex).toString(),
          "variant": _questionSetVariants.firstWhere(
              (v) => v["index"] == _selectedSetIndex,
              orElse: () => _questionSetVariants.first,
          )["id"] as String,
        };

        final geminiKey = widget.apiClient.sessionService.geminiApiKey;
        if (geminiKey != null && geminiKey.isNotEmpty) {
          formDataMap["apiKey"] = geminiKey;
        }

        final formData = FormData.fromMap(formDataMap);

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
            "setIndex": _selectedSetIndex == 999
                ? (DateTime.now().millisecondsSinceEpoch % 1000) + 10
                : _selectedSetIndex,
            "variant": _questionSetVariants.firstWhere(
                (v) => v["index"] == _selectedSetIndex,
                orElse: () => _questionSetVariants.first,
            )["id"] as String,
          },
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final newSet = StudySetModel.fromJson(response.data);
        setState(() {
          // Clear and refresh the upload state immediately so the first file does not persist!
          _selectedFile = null;
          _selectedFileBytes = null;
          _fileSizeBytes = 0;
          _titleController.clear();
          _textController.clear();
          _urlController.clear();
        });

        widget.onStudySetCreated?.call(newSet);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✨ Successfully synthesized '${newSet.title}'! Form refreshed for your next upload."),
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

  Widget _buildModePresetPill({
    required String emoji,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.75), width: 1.3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text("Study Notes Extractor & Studio", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Reset Form & Clear Selection",
            onPressed: _resetForm,
          ),
          const SizedBox(width: 8),
        ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Assign to Course", style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary)),
                      if (widget.courses.any((c) => c.studySets.isNotEmpty))
                        TextButton.icon(
                          key: const Key("quick_extract_module_btn"),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.menu_book_rounded, size: 14),
                          label: const Text("Extract from Module", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: _showExtractFromModulesDialog,
                        ),
                    ],
                  ),
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
                    height: 310,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Text Editor with "Extract Clean Text" Action Bar
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "Notes & Raw Text Editor",
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    if (_textController.text.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: context.cardBorderColor.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "${_textController.text.length} chars",
                                          style: TextStyle(fontSize: 10.5, color: context.textSecondary),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                InkWell(
                                  onTap: _isExtractingTextToEditor ? null : _extractCleanTextFromImageOrFile,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isExtractingTextToEditor) ...[
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                                          ),
                                          const SizedBox(width: 6),
                                          const Text("Extracting...", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                        ] else ...[
                                          const Icon(Icons.document_scanner_rounded, size: 14, color: Color(0xFF6366F1)),
                                          const SizedBox(width: 6),
                                          const Text("📷 Extract Clean Text from Image / File", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: TextStyle(color: context.textPrimary, fontSize: 13.5, height: 1.5),
                                decoration: InputDecoration(
                                  hintText: "Paste lecture notes or tap the Extract button above to convert any photo, screenshot, or document into clear, readable text...",
                                  alignLabelWithHint: true,
                                  contentPadding: const EdgeInsets.all(14),
                                  suffixIcon: _textController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          tooltip: "Clear Text",
                                          onPressed: () => setState(() => _textController.clear()),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Tab 2: File / Photo Picker
                        _selectedFile == null
                            ? InkWell(
                                onTap: _pickFile,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                                  decoration: BoxDecoration(
                                    color: context.surfaceColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? AppColors.primary.withValues(alpha: 0.5) : AppColors.primaryDark.withValues(alpha: 0.3),
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 44,
                                        color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        "Tap to browse Screenshot, Whiteboard Photo, PDF, Word, or TXT",
                                        style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "Supports textbook screenshots, handwritten notes, slides, and docs up to 30MB",
                                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.surfaceColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.accent, width: 1.5),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        if (_isImageFile(_selectedFile!.name) && _selectedFileBytes != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.memory(
                                              _selectedFileBytes!,
                                              width: 64,
                                              height: 64,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else
                                          Container(
                                            width: 52,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: AppColors.accent.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.description_rounded, color: AppColors.accent, size: 28),
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _selectedFile!.name,
                                                      style: TextStyle(
                                                        color: context.textPrimary,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      "READY",
                                                      style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                "${(_fileSizeBytes / 1024).toStringAsFixed(1)} KB ready for extraction",
                                                style: TextStyle(color: context.textSecondary, fontSize: 12),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                 spacing: 8,
                                                 runSpacing: 4,
                                                 children: [
                                                   ElevatedButton.icon(
                                                     style: ElevatedButton.styleFrom(
                                                       backgroundColor: isDark ? const Color(0xFF4F46E5) : const Color(0xFF6366F1),
                                                       foregroundColor: Colors.white,
                                                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                       minimumSize: Size.zero,
                                                       tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     ),
                                                     icon: _isScanning
                                                         ? const SizedBox(
                                                             width: 12,
                                                             height: 12,
                                                             child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                           )
                                                         : const Icon(Icons.document_scanner_rounded, size: 14),
                                                     label: Text(
                                                       _isScanning
                                                           ? "Scanning Content..."
                                                           : (_scannedResult != null
                                                               ? "View Scanned Content (${_scannedResult!['charCount']} chars)"
                                                               : "Scan & View Extracted Content"),
                                                       style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                     ),
                                                     onPressed: _isScanning
                                                         ? null
                                                         : (_scannedResult != null
                                                             ? () => _showScannedContentSheet(_scannedResult!)
                                                             : _scanAndInspectContent),
                                                   ),
                                                   OutlinedButton.icon(
                                                     style: OutlinedButton.styleFrom(
                                                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                       minimumSize: Size.zero,
                                                       tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     ),
                                                     icon: const Icon(Icons.file_upload_outlined, size: 14),
                                                     label: const Text("Replace File", style: TextStyle(fontSize: 12)),
                                                     onPressed: _pickFile,
                                                   ),
                                                   OutlinedButton.icon(
                                                     style: OutlinedButton.styleFrom(
                                                       foregroundColor: const Color(0xFF8B5CF6),
                                                       side: const BorderSide(color: Color(0xFF8B5CF6)),
                                                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                       minimumSize: Size.zero,
                                                       tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     ),
                                                     icon: const Icon(Icons.edit_note_rounded, size: 14),
                                                     label: const Text("✏️ Open Clear Text in Note Editor", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                     onPressed: _isScanning ? null : _scanAndTransferToEditor,
                                                   ),
                                                   OutlinedButton.icon(
                                                     style: OutlinedButton.styleFrom(
                                                       foregroundColor: AppColors.danger,
                                                       side: const BorderSide(color: AppColors.danger),
                                                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                       minimumSize: Size.zero,
                                                       tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     ),
                                                     icon: const Icon(Icons.close_rounded, size: 14),
                                                     label: const Text("Clear / Remove", style: TextStyle(fontSize: 12)),
                                                     onPressed: _clearFile,
                                                   ),
                                                 ],
                                               ),
                                               if (_isScanning) ...[
                                                 const SizedBox(height: 8),
                                                 Container(
                                                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                   decoration: BoxDecoration(
                                                     color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                                     borderRadius: BorderRadius.circular(8),
                                                   ),
                                                   child: Row(
                                                     children: [
                                                       const SizedBox(
                                                         width: 14,
                                                         height: 14,
                                                         child: CircularProgressIndicator(strokeWidth: 2),
                                                       ),
                                                       const SizedBox(width: 10),
                                                       Text(
                                                         "Reading and transcribing image contents...",
                                                         style: TextStyle(
                                                           fontSize: 11.5,
                                                           color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
                                                           fontWeight: FontWeight.w600,
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ],
                                               if (_scannedResult != null && (_scannedResult!['extractedText'] as String).isNotEmpty) ...[
                                                 const SizedBox(height: 8),
                                                 Container(
                                                   padding: const EdgeInsets.all(10),
                                                   decoration: BoxDecoration(
                                                     color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                                     borderRadius: BorderRadius.circular(8),
                                                     border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                                   ),
                                                   child: Column(
                                                     crossAxisAlignment: CrossAxisAlignment.start,
                                                     children: [
                                                       Row(
                                                         children: [
                                                           const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                                                           const SizedBox(width: 6),
                                                           Text(
                                                             "Scanned: ${_scannedResult!['charCount']} chars, ${_scannedResult!['wordCount']} words",
                                                             style: TextStyle(
                                                               fontSize: 11,
                                                               fontWeight: FontWeight.bold,
                                                               color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                                                             ),
                                                           ),
                                                           const Spacer(),
                                                           InkWell(
                                                             onTap: () => _showScannedContentSheet(_scannedResult!),
                                                             child: Text(
                                                               "View All ↗",
                                                               style: TextStyle(
                                                                 fontSize: 11,
                                                                 color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                                                                 fontWeight: FontWeight.bold,
                                                               ),
                                                             ),
                                                           ),
                                                         ],
                                                       ),
                                                       const SizedBox(height: 6),
                                                       Text(
                                                         (_scannedResult!['extractedText'] as String).length > 180
                                                             ? "${(_scannedResult!['extractedText'] as String).substring(0, 180)}..."
                                                             : (_scannedResult!['extractedText'] as String),
                                                         style: TextStyle(
                                                           fontSize: 11,
                                                           color: context.textSecondary,
                                                           fontFamily: "monospace",
                                                         ),
                                                         maxLines: 3,
                                                         overflow: TextOverflow.ellipsis,
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ],
                                              ],
                                            ),
                                        ),
                                      ],
                                    ),
                                     if (_isImageFile(_selectedFile!.name)) ...[
                                       const SizedBox(height: 10),
                                       Builder(
                                         builder: (ctx) {
                                           final hasGeminiKey = widget.apiClient.sessionService.geminiApiKey?.isNotEmpty ?? false;
                                           final bannerColor = hasGeminiKey ? const Color(0xFF6366F1) : const Color(0xFF10B981);
                                           final textColor = isDark
                                               ? (hasGeminiKey ? const Color(0xFFA5B4FC) : const Color(0xFF6EE7B7))
                                               : (hasGeminiKey ? const Color(0xFF4338CA) : const Color(0xFF065F46));
                                           return Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                             decoration: BoxDecoration(
                                               color: bannerColor.withValues(alpha: isDark ? 0.15 : 0.08),
                                               borderRadius: BorderRadius.circular(10),
                                               border: Border.all(
                                                 color: bannerColor.withValues(alpha: isDark ? 0.4 : 0.3),
                                               ),
                                             ),
                                             child: Row(
                                               children: [
                                                 Icon(
                                                   hasGeminiKey ? Icons.auto_awesome : Icons.bolt_rounded,
                                                   color: bannerColor,
                                                   size: 16,
                                                 ),
                                                 const SizedBox(width: 8),
                                                 Expanded(
                                                   child: Text(
                                                     hasGeminiKey
                                                         ? "✨ Gemini Vision OCR Ready: Cloud multimodal transcription active."
                                                         : "⚡ Native Local OCR Active: Offline screenshot transcription enabled.",
                                                     style: TextStyle(
                                                       fontSize: 11.5,
                                                       color: textColor,
                                                       fontWeight: FontWeight.w600,
                                                     ),
                                                   ),
                                                 ),
                                                 const SizedBox(width: 6),
                                                 TextButton(
                                                   style: TextButton.styleFrom(
                                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                     minimumSize: Size.zero,
                                                     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     backgroundColor: bannerColor.withValues(alpha: isDark ? 0.25 : 0.15),
                                                   ),
                                                   onPressed: _showGeminiKeyDialog,
                                                   child: Text(
                                                     hasGeminiKey ? "Key Set" : "Gemini Key (Opt.)",
                                                     style: TextStyle(
                                                       fontSize: 11,
                                                       fontWeight: FontWeight.bold,
                                                       color: textColor,
                                                     ),
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           );
                                         },
                                       ),
                                     ],
                                    ],
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
                        _buildModePresetPill(
                          emoji: "✨ 🎯",
                          label: "All Types (Simulated Exam)",
                          color: const Color(0xFF6366F1),
                          onTap: () {
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
                                "Flashcards",
                                "Summary",
                              ]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildModePresetPill(
                          emoji: "✔ 📚",
                          label: "Objective (MCQ + T/F)",
                          color: isDark ? AppColors.primary : AppColors.primaryDark,
                          onTap: () {
                            setState(() {
                              _selectedModes.clear();
                              _selectedModes.addAll(["Multiple Choice", "True / False"]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildModePresetPill(
                          emoji: "✍️",
                          label: "Active Recall (ID + Cloze + Enum)",
                          color: const Color(0xFF10B981),
                          onTap: () {
                            setState(() {
                              _selectedModes.clear();
                              _selectedModes.addAll(["Identification", "Cloze / Fill-in", "Enumeration"]);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildModePresetPill(
                          emoji: "🧩",
                          label: "Drills (Matching + Scenario)",
                          color: const Color(0xFFF59E0B),
                          onTap: () {
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
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("At least one exam mode or question type must remain active."),
                                  duration: Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Question Set & Variety Selector (Anti-Repetition)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_questionSetVariants.firstWhere(
                          (v) => v["index"] == _selectedSetIndex,
                          orElse: () => _questionSetVariants.first,
                        )["color"] as Color).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shuffle_rounded,
                                  size: 18,
                                  color: _questionSetVariants.firstWhere(
                                    (v) => v["index"] == _selectedSetIndex,
                                    orElse: () => _questionSetVariants.first,
                                  )["color"] as Color,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Question Set & Angle",
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (_questionSetVariants.firstWhere(
                                  (v) => v["index"] == _selectedSetIndex,
                                  orElse: () => _questionSetVariants.first,
                                )["color"] as Color).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _questionSetVariants.firstWhere(
                                  (v) => v["index"] == _selectedSetIndex,
                                  orElse: () => _questionSetVariants.first,
                                )["badge"] as String,
                                style: TextStyle(
                                  color: _questionSetVariants.firstWhere(
                                    (v) => v["index"] == _selectedSetIndex,
                                    orElse: () => _questionSetVariants.first,
                                  )["color"] as Color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Rotate through question sets to prevent identical questions and answers from repeating:",
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _questionSetVariants.map((variant) {
                              final int idx = variant["index"] as int;
                              final String badge = variant["badge"] as String;
                              final Color color = variant["color"] as Color;
                              final isSelected = _selectedSetIndex == idx;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setState(() => _selectedSetIndex = idx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? color.withValues(alpha: 0.15) : context.secondaryBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected ? color : context.cardBorderColor,
                                        width: isSelected ? 1.8 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isSelected ? color : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: color, width: 1.5),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          badge,
                                          style: TextStyle(
                                            color: isSelected ? color : context.textPrimary,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.secondaryBg.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 16,
                                color: _questionSetVariants.firstWhere(
                                  (v) => v["index"] == _selectedSetIndex,
                                  orElse: () => _questionSetVariants.first,
                                )["color"] as Color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _questionSetVariants.firstWhere(
                                    (v) => v["index"] == _selectedSetIndex,
                                    orElse: () => _questionSetVariants.first,
                                  )["desc"] as String,
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key("extract_text_from_modules_btn"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isExtractingTextToEditor
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
                              : const Icon(Icons.auto_stories_rounded, size: 18),
                          label: Text(
                            _isExtractingTextToEditor
                                ? "Extracting Text from Module..."
                                : "📖 Extract Text based on Provided Modules",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: _isExtractingTextToEditor ? null : _showExtractFromModulesDialog,
                        ),
                      ),
                    ],
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

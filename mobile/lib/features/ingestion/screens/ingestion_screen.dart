import "dart:async";
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
import "../../settings/services/settings_service.dart";
import "../widgets/camera_scanner_modal.dart";
import "../widgets/progressive_exam_studio.dart";

class IngestionScreen extends StatefulWidget {
  final List<CourseModel> courses;
  final ApiClient apiClient;
  final SettingsService? settingsService;
  final void Function(StudySetModel)? onStudySetCreated;
  final String? draftTitle;
  final String? draftContent;
  final int draftRevision;
  final String? initialCourseId;
  final ValueChanged<String>? onCourseSelected;

  const IngestionScreen({
    super.key,
    required this.courses,
    required this.apiClient,
    this.settingsService,
    this.onStudySetCreated,
    this.draftTitle,
    this.draftContent,
    this.draftRevision = 0,
    this.initialCourseId,
    this.onCourseSelected,
  });

  @override
  State<IngestionScreen> createState() => _IngestionScreenState();
}

class _IngestionScreenState extends State<IngestionScreen> with SingleTickerProviderStateMixin {
  static const int _maxUploadBytes = 30 * 1024 * 1024;
  late final TabController _tabController;
  late String _selectedCourseId;
  final _titleController = TextEditingController();
  bool _isCustomTitle = false;
  final _textController = TextEditingController();
  final _urlController = TextEditingController();

  PlatformFile? _selectedFile;
  Uint8List? _selectedFileBytes;
  int _fileSizeBytes = 0;
  int _targetCount = 15;
  bool _isLoading = false;
  bool _fastMode = false;
  bool _showAdvancedExamOptions = false;
  bool _isScanning = false;
  bool _isExtractingTextToEditor = false;
  bool _isScrapingUrl = false;
  bool _isSavingToNotebook = false;
  final _transcriptTextController = TextEditingController();
  Map<String, dynamic>? _scannedResult;
  Timer? _urlScanDebounce;
  Map<String, dynamic>? _detectedVideoInfo;
  bool _isAutoScanningVideo = false;
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
    _targetCount = widget.settingsService?.settings.defaultQuestionCount ?? 15;
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialCourseId != null &&
        widget.initialCourseId!.isNotEmpty &&
        widget.courses.any((c) => c.id == widget.initialCourseId)) {
      _selectedCourseId = widget.initialCourseId!;
    } else {
      _selectedCourseId = widget.courses.isNotEmpty ? widget.courses.first.id : "";
    }
    _applyIncomingDraft();
  }

  @override
  void didUpdateWidget(IngestionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.courses.isNotEmpty) {
      final hasSelected = widget.courses.any((c) => c.id == _selectedCourseId);
      final hasInitial = widget.initialCourseId != null &&
          widget.courses.any((c) => c.id == widget.initialCourseId);

      if (!hasSelected) {
        _selectedCourseId = hasInitial ? widget.initialCourseId! : widget.courses.first.id;
      } else if (widget.initialCourseId != oldWidget.initialCourseId && hasInitial) {
        _selectedCourseId = widget.initialCourseId!;
      }
    }
    if (widget.draftRevision != oldWidget.draftRevision) {
      _applyIncomingDraft();
    }
  }

  void _applyIncomingDraft() {
    final content = widget.draftContent?.trim();
    final title = widget.draftTitle?.trim();
    if (content == null || content.isEmpty) return;

    _titleController.text = title == null || title.isEmpty ? "Scanned study notes" : title;
    _textController.text = content;
    _errorMessage = null;
    // The controller is available after initState; scheduling avoids changing a
    // tab while the parent IndexedStack is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabController.animateTo(0);
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _urlScanDebounce?.cancel();
    _tabController.dispose();
    _titleController.dispose();
    _textController.dispose();
    _urlController.dispose();
    _transcriptTextController.dispose();
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
      _isCustomTitle = false;
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
        if (size > _maxUploadBytes) {
          setState(() => _errorMessage = "${file.name} is larger than 30 MB. Choose a smaller file or compress the images first.");
          return;
        }
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

        // Automatically extract text and bullet points into the Note Editor!
        await _autoExtractFileToEditor(file, bytes);
      }
    } catch (e) {
      setState(() => _errorMessage = "Error picking file: $e");
    }
  }

  Future<void> _autoExtractFileToEditor(PlatformFile file, Uint8List bytes) async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final multipartFile = MultipartFile.fromBytes(
        bytes,
        filename: file.name,
      );

      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };

      final response = await widget.apiClient.dio.post(
        ApiConstants.scanContent,
        data: FormData.fromMap(formDataMap),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final cleanText = (data["extractedText"] ?? "") as String;
        final candidateTitle = (data["suggestedTitle"] ?? "") as String;
        final charCount = data["charCount"] ?? cleanText.length;

        setState(() {
          _scannedResult = data;
          if (cleanText.trim().isNotEmpty) {
            _textController.text = cleanText.trim();
            if (!_isCustomTitle || _titleController.text.trim().isEmpty) {
              _titleController.text = candidateTitle.isNotEmpty ? candidateTitle : file.name.split('.').first;
            }
            // Switch to Note Editor tab so the user immediately sees all extracted text & bullet points!
            _tabController.animateTo(0);
          }
        });

        if (mounted && cleanText.trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✨ Extracted $charCount characters from '${file.name}' directly into Note Editor!"),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
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

  String? _validGuidOrNull(String? id) {
    if (id == null) return null;
    final clean = id.trim();
    if (clean.isEmpty) return null;
    final guidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return guidRegex.hasMatch(clean) ? clean : null;
  }

  String? _extractYouTubeVideoId(String rawUrl) {
    if (rawUrl.trim().isEmpty) return null;
    final match = RegExp(r'(?:v=|\/embed\/|\/v\/|youtu\.be\/|\/shorts\/)([0-9A-Za-z_-]{11})').firstMatch(rawUrl);
    return match?.group(1);
  }

  void _onUrlChanged(String rawUrl) {
    _urlScanDebounce?.cancel();
    final clean = rawUrl.trim();
    if (clean.isEmpty) {
      setState(() {
        _detectedVideoInfo = null;
        _isAutoScanningVideo = false;
      });
      return;
    }

    final videoId = _extractYouTubeVideoId(clean);
    final isYt = clean.toLowerCase().contains("youtube.com") || clean.toLowerCase().contains("youtu.be");

    if (videoId != null || isYt || clean.startsWith("http://") || clean.startsWith("https://")) {
      if (videoId != null && _detectedVideoInfo?['videoId'] != videoId) {
        setState(() {
          _detectedVideoInfo = {
            'videoId': videoId,
            'thumbnailUrl': 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
            'title': 'Loading video details...',
            'loading': true,
            'isYouTube': true,
          };
        });
      }

      _urlScanDebounce = Timer(const Duration(milliseconds: 500), () {
        _autoInspectUrl(clean);
      });
    }
  }

  Future<void> _autoInspectUrl(String rawUrl) async {
    String cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) return;
    if (!cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) {
      cleanUrl = "https://$cleanUrl";
    }
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (uri.scheme != "http" && uri.scheme != "https")) return;

    final videoId = _extractYouTubeVideoId(cleanUrl);
    final isYt = cleanUrl.toLowerCase().contains("youtube.com") || cleanUrl.toLowerCase().contains("youtu.be");

    if (mounted) {
      setState(() {
        _isAutoScanningVideo = true;
      });
    }

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.scanUrl,
        data: {"url": cleanUrl},
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final title = (data["title"] ?? data["suggestedTitle"] ?? "") as String;
        final author = (data["author"] ?? "") as String;
        final duration = (data["duration"] ?? "") as String;
        final extractedText = (data["extractedText"] ?? "") as String;
        final thumb = (data["thumbnailUrl"] ?? (videoId != null ? "https://i.ytimg.com/vi/$videoId/hqdefault.jpg" : "")) as String;

        if (mounted) {
          setState(() {
            _isAutoScanningVideo = false;
            _detectedVideoInfo = {
              'videoId': videoId ?? data["videoId"],
              'title': title.isNotEmpty ? title : (isYt ? "YouTube Video" : uri.host),
              'author': author,
              'duration': duration,
              'thumbnailUrl': thumb,
              'extractedText': extractedText,
              'loading': false,
              'isYouTube': isYt,
            };

            // Auto-fill Study Set Title if empty or not customized
            if (!_isCustomTitle || _titleController.text.trim().isEmpty) {
              if (title.isNotEmpty) {
                _titleController.text = title;
              }
            }

            // Automatically export extracted video notes to the editor if editor is empty
            if (extractedText.isNotEmpty && _textController.text.trim().isEmpty) {
              _textController.text = extractedText;
            }

            _errorMessage = null;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isAutoScanningVideo = false;
          if (_detectedVideoInfo != null) {
            _detectedVideoInfo!['loading'] = false;
          }
        });
      }
    }
  }

  Future<void> _scrapeAndLoadUrlToEditor() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _errorMessage = "Please provide an article or documentation URL to scrape.");
      return;
    }

    if (_detectedVideoInfo != null &&
        (_detectedVideoInfo!['extractedText'] as String? ?? '').trim().isNotEmpty) {
      final cleanText = (_detectedVideoInfo!['extractedText'] as String).trim();
      final title = (_detectedVideoInfo!['title'] as String? ?? '').trim();
      setState(() {
        _textController.text = cleanText;
        if (!_isCustomTitle || _titleController.text.trim().isEmpty) {
          if (title.isNotEmpty) _titleController.text = title;
        }
        _tabController.animateTo(0);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🎬 Video outline & notes loaded into Note Editor! Review and tap Generate Study Set."),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    String cleanUrl = rawUrl;
    if (!cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) {
      cleanUrl = "https://$cleanUrl";
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (uri.scheme != "http" && uri.scheme != "https")) {
      setState(() => _errorMessage = "Please enter a valid HTTP(S) URL (e.g. https://...).");
      return;
    }

    setState(() {
      _isScrapingUrl = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.scanUrl,
        data: {
          "url": rawUrl,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final cleanText = (data["extractedText"] ?? "") as String;
        final suggestedTitle = (data["suggestedTitle"] ?? data["title"] ?? "") as String;
        final charCount = data["charCount"] ?? data["fullTextLength"] ?? cleanText.length;

        if (cleanText.trim().isEmpty) {
          setState(() {
            _errorMessage = "No readable instructional text could be found at that URL.";
          });
          return;
        }

        setState(() {
          _textController.text = cleanText.trim();
          if (!_isCustomTitle || _titleController.text.trim().isEmpty) {
            _titleController.text = suggestedTitle.isNotEmpty ? suggestedTitle : (uri.host);
          }
          // Navigate to Note Editor so user can verify, edit, and synthesize
          _tabController.animateTo(0);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🌐 Scraped and loaded $charCount characters from '$rawUrl' into Note Editor!"),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } on DioException catch (e) {
      String msg = "Couldn't generate, try again.";
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        msg = data["message"]?.toString() ?? data["title"]?.toString() ?? msg;
      } else if (e.message != null && e.message!.isNotEmpty) {
        msg = e.message!;
      }
      setState(() {
        _errorMessage = msg;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Scraping error: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isScrapingUrl = false);
      }
    }
  }

  void _showCreateCourseDialog() {
    final codeCtrl = TextEditingController(text: "GEN-101");
    final nameCtrl = TextEditingController(text: "General Studies");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.school_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              "Create Course",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ctx.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: "Course Code (e.g. CS-101)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Course Name (e.g. General Studies)"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final name = nameCtrl.text.trim();
              if (code.isNotEmpty && name.isNotEmpty) {
                try {
                  final resp = await widget.apiClient.dio.post(
                    "/api/v1/courses",
                    data: {
                      "code": code,
                      "name": name,
                      "colorHex": "#6366F1",
                    },
                  );
                  if (resp.statusCode == 200 && resp.data is Map) {
                    final newCourse = CourseModel.fromJson(resp.data as Map<String, dynamic>);
                    setState(() {
                      widget.courses.add(newCourse);
                      _selectedCourseId = newCourse.id;
                    });
                    widget.onCourseSelected?.call(newCourse.id);
                  }
                } catch (_) {}
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
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

      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };

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
      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };

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


  Future<void> _saveExtractedNotesToNotebook() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No note content to save yet. Type or extract notes first.")),
      );
      return;
    }

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : "Lecture Notes (${DateTime.now().month}/${DateTime.now().day})";

    setState(() => _isSavingToNotebook = true);

    try {
      final success = await widget.apiClient.saveNotebookNote(
        courseId: _selectedCourseId,
        title: title,
        markdown: text,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text("✓ '$title' saved directly to your Course Notebook!")),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Could not save note to server. Please verify connection."),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingToNotebook = false);
      }
    }
  }


  void _openCameraScanner() {
    CameraScannerModal.show(
      context,
      courses: widget.courses,
      initialCourseId: _selectedCourseId,
      apiClient: widget.apiClient,
      onExportAndCreateExam: (courseId, title, scannedText) {
        final course = widget.courses.firstWhere(
          (c) => c.id == courseId,
          orElse: () => widget.courses.isNotEmpty
              ? widget.courses.first
              : CourseModel(id: courseId.isNotEmpty ? courseId : "default", code: "GEN-101", name: "General Studies", colorHex: "#6366F1", createdAt: DateTime.now()),
        );
        ProgressiveExamStudio.show(
          context,
          courseId: course.id,
          courseName: course.name,
          initialTitle: title,
          sourceText: scannedText,
          apiClient: widget.apiClient,
          onExamSaved: (newSet) {
            if (widget.onStudySetCreated != null) {
              widget.onStudySetCreated!(newSet);
            }
          },
        );
      },
      onExportToEditor: (title, scannedText) {
        setState(() {
          _titleController.text = title;
          _textController.text = scannedText;
          _tabController.animateTo(0);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✨ Transcribed notes exported to Note Editor!"),
            duration: Duration(seconds: 2),
          ),
        );
      },
    );
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                  buffer.writeln("• Key Concept ($answer): ${q.explanation ?? q.prompt}");
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

      final formDataMap = <String, dynamic>{
        "file": multipartFile,
      };

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
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981)),
                          ),
                          icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                          label: const Text("Save to Notebook"),
                          onPressed: () async {
                            final noteTitle = fileName.split('.').first;
                            final ok = await widget.apiClient.saveNotebookNote(
                              courseId: _selectedCourseId,
                              title: noteTitle.isNotEmpty ? noteTitle : "Scanned Notes",
                              markdown: extractedText,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? "✓ Scanned notes saved to Course Notebook!" : "Could not save notes. Check connection."),
                                  backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
        if (_textController.text.trim().length < 200) {
          setState(() => _errorMessage = "Add at least 200 characters of study notes (${_textController.text.trim().length}/200).");
          return;
        }

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestText,
          data: {
            "courseId": _validGuidOrNull(_selectedCourseId),
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
        if (fileBytes.length > _maxUploadBytes) {
          setState(() => _errorMessage = "This file is larger than 30 MB. Choose a smaller file or compress the images first.");
          return;
        }

        final multipartFile = MultipartFile.fromBytes(
          fileBytes,
          filename: _selectedFile!.name,
        );

        final formDataMap = <String, dynamic>{
          "file": multipartFile,
          if (_validGuidOrNull(_selectedCourseId) != null) "courseId": _validGuidOrNull(_selectedCourseId)!,
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

        final formData = FormData.fromMap(formDataMap);

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestFile,
          data: formData,
        );
      } else {
        // URL Ingestion
        final rawUrl = _urlController.text.trim();
        if (rawUrl.isEmpty) {
          setState(() => _errorMessage = "Please provide an article or documentation URL.");
          return;
        }

        String targetUrl = rawUrl;
        if (!targetUrl.startsWith("http://") && !targetUrl.startsWith("https://")) {
          targetUrl = "https://$targetUrl";
        }

        response = await widget.apiClient.dio.post(
          ApiConstants.ingestUrl,
          data: {
            "courseId": _validGuidOrNull(_selectedCourseId),
            "title": _titleController.text.trim(),
            "url": targetUrl,
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
          _detectedVideoInfo = null;
          _isAutoScanningVideo = false;
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
      String msg = "Couldn't generate, try again.";
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        msg = data["message"]?.toString() ?? data["title"]?.toString() ?? msg;
      } else if (e.message != null && e.message!.isNotEmpty) {
        msg = e.message!;
      }
      setState(() {
        _errorMessage = msg;
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

  Widget _buildDetectedVideoCard(BuildContext context) {
    if (_detectedVideoInfo == null && !_isAutoScanningVideo) {
      return const SizedBox.shrink();
    }

    final info = _detectedVideoInfo ?? {};
    final title = (info['title'] as String? ?? '').trim();
    final author = (info['author'] as String? ?? '').trim();
    final duration = (info['duration'] as String? ?? '').trim();
    final thumb = (info['thumbnailUrl'] as String? ?? '').trim();
    final isYt = info['isYouTube'] == true || _extractYouTubeVideoId(_urlController.text.trim()) != null;
    final isLoading = _isAutoScanningVideo || info['loading'] == true;
    final extractedText = (info['extractedText'] as String? ?? '').trim();
    final hasExtractedText = extractedText.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isYt
            ? const Color(0xFFEF4444).withValues(alpha: 0.08)
            : const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isYt
              ? const Color(0xFFEF4444).withValues(alpha: 0.35)
              : const Color(0xFF6366F1).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header badge row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isYt ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isYt ? Icons.smart_display_rounded : Icons.public_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isYt ? "YOUTUBE VIDEO" : "WEB SOURCE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (duration.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, color: Colors.white70, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              if (isLoading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Analyzing...",
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else if (hasExtractedText)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 4),
                    Text(
                      "Content Extracted",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Thumbnail and Details row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 112,
                  height: 64,
                  color: Colors.black26,
                  child: thumb.isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Icon(Icons.broken_image_rounded, size: 24, color: Colors.white38),
                              ),
                            ),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: Icon(Icons.video_library_rounded, size: 28, color: Colors.white38),
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // Video Title & Author
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty
                          ? title
                          : (isLoading ? "Fetching video metadata & captions..." : "Video detected"),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (author.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.person_pin_rounded, size: 13, color: context.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    // Quick Actions Bar inside the card
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        InkWell(
                          onTap: () {
                            _scrapeAndLoadUrlToEditor();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.edit_note_rounded, size: 13, color: Color(0xFF818CF8)),
                                SizedBox(width: 4),
                                Text(
                                  "Load to Note Editor",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF818CF8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (hasExtractedText)
                          InkWell(
                            onTap: () {
                              _showExtractedContentDialog(title, extractedText);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.remove_red_eye_outlined, size: 12, color: context.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    "View Details",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showExtractedContentDialog(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.smart_display_rounded, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.isNotEmpty ? title : "Extracted Video Details",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text("Export to Note Editor"),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _scrapeAndLoadUrlToEditor();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModePresetPill({
    required IconData icon,
    required String label,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    const activeColor = Color(0xFF6366F1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.16)
                : context.surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.cardBorderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeColor : context.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeColor : context.textPrimary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
            icon: const Icon(Icons.document_scanner_rounded),
            tooltip: "Open Camera Text Scanner",
            onPressed: _openCameraScanner,
          ),
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
            Tab(icon: Icon(Icons.link_rounded), text: "Link"),
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
                  // In-App Camera Scanner & Multi-Kind Exam Generation Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF0369A1).withValues(alpha: 0.25), const Color(0xFF4338CA).withValues(alpha: 0.25)]
                            : [const Color(0xFFE0F2FE), const Color(0xFFEEF2FF)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 420;
                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF06B6D4), Color(0xFF6366F1)],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.document_scanner_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "📷 In-App Camera Text Scanner",
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Snap physical notes or textbook pages to instantly transcribe text and generate smart practice exams.",
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF06B6D4),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                                  label: const Text("Scan", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: _openCameraScanner,
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF06B6D4), Color(0xFF6366F1)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.document_scanner_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "📷 In-App Camera Text Scanner",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Snap physical notes or textbook pages to instantly transcribe text and generate smart practice exams.",
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF06B6D4),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.camera_alt_rounded, size: 16),
                              label: const Text("Scan", style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: _openCameraScanner,
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Direct Note & Document Extractor Tip
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.secondaryBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.cardBorderColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Tip: Questions and concepts are extracted directly from your study notes, whiteboard photos, and documents.",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: context.textSecondary,
                              height: 1.35,
                            ),
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
                                    "⚡ Rapid processing",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Optimized rapid generation for shorter study sets.",
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _showCreateCourseDialog,
                            icon: const Icon(Icons.add_rounded, size: 15),
                            label: const Text("Create Course", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
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
                            if (val != null) {
                              setState(() => _selectedCourseId = val);
                              widget.onCourseSelected?.call(val);
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Title input
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: context.textPrimary),
                    onChanged: (val) => setState(() => _isCustomTitle = val.trim().isNotEmpty),
                    decoration: const InputDecoration(
                      labelText: "Study Set Title",
                      hintText: "e.g. Chapter 4: Cellular Respiration & Krebs Cycle",
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tab View Content
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 310,
                      maxHeight: (340.0 * MediaQuery.textScalerOf(context).scale(1.0)).clamp(310.0, 540.0),
                    ),
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
                                InkWell(
                                  onTap: _isSavingToNotebook ? null : _saveExtractedNotesToNotebook,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isSavingToNotebook) ...[
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                          ),
                                          const SizedBox(width: 6),
                                          const Text("Saving...", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                        ] else ...[
                                          const Icon(Icons.bookmark_add_rounded, size: 14, color: Color(0xFF10B981)),
                                          const SizedBox(width: 6),
                                          const Text("💾 Save to Notebook", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
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
                                onChanged: (_) => setState(() {}),
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
                                                     label: const Text("Extract to Note Editor", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                                       Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                         decoration: BoxDecoration(
                                           color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08),
                                           borderRadius: BorderRadius.circular(10),
                                           border: Border.all(
                                             color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.4 : 0.3),
                                           ),
                                         ),
                                         child: Row(
                                           children: [
                                             const Icon(
                                               Icons.auto_awesome,
                                               color: Color(0xFF10B981),
                                               size: 16,
                                             ),
                                             const SizedBox(width: 8),
                                             Expanded(
                                               child: Text(
                                                 "High-Precision OCR Active: Multimodal and native text transcription enabled.",
                                                 style: TextStyle(
                                                   fontSize: 11.5,
                                                   color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                                                   fontWeight: FontWeight.w600,
                                                 ),
                                               ),
                                             ),
                                           ],
                                         ),
                                       ),
                                     ],
                                    ],
                                  ),
                                ),

                        // Tab 3: YouTube & Lecture Transcript -> Auto-Notes
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (ctx) {
                                  final urlText = _urlController.text.trim().toLowerCase();
                                  final isYt = urlText.contains("youtube.com") || urlText.contains("youtu.be");
                                  final isWeb = urlText.startsWith("http://") || urlText.startsWith("https://");

                                  return TextField(
                                    controller: _urlController,
                                    keyboardType: TextInputType.url,
                                    style: TextStyle(color: context.textPrimary),
                                    decoration: InputDecoration(
                                      labelText: isYt
                                          ? "YouTube Video URL"
                                          : (isWeb ? "Web Article URL" : "Web / Video URL"),
                                      hintText: isYt
                                          ? "https://www.youtube.com/watch?v=..."
                                          : "https://en.wikipedia.org/... or YouTube URL",
                                      prefixIcon: Icon(
                                        isYt
                                            ? Icons.smart_display_rounded
                                            : (isWeb ? Icons.language_rounded : Icons.link_rounded),
                                        color: isYt
                                            ? const Color(0xFFEF4444)
                                            : (isWeb ? const Color(0xFF6366F1) : context.textSecondary),
                                      ),
                                      suffixIcon: _urlController.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear_rounded, size: 18),
                                              tooltip: "Clear URL",
                                              onPressed: () {
                                                _urlScanDebounce?.cancel();
                                                setState(() {
                                                  _urlController.clear();
                                                  _detectedVideoInfo = null;
                                                  _isAutoScanningVideo = false;
                                                });
                                              },
                                            )
                                          : IconButton(
                                              icon: const Icon(Icons.content_paste_rounded, size: 18),
                                              tooltip: "Paste URL from Clipboard",
                                              onPressed: () async {
                                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                                if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                                  _urlController.text = data.text!.trim();
                                                  _onUrlChanged(data.text!.trim());
                                                  setState(() {});
                                                }
                                              },
                                            ),
                                    ),
                                    onChanged: (v) {
                                      _onUrlChanged(v);
                                      setState(() {});
                                    },
                                  );
                                },
                              ),
                              _buildDetectedVideoCard(context),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _transcriptTextController,
                                maxLines: 3,
                                style: TextStyle(color: context.textPrimary, fontSize: 12.5),
                                decoration: const InputDecoration(
                                  labelText: "Or Paste Lecture Transcript / Otter.ai / Zoom Audio text",
                                  hintText: "00:01 Welcome class, today we examine the cellular Krebs cycle...",
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: _isScrapingUrl
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.arrow_forward_rounded, size: 16),
                                    label: Text(
                                      _isScrapingUrl
                                          ? "Extracting to Editor..."
                                          : "Extract to Note Editor",
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: (_isScrapingUrl || _isLoading)
                                        ? null
                                        : () {
                                            if (_transcriptTextController.text.trim().isNotEmpty && _urlController.text.trim().isEmpty) {
                                              setState(() {
                                                _textController.text = _transcriptTextController.text.trim();
                                                if (!_isCustomTitle || _titleController.text.trim().isEmpty) {
                                                  _titleController.text = "Lecture Transcript Notes";
                                                }
                                                _tabController.animateTo(0);
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text("📝 Transcript loaded into Note Editor! Review and tap Generate Study Set."),
                                                  backgroundColor: Color(0xFF10B981),
                                                ),
                                              );
                                            } else {
                                              _scrapeAndLoadUrlToEditor();
                                            }
                                          },
                                  ),
                                ],
                              ),
                            if (_isScrapingUrl) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Scraping article content, headings & learning outcomes...",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
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
                ),

                  const SizedBox(height: 20),
                  const SizedBox(height: 16),

                  // Smart Defaults & Advanced Options Disclosure
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "Recommended Setup Active",
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "SMART DEFAULT",
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${_selectedModes.join(' + ')} · $_targetCount Questions",
                                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _showAdvancedExamOptions = !_showAdvancedExamOptions),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: Icon(
                            _showAdvancedExamOptions ? Icons.expand_less_rounded : Icons.tune_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _showAdvancedExamOptions ? "Close" : "Advanced",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_showAdvancedExamOptions) ...[
                    const SizedBox(height: 14),
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
                            icon: Icons.all_inclusive_rounded,
                            label: "All Types (Simulated Exam)",
                            isSelected: _selectedModes.length >= 8,
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
                            icon: Icons.fact_check_outlined,
                            label: "Objective (MCQ + T/F)",
                            isSelected: _selectedModes.length == 2 &&
                                _selectedModes.contains("Multiple Choice") &&
                                _selectedModes.contains("True / False"),
                            onTap: () {
                              setState(() {
                                _selectedModes.clear();
                                _selectedModes.addAll(["Multiple Choice", "True / False"]);
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildModePresetPill(
                            icon: Icons.edit_note_rounded,
                            label: "Active Recall (ID + Cloze + Enum)",
                            isSelected: _selectedModes.length == 3 &&
                                _selectedModes.contains("Identification") &&
                                _selectedModes.contains("Cloze / Fill-in") &&
                                _selectedModes.contains("Enumeration"),
                            onTap: () {
                              setState(() {
                                _selectedModes.clear();
                                _selectedModes.addAll(["Identification", "Cloze / Fill-in", "Enumeration"]);
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildModePresetPill(
                            icon: Icons.extension_outlined,
                            label: "Drills (Matching + Scenario)",
                            isSelected: _selectedModes.length == 2 &&
                                _selectedModes.contains("Matching Type") &&
                                _selectedModes.contains("Scenario Drills"),
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
                          selectedColor: const Color(0xFF6366F1),
                          backgroundColor: context.surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF6366F1) : context.cardBorderColor,
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

                    // Target questions controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Target Questions:",
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "$_targetCount Questions",
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        // Quick-Select Badges
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [5, 10, 15, 20].map((count) {
                            final isSelected = _targetCount == count;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text("$count"),
                                selected: isSelected,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : context.textPrimary,
                                ),
                                selectedColor: const Color(0xFF6366F1),
                                backgroundColor: context.surfaceColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? const Color(0xFF6366F1) : context.cardBorderColor,
                                  ),
                                ),
                                onSelected: (_) => setState(() => _targetCount = count),
                              ),
                            );
                          }).toList(),
                        ),
                        // Compact Stepper + Capped Slider
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                              color: context.textSecondary,
                              tooltip: "Decrease questions",
                              onPressed: _targetCount > 5
                                  ? () => setState(() => _targetCount = (_targetCount - 5).clamp(5, 20))
                                  : null,
                            ),
                            SizedBox(
                              width: 200,
                              child: Slider(
                                value: _targetCount.toDouble(),
                                min: 5,
                                max: 20,
                                divisions: 3,
                                activeColor: const Color(0xFF6366F1),
                                onChanged: (val) => setState(() => _targetCount = val.toInt()),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                              color: context.textSecondary,
                              tooltip: "Increase questions",
                              onPressed: _targetCount < 20
                                  ? () => setState(() => _targetCount = (_targetCount + 5).clamp(5, 20))
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],

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

                  Builder(
                    builder: (context) {
                      final isTextTab = _tabController.index == 0;
                      final textLen = _textController.text.trim().length;
                      final hasMinText = !isTextTab || textLen >= 200;
                      final canGenerate = !_isLoading && (textLen == 0 || hasMinText);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isTextTab && textLen < 200)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "Add at least 200 characters ($textLen/200)",
                                style: const TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
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
                                  : (_fastMode ? "⚡ Quick Local Processing" : "Generate Study Set from Notes"),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: canGenerate ? _handleGenerate : null,
                          ),
                        ],
                      );
                    },
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

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
  String? _errorMessage;
  StudySetModel? _lastGeneratedSet;

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
    _tabController.dispose();
    _titleController.dispose();
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["pdf", "docx", "txt", "md"],
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
      _lastGeneratedSet = null;
    });

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
            "questionTypes": ["multiple_choice", "identification"],
          },
        );
      } else if (_tabController.index == 1) {
        // File Upload Ingestion
        if (_selectedFile == null) {
          setState(() => _errorMessage = "Please select a document file (.pdf, .docx, .txt).");
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
          },
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final newSet = StudySetModel.fromJson(response.data);
        setState(() {
          _lastGeneratedSet = newSet;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text("AI Study Synthesizer Studio", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.textPrimary)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
          labelColor: isDark ? Colors.white : AppColors.primaryDark,
          unselectedLabelColor: context.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.notes_rounded), text: "Paste Text"),
            Tab(icon: Icon(Icons.upload_file_rounded), text: "Upload File"),
            Tab(icon: Icon(Icons.link_rounded), text: "Article URL"),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF2E1065)]
                        : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Powered by Google Gemini AI",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF312E81),
                            ),
                          ),
                          Text(
                            "Curriculum synthesis with active recall & distractor rationale",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF4338CA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                Container(
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
                const SizedBox(height: 16),
              ],

              if (_lastGeneratedSet != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            "Study Set Ready: ${_lastGeneratedSet!.title}",
                            style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "${_lastGeneratedSet!.questionCount} questions synthesized directly from document concepts.",
                        style: const TextStyle(color: AppColors.accent, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                  hintText: "e.g. Chapter 4: Database Normalization",
                ),
              ),
              const SizedBox(height: 20),

              // Tab View Content
              SizedBox(
                height: 220,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Text
                    TextField(
                      controller: _textController,
                      maxLines: 8,
                      style: TextStyle(color: context.textPrimary),
                      decoration: const InputDecoration(
                        labelText: "Lecture Notes or Text Content",
                        hintText: "Paste textbook paragraphs, slide content, or key definitions here...",
                      ),
                    ),

                    // Tab 2: File Picker
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
                              _selectedFile != null ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                              size: 48,
                              color: _selectedFile != null
                                  ? AppColors.accent
                                  : (isDark ? AppColors.primaryLight : AppColors.primaryDark),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedFile != null ? _selectedFile!.name : "Tap to browse PDF, Word (DOCX), or TXT",
                              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedFile != null
                                  ? "${(_fileSizeBytes / 1024).toStringAsFixed(1)} KB ready for extraction"
                                  : "Supports textbooks, syllabus, lecture handouts up to 25MB",
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
                            hintText: "https://learn.microsoft.com/en-us/...",
                            prefixIcon: Icon(Icons.language_rounded, color: context.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "The backend extracts clean instructional paragraphs and discards advertisements.",
                          style: TextStyle(color: context.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

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

              const SizedBox(height: 28),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? "Synthesizing with Gemini AI..." : "Generate AI Study Set (Gemini)"),
                onPressed: _isLoading ? null : _handleGenerate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

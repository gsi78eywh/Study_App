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

  const IngestionScreen({
    super.key,
    required this.courses,
    required this.apiClient,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedCourseId = widget.courses.isNotEmpty ? widget.courses.first.id : "";
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
        if (_titleController.text.isEmpty) {
          _titleController.text = file.name.split('.').first;
        }
      });
    }
  }

  Future<void> _handleGenerate() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Please enter a title for the study set.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
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

        final bytes = await _selectedFile!.readAsBytes();
        final multipartFile = MultipartFile.fromBytes(
          bytes,
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
        if (!mounted) return;
        Navigator.pop(context, newSet);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Study Ingestion"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.darkTextSecondary,
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
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                  ),
                  child: Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],

              // Course Selector
              Text("Assign to Course", style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkCardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCourseId,
                    isExpanded: true,
                    dropdownColor: AppColors.darkCard,
                    items: widget.courses.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text("${c.code} - ${c.name}", style: const TextStyle(color: Colors.white)),
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
                style: const TextStyle(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
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
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _selectedFile != null ? AppColors.primary : AppColors.darkCardBorder,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _selectedFile != null ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                              size: 48,
                              color: _selectedFile != null ? AppColors.accent : AppColors.primaryLight,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedFile != null ? _selectedFile!.name : "Tap to browse PDF, Word (DOCX), or TXT",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedFile != null
                                  ? "${(_fileSizeBytes / 1024).toStringAsFixed(1)} KB ready for extraction"
                                  : "Supports textbooks, syllabus, lecture handouts up to 25MB",
                              style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
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
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: "Web Article or Documentation URL",
                            hintText: "https://learn.microsoft.com/en-us/...",
                            prefixIcon: Icon(Icons.language_rounded, color: AppColors.darkTextSecondary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "The C# backend crawler strips advertisements, scripts, and layouts to extract clean instructional text.",
                          style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
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
                  const Text("Target Questions:", style: TextStyle(color: AppColors.darkTextSecondary)),
                  Text("$_targetCount Questions", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _targetCount.toDouble(),
                min: 5,
                max: 20,
                divisions: 3,
                activeColor: AppColors.primary,
                onChanged: (val) => setState(() => _targetCount = val.toInt()),
              ),

              const SizedBox(height: 28),

              ElevatedButton.icon(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? "Synthesizing with Semantic Kernel..." : "Generate AI Study Set"),
                onPressed: _isLoading ? null : _handleGenerate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import "dart:async";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:image_picker/image_picker.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../services/clipboard_image_reader.dart";
import "../services/fast_ocr_service.dart";

enum ScannerMode {
  handwritten("Notes", Icons.edit_note_rounded, "Handwritten notes"),
  textbook("Book", Icons.menu_book_rounded, "Printed pages"),
  examSheet("Exam", Icons.assignment_outlined, "Test papers"),
  definitions("Terms", Icons.science_outlined, "Formulas & terms"),
  syllabus("Outline", Icons.calendar_month_rounded, "Course outline");

  final String label;
  final IconData icon;
  final String description;
  const ScannerMode(this.label, this.icon, this.description);
}

class CameraScannerModal extends StatefulWidget {
  final List<CourseModel> courses;
  final String? initialCourseId;
  final ApiClient apiClient;
  final void Function(String courseId, String title, String scannedText) onExportAndCreateExam;
  final void Function(String title, String scannedText)? onExportToEditor;
  final VoidCallback? onSaveToNotebook;

  const CameraScannerModal({
    super.key,
    required this.courses,
    this.initialCourseId,
    required this.apiClient,
    required this.onExportAndCreateExam,
    this.onExportToEditor,
    this.onSaveToNotebook,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CourseModel> courses,
    String? initialCourseId,
    required ApiClient apiClient,
    required void Function(String courseId, String title, String scannedText) onExportAndCreateExam,
    void Function(String title, String scannedText)? onExportToEditor,
    VoidCallback? onSaveToNotebook,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CameraScannerModal(
        courses: courses,
        initialCourseId: initialCourseId,
        apiClient: apiClient,
        onExportAndCreateExam: onExportAndCreateExam,
        onExportToEditor: onExportToEditor,
        onSaveToNotebook: onSaveToNotebook,
      ),
    );
  }

  @override
  State<CameraScannerModal> createState() => _CameraScannerModalState();
}

class _CameraScannerModalState extends State<CameraScannerModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanLaserController;
  final ImagePicker _picker = ImagePicker();

  late String _selectedCourseId;
  ScannerMode _selectedMode = ScannerMode.handwritten;

  Uint8List? _capturedImageBytes;
  String? _capturedImageName;
  bool _isScanning = false;
  bool _isGeneratingFlashcards = false;
  bool _isSavingToNotebook = false;
  String? _errorMessage;

  // Extracted Result
  String _extractedText = "";
  int _charCount = 0;
  int _wordCount = 0;
  String _ocrEngine = "";
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  static const Map<String, Map<String, String>> _samplePresets = {
    "biology": {
      "name": "🧬 Biology: Cellular Respiration & ATP",
      "title": "Cellular Respiration & Energy Notes",
      "text": """Cellular Respiration and ATP Synthesis

1. Glycolysis:
- Occurs in the cytoplasm of cells.
- Anaerobic process: does not require oxygen.
- Glucose (6-carbon molecule) is split into two molecules of pyruvate (3 carbons each).
- Net yield: 2 ATP molecules and 2 NADH molecules per glucose.

2. The Krebs Cycle (Citric Acid Cycle):
- Located inside the mitochondrial matrix.
- Aerobic pathway requiring oxygen availability.
- Pyruvate is converted into Acetyl-CoA before entering the cycle.
- Produces ATP, NADH, and FADH2 while releasing CO2 as a byproduct.

3. Oxidative Phosphorylation and Electron Transport Chain (ETC):
- Located on the inner mitochondrial membrane (cristae).
- High-energy electrons from NADH and FADH2 drive proton pumps into the intermembrane space.
- Proton gradient drives ATP Synthase to generate approximately 26 to 28 ATP molecules.
- Oxygen is the terminal electron acceptor, reacting with protons to form water (H2O).
- Total theoretical maximum yield of cellular respiration is 30 to 32 ATP per glucose.

Key Concepts:
- ATP Synthase: Rotary motor enzyme synthesizing ATP from ADP and inorganic phosphate.
- Chemiosmosis: Diffusion of hydrogen ions across a membrane down their electrochemical gradient."""
    },
    "cs": {
      "name": "💻 Computer Science: Data Structures & Trees",
      "title": "Data Structures & Tree Traversal",
      "text": """Data Structures: Binary Trees and Graph Traversals

1. Binary Search Tree (BST) Properties:
- A node-based binary tree data structure.
- Left subtree of a node contains only nodes with keys lesser than the node's key.
- Right subtree of a node contains only nodes with keys greater than the node's key.
- Both left and right subtrees must also be binary search trees.
- Average search, insert, and delete time complexity is O(log n). Worst case is O(n) for unbalanced trees.

2. Self-Balancing Trees:
- AVL Tree: Strictly balanced binary search tree where height difference between left and right subtrees is at most 1.
- Red-Black Tree: Guarantees search in O(log n) time by enforcing color properties and rotations during insert and delete.

3. Tree Traversal Algorithms:
- Inorder Traversal (Left, Root, Right): Traverses BST in ascending numerical order.
- Preorder Traversal (Root, Left, Right): Commonly used to create a duplicate copy of the tree.
- Postorder Traversal (Left, Right, Root): Used to delete or free tree nodes from leaves to root."""
    },
    "chemistry": {
      "name": "🧪 Chemistry: Chemical Equilibrium & Le Chatelier",
      "title": "Chemical Equilibrium & Reaction Dynamics",
      "text": """Chemical Equilibrium and Le Chatelier's Principle

1. Dynamic Chemical Equilibrium:
- Occurs in a reversible chemical reaction when the rate of the forward reaction equals the rate of the reverse reaction.
- Concentrations of reactants and products remain constant over time.
- Equilibrium Constant (Keq) expresses the ratio of product concentrations to reactant concentrations at a given temperature.

2. Le Chatelier's Principle:
- When a chemical system at equilibrium is disturbed by a change in temperature, pressure, or concentration, the system shifts in the direction that counteracts the disturbance.
- Increasing reactant concentration shifts equilibrium towards products.
- Increasing pressure shifts equilibrium toward the side with fewer gas moles.
- For an exothermic reaction, increasing temperature shifts equilibrium toward reactants."""
    }
  };

  void _loadSamplePreset(String key) {
    final preset = _samplePresets[key];
    if (preset == null) return;

    final dummyPngBytes = _createSimplePlaceholderBytes(preset["title"]!);

    setState(() {
      _capturedImageBytes = dummyPngBytes;
      _capturedImageName = "${key}_notes_scan.png";
      _extractedText = preset["text"]!;
      _titleController.text = preset["title"]!;
      _textController.text = preset["text"]!;
      _charCount = preset["text"]!.length;
      _wordCount = preset["text"]!.split(RegExp(r"\s+")).length;
      _ocrEngine = "Gemini Multimodal Vision (Preset)";
      _errorMessage = null;
      _isScanning = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✨ Loaded ${preset["title"]} sample scan!"),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Uint8List _createSimplePlaceholderBytes(String text) {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
  }

  @override
  void initState() {
    super.initState();
    _selectedCourseId = (widget.initialCourseId != null && widget.initialCourseId!.isNotEmpty)
        ? widget.initialCourseId!
        : (widget.courses.isNotEmpty ? widget.courses.first.id : "");
    _scanLaserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLaserController.dispose();
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera() async {
    try {
      XFile? photo;
      try {
        photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 92,
        );
      } catch (_) {
        // Fallback to gallery/file picker on web/devices without direct camera API
        photo = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 95,
        );
      }

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedImageBytes = bytes;
          _capturedImageName = photo!.name.isNotEmpty ? photo.name : "camera_scan.png";
          _errorMessage = null;
        });
        await _performOcrScan(bytes, _capturedImageName!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Could not open camera ($e). Try 'Pick Image' or 'Paste Screenshot' instead.";
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedImageBytes = bytes;
          _capturedImageName = photo.name.isNotEmpty ? photo.name : "screenshot_scan.png";
          _errorMessage = null;
        });
        await _performOcrScan(bytes, _capturedImageName!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Image selection error: $e";
      });
    }
  }

  Future<void> _pasteScreenshotFromClipboard() async {
    setState(() {
      _errorMessage = null;
    });

    final payload = await readClipboardScreenshot();
    if (payload != null && payload.bytes.isNotEmpty) {
      setState(() {
        _capturedImageBytes = payload.bytes;
        _capturedImageName = payload.name;
      });
      await _performOcrScan(payload.bytes, payload.name);
      return;
    }

    // If no image in clipboard, prompt image picker so user is never stuck
    await _pickFromGallery();
  }

  Future<void> _performOcrScan(Uint8List imageBytes, String filename) async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final result = await FastOcrService.extractTextFromImage(
        imageBytes: imageBytes,
        filename: filename,
        apiClient: widget.apiClient,
      );

      if (!mounted) return;
      setState(() {
        _extractedText = result.extractedText;
        _titleController.text = result.suggestedTitle;
        _textController.text = result.extractedText;
        _charCount = result.charCount;
        _wordCount = result.wordCount;
        _ocrEngine = result.ocrEngine;
      });

      if (result.extractedText.trim().isEmpty) {
        setState(() {
          _errorMessage =
              "No clear text detected in this image. Please ensure the screenshot or camera photo is sharp and well-lit, or type/paste text directly below.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "OCR Scan error: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _clearScan() {
    setState(() {
      _capturedImageBytes = null;
      _capturedImageName = null;
      _extractedText = "";
      _charCount = 0;
      _wordCount = 0;
      _titleController.clear();
      _textController.clear();
      _errorMessage = null;
      _isScanning = false;
    });
  }


  Future<void> _autoGenerateFlashcardsFromOcr() async {
    final text = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : _extractedText.trim();
    if (text.isEmpty) return;

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : "Scanned Cards (${DateTime.now().month}/${DateTime.now().day})";

    setState(() => _isGeneratingFlashcards = true);

    try {
      await widget.apiClient.dio.post(
        ApiConstants.ingestText,
        data: {
          "courseId": _selectedCourseId.isNotEmpty ? _selectedCourseId : null,
          "title": title,
          "content": text,
          "questionTypes": ["identification", "multiple_choice"],
          "targetCount": 8,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚡ Flashcards created for '$title'"),
            backgroundColor: const Color(0xFFFF6B00),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // Offline fallback: synthesize directly on device via onExportAndCreateExam
      if (mounted) {
        final courseId = _selectedCourseId.isNotEmpty
            ? _selectedCourseId
            : (widget.courses.isNotEmpty ? widget.courses.first.id : "");
        Navigator.of(context).pop();
        widget.onExportAndCreateExam(courseId, title, text);
      }
    }
  }

  Future<void> _saveScannedNotesToNotebook() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : "Scanned Lecture Note (${DateTime.now().month}/${DateTime.now().day})";

    setState(() => _isSavingToNotebook = true);

    try {
      final success = await widget.apiClient.saveNotebookNote(
        courseId: _selectedCourseId,
        title: title,
        markdown: text,
      );

      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text("✓ '$title' saved directly to Course Notebook!")),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          setState(() {
            _isSavingToNotebook = false;
            _errorMessage = "Failed to save note to Course Notebook. Please check connection.";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to save note to Course Notebook. Please check connection."),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSavingToNotebook = false;
          _errorMessage = "Could not save to notebook: $e";
        });
      }
    }
  }

  void _triggerAutoExportAndCreateExam() {
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : "Scanned Notes ${DateTime.now().month}/${DateTime.now().day}";
    final content = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : _extractedText.trim();

    if (content.isEmpty) {
      setState(() => _errorMessage = "Please scan or enter text before generating an exam.");
      return;
    }

    final courseId = _selectedCourseId.isNotEmpty
        ? _selectedCourseId
        : (widget.courses.isNotEmpty ? widget.courses.first.id : "");

    Navigator.of(context).pop();
    widget.onExportAndCreateExam(courseId, title, content);
  }

  void _triggerExportToEditor() {
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : "Scanned Notes";
    final content = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : _extractedText.trim();

    if (content.isEmpty) {
      setState(() => _errorMessage = "No text available to export.");
      return;
    }

    Navigator.of(context).pop();
    if (widget.onExportToEditor != null) {
      widget.onExportToEditor!(title, content);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 25,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header (UnionBank Clean Icon-First Header)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B00), Color(0xFFF97316)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Smart Scanner",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        "Instant Offline & Vision OCR",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target Course Selector
                  if (widget.courses.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          "Target Course:",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: context.secondaryBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.cardBorderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: widget.courses.any((c) => c.id == _selectedCourseId)
                                    ? _selectedCourseId
                                    : (widget.courses.isNotEmpty ? widget.courses.first.id : ""),
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: widget.courses.isNotEmpty
                                    ? widget.courses.map((course) {
                                        return DropdownMenuItem<String>(
                                          value: course.id,
                                          child: Text(
                                            course.name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                        );
                                      }).toList()
                                    : [
                                        DropdownMenuItem<String>(
                                          value: "",
                                          child: Text(
                                            "Default Space (General Studies)",
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: context.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedCourseId = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Mode Selector Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ScannerMode.values.map((mode) {
                        final isSelected = _selectedMode == mode;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: isSelected,
                            onSelected: (_) => setState(() => _selectedMode = mode),
                            avatar: Icon(
                              mode.icon,
                              size: 15,
                              color: isSelected ? Colors.white : context.textSecondary,
                            ),
                            label: Text(mode.label),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : context.textPrimary,
                            ),
                            selectedColor: const Color(0xFF6366F1),
                            backgroundColor: context.secondaryBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF6366F1) : context.cardBorderColor,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Camera Viewfinder HUD / Reticle Card
                  _buildViewfinderHUD(context, isDark),
                  const SizedBox(height: 16),

                  // Error Banner if any
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Scanned Results & Auto-Export Panel
                  if (_extractedText.isNotEmpty)
                    _buildExtractedResultInspector(context, isDark),

                  // Quick Academic Notes Presets
                  if (_extractedText.isEmpty && !_isScanning)
                    _buildSamplePresetsSection(context, isDark),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinderHUD(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      height: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF030712),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF06B6D4).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background grid pattern simulation
            Positioned.fill(
              child: Opacity(
                opacity: 0.08,
                child: CustomPaint(
                  painter: _GridPainter(),
                ),
              ),
            ),

            // Captured Image Preview (if present)
            if (_capturedImageBytes != null)
              Positioned.fill(
                child: Image.memory(
                  _capturedImageBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.image, color: Colors.white24, size: 48),
                  ),
                ),
              ),

            // Corner Reticles [ ]
            const Positioned(
              top: 14,
              left: 14,
              child: _ReticleCorner(alignment: Alignment.topLeft),
            ),
            const Positioned(
              top: 14,
              right: 14,
              child: _ReticleCorner(alignment: Alignment.topRight),
            ),
            const Positioned(
              bottom: 14,
              left: 14,
              child: _ReticleCorner(alignment: Alignment.bottomLeft),
            ),
            const Positioned(
              bottom: 14,
              right: 14,
              child: _ReticleCorner(alignment: Alignment.bottomRight),
            ),

            // Captured filename tag
            if (_capturedImageName != null)
              Positioned(
                top: 18,
                left: 28,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    _capturedImageName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),

            // Animated Laser Scanline Beam
            if (_isScanning || _capturedImageBytes != null)
              AnimatedBuilder(
                animation: _scanLaserController,
                builder: (context, child) {
                  return Positioned(
                    top: _scanLaserController.value * 230,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFF06B6D4),
                            Color(0xFF67E8F9),
                            Color(0xFF06B6D4),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            // Center Call-to-action or status
            if (_isScanning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Color(0xFF06B6D4),
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Extracting text via Seth AI Vision OCR...",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (_capturedImageBytes == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Tap an icon to scan",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildScanIconTile(
                          icon: Icons.camera_alt_rounded,
                          label: "Camera",
                          color: const Color(0xFFFF6B00),
                          onTap: _captureFromCamera,
                        ),
                        _buildScanIconTile(
                          icon: Icons.photo_library_rounded,
                          label: "Gallery",
                          color: const Color(0xFF06B6D4),
                          onTap: _pickFromGallery,
                        ),
                        _buildScanIconTile(
                          icon: Icons.content_paste_rounded,
                          label: "Paste",
                          color: const Color(0xFF10B981),
                          onTap: _pasteScreenshotFromClipboard,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Positioned(
                bottom: 12,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.75),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text("Rescan", style: TextStyle(fontSize: 12)),
                  onPressed: _clearScan,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedResultInspector(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OCR Stats Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 13),
                    const SizedBox(width: 4),
                    Text(
                      "$_charCount chars • $_wordCount words",
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_ocrEngine.isNotEmpty)
                Expanded(
                  child: Text(
                    _ocrEngine,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Title Input
          Text(
            "Study Set Title:",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: "Enter title for this study material",
              filled: true,
              fillColor: context.secondaryBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.cardBorderColor),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Transcribed Text Input
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Transcribed Content (Editable):",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              Text(
                "Review & tweak if needed",
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _textController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: "Scanned text from your notes will appear here...",
              filled: true,
              fillColor: context.secondaryBg,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.cardBorderColor),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // UnionBank Icon-First Action Bar (Exam, Cards, Save, Editor)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildResultActionTile(
                  context,
                  icon: Icons.quiz_rounded,
                  label: "Exam",
                  color: const Color(0xFFFF6B00),
                  filled: true,
                  onTap: _triggerAutoExportAndCreateExam,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildResultActionTile(
                  context,
                  icon: Icons.bolt_rounded,
                  label: _isGeneratingFlashcards ? "..." : "Cards",
                  color: const Color(0xFF10B981),
                  filled: true,
                  onTap: _isGeneratingFlashcards ? null : _autoGenerateFlashcardsFromOcr,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildResultActionTile(
                  context,
                  icon: Icons.bookmark_add_rounded,
                  label: "Save",
                  color: const Color(0xFF0EA5E9),
                  filled: false,
                  onTap: _isSavingToNotebook ? null : _saveScannedNotesToNotebook,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildResultActionTile(
                  context,
                  icon: Icons.edit_note_rounded,
                  label: "Editor",
                  color: const Color(0xFF6366F1),
                  filled: false,
                  onTap: _triggerExportToEditor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanIconTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? color : color.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: filled ? Colors.white : color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSamplePresetsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFFF6B00), size: 16),
            const SizedBox(width: 6),
            Text(
              "Quick Sample Scans",
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: _samplePresets.entries.map((entry) {
            final shortName = entry.key == "biology"
                ? "Biology"
                : entry.key == "cs"
                    ? "CompSci"
                    : "Chemistry";
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.cardBorderColor),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _loadSamplePreset(entry.key),
                  child: Text(
                    shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ReticleCorner extends StatelessWidget {
  final Alignment alignment;
  const _ReticleCorner({required this.alignment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        border: Border(
          top: alignment == Alignment.topLeft || alignment == Alignment.topRight
              ? const BorderSide(color: Color(0xFF06B6D4), width: 3)
              : BorderSide.none,
          bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
              ? const BorderSide(color: Color(0xFF06B6D4), width: 3)
              : BorderSide.none,
          left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
              ? const BorderSide(color: Color(0xFF06B6D4), width: 3)
              : BorderSide.none,
          right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
              ? const BorderSide(color: Color(0xFF06B6D4), width: 3)
              : BorderSide.none,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..strokeWidth = 0.5;

    const double step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

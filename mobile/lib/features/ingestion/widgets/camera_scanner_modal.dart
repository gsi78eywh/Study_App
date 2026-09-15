import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "package:image_picker/image_picker.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

enum ScannerMode {
  handwritten("Handwritten Notes", Icons.edit_note_rounded, "Optimized for handwritten lecture notes and diagrams"),
  textbook("Book & Printed", Icons.menu_book_rounded, "Optimized for textbook pages, dense paragraphs, and publications"),
  examSheet("Exam & Quiz Sheet", Icons.assignment_outlined, "Optimized for review questionnaires and test papers"),
  definitions("Formulas & Glossary", Icons.science_outlined, "Optimized for definitions, terms, and formulas");

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

  @override
  void initState() {
    super.initState();
    _selectedCourseId = widget.initialCourseId ??
        (widget.courses.isNotEmpty ? widget.courses.first.id : "");
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
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedImageBytes = bytes;
          _capturedImageName = photo.name;
          _errorMessage = null;
        });
        await _performOcrScan(bytes, photo.name);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Camera access error: $e. You can also pick an image from gallery or try a sample note.";
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
          _capturedImageName = photo.name;
          _errorMessage = null;
        });
        await _performOcrScan(bytes, photo.name);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Image selection error: $e";
      });
    }
  }

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
    // 1x1 transparent PNG header placeholder
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
  }

  Future<void> _performOcrScan(Uint8List imageBytes, String filename) async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final multipartFile = MultipartFile.fromBytes(imageBytes, filename: filename);
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
        final rawTitle = (data["suggestedTitle"] ?? "") as String;
        final defaultTitle = rawTitle.isNotEmpty ? rawTitle : filename.split('.').first;

        setState(() {
          _extractedText = cleanText;
          _titleController.text = defaultTitle;
          _textController.text = cleanText;
          _charCount = data["charCount"] ?? cleanText.length;
          _wordCount = data["wordCount"] ?? (cleanText.isEmpty ? 0 : cleanText.split(RegExp(r"\s+")).length);
          _ocrEngine = data["ocrEngine"] ?? "Gemini Vision OCR";
        });

        if (cleanText.trim().isEmpty) {
          setState(() {
            _errorMessage = "No readable text recognized. Ensure lighting is clear and focused, or paste/type notes directly.";
          });
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "Scan failed. Ensure backend is running.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "OCR Scan error: $e";
      });
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

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "In-App Camera Scanner",
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        "Scan text or physical notes & auto-create exams",
                        style: TextStyle(
                          fontSize: 12,
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
                                value: _selectedCourseId.isNotEmpty
                                    ? _selectedCourseId
                                    : widget.courses.first.id,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: widget.courses.map((course) {
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
                                }).toList(),
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
                  errorBuilder: (_, __, ___) => const Center(
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
                      "Transcribing text via Gemini Vision OCR...",
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
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Color(0xFF06B6D4),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Align physical note or textbook page in frame",
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF06B6D4),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 16),
                        label: const Text("Take Photo", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _captureFromCamera,
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text("Pick Image"),
                        onPressed: _pickFromGallery,
                      ),
                    ],
                  ),
                ],
              )
            else
              Positioned(
                bottom: 12,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text("Retake Photo", style: TextStyle(fontSize: 12)),
                      onPressed: _clearScan,
                    ),
                  ],
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

          // Auto-Export Action Buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                "🚀 Auto-Export & Slowly Create Exam Kinds",
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _triggerAutoExportAndCreateExam,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.cardBorderColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text("Send to Editor"),
                  onPressed: _triggerExportToEditor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.cardBorderColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text("Rescan"),
                  onPressed: _clearScan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSamplePresetsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 16),
            const SizedBox(width: 6),
            Text(
              "Or Test with Preset Academic Notes (1-Tap):",
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._samplePresets.entries.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _loadSamplePreset(entry.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: context.secondaryBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.value["name"]!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF6366F1)),
                  ],
                ),
              ),
            ),
          );
        }),
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

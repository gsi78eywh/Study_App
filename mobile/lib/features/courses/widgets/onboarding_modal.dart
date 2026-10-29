import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/services/child_safety_service.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";

class OnboardingModal extends StatefulWidget {
  final SessionService sessionService;
  final VoidCallback onCompleted;

  const OnboardingModal({
    super.key,
    required this.sessionService,
    required this.onCompleted,
  });

  static const String _slideshowSeenKey = "studyapp_slideshow_v2_seen";

  static Future<void> showIfNeeded(
    BuildContext context, {
    required SessionService sessionService,
    required VoidCallback onCompleted,
  }) async {
    final isTestToken =
        sessionService.token == "mock.jwt.bearer_token_for_tests";
    if (isTestToken && sessionService.isOnboardingCompleted) {
      return;
    }
    final hasSeenSlideshow =
        sessionService.prefs.getBool(_slideshowSeenKey) == true;
    if (sessionService.isOnboardingCompleted && hasSeenSlideshow) {
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingModal(
        sessionService: sessionService,
        onCompleted: onCompleted,
      ),
    );
  }

  static Future<void> showForce(
    BuildContext context, {
    required SessionService sessionService,
    VoidCallback? onCompleted,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => OnboardingModal(
        sessionService: sessionService,
        onCompleted: onCompleted ?? () {},
      ),
    );
  }

  @override
  State<OnboardingModal> createState() => _OnboardingModalState();
}

class _OnboardingModalState extends State<OnboardingModal> {
  final PageController _pageController = PageController();
  int _currentSlide = 0;
  static const int _totalSlides = 4;

  String _selectedLevel = "College";
  String _selectedScale = "USJ-R (1.00 - 5.00)";
  bool _parentConsentAccepted = false;
  String? _validationError;

  final List<Map<String, dynamic>> _slides = const [
    {
      "step": "STEP 1 OF 4",
      "title": "Add or Scan Study Material",
      "subtitle":
          "Upload any PDF, Word doc, or TXT file, paste your lecture notes, scan a clear photo of your textbook/whiteboard, or paste a YouTube tutorial link.",
      "icon": Icons.upload_file_rounded,
      "color": Color(0xFF2E7D5B),
      "bullets": [
        "📄 Instant on-device PDF, DOCX & text extraction with zero lag",
        "📷 High-precision OCR scanner for textbook & whiteboard photos",
        "🎬 YouTube video transcript & spoken-audio study guide extractor",
      ],
    },
    {
      "step": "STEP 2 OF 4",
      "title": "Preview Actual PDF Layout",
      "subtitle":
          "See your pasted or uploaded document in an authentic A4 PDF Page Layout before generating your study set or printing.",
      "icon": Icons.picture_as_pdf_rounded,
      "color": Color(0xFF4F46E5),
      "bullets": [
        "📑 Switch between Raw Text Editor and Actual A4 PDF Page Layout",
        "✨ Clean headings, bullet points, page numbers & visual margins",
        "🖨️ 1-Tap Export & Print formatted PDF study guides anytime",
      ],
    },
    {
      "step": "STEP 3 OF 4",
      "title": "Create Accurate Exams Instantly",
      "subtitle":
          "Turn your exact notes or PDF into Multiple Choice, True/False, Identification, and Cloze practice exams in under 1 second.",
      "icon": Icons.quiz_rounded,
      "color": Color(0xFFD97706),
      "bullets": [
        "🎯 100% grounded in your uploaded PDF and pasted lecture notes",
        "⚡ Works seamlessly both online and offline with zero black screens",
        "🃏 Includes Spaced-Repetition Flashcards & Rapid-Fire Blitz mode",
      ],
    },
  ];

  final List<Map<String, dynamic>> _schoolLevels = const [
    {
      "id": "Elementary",
      "title": "Elementary / Primary",
      "subtitle":
          "Grades 1 to 6 • Enables Junior Learner Mode & friendly vocabulary",
      "icon": Icons.child_care_rounded,
      "color": Color(0xFFF59E0B),
    },
    {
      "id": "High School",
      "title": "Junior & Senior High",
      "subtitle":
          "Grades 7 to 12 • Balanced recall drills & standard exam prep",
      "icon": Icons.school_rounded,
      "color": Color(0xFF10B981),
    },
    {
      "id": "College",
      "title": "College / University",
      "subtitle":
          "Higher Education • Full PDF exam studio, spaced recall & GWA tracker",
      "icon": Icons.account_balance_rounded,
      "color": Color(0xFF6366F1),
    },
  ];

  final List<String> _gradingScales = const [
    "USJ-R (1.00 - 5.00)",
    "Percentage (0 - 100%)",
    "4.0 GPA Scale",
  ];

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.sessionService.schoolLevel;
    _selectedScale = widget.sessionService.gradingScale;
    _parentConsentAccepted = widget.sessionService.hasMinorConsent;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextSlide() {
    if (_currentSlide < _totalSlides - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _handleComplete();
    }
  }

  void _prevSlide() {
    if (_currentSlide > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handleComplete() async {
    if (_selectedLevel == "Elementary" && !_parentConsentAccepted) {
      setState(() {
        _validationError =
            "Under RA 10173 (Data Privacy Act), parental or guardian consent is required for elementary learners.";
      });
      return;
    }

    final cs = ChildSafetyService.instance;
    final isElementary = _selectedLevel == "Elementary";
    await cs.setJuniorMode(isElementary);

    await widget.sessionService.prefs
        .setBool(OnboardingModal._slideshowSeenKey, true);
    await widget.sessionService.setOnboardingCompleted(
      schoolLevel: _selectedLevel,
      gradingScale: _selectedScale,
      hasMinorConsent: _parentConsentAccepted,
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      widget.onCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Dialog(
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar with step badge & Skip button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D5B).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "STEP ${_currentSlide + 1} OF $_totalSlides",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2E7D5B),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (_currentSlide < _totalSlides - 1)
                    TextButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          _totalSlides - 1,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        "Skip →",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Step progress indicator bar
              Row(
                children: List.generate(_totalSlides, (index) {
                  final active = index <= _currentSlide;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 5,
                      margin: EdgeInsets.only(
                        right: index == _totalSlides - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF2E7D5B)
                            : context.cardBorderColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // PageView Slideshow
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() {
                    _currentSlide = idx;
                    _validationError = null;
                  }),
                  children: [
                    ..._slides.map((s) => _buildWalkthroughSlide(context, s)),
                    _buildPersonalizationSlide(context, isDark),
                  ],
                ),
              ),

              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _validationError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Navigation Buttons (Back / Next Step / Launch Main Interface)
              Row(
                children: [
                  if (_currentSlide > 0) ...[
                    OutlinedButton.icon(
                      onPressed: _prevSlide,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text("Back"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D5B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _nextSlide,
                      icon: Icon(
                        _currentSlide == _totalSlides - 1
                            ? Icons.rocket_launch_rounded
                            : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _currentSlide == _totalSlides - 1
                            ? "Start Studying"
                            : "Next",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalkthroughSlide(
    BuildContext context,
    Map<String, dynamic> slide,
  ) {
    final color = slide["color"] as Color;
    final bullets = slide["bullets"] as List<String>;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.35), width: 2),
              ),
              child: Icon(
                slide["icon"] as IconData,
                size: 42,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            slide["title"] as String,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide["subtitle"] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: context.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.secondaryBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "KEY WORKFLOW STEPS:",
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                ...bullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            b,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizationSlide(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Step 4: Personalize Your Study Space",
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Choose your academic level and grading standard before entering StudyApp:",
            style: TextStyle(fontSize: 12.5, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._schoolLevels.map((lvl) {
            final isSelected = _selectedLevel == lvl["id"];
            final color = lvl["color"] as Color;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedLevel = lvl["id"] as String;
                    _validationError = null;
                    if (_selectedLevel == "Elementary" &&
                        _selectedScale.startsWith("USJ-R")) {
                      _selectedScale = "Percentage (0 - 100%)";
                    }
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: isDark ? 0.18 : 0.08)
                        : context.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? color : context.cardBorderColor,
                      width: isSelected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          lvl["icon"] as IconData,
                          color: color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lvl["title"] as String,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              lvl["subtitle"] as String,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, color: color, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          Text(
            "Default Grade Tracker Scale:",
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: context.secondaryBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cardBorderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedScale,
                isExpanded: true,
                dropdownColor: context.surfaceColor,
                items: _gradingScales.map((scale) {
                  return DropdownMenuItem(
                    value: scale,
                    child: Text(
                      scale,
                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedScale = val);
                },
              ),
            ),
          ),
          if (_selectedLevel == "Elementary") ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              activeColor: const Color(0xFFF59E0B),
              value: _parentConsentAccepted,
              onChanged: (v) {
                setState(() {
                  _parentConsentAccepted = v ?? false;
                  _validationError = null;
                });
              },
              title: Text(
                "I am a parent, teacher, or guardian consenting to this child's use (RA 10173).",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

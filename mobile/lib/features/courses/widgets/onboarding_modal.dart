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

  static Future<void> showIfNeeded(
    BuildContext context, {
    required SessionService sessionService,
    required VoidCallback onCompleted,
  }) async {
    if (sessionService.isOnboardingCompleted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingModal(
        sessionService: sessionService,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<OnboardingModal> createState() => _OnboardingModalState();
}

class _OnboardingModalState extends State<OnboardingModal> {
  String _selectedLevel = "College";
  String _selectedScale = "USJ-R (1.00 - 5.00)";
  bool _parentConsentAccepted = false;
  String? _validationError;

  final List<Map<String, dynamic>> _schoolLevels = [
    {
      "id": "Elementary",
      "title": "Elementary / Primary",
      "subtitle": "Grades 1 to 6 • Enables Junior Learner Mode, friendly vocabulary, and pediatric eye rest",
      "icon": Icons.child_care_rounded,
      "color": Color(0xFFF59E0B),
    },
    {
      "id": "High School",
      "title": "Junior & Senior High",
      "subtitle": "Grades 7 to 12 • Balanced recall drills, standard eye-care intervals, and exam prep",
      "icon": Icons.school_rounded,
      "color": Color(0xFF10B981),
    },
    {
      "id": "College",
      "title": "College / University",
      "subtitle": "Higher Education • Full curriculum extractor, spaced recall, and comprehensive grade tracking",
      "icon": Icons.account_balance_rounded,
      "color": Color(0xFF6366F1),
    },
  ];

  final List<String> _gradingScales = [
    "USJ-R (1.00 - 5.00)",
    "Percentage (0 - 100%)",
    "4.0 GPA Scale",
  ];

  Future<void> _handleComplete() async {
    if (_selectedLevel == "Elementary" && !_parentConsentAccepted) {
      setState(() {
        _validationError = "Under RA 10173 (Data Privacy Act), parental or guardian consent is required for elementary learners.";
      });
      return;
    }

    final cs = ChildSafetyService.instance;
    final isElementary = _selectedLevel == "Elementary";
    await cs.setJuniorMode(isElementary);

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome to StudyApp",
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "Personalize your learning space & study standards",
                          style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: School Level
                      Text(
                        "1. What is your current school level?",
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                if (_selectedLevel == "Elementary" && _selectedScale.startsWith("USJ-R")) {
                                  _selectedScale = "Percentage (0 - 100%)";
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(12),
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
                                    child: Icon(lvl["icon"] as IconData, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
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
                                        const SizedBox(height: 2),
                                        Text(
                                          lvl["subtitle"] as String,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: context.textSecondary,
                                            height: 1.3,
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
                      const SizedBox(height: 14),

                      // Section 2: Grading Scale
                      Text(
                        "2. Select your default Grade Tracker scale:",
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                      const SizedBox(height: 14),

                      // Section 3: Minor Consent Flow (If Elementary)
                      if (_selectedLevel == "Elementary") ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.shield_rounded, color: Color(0xFFF59E0B), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Learner Privacy Notice (RA 10173)",
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                        color: const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "In accordance with Republic Act No. 10173 (Data Privacy Act of 2012), student data is kept strictly private, never harvested or sold, and processed with kid-safe educational guardrails.",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: _parentConsentAccepted,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                activeColor: const Color(0xFFF59E0B),
                                title: Text(
                                  "I confirm I have parental/guardian consent to use StudyApp.",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.textPrimary,
                                  ),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _parentConsentAccepted = val ?? false;
                                    _validationError = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Validation error
                      if (_validationError != null) ...[
                        Text(
                          _validationError!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _handleComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Save & Get Started", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

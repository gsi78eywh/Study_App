import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class UserManualSheet extends StatefulWidget {
  final VoidCallback? onOpenIngest;
  final VoidCallback? onOpenGradeTracker;
  final VoidCallback? onOpenFlashcards;
  final VoidCallback? onOpenAiTutor;

  const UserManualSheet({
    super.key,
    this.onOpenIngest,
    this.onOpenGradeTracker,
    this.onOpenFlashcards,
    this.onOpenAiTutor,
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onOpenIngest,
    VoidCallback? onOpenGradeTracker,
    VoidCallback? onOpenFlashcards,
    VoidCallback? onOpenAiTutor,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserManualSheet(
        onOpenIngest: onOpenIngest,
        onOpenGradeTracker: onOpenGradeTracker,
        onOpenFlashcards: onOpenFlashcards,
        onOpenAiTutor: onOpenAiTutor,
      ),
    );
  }

  @override
  State<UserManualSheet> createState() => _UserManualSheetState();
}

class _UserManualSheetState extends State<UserManualSheet> {
  int _selectedCategoryIndex = 0;

  final List<_ManualSection> _sections = [
    const _ManualSection(
      title: "Core Workflow Loop",
      icon: Icons.loop_rounded,
      badgeColor: Color(0xFF6366F1),
      description: "How StudyApp guides your daily academic journey from capture to exam mastery.",
      items: [
        _ManualItem(
          heading: "1. Capture Effortlessly",
          summary: "Students often don't have time to take detailed notes during rapid lectures. Passive Capture converts textbook photos, blackboard snapshots, or YouTube lectures into clean, structured notes and flashcards with one tap.",
          steps: [
            "Open Ingest / Studio tab",
            "Upload image/document or paste YouTube lecture URL",
            "Tap '1-Tap Auto-Flashcards' or 'Save to Notebook'",
          ],
        ),
        _ManualItem(
          heading: "2. Track Academic Standing",
          summary: "No more surprise failing grades at the end of the term. The Grade Tracker runs real-time collegiate GWA calculations using the USJ-R scale and computes required exam scores.",
          steps: [
            "Tap 'Grade Tracker' on any course row",
            "Input Prelim, Midterm, and Semi-Final scores",
            "Run 'What Grade Do I Need' simulations for your Final exam",
          ],
        ),
        _ManualItem(
          heading: "3. Follow the Priority Engine",
          summary: "Overcoming cognitive overload: You never have to ask 'what should I study today?' The Priority Engine computes a 100-point composite urgency score and presents 1 daily hero study session.",
          steps: [
            "Open Dashboard each morning",
            "Review the Priority Study Recommendation & Risk Badge",
            "Tap 'Start Priority Session' to practice high-yield topics",
          ],
        ),
      ],
    ),
    const _ManualSection(
      title: "Passive Capture (OCR & Video)",
      icon: Icons.document_scanner_rounded,
      badgeColor: Color(0xFF10B981),
      description: "Zero-friction note taking from blackboards, PDFs, and YouTube transcripts.",
      items: [
        _ManualItem(
          heading: "Blackboard & Textbook OCR Scanner",
          summary: "Uses native offline OCR or Gemini Vision to extract clear text from photos of slides, printed handouts, or handwritten notes. Strips UI noise and formats paragraphs cleanly.",
          steps: [
            "Tap '📷 Camera Scanner' or 'Extract Clean Text'",
            "Take a well-lit photo or choose a document (PDF/DOCX)",
            "Review extracted text in the editor and save directly to your Course Notebook",
          ],
        ),
        _ManualItem(
          heading: "YouTube & Lecture Transcript Synthesis",
          summary: "Paste any educational YouTube lecture URL or audio transcript. The engine strips timestamp clutter, structures the lecture into Cornell Notes (Summary, Cues, Notes), and automatically creates active recall flashcards.",
          steps: [
            "Go to Ingest / Studio ➔ Tab 3 'YouTube & Transcripts'",
            "Paste the video URL or lecture transcript",
            "Tap 'Synthesize Structured Notes & Auto-Flashcards'",
          ],
        ),
      ],
    ),
    const _ManualSection(
      title: "Grade Tracker & GWA (USJ-R)",
      icon: Icons.assessment_rounded,
      badgeColor: Color(0xFFF59E0B),
      description: "University of San Jose-Recoletos grading scale & exam target calculations.",
      items: [
        _ManualItem(
          heading: "Collegiate Grading Scale & Honors",
          summary: "Based on USJ-R standards: 1.0 (97-100%), 1.1-1.5 (Dean's List / Superior), 1.6-2.5 (Good/Very Good), 2.6-3.0 (Passing Cutoff 75.0%), and 5.0 (Failure / < 75%). Tracks Latin Honors (Summa, Magna, Cum Laude).",
          steps: [
            "Passing threshold is strictly 75.0% (3.0 GWA)",
            "Scores below 75% trigger an immediate Academic Risk probation warning",
            "Term weights default to: Prelim 20%, Midterm 20%, Semi-Final 20%, Final 40%",
          ],
        ),
        _ManualItem(
          heading: "'What Grade Do I Need' Calculator",
          summary: "Enter your target grade (e.g. 1.5 for Dean's List, or 3.0 to pass). The calculator calculates the exact percentage you must achieve on your remaining Final Exam to hit your goal.",
          steps: [
            "Open Grade Tracker on your course",
            "Switch to the 'What Grade Do I Need' tab",
            "Set your desired target grade and tap 'Calculate Target Final'",
          ],
        ),
      ],
    ),
    const _ManualSection(
      title: "Study Priority Engine",
      icon: Icons.track_changes_rounded,
      badgeColor: Color(0xFFEF4444),
      description: "The 100-point algorithm that tells you what to study today.",
      items: [
        _ManualItem(
          heading: "How Priority Scoring Works",
          summary: "Priority Score (100 pts max) = Grade Risk (0-40 pts) + Exam Deadline Proximity (0-35 pts) + Question Retention Gaps (0-25 pts). The course with the highest urgency becomes today's hero session.",
          steps: [
            "🚨 CRITICAL RISK (+40 pts): Running grade < 75.0% (USJ-R failing zone)",
            "⚠️ BORDERLINE DANGER (+32 pts): Running grade between 75.0% and 78.0%",
            "🎯 TARGET BEHIND (+18 pts): Running grade is below your personal target",
            "📅 EXAM PROXIMITY: Exam in <= 2 days (+35 pts), <= 7 days (+25 pts)",
          ],
        ),
        _ManualItem(
          heading: "Focused Daily Action",
          summary: "Instead of wondering which subject to study across multiple classes, the widget gives you 1 targeted session duration (e.g., 25 min) and highlights high-yield misconception flashcards.",
          steps: [
            "Look for the glowing 'Today's Priority Study Recommendation' card on your Dashboard",
            "Check the dynamic risk explanation badge",
            "Tap 'Start Priority Session' to begin immediate practice",
          ],
        ),
      ],
    ),
    const _ManualSection(
      title: "Resilience & Security",
      icon: Icons.shield_rounded,
      badgeColor: Color(0xFF8B5CF6),
      description: "Network delays, load balancing, offline queues, and child safety.",
      items: [
        _ManualItem(
          heading: "Network Delay & Load Balancing Protection",
          summary: "StudyApp is engineered for intermittent campus Wi-Fi and congested networks. Requests auto-retry with exponential backoff, rate limits protect server health, and memory caching prevents lag.",
          steps: [
            "Transient network dropouts automatically retry without losing your quiz progress",
            "Cached grade summaries and study plans display instantly even with high latency",
            "Toggle 'Low Data Mode' in Settings to compress transfers on cellular data",
          ],
        ),
        _ManualItem(
          heading: "Device Availability & Security",
          summary: "Responsive on phones, foldables, tablets, and desktop browsers without layout overflows. Student tokens are stored in secure storage, and child safety standards (DSWD Makabata 1383) are strictly adhered to.",
          steps: [
            "No backend architecture or API keys are exposed to public screens",
            "Access DSWD Makabata 1383 child safeguard from the top menu anytime",
            "Data syncs safely with token-authenticated endpoints only",
          ],
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final currentSection = _sections[_selectedCategoryIndex];

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "StudyApp User Manual & Guide",
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            "Key features, purposes, and how to maximize your GWA",
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: "Close Guide",
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Category Selector Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: List.generate(_sections.length, (i) {
                    final sec = _sections[i];
                    final isSelected = _selectedCategoryIndex == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => setState(() => _selectedCategoryIndex = i),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? sec.badgeColor.withValues(alpha: isDark ? 0.25 : 0.15)
                                : cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? sec.badgeColor : borderColor,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                sec.icon,
                                size: 16,
                                color: isSelected ? sec.badgeColor : textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                sec.title,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? (isDark ? Colors.white : sec.badgeColor) : textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const Divider(height: 1),

              // Main Section Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    // Section Header Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: currentSection.badgeColor.withValues(alpha: isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: currentSection.badgeColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: currentSection.badgeColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(currentSection.icon, color: currentSection.badgeColor, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSection.title,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentSection.description,
                                  style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Items inside section
                    ...currentSection.items.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF10B981)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.heading,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.summary,
                              style: TextStyle(fontSize: 13, color: textSecondary, height: 1.45),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor.withValues(alpha: 0.6)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "HOW TO USE / BEST PRACTICE:",
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: currentSection.badgeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ...item.steps.map((st) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("• ", style: TextStyle(color: currentSection.badgeColor, fontWeight: FontWeight.bold)),
                                          Expanded(
                                            child: Text(
                                              st,
                                              style: TextStyle(fontSize: 12.5, color: textPrimary, height: 1.35),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 8),

                    // Quick Jump Action Shortcuts
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (widget.onOpenIngest != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.document_scanner_rounded, size: 16),
                            label: const Text("Open Ingest & OCR"),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenIngest?.call();
                            },
                          ),
                        if (widget.onOpenGradeTracker != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF59E0B),
                              side: const BorderSide(color: Color(0xFFF59E0B)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.assessment_rounded, size: 16),
                            label: const Text("Launch Grade Tracker"),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenGradeTracker?.call();
                            },
                          ),
                        if (widget.onOpenFlashcards != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6366F1),
                              side: const BorderSide(color: Color(0xFF6366F1)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.style_outlined, size: 16),
                            label: const Text("Open Flashcards"),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenFlashcards?.call();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ManualSection {
  final String title;
  final IconData icon;
  final Color badgeColor;
  final String description;
  final List<_ManualItem> items;

  const _ManualSection({
    required this.title,
    required this.icon,
    required this.badgeColor,
    required this.description,
    required this.items,
  });
}

class _ManualItem {
  final String heading;
  final String summary;
  final List<String> steps;

  const _ManualItem({
    required this.heading,
    required this.summary,
    required this.steps,
  });
}

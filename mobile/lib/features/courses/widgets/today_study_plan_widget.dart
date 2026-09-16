import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/theme/app_theme.dart";
import "../../practice/models/adaptive_models.dart";

class TodayStudyPlanWidget extends StatelessWidget {
  final TodayStudyPlanModel? plan;
  final bool isLoading;
  final VoidCallback onStartSmartSession;
  final VoidCallback onOpenMistakeBank;
  final VoidCallback? onOpenStudentBrain;
  final VoidCallback? onOpenAcademicPlanner;
  final ValueChanged<String>? onShowReadinessBreakdown;
  final ValueChanged<StudyPlanStepModel>? onStepTapped;

  const TodayStudyPlanWidget({
    super.key,
    this.plan,
    this.isLoading = false,
    required this.onStartSmartSession,
    required this.onOpenMistakeBank,
    this.onOpenStudentBrain,
    this.onOpenAcademicPlanner,
    this.onShowReadinessBreakdown,
    this.onStepTapped,
  });

  String _formatDate() {
    final now = DateTime.now();
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return "${months[now.month - 1]} ${now.day}";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    if (isLoading && plan == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.cardBorderColor),
        ),
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
            SizedBox(height: 14),
            Text("Synthesizing your adaptive study plan...", style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    if (plan == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E1B4B).withValues(alpha: 0.85), context.surfaceColor]
                : [const Color(0xFFEEF2FF), context.surfaceColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35), width: 1.5),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("🎯 Your Daily Study Plan", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
            const SizedBox(height: 6),
            Text("Organize course materials or launch a Smart Session to get targeted daily recommendations.", style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onStartSmartSession,
              icon: const Icon(Icons.bolt_rounded, color: Colors.yellow),
              label: const Text("Start 25-Minute Smart Session"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    final p = plan!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF1E1B4B).withValues(alpha: 0.85),
                  context.surfaceColor,
                ]
              : [
                  const Color(0xFFEEF2FF),
                  context.surfaceColor,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Badge, Date, and Exam Countdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.psychology_rounded, color: Colors.white, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          "ADAPTIVE STUDY PLAN",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Today — ${_formatDate()}",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
              if (p.daysUntilExam != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFFEF4444), size: 13),
                      const SizedBox(width: 4),
                      Text(
                        p.daysUntilExam == 0
                            ? "EXAM TODAY"
                            : "${p.daysUntilExam}d until Exam",
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Course Title & Readiness Chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.courseCode,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                      ),
                    ),
                    Text(
                      p.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: context.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  if (onShowReadinessBreakdown != null) {
                    onShowReadinessBreakdown!(p.courseId ?? "");
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${p.readiness.overallReadinessPercent.round()}% Ready",
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          Text(
                            "Explainable",
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: const Color(0xFF10B981).withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFF10B981)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Topic Mastery Priorities (Visual Meter)
          if (p.priorities.isNotEmpty) ...[
            Text(
              "TOPIC MASTERY PRIORITIES",
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: p.priorities.take(3).map((item) {
                final isHigh = item.status == "High Priority";
                final isReview = item.status == "Needs Review";
                final color = isHigh
                    ? const Color(0xFFEF4444)
                    : isReview
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981);
                final icon = isHigh
                    ? Icons.error_outline_rounded
                    : isReview
                        ? Icons.replay_rounded
                        : Icons.check_circle_outline_rounded;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 6),
                      Text(
                        item.topicName,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "${item.masteryPercent.round()}%",
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Structured 4-Step Learning Sequence
          Text(
            "YOUR ${p.totalEstimatedMinutes}-MINUTE LEARNING SEQUENCE",
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...p.steps.map((step) => _buildStepTile(context, step)),

          const SizedBox(height: 16),

          // Primary CTA Button: Start Smart Session (25 min)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onStartSmartSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 22, color: Color(0xFFFDE047)),
                      const SizedBox(width: 8),
                      Text(
                        "Start Smart Session (${p.totalEstimatedMinutes} min)",
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Row of Human-Centered Actions: Mistake Bank + "I'm Overwhelmed" + Wellbeing Check-in
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenMistakeBank,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.cardBorderColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology_alt_rounded, size: 16, color: Color(0xFFEC4899)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Mistakes (${p.readiness.unresolvedMistakesCount})",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _showOverwhelmedSheet(context, p),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("😵", style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        "I'm Overwhelmed",
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _showWellbeingSheet(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: const Text("🧘", style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Secondary Row: Student Brain OS + Academic Tasks
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenStudentBrain,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.psychology_rounded, size: 15, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        Text(
                          "My Student Brain",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onOpenAcademicPlanner,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.cardBorderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 15, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 6),
                        Text(
                          "Academic Tasks",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOverwhelmedSheet(BuildContext context, TodayStudyPlanModel p) {
    final topTopic = p.topPriorityCourse?.topicName ?? "Core Concepts";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: ctx.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.cardBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text("😵", style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Text(
                    "Let's Simplify",
                    style: GoogleFonts.outfit(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Cognitive overload is completely normal. We won't solve all your assignments or exams right now.",
                style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "YOUR SINGLE MICRO-STEP RIGHT NOW:",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6366F1),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Review just $topTopic for 15 minutes.",
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: ctx.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "No long exams, no complex planning. Just 3 gentle flashcards and 2 practice questions.",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: ctx.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onStartSmartSession();
                  },
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: const Text("Start With This (15 min)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  "🌿 Take a deep breath. Learning happens in small, durable steps.",
                  style: GoogleFonts.inter(fontSize: 11, color: ctx.textSecondary, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showWellbeingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: ctx.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.cardBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text("🧘", style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(
                    "Student Wellbeing Check-In",
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "How are you feeling as a learner today?",
                style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMoodItem(ctx, "😊", "Good", "Full session", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Energized! Today's full 25-minute smart session is ready.")),
                    );
                  }),
                  _buildMoodItem(ctx, "😐", "Okay", "Standard", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Steady pace. Stick to your 4-step daily plan.")),
                    );
                  }),
                  _buildMoodItem(ctx, "😓", "Overloaded", "10 min plan", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Plan scaled down! Focus on just 1 weak topic today.")),
                    );
                  }),
                  _buildMoodItem(ctx, "😴", "Tired", "5 min cards", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Rest is essential for memory consolidation. Do 5 cards and rest.")),
                    );
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoodItem(BuildContext ctx, String emoji, String label, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ctx.cardBorderColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
            Text(sub, style: GoogleFonts.inter(fontSize: 9, color: ctx.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTile(BuildContext context, StudyPlanStepModel step) {
    IconData icon;
    Color color;

    switch (step.stepType) {
      case "spaced_flashcards":
        icon = Icons.style_rounded;
        color = const Color(0xFF10B981);
        break;
      case "retrieval_practice":
        icon = Icons.quiz_rounded;
        color = const Color(0xFF6366F1);
        break;
      case "mistake_drill":
        icon = Icons.replay_rounded;
        color = const Color(0xFFEF4444);
        break;
      case "socratic_tutor":
      default:
        icon = Icons.auto_awesome_rounded;
        color = const Color(0xFF8B5CF6);
        break;
    }

    return InkWell(
      onTap: () => onStepTapped?.call(step),
      borderRadius: BorderRadius.circular(14),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${step.stepNumber}. ${step.title}",
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "${step.durationMinutes} min",
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  "Why: ${step.reason}",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}

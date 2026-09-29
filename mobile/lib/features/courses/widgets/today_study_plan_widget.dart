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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (p.gradeRiskLevel != null && p.gradeRiskLevel != "Normal" && p.gradeRiskLevel != "Good Standing")
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (p.gradeRiskLevel == "Critical Risk" ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                        border: Border.all(color: (p.gradeRiskLevel == "Critical Risk" ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)).withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: p.gradeRiskLevel == "Critical Risk" ? const Color(0xFFEF4444) : const Color(0xFFF59E0B), size: 12),
                          const SizedBox(width: 3),
                          Text(
                            p.gradeRiskLevel!.toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: p.gradeRiskLevel == "Critical Risk" ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
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
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width - 64,
                  ),
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
                      Flexible(
                        child: Text(
                          item.topicName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
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

          const SizedBox(height: 14),

          // Mistake Bank Active Recall Feedback Banner
          if (p.readiness.unresolvedMistakesCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFEC4899).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFFEC4899)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${p.readiness.unresolvedMistakesCount} error concepts flagged in Mistake Bank → auto-added to your retrieval drills.",
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onOpenMistakeBank,
                    child: Text(
                      "Review",
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEC4899),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Primary CTA Hero Button: Start Smart Session (25 min)
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
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 22, color: Color(0xFFFDE047)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Start Priority Session: ${p.courseCode} (${p.totalEstimatedMinutes} min)",
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Unified Secondary Utility Bar (Visually receded to highlight Start Smart Session)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cardBorderColor.withValues(alpha: 0.6)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSubtleAction(
                    icon: Icons.psychology_alt_rounded,
                    color: const Color(0xFFEC4899),
                    label: "Mistakes (${p.readiness.unresolvedMistakesCount})",
                    onTap: onOpenMistakeBank,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtleAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
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

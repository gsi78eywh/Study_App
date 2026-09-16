import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../practice/models/adaptive_models.dart";

class StudentBrainModal extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onStartSmartSession;
  final VoidCallback onOpenMistakeBank;
  final VoidCallback onOpenAcademicPlanner;

  const StudentBrainModal({
    super.key,
    required this.apiClient,
    required this.onStartSmartSession,
    required this.onOpenMistakeBank,
    required this.onOpenAcademicPlanner,
  });

  static Future<void> show(
    BuildContext context, {
    required ApiClient apiClient,
    required VoidCallback onStartSmartSession,
    required VoidCallback onOpenMistakeBank,
    required VoidCallback onOpenAcademicPlanner,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StudentBrainModal(
        apiClient: apiClient,
        onStartSmartSession: onStartSmartSession,
        onOpenMistakeBank: onOpenMistakeBank,
        onOpenAcademicPlanner: onOpenAcademicPlanner,
      ),
    );
  }

  @override
  State<StudentBrainModal> createState() => _StudentBrainModalState();
}

class _StudentBrainModalState extends State<StudentBrainModal> {
  bool _isLoading = true;
  StudentBrainProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final data = await widget.apiClient.getStudentBrainProfile();
    if (mounted) {
      setState(() {
        _profile = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.cardBorderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "MY STUDENT BRAIN",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "Personal Academic Operating System",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: context.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: context.textSecondary,
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _profile == null
                    ? Center(
                        child: Text(
                          "Unable to load student profile.",
                          style: TextStyle(color: context.textSecondary),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Philosophy Banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Text("💡", style: TextStyle(fontSize: 20)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "\"A second brain for learning—not to think for you, but to help you know what to study, why, and what to do next.\"",
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: context.textPrimary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // 2. Academic OS Metrics Grid
                            Text(
                              "ACADEMIC PROFILE SNAPSHOT",
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildMetricsGrid(context, _profile!),
                            const SizedBox(height: 20),

                            // 3. Priority Recommendation with Explicit WHY
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "TODAY'S PRIORITY",
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${_profile!.priorityCourseCode}: ${_profile!.priorityCourse}",
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: context.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        "${_profile!.priorityMasteryPercent.round()}% Mastery",
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF6366F1),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Why is the Student Brain recommending this?",
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _profile!.priorityWhy,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.textPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),

                            // 4. The 5 Daily Answers
                            Text(
                              "5 DAILY STUDENT BRAIN ANSWERS",
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDailyAnswerCard(
                              context,
                              number: "1",
                              icon: Icons.checklist_rounded,
                              iconColor: const Color(0xFF3B82F6),
                              question: "What do I need to do?",
                              answer: _profile!.dailyAnswers.whatDoINeedToDo,
                            ),
                            _buildDailyAnswerCard(
                              context,
                              number: "2",
                              icon: Icons.menu_book_rounded,
                              iconColor: const Color(0xFF10B981),
                              question: "What should I study?",
                              answer: _profile!.dailyAnswers.whatShouldIStudy,
                            ),
                            _buildDailyAnswerCard(
                              context,
                              number: "3",
                              icon: Icons.warning_amber_rounded,
                              iconColor: const Color(0xFFF59E0B),
                              question: "What am I struggling with?",
                              answer: _profile!.dailyAnswers.whatAmIStrugglingWith,
                            ),
                            _buildDailyAnswerCard(
                              context,
                              number: "4",
                              icon: Icons.lightbulb_outline_rounded,
                              iconColor: const Color(0xFF8B5CF6),
                              question: "How can I learn it?",
                              answer: _profile!.dailyAnswers.howCanILearnIt,
                            ),
                            _buildDailyAnswerCard(
                              context,
                              number: "5",
                              icon: Icons.bolt_rounded,
                              iconColor: const Color(0xFFEC4899),
                              question: "What should I do next?",
                              answer: _profile!.dailyAnswers.whatShouldIDoNext,
                            ),
                            const SizedBox(height: 20),

                            // 5. Action Hub Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onStartSmartSession();
                                    },
                                    icon: const Icon(Icons.bolt_rounded, color: Colors.yellow),
                                    label: const Text("Launch Smart Session"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onOpenAcademicPlanner();
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                                    label: const Text("Academic Calendar"),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onOpenMistakeBank();
                                    },
                                    icon: const Icon(Icons.psychology_alt_rounded, size: 16, color: Color(0xFFEC4899)),
                                    label: const Text("Mistake Bank"),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
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
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context, StudentBrainProfileModel p) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard(context, "${p.coursesCount}", "Courses", Icons.school_outlined, const Color(0xFF6366F1)),
        _buildStatCard(context, "${p.upcomingDeadlinesCount}", "Deadlines", Icons.event_note_outlined, const Color(0xFFF59E0B)),
        _buildStatCard(context, "${p.upcomingExamsCount}", "Upcoming Exams", Icons.timer_outlined, const Color(0xFFEF4444)),
        _buildStatCard(context, "${p.weakConceptsCount}", "Weak Concepts", Icons.error_outline_rounded, const Color(0xFFEC4899)),
        _buildStatCard(context, "${p.masteredConceptsCount}", "Mastered", Icons.verified_outlined, const Color(0xFF10B981)),
        _buildStatCard(context, "${p.pendingReviewsCount}", "Pending Cards", Icons.style_outlined, const Color(0xFF8B5CF6)),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAnswerCard(
    BuildContext context, {
    required String number,
    required IconData icon,
    required Color iconColor,
    required String question,
    required String answer,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$number. $question",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  answer,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

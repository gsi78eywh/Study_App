import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../models/grade_models.dart';

class GradeTrackerSheet extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback? onGradesUpdated;

  const GradeTrackerSheet({
    super.key,
    required this.apiClient,
    this.onGradesUpdated,
  });

  static Future<void> show(BuildContext context, ApiClient apiClient, {VoidCallback? onGradesUpdated}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GradeTrackerSheet(
        apiClient: apiClient,
        onGradesUpdated: onGradesUpdated,
      ),
    );
  }

  @override
  State<GradeTrackerSheet> createState() => _GradeTrackerSheetState();
}

class _GradeTrackerSheetState extends State<GradeTrackerSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  GradeSummaryModel? _summary;
  bool _isLoading = true;
  String? _errorMessage;

  // What-If Calculator State
  CourseGradeModel? _selectedWhatIfCourse;
  double _targetGwa = 1.75;
  WhatIfResultModel? _whatIfResult;
  bool _isCalculatingWhatIf = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGrades();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGrades() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final summary = await widget.apiClient.getGradesSummary();
    if (!mounted) return;

    if (summary == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Could not load grade telemetry from server.";
      });
      return;
    }

    setState(() {
      _summary = summary;
      _isLoading = false;
      if (summary.courses.isNotEmpty && _selectedWhatIfCourse == null) {
        _selectedWhatIfCourse = summary.courses.first;
        _runWhatIfCalculation();
      }
    });
  }

  Future<void> _runWhatIfCalculation() async {
    if (_selectedWhatIfCourse == null) return;
    setState(() => _isCalculatingWhatIf = true);

    final res = await widget.apiClient.calculateWhatIf(
      courseId: _selectedWhatIfCourse!.courseId,
      targetGwa: _targetGwa,
      prelimGrade: _selectedWhatIfCourse!.prelimGrade,
      midtermGrade: _selectedWhatIfCourse!.midtermGrade,
      semiFinalGrade: _selectedWhatIfCourse!.semiFinalGrade,
      prelimWeight: _selectedWhatIfCourse!.prelimWeight,
      midtermWeight: _selectedWhatIfCourse!.midtermWeight,
      semiFinalWeight: _selectedWhatIfCourse!.semiFinalWeight,
      finalWeight: _selectedWhatIfCourse!.finalWeight,
    );

    if (!mounted) return;
    setState(() {
      _whatIfResult = res;
      _isCalculatingWhatIf = false;
    });
  }

  void _showEditCourseGradesDialog(CourseGradeModel course) {
    final prelimController = TextEditingController(text: course.prelimGrade?.toStringAsFixed(1) ?? "");
    final midtermController = TextEditingController(text: course.midtermGrade?.toStringAsFixed(1) ?? "");
    final semiFinalController = TextEditingController(text: course.semiFinalGrade?.toStringAsFixed(1) ?? "");
    final finalController = TextEditingController(text: course.finalGrade?.toStringAsFixed(1) ?? "");
    final unitsController = TextEditingController(text: course.units.toStringAsFixed(1));
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Color(0xFF6366F1), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.courseCode, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(course.courseName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ctx.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("USJ-R Term Grade Inputs (0 - 100%)", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: ctx.textPrimary)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildGradeInputField("Prelim (20%)", prelimController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGradeInputField("Midterm (20%)", midtermController)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildGradeInputField("Semi-Final (20%)", semiFinalController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGradeInputField("Final (40%)", finalController)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildGradeInputField("Academic Units", unitsController),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text("Cancel", style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final pGrade = double.tryParse(prelimController.text.trim());
                      final mGrade = double.tryParse(midtermController.text.trim());
                      final sfGrade = double.tryParse(semiFinalController.text.trim());
                      final fGrade = double.tryParse(finalController.text.trim());
                      final units = double.tryParse(unitsController.text.trim()) ?? 3.0;

                      final success = await widget.apiClient.updateCourseGrades(
                        course.courseId,
                        {
                          "units": units,
                          "prelimGrade": pGrade,
                          "midtermGrade": mGrade,
                          "semiFinalGrade": sfGrade,
                          "finalGrade": fGrade,
                          "prelimWeight": 0.20,
                          "midtermWeight": 0.20,
                          "semiFinalWeight": 0.20,
                          "finalWeight": 0.40,
                        },
                      );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }

                      if (success) {
                        _loadGrades();
                        widget.onGradesUpdated?.call();
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Save Grades"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradeInputField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            hintText: "e.g. 85.5",
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel) {
      case "Critical Risk":
        return const Color(0xFFEF4444);
      case "Danger":
        return const Color(0xFFF97316);
      case "Warning":
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.cardBorderColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Grade Tracker & GWA",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "USJ-R Recoletos Scale (1.0 - 5.0)",
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: context.textSecondary),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: context.textSecondary,
            indicatorColor: const Color(0xFF6366F1),
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: "Course Grades & GWA"),
              Tab(icon: Icon(Icons.calculate_rounded, size: 18), text: "What Grade Do I Need?"),
            ],
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage!, style: const TextStyle(color: Color(0xFFEF4444))),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _loadGrades, child: const Text("Retry")),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildGradesOverviewTab(context, isDark),
                          _buildWhatIfCalculatorTab(context, isDark),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradesOverviewTab(BuildContext context, bool isDark) {
    final s = _summary!;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // GWA Hero Gauge Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E1B4B), context.surfaceColor]
                  : [const Color(0xFFEEF2FF), context.surfaceColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              // Circle GWA Badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF6366F1), width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.cumulativeGwa > 0 ? s.cumulativeGwa.toStringAsFixed(2) : "N/A",
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Cumulative GWA",
                      style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.honorsStatus,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: s.cumulativeGwa <= 1.5 && s.cumulativeGwa > 0
                            ? const Color(0xFF10B981)
                            : s.cumulativeGwa > 3.0
                                ? const Color(0xFFEF4444)
                                : context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${s.totalUnits.toStringAsFixed(1)} Total Units • Passing Cutoff: 3.0 (75.0%)",
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Subject Breakdown (${s.courses.length})",
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            Text(
              "Tap to Edit Grades",
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (s.courses.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(Icons.school_outlined, size: 40, color: Colors.grey),
                const SizedBox(height: 10),
                Text("No courses registered yet.", style: TextStyle(color: context.textSecondary)),
              ],
            ),
          )
        else
          ...s.courses.map((course) {
            final riskColor = _getRiskColor(course.riskLevel);

            return InkWell(
              onTap: () => _showEditCourseGradesDialog(course),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                course.courseCode,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF6366F1)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${course.units.toStringAsFixed(0)} Units",
                              style: TextStyle(color: context.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                        // Risk Chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: riskColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            course.riskLevel,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 10.5, color: riskColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      course.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: context.textPrimary),
                    ),
                    const SizedBox(height: 10),
                    // Running Grade and GWA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              course.runningPercentage != null
                                  ? "${course.runningPercentage!.toStringAsFixed(1)}%"
                                  : "No grades yet",
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: course.runningPercentage != null && course.runningPercentage! < 75.0
                                    ? const Color(0xFFEF4444)
                                    : context.textPrimary,
                              ),
                            ),
                            if (course.runningGwa != null) ...[
                              const SizedBox(width: 6),
                              Text("→ GWA ${course.runningGwa!.toStringAsFixed(2)}", style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            Text("P: ${course.prelimGrade?.toStringAsFixed(0) ?? '-'}", style: TextStyle(fontSize: 10.5, color: context.textSecondary)),
                            const SizedBox(width: 6),
                            Text("M: ${course.midtermGrade?.toStringAsFixed(0) ?? '-'}", style: TextStyle(fontSize: 10.5, color: context.textSecondary)),
                            const SizedBox(width: 6),
                            Text("SF: ${course.semiFinalGrade?.toStringAsFixed(0) ?? '-'}", style: TextStyle(fontSize: 10.5, color: context.textSecondary)),
                            const SizedBox(width: 6),
                            Text("F: ${course.finalGrade?.toStringAsFixed(0) ?? '-'}", style: TextStyle(fontSize: 10.5, color: context.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildWhatIfCalculatorTab(BuildContext context, bool isDark) {
    final s = _summary!;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.psychology_rounded, color: Color(0xFF6366F1), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Calculate the exact Final Exam grade you need to reach your target USJ-R GWA or passing threshold.",
                  style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: context.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Select Course
        Text("Target Course", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.cardBorderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CourseGradeModel>(
              isExpanded: true,
              value: _selectedWhatIfCourse,
              items: s.courses.map((c) {
                return DropdownMenuItem(
                  value: c,
                  child: Text("${c.courseCode} — ${c.courseName}", maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (c) {
                setState(() => _selectedWhatIfCourse = c);
                _runWhatIfCalculation();
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Select Target USJ-R GWA
        Text("Desired Subject GWA", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTargetGwaChip(1.0, "1.0 (99% - Highest)"),
            _buildTargetGwaChip(1.5, "1.5 (93% - Dean's List)"),
            _buildTargetGwaChip(2.0, "2.0 (87% - Very Good)"),
            _buildTargetGwaChip(2.5, "2.5 (81% - Good)"),
            _buildTargetGwaChip(3.0, "3.0 (75% - Passing Cutoff)"),
          ],
        ),
        const SizedBox(height: 20),

        // What-If Result Card
        if (_isCalculatingWhatIf)
          const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
        else if (_whatIfResult != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _whatIfResult!.isAchievable
                    ? [const Color(0xFF064E3B).withValues(alpha: isDark ? 0.8 : 0.15), context.surfaceColor]
                    : [const Color(0xFF7F1D1D).withValues(alpha: isDark ? 0.8 : 0.15), context.surfaceColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _whatIfResult!.isAchievable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Target Final Score Needed",
                      style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Icon(
                      _whatIfResult!.isAchievable ? Icons.check_circle_rounded : Icons.warning_rounded,
                      color: _whatIfResult!.isAchievable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _whatIfResult!.neededFinalGrade != null
                      ? "${_whatIfResult!.neededFinalGrade!.toStringAsFixed(1)}%"
                      : "Unattainable",
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _whatIfResult!.isAchievable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _whatIfResult!.assessment,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: context.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTargetGwaChip(double gwa, String label) {
    final isSelected = (_targetGwa - gwa).abs() < 0.05;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF6366F1),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: FontWeight.bold,
        fontSize: 11.5,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _targetGwa = gwa);
          _runWhatIfCalculation();
        }
      },
    );
  }
}

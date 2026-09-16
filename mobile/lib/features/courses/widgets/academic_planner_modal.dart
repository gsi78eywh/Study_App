import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";
import "../../practice/models/adaptive_models.dart";

class AcademicPlannerModal extends StatefulWidget {
  final ApiClient apiClient;
  final List<CourseModel> courses;

  const AcademicPlannerModal({
    super.key,
    required this.apiClient,
    required this.courses,
  });

  static Future<void> show(
    BuildContext context, {
    required ApiClient apiClient,
    required List<CourseModel> courses,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AcademicPlannerModal(
        apiClient: apiClient,
        courses: courses,
      ),
    );
  }

  @override
  State<AcademicPlannerModal> createState() => _AcademicPlannerModalState();
}

class _AcademicPlannerModalState extends State<AcademicPlannerModal> {
  bool _isLoading = true;
  List<AcademicTaskModel> _tasks = [];
  bool _isCreating = false;

  // New task form fields
  final _titleController = TextEditingController();
  String _selectedType = "assignment";
  String _selectedDifficulty = "Medium";
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 5));
  String? _selectedCourseId;
  List<String> _breakdownSteps = [];
  bool _isGeneratingBreakdown = false;

  @override
  void initState() {
    super.initState();
    if (widget.courses.isNotEmpty) {
      _selectedCourseId = widget.courses.first.id;
    }
    _loadTasks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    final tasks = await widget.apiClient.getAcademicTasks();
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleTask(AcademicTaskModel task) async {
    final success = await widget.apiClient.toggleAcademicTask(task.id);
    if (success && mounted) {
      setState(() {
        task.isCompleted = !task.isCompleted;
      });
    }
  }

  Future<void> _generateAiBreakdown() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an assignment or project title first.")),
      );
      return;
    }

    setState(() => _isGeneratingBreakdown = true);
    final res = await widget.apiClient.generateAssignmentBreakdown(
      title: title,
      type: _selectedType,
      dueDate: _selectedDate,
    );

    if (mounted) {
      setState(() {
        _isGeneratingBreakdown = false;
        if (res != null) {
          _breakdownSteps = res.actionSteps;
        }
      });
    }
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isLoading = true);
    final created = await widget.apiClient.createAcademicTask(
      courseId: _selectedCourseId,
      title: title,
      type: _selectedType,
      dueDate: _selectedDate,
      estimatedDifficulty: _selectedDifficulty,
      actionSteps: _breakdownSteps,
    );

    if (mounted) {
      setState(() {
        if (created != null) {
          _tasks.insert(0, created);
          _isCreating = false;
          _titleController.clear();
          _breakdownSteps.clear();
        }
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Academic task & AI execution plan saved!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
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
                        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF6366F1), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ACADEMIC CALENDAR & PLANNER",
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          "Deadlines, Projects & AI Step-by-Step Roadmaps",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: context.textSecondary,
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

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Create Task Card / Toggle Button
                        if (!_isCreating)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _isCreating = true),
                              icon: const Icon(Icons.add_task_rounded, size: 18),
                              label: const Text("Plan Assignment or Project with AI"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          )
                        else
                          _buildCreationCard(context),

                        const SizedBox(height: 20),

                        // Upcoming Academic Deadlines
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "UPCOMING DEADLINES (${_tasks.where((t) => !t.isCompleted).length})",
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: context.textSecondary,
                              ),
                            ),
                            Text(
                              "${_tasks.where((t) => t.isCompleted).length} Completed",
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (_tasks.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.cardBorderColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.event_available_rounded, size: 36, color: Color(0xFF6366F1)),
                                  const SizedBox(height: 8),
                                  Text(
                                    "No upcoming deadlines",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Add a project or scan your syllabus to generate an execution roadmap.",
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _tasks.length,
                            itemBuilder: (ctx, i) => _buildTaskItem(context, _tasks[i]),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "AI ASSIGNMENT PLANNER",
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF6366F1),
                  letterSpacing: 0.6,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _isCreating = false),
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title Input
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: "e.g. Java OOP Project / Biology Research Report",
              hintStyle: TextStyle(fontSize: 13, color: context.textSecondary),
              filled: true,
              fillColor: context.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.cardBorderColor),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Type Chips
          Wrap(
            spacing: 6,
            children: ["assignment", "project", "exam", "quiz", "presentation"].map((type) {
              final isSel = _selectedType == type;
              return ChoiceChip(
                label: Text(type[0].toUpperCase() + type.substring(1)),
                selected: isSel,
                onSelected: (_) => setState(() => _selectedType = type),
                selectedColor: const Color(0xFF6366F1),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: isSel ? Colors.white : context.textPrimary,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Difficulty Chips
          Wrap(
            spacing: 6,
            children: ["Easy", "Medium", "Hard"].map((diff) {
              final isSel = _selectedDifficulty == diff;
              return ChoiceChip(
                label: Text(diff),
                selected: isSel,
                onSelected: (_) => setState(() => _selectedDifficulty = diff),
                selectedColor: const Color(0xFF10B981),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: isSel ? Colors.white : context.textPrimary,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Due Date Picker Row
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 15, color: context.textSecondary),
              const SizedBox(width: 8),
              Text(
                "Due: ${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}",
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: const Text("Change Date"),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // AI Generate Breakdown Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGeneratingBreakdown ? null : _generateAiBreakdown,
              icon: _isGeneratingBreakdown
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_isGeneratingBreakdown ? "Synthesizing Roadmap..." : "⚡ Generate Day-by-Day AI Plan"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Breakdown Steps Preview
          if (_breakdownSteps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              "PROPOSED DAILY EXECUTION ROADMAP:",
              style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: context.textSecondary),
            ),
            const SizedBox(height: 6),
            ..._breakdownSteps.map((step) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right_rounded, color: Color(0xFF6366F1), size: 18),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          step,
                          style: GoogleFonts.inter(fontSize: 11, color: context.textPrimary),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Confirm & Add to Academic Calendar"),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskItem(BuildContext context, AcademicTaskModel task) {
    final days = task.daysRemaining;
    final isUrgent = days <= 3 && !task.isCompleted;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUrgent
              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
              : context.cardBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: task.isCompleted,
                onChanged: (_) => _toggleTask(task),
                activeColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: task.isCompleted ? context.textSecondary : context.textPrimary,
                        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task.courseCode,
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF6366F1)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          task.type.toUpperCase(),
                          style: GoogleFonts.inter(fontSize: 10, color: context.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : context.cardBorderColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  days == 0 ? "Today!" : "$days days",
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUrgent ? const Color(0xFFEF4444) : context.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // Sub-steps if present
          if (task.actionSteps.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...task.actionSteps.map((step) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF6366F1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

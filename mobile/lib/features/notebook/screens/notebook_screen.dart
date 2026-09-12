import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/models/course_models.dart";

class NoteItem {
  final String id;
  final String courseCode;
  final String title;
  final String content;
  final String tags;
  final DateTime updatedAt;

  NoteItem({
    required this.id,
    required this.courseCode,
    required this.title,
    required this.content,
    required this.tags,
    required this.updatedAt,
  });
}

class NotebookScreen extends StatefulWidget {
  final List<CourseModel> courses;
  final ApiClient apiClient;

  const NotebookScreen({
    super.key,
    required this.courses,
    required this.apiClient,
  });

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  final List<NoteItem> _notes = [];
  String _selectedFilter = "ALL";
  String _searchQuery = "";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRemoteNotes();
  }

  Future<void> _fetchRemoteNotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.apiClient.dio.get("/api/v1/notebooks");
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        final remoteNotes = list.map((item) {
          return NoteItem(
            id: item["id"]?.toString() ?? UniqueKey().toString(),
            courseCode: item["courseCode"]?.toString() ?? "GENERAL",
            title: item["title"]?.toString() ?? "Untitled Note",
            content: item["content"]?.toString() ?? "",
            tags: item["tags"]?.toString() ?? "#Notes",
            updatedAt: DateTime.tryParse(item["updatedAt"]?.toString() ?? "") ?? DateTime.now(),
          );
        }).toList();

        setState(() {
          for (final r in remoteNotes) {
            if (!_notes.any((n) => n.id == r.id)) {
              _notes.insert(0, r);
            }
          }
        });
      }
    } catch (_) {
      // Offline fallback: locally created notes continue seamlessly
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddNoteDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final tagsController = TextEditingController(text: "#Lecture");
    String selectedCourse = widget.courses.isNotEmpty ? widget.courses.first.code : "GENERAL";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Create Digital Lecture Note", style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.courses.isNotEmpty) ...[
                    Row(
                      children: [
                        Text("Course: ", style: TextStyle(color: ctx.textSecondary)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: widget.courses.any((c) => c.code == selectedCourse) ? selectedCourse : widget.courses.first.code,
                          dropdownColor: ctx.surfaceColor,
                          style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold),
                          items: widget.courses.map((c) => DropdownMenuItem(value: c.code, child: Text(c.code))).toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => selectedCourse = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Note Title",
                      hintText: "e.g. Dynamic Programming & Memoization",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagsController,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Tags",
                      hintText: "#Algorithms #ExamPrep",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 6,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Lecture Notes & Key Concepts",
                      hintText: "Enter formulas, summaries, bullet points...",
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                final tags = tagsController.text.trim();

                if (title.isEmpty || content.isEmpty) return;

                final newNote = NoteItem(
                  id: "note-${DateTime.now().millisecondsSinceEpoch}",
                  courseCode: selectedCourse,
                  title: title,
                  content: content,
                  tags: tags.isEmpty ? "#Notes" : tags,
                  updatedAt: DateTime.now(),
                );

                setState(() => _notes.insert(0, newNote));
                Navigator.pop(ctx);

                try {
                  await widget.apiClient.dio.post("/api/v1/notebooks", data: {
                    "courseCode": selectedCourse,
                    "title": title,
                    "content": content,
                    "tags": tags,
                  });
                } catch (_) {}

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Note saved to digital notebook"),
                      backgroundColor: AppColors.accent,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text("Save Note"),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteDetail(NoteItem note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                note.courseCode,
                style: TextStyle(
                  color: ctx.isDarkMode ? AppColors.primaryLight : AppColors.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note.title,
                style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(note.tags, style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SelectableText(
                note.content,
                style: TextStyle(color: ctx.textPrimary, fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text("Copy Text"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "${note.title}\n\n${note.content}"));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Copied note to clipboard"), duration: Duration(seconds: 2)),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final availableCourses = <String>["ALL", ...widget.courses.map((c) => c.code).toSet()];

    final filtered = _notes.where((n) {
      final matchesCourse = (_selectedFilter == "ALL" || n.courseCode == _selectedFilter);
      final matchesSearch = _searchQuery.isEmpty ||
          n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.content.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.tags.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCourse && matchesSearch;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isLoading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Digital Notebook",
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Personalized lecture notes, derivations & formulas",
                        style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text("New Note", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _showAddNoteDialog,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: "Search notes by title, keyword, or tag...",
                  prefixIcon: Icon(Icons.search_rounded, color: context.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: context.textSecondary),
                          onPressed: () => setState(() => _searchQuery = ""),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 14),

              if (availableCourses.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: availableCourses.map((code) {
                      final isSelected = _selectedFilter == code;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(code == "ALL" ? "All Subjects" : code),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                          selectedColor: isDark ? AppColors.primary : AppColors.primaryDark,
                          backgroundColor: context.surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? (isDark ? AppColors.primary : AppColors.primaryDark)
                                  : context.cardBorderColor,
                            ),
                          ),
                          onSelected: (_) => setState(() => _selectedFilter = code),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.menu_book_rounded, size: 56, color: context.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      Text(
                        _notes.isEmpty ? "Your Notebook is Empty" : "No Matching Notes Found",
                        style: GoogleFonts.outfit(fontSize: 18, color: context.textPrimary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _notes.isEmpty
                            ? "Tap '+ New Note' to capture your first study summary, key formula, or revision takeaway."
                            : "Try searching with a different keyword or select another subject filter.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
                      ),
                      if (_notes.isEmpty) ...[
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text("Create Your First Note"),
                          onPressed: _showAddNoteDialog,
                        ),
                      ],
                    ],
                  ),
                )
              else
                ...filtered.map((note) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                note.courseCode,
                                style: TextStyle(
                                  color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              "${note.updatedAt.month}/${note.updatedAt.day}",
                              style: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          note.title,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          note.tags,
                          style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          note.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text("View Full Note"),
                            onPressed: () => _showNoteDetail(note),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

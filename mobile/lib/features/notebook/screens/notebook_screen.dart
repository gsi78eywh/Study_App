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
    _loadSeedNotes();
    _fetchRemoteNotes();
  }

  void _loadSeedNotes() {
    _notes.addAll([
      NoteItem(
        id: "note-1",
        courseCode: "CS301",
        title: "Raft Consensus - State Machine Replication",
        tags: "#Distributed #Consensus #Raft",
        updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
        content:
            "• Node Roles: Leader, Follower, Candidate.\n"
            "• Terms act as logical clocks: Each term begins with an election.\n"
            "• Election Safety: At most one leader can be elected in a given term.\n"
            "• Leader Append-Only: A leader never overwrites or truncates its own log entries.\n"
            "• Log Matching Invariant: If two logs contain an entry with the same index and term, then they are identical up to that point.\n\n"
            "Key takeaway: In network partitions, minority partitions cannot commit entries because they lack quorum (majority > N/2).",
      ),
      NoteItem(
        id: "note-2",
        courseCode: "BIO102",
        title: "Eukaryotic vs Prokaryotic Transcription",
        tags: "#Genetics #RNA #Transcription",
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        content:
            "1. Transcription Initiation:\n"
            "   - Prokaryotes: RNA Polymerase binds directly to promoter with Sigma factor.\n"
            "   - Eukaryotes: Requires transcription factors (TFIID, TATA box).\n"
            "2. Post-Transcriptional Modifications (Eukaryotes only):\n"
            "   - 5' 7-methylguanosine cap for ribosome recognition and stability.\n"
            "   - 3' Poly-A tail (150-250 adenines) protects against enzymatic degradation.\n"
            "   - RNA Splicing: Spliceosome removes introns and ligates exons.",
      ),
      NoteItem(
        id: "note-3",
        courseCode: "MATH201",
        title: "Gram-Schmidt Orthogonalization Process",
        tags: "#LinearAlgebra #Vectors #Orthogonality",
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        content:
            "Given a linearly independent basis {v1, v2, ..., vn}:\n\n"
            "Step 1: u1 = v1\n"
            "Step 2: u2 = v2 - proj_{u1}(v2) = v2 - ((v2 · u1) / (u1 · u1)) u1\n"
            "Step k: uk = vk - Σ [((vk · uj) / (uj · uj)) uj] for j = 1 to k-1\n\n"
            "Normalize each uk by dividing by its norm: ek = uk / ||uk|| to obtain an orthonormal basis {e1, e2, ..., en}.",
      ),
    ]);
  }

  Future<void> _fetchRemoteNotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.apiClient.dio.get("/api/v1/notebooks");
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        if (list.isNotEmpty) {
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
      }
    } catch (_) {
      // Backend not yet reached or offline mode; local notes continue seamlessly
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddNoteDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final tagsController = TextEditingController(text: "#Lecture");
    String selectedCourse = widget.courses.isNotEmpty ? widget.courses.first.code : "CS301";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Create Digital Lecture Note", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text("Course: ", style: TextStyle(color: AppColors.darkTextSecondary)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: selectedCourse,
                        dropdownColor: AppColors.darkCard,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: widget.courses.map((c) => DropdownMenuItem(value: c.code, child: Text(c.code))).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedCourse = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Note Title",
                      hintText: "e.g. Dynamic Programming & Memoization",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagsController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Tags",
                      hintText: "#Algorithms #ExamPrep",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
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
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(note.courseCode, style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note.title,
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
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
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Synchronized lecture notes, derivations & formulas",
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.darkTextSecondary),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search notes by title, keyword, or tag...",
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.darkTextSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.darkTextSecondary),
                          onPressed: () => setState(() => _searchQuery = ""),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 14),

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
                          color: isSelected ? Colors.white : AppColors.darkTextSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.darkCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.darkCardBorder),
                        ),
                        onSelected: (_) => setState(() => _selectedFilter = code),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkCardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 56, color: AppColors.darkTextSecondary),
                      const SizedBox(height: 16),
                      Text("No notes found", style: GoogleFonts.outfit(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text("Tap '+ New Note' to capture your first study summary.", style: TextStyle(color: AppColors.darkTextSecondary)),
                    ],
                  ),
                )
              else
                ...filtered.map((note) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkCardBorder),
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
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                note.courseCode,
                                style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            Text(
                              "${note.updatedAt.month}/${note.updatedAt.day}",
                              style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          note.title,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
                          style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
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

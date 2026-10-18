import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/network/api_client.dart";
import "../../../core/theme/app_theme.dart";
import "../services/seth_ai_engine.dart";

class EasyWritingStudioModal extends StatefulWidget {
  final ApiClient? apiClient;
  final String? initialText;
  final String initialMode; // "correct" or "make"

  const EasyWritingStudioModal({
    super.key,
    this.apiClient,
    this.initialText,
    this.initialMode = "correct",
  });

  static Future<void> show(
    BuildContext context, {
    ApiClient? apiClient,
    String? initialText,
    String initialMode = "correct",
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EasyWritingStudioModal(
        apiClient: apiClient,
        initialText: initialText,
        initialMode: initialMode,
      ),
    );
  }

  @override
  State<EasyWritingStudioModal> createState() => _EasyWritingStudioModalState();
}

class _EasyWritingStudioModalState extends State<EasyWritingStudioModal> {
  late String _mode; // "correct" or "make"
  final TextEditingController _inputController = TextEditingController();
  String _selectedFormat = "Academic Essay & Study Guide";
  String _selectedTone = "Google-Standard Academic & Clear";
  bool _isLoading = false;
  SethAiWritingResult? _result;

  static const List<String> _formats = [
    "Academic Essay & Study Guide",
    "Comprehensive Exam Reviewer",
    "Research Paper Outline",
    "Step-by-Step Concept Breakdown",
    "Bisaya / Tagalog / English Study Guide",
  ];

  static const List<String> _tones = [
    "Google-Standard Academic & Clear",
    "Simple & Easy to Understand",
    "University & Peer-Reviewed Level",
    "Professional & Concise",
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _inputController.text = widget.initialText!.trim();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _runStudio() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await SethAiEngine.runWritingStudio(
        mode: _mode,
        textOrTopic: text,
        format: _selectedFormat,
        tone: _selectedTone,
        apiClient: widget.apiClient,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error running Seth AI Studio: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMake = _mode == "make";

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        children: [
          // Drag handle + Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: context.cardBorderColor)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: context.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Seth AI • Easy Maker & Corrector",
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            "Google-Standard Academic Writing, Grammar & Study Guide Studio",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: context.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Mode Toggle Tabs
                Row(
                  children: [
                    Expanded(
                      child: _buildModeTab(
                        modeKey: "correct",
                        icon: Icons.spellcheck_rounded,
                        title: "Easy Corrector",
                        subtitle: "Grammar & Clarity Fixer",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildModeTab(
                        modeKey: "make",
                        icon: Icons.auto_awesome_rounded,
                        title: "Easy Maker",
                        subtitle: "Essay & Guide Creator",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // Format & Tone selectors
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (isMake)
                      _buildDropdownChip(
                        label: "Format",
                        value: _selectedFormat,
                        items: _formats,
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedFormat = v);
                        },
                      ),
                    _buildDropdownChip(
                      label: "Standard / Tone",
                      value: _selectedTone,
                      items: _tones,
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedTone = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Input Box
                Container(
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.cardBorderColor),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isMake ? Icons.lightbulb_outline_rounded : Icons.edit_note_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isMake
                                  ? "Enter Topic, Question, or Assignment Prompt"
                                  : "Paste Essay, Paragraph, or Study Notes to Correct",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                setState(() {
                                  _inputController.text = data.text!.trim();
                                });
                              }
                            },
                            icon: const Icon(Icons.content_paste_rounded, size: 15),
                            label: const Text("Paste", style: TextStyle(fontSize: 12)),
                          ),
                          if (_inputController.text.isNotEmpty)
                            IconButton(
                              onPressed: () => setState(() => _inputController.clear()),
                              icon: Icon(Icons.delete_outline_rounded, size: 17, color: context.textSecondary),
                              tooltip: "Clear",
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _inputController,
                        minLines: 4,
                        maxLines: 7,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: isMake
                              ? "e.g. Photosynthesis and Cellular Respiration, Philippine History, Cognitive Load Theory, or How to build a REST API..."
                              : "e.g. Paste your draft essay, sentences, or study notes here and Seth AI will fix grammar, spelling, and elevate clarity to Google standard...",
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _inputController.text.trim().isEmpty
                        ? null
                        : _runStudio,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(isMake ? Icons.auto_awesome_rounded : Icons.done_all_rounded, size: 18),
                    label: Text(
                      _isLoading
                          ? (isMake
                              ? "Seth AI is crafting your Google-standard guide..."
                              : "Seth AI is proofreading & elevating your writing...")
                          : (isMake
                              ? "Generate with Seth AI Easy Maker"
                              : "Correct & Elevate with Seth AI"),
                    ),
                  ),
                ),

                // Results Section
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Google-Standard Quality • ${_result!.qualityScore}%",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _result!.markdownReport));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Copied Seth AI output to clipboard!"),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text("Copy All", style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildRichMarkdown(_result!.markdownReport, context),
                        if (_result!.sources.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          Text(
                            "Verified Google & Encyclopedia Grounding Sources",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _result!.sources.map((s) {
                              return ActionChip(
                                avatar: const Icon(Icons.public_rounded, size: 14, color: AppColors.primary),
                                label: Text(
                                  s.title,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: s.url));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Source URL copied: ${s.url}"),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichMarkdown(String rawText, BuildContext context) {
    final baseColor = context.textPrimary;
    final lines = rawText.split("\n");
    final spans = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: "\n"));

      if (line.startsWith("### ")) {
        spans.add(
          TextSpan(
            text: line.substring(4),
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 15.5,
              color: AppColors.primary,
            ),
          ),
        );
      } else if (line.startsWith("## ")) {
        spans.add(
          TextSpan(
            text: line.substring(3),
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 16.5,
              color: baseColor,
            ),
          ),
        );
      } else if (line.startsWith("# ")) {
        spans.add(
          TextSpan(
            text: line.substring(2),
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: baseColor,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: line.replaceAll("**", ""),
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.55,
              color: baseColor,
              fontWeight: line.contains("**") ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }
    }

    return SelectableText.rich(TextSpan(children: spans));
  }

  Widget _buildModeTab({
    required String modeKey,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == modeKey;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _mode = modeKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.14)
              : context.scaffoldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : context.cardBorderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.primary : context.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primary : context.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.textSecondary,
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

  Widget _buildDropdownChip({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text("$label: $e"),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}


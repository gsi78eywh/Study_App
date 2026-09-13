class FlashcardTextSanitizer {
  /// Strips cloze metadata, surrounding quotes, and leading MCQ distractor letters/bullets
  /// from question prompts to create clean, readable flashcard fronts.
  static String cleanFront(String raw) {
    var text = raw.trim();

    // Strip wrapping double quotes
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith('“') && text.endsWith('”'))) {
      text = text.substring(1, text.length - 1).trim();
    }

    // Strip cloze wrapper prefixes
    final clozePrefix = RegExp(
      r'^(?:Fill in the (?:missing (?:word|key term)|blank)(?: from your (?:study )?notes)?:\s*["“]?|True or False:\s*(?:According to (?:your )?(?:study )?(?:material|notes):\s*["“]?)?)',
      caseSensitive: false,
    );
    if (clozePrefix.hasMatch(text)) {
      text = text.replaceFirst(clozePrefix, '').trim();
      if (text.endsWith('"') || text.endsWith('”')) {
        text = text.substring(0, text.length - 1).trim();
      }
    }

    // Strip leading markdown bullets and MCQ distractor option letters (e.g. "* A) ", "- B. ")
    final optionPrefix = RegExp(
      r'^(?:[\*\-\•\+\>]\s*)*(?:[\(\[]?[A-Fa-f][\)\]][\.:\s\-]*|[\(\[]?[A-Fa-f]\.[\s\-]*|[A-Fa-f]\s*[:\-]\s*)',
      caseSensitive: false,
    );
    text = text.replaceFirst(optionPrefix, '').trim();

    // Strip residual leading bullets or bold asterisks
    text = text.replaceFirst(RegExp(r'^(?:[\*\-\•\+\>]+\s*)+'), '').trim();
    text = text.replaceFirst(RegExp(r'^\*{1,2}|\*{1,2}$'), '').trim();

    return text.isEmpty ? raw : text;
  }

  /// Strips distractor letter tags (e.g. "* A) ", "B. ") from verified answers.
  static String cleanAnswer(String raw) {
    var text = raw.trim();
    final optionPrefix = RegExp(
      r'^(?:[\*\-\•\+\>]\s*)*(?:[\(\[]?[A-Fa-f][\)\]][\.:\s\-]*|[\(\[]?[A-Fa-f]\.[\s\-]*|[A-Fa-f]\s*[:\-]\s*)',
      caseSensitive: false,
    );
    text = text.replaceFirst(optionPrefix, '').trim();
    text = text.replaceFirst(RegExp(r'^\*{1,2}|\*{1,2}$'), '').trim();
    return text.isEmpty ? raw : text;
  }

  /// Cleans explanation blocks from leaked option markers or raw quotes.
  static String cleanExplanation(String raw) {
    var text = raw.trim();
    text = text.replaceAll(
      RegExp(r'Full text from your (?:study )?notes:\s*["“]?[\*\-\•\+\>]*\s*(?:[A-Fa-f][\)\.]\s*)?', caseSensitive: false),
      'Source notes: ',
    );
    text = text.replaceAll(
      RegExp(r'Notes excerpt:\s*["“]?[\*\-\•\+\>]*\s*(?:[A-Fa-f][\)\.]\s*)?', caseSensitive: false),
      'Excerpt: ',
    );
    return text;
  }
}

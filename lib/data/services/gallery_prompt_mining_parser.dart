import '../../core/autocomplete/completion_models.dart';

/// Flattens NovelAI weighting syntax into semantic tags for mining only.
/// Source prompt text remains untouched.
abstract final class GalleryPromptMiningParser {
  static final RegExp _numericWeightPrefix = RegExp(
    r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*::\s*',
  );
  static final RegExp _suffixWeight = RegExp(r':\s*-?\d+(?:\.\d+)?$');
  static final RegExp _artistPrefix = RegExp(
    r'^artist\s*:\s*',
    caseSensitive: false,
  );

  static List<GalleryPromptMiningTag> parse(String prompt) {
    final tags = <GalleryPromptMiningTag>[];
    var tokenStart = 0;
    var lineIndex = 0;
    var tokenLine = 0;
    var escaped = false;

    void addTag(int end) {
      final display = _cleanFragment(prompt.substring(tokenStart, end));
      if (display.isEmpty) return;
      var base = display.replaceFirst(_suffixWeight, '').trim();
      final explicitArtist = _artistPrefix.hasMatch(base);
      base = base.replaceFirst(_artistPrefix, '');
      final lookupTerm = base
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(r'\,', ',')
          .trim();
      if (lookupTerm.isEmpty) return;
      tags.add(
        GalleryPromptMiningTag(
          displayToken: display,
          patternToken: lookupTerm,
          lookupTerm: lookupTerm,
          explicitArtist: explicitArtist,
          lineIndex: tokenLine,
        ),
      );
    }

    for (var index = 0; index < prompt.length; index++) {
      final character = prompt[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (character == ',' || character == '，' || character == '\n') {
        addTag(index);
        tokenStart = index + 1;
        if (character == '\n') lineIndex++;
        tokenLine = lineIndex;
      }
    }
    addTag(prompt.length);
    return List.unmodifiable(tags);
  }

  static String _cleanFragment(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    for (var pass = 0; pass < 8; pass++) {
      final previous = value;
      value = value
          .replaceFirst(RegExp(r'^(?:\{+|\[+)\s*'), '')
          .replaceFirst(RegExp(r'\s*(?:\}+|\]+)$'), '')
          .replaceFirst(RegExp(r'^::\s*'), '')
          .replaceFirst(_numericWeightPrefix, '')
          .replaceFirst(RegExp(r'\s*::$'), '')
          .trim();
      if (_hasSingleOuterParentheses(value)) {
        value = value.substring(1, value.length - 1).trim();
      }
      if (value == previous) break;
    }
    if (RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)?\s*::$').hasMatch(value)) {
      return '';
    }
    return value;
  }

  static bool _hasSingleOuterParentheses(String value) {
    if (value.length < 2 || value[0] != '(' || value[value.length - 1] != ')') {
      return false;
    }
    var depth = 0;
    for (var index = 0; index < value.length; index++) {
      if (value[index] == '(') depth++;
      if (value[index] == ')') depth--;
      if (depth == 0 && index < value.length - 1) return false;
      if (depth < 0) return false;
    }
    return depth == 0;
  }
}

class GalleryPromptMiningTag {
  const GalleryPromptMiningTag({
    required this.displayToken,
    required this.patternToken,
    required this.lookupTerm,
    required this.explicitArtist,
    required this.lineIndex,
    this.category,
  });

  final String displayToken;
  final String patternToken;
  final String lookupTerm;
  final bool explicitArtist;
  final int lineIndex;
  final TagCategory? category;

  GalleryPromptMiningTag withResolution({
    required TagCategory? category,
    String? patternToken,
  }) =>
      GalleryPromptMiningTag(
        displayToken: displayToken,
        patternToken: patternToken ?? this.patternToken,
        lookupTerm: lookupTerm,
        explicitArtist: explicitArtist,
        lineIndex: lineIndex,
        category: category,
      );
}

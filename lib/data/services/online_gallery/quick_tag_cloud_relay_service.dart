import 'dart:math' as math;

import '../../models/online_gallery/quick_tag_cloud_relay.dart';

class QuickTagCloudRelayOutput {
  const QuickTagCloudRelayOutput({
    required this.positive,
    required this.negative,
    required this.characters,
    required this.mergedCount,
    required this.lockedCount,
  });

  final String positive;
  final String negative;
  final List<QuickTagCloudRelayCharacter> characters;
  final int mergedCount;
  final int lockedCount;
  bool get isEmpty => positive.isEmpty && negative.isEmpty && characters.isEmpty;

  /// Character sections remain explicitly separate, including character UC.
  String get allText => [
    if (positive.isNotEmpty) positive,
    if (negative.isNotEmpty) 'Negative:\n$negative',
    for (var index = 0; index < characters.length; index++)
      [
        'Character ${index + 1}: ${characters[index].label}',
        if (characters[index].positive.isNotEmpty) characters[index].positive,
        if (characters[index].negative.isNotEmpty)
          'Negative:\n${characters[index].negative}',
      ].join('\n'),
  ].join('\n\n');
}

/// Deterministic local composition; no request, account or generation side effects.
/// Semantics checked against AgIzT/NovelAI-Tag at ec95f2b98542e5fac0a48586e0fa2ad100eb3569:
/// tag-relay-core.js, tag-relay-compose.js and nai-sd.js. Characters are retained
/// in native independent slots instead of flattening their positive prompts.
class QuickTagCloudRelayService {
  const QuickTagCloudRelayService();

  /// Both global selection and the source's current access switches must allow
  /// a stored source snapshot before preview, clipboard or generation can use it.
  static Set<String> effectiveRatings(
    Set<String> selectedRatings, {
    required bool allowNsfw,
    required bool allowR18g,
  }) => Set.unmodifiable({
    for (final rating in selectedRatings)
      if (rating == 'g' || rating == 's' ||
          (rating == 'q' && allowNsfw) ||
          (rating == 'e' && allowNsfw && allowR18g)) rating,
  });

  static String clean(String value) => value
      .replaceAll(RegExp(r'^[\s,，]+|[\s,，]+$'), '').trim();

  QuickTagCloudRelayOutput compile(
    QuickTagCloudRelayPlan plan, {
    QuickTagCloudRelayFormat format = QuickTagCloudRelayFormat.nai,
    QuickTagCloudRelayJoin join = QuickTagCloudRelayJoin.comma,
    Set<String> allowedRatings = const {'g', 's'},
  }) {
    final positive = <String>[];
    final negative = <String>[];
    final characters = <QuickTagCloudRelayCharacter>[];
    var locked = 0;
    for (final block in plan.blocks) {
      if (!block.enabled) continue;
      if (!block.allowedBy(allowedRatings)) {
        locked++;
        continue;
      }
      String adapt(String value) => compileBlock(value, format, block.weight);
      positive.addAll(splitTopLevel(adapt(block.positive)));
      negative.addAll(splitTopLevel(adapt(block.negative)));
      for (final character in block.characters) {
        final pos = adapt(character.positive);
        final neg = adapt(character.negative);
        if (pos.isEmpty && neg.isEmpty) continue;
        characters.add(QuickTagCloudRelayCharacter(
          label: character.label, positive: pos, negative: neg,
        ));
      }
    }
    final pos = _deduplicate(positive);
    final neg = _deduplicate(negative);
    final separator = join == QuickTagCloudRelayJoin.newline ? ',\n' : ', ';
    return QuickTagCloudRelayOutput(
      positive: pos.join(separator), negative: neg.join(separator),
      characters: List.unmodifiable(characters), lockedCount: locked,
      mergedCount: positive.length + negative.length - pos.length - neg.length,
    );
  }

  String compileBlock(
    String value, QuickTagCloudRelayFormat format, double weight,
  ) {
    if (!weight.isFinite || weight < QuickTagCloudRelayBlock.minimumWeight ||
        weight > QuickTagCloudRelayBlock.maximumWeight) {
      throw const FormatException('Relay weight outside 0.05–10');
    }
    final source = clean(value);
    if (source.isEmpty) return '';
    final adapted = format == QuickTagCloudRelayFormat.sd
        ? naiToSd(source) : source;
    final label = _weightLabel(weight);
    if (format == QuickTagCloudRelayFormat.plain || label == '1') return adapted;
    if (format == QuickTagCloudRelayFormat.sd) return '($adapted:$label)';
    if (RegExp(r'(?:^|[^\d.])[+-]?\d+(?:\.\d+)?::').hasMatch(adapted)) {
      final layers = (math.log(weight) / math.log(1.05)).round();
      final opening = (layers >= 0 ? '{' : '[') * layers.abs();
      final closing = (layers >= 0 ? '}' : ']') * layers.abs();
      return '$opening$adapted$closing';
    }
    return '$label::$adapted::';
  }

  /// Closed numeric groups and bracket groups keep their inner commas.
  /// An unclosed numeric group ends at its first comma, newline or close bracket.
  static List<String> splitTopLevel(String value) {
    final source = clean(value);
    final result = <String>[];
    var start = 0;
    final closing = <String>[];
    var numeric = false, closedNumeric = false, escaped = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (escaped) { escaped = false; continue; }
      if (char == r'\') { escaped = true; continue; }
      if (source.startsWith('::', index)) {
        if (numeric) {
          numeric = false;
          index++;
          continue;
        }
        if (RegExp(r'^[+-]?\d+(?:\.\d+)?$')
            .hasMatch(source.substring(start, index).trim())) {
          numeric = true;
          closedNumeric = source.indexOf('::', index + 2) >= 0;
          index++;
          continue;
        }
      }
      if (numeric && !closedNumeric && ',\n}]'.contains(char)) numeric = false;
      if (!numeric) {
        final close = switch (char) { '{' => '}', '[' => ']', '(' => ')', _ => null };
        if (close != null) closing.add(close);
        if (closing.isNotEmpty && char == closing.last) closing.removeLast();
      }
      if (char == ',' && closing.isEmpty && !numeric) {
        final token = clean(source.substring(start, index));
        if (token.isNotEmpty) result.add(token);
        start = index + 1;
      }
    }
    final tail = clean(source.substring(start));
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  static List<String> _deduplicate(List<String> values) {
    final seen = <String>{};
    return values.where((value) =>
      seen.add(value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()),
    ).toList();
  }

  static String _weightLabel(double value) => value.toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '');

  static String naiToSd(String source) => _NaiSdReader(source).read().text;
}

/// Small bounded reader; numeric groups use upstream's nearest closing `::`.
class _NaiSdReader {
  _NaiSdReader(this.source, [this.depth = 0]);
  static final _numericWeight = RegExp(r'([+-]?\d+(?:\.\d+)?)::');
  final String source;
  final int depth;
  var position = 0;

  ({String text, int closingCount, int closingStart}) read([String stop = '']) {
    if (depth > 64) throw const FormatException('Prompt nesting is too deep');
    final out = StringBuffer();
    while (position < source.length) {
      final char = source[position];
      if (stop.isNotEmpty && char == stop) {
        final start = position;
        while (position < source.length && source[position] == stop) position++;
        return (text: out.toString(), closingCount: position - start, closingStart: start);
      }
      if (char == r'\' && position + 1 < source.length) {
        out.write(source.substring(position, position + 2));
        position += 2;
        continue;
      }
      if (char == '}' || char == ']') { position++; continue; }
      final code = char.codeUnitAt(0);
      final isDigit = code >= 48 && code <= 57;
      final previous = position == 0 ? 0 : source.codeUnitAt(position - 1);
      final startsNumber = char == '+' || char == '-' ||
          (isDigit && (previous < 48 || previous > 57));
      final numeric = startsNumber
          ? _numericWeight.matchAsPrefix(source, position) : null;
      if (numeric != null) {
        _readNumeric(numeric, out);
        continue;
      }
      if (char == '{' || char == '[') {
        _readBracket(char, out);
        continue;
      }
      out.write(char);
      position++;
    }
    return (text: out.toString(), closingCount: 0, closingStart: position);
  }

  void _readNumeric(Match numeric, StringBuffer out) {
    position = numeric.end;
    // An immediately empty numeric segment retains the surrounding delimiter.
    if (position == source.length || ',\n'.contains(source[position])) return;
    final end = source.indexOf('::', position);
    var limit = end;
    if (limit < 0) {
      limit = position;
      while (limit < source.length && !',\n}]'.contains(source[limit])) limit++;
    }
    final content = QuickTagCloudRelayService.clean(source.substring(position, limit));
    position = end < 0 ? limit : limit + 2;
    if (content.isEmpty) return;
    final number = double.tryParse(numeric.group(1)!);
    if (number == null || !number.isFinite) {
      throw const FormatException('Invalid numeric prompt weight');
    }
    final inner = _NaiSdReader(content, depth + 1).read().text;
    out.write('($inner:${QuickTagCloudRelayService._weightLabel(number)})');
  }

  void _readBracket(String opening, StringBuffer out) {
    var count = 0;
    while (position < source.length && source[position] == opening) {
      count++; position++;
    }
    final reader = _NaiSdReader(source.substring(position), depth + 1);
    final inner = reader.read(opening == '{' ? '}' : ']');
    if (inner.closingCount == 0) {
      out.write(inner.text);
      position += reader.position;
      return;
    }
    final matched = math.min(count, inner.closingCount);
    position += inner.closingStart + matched;
    final content = QuickTagCloudRelayService.clean(inner.text);
    if (content.isEmpty) return;
    final factor = math.pow(1.05, opening == '{' ? matched : -matched).toDouble();
    if (!factor.isFinite) throw const FormatException('Prompt weight overflow');
    out.write('($content:${QuickTagCloudRelayService._weightLabel(factor)})');
  }
}

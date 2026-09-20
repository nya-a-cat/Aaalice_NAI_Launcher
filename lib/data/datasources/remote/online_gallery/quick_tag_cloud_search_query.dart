import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Search grammar follows NovelAI-Tag search.js at ec95f2b98542e5fac0a48586e0fa2ad100eb3569.
const quickTagCloudTextConditionLimit = 10;

const quickTagCloudTextFields = {
  'default',
  'title',
  'prompt',
  'negative',
  'note',
  'raw',
  'author',
  'codex',
  'type',
  'path',
};

String normalizeQuickTagCloudSearchInput(String value) => unorm.nfkc(value)
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‘’]'), "'");

String normalizeQuickTagCloudSearchText(String value) =>
    normalizeQuickTagCloudSearchInput(value)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

class QuickTagCloudSearchIssue {
  const QuickTagCloudSearchIssue(this.code, this.message, [this.value = '']);

  final String code;
  final String message;
  final String value;
}

class QuickTagCloudSearchFilter {
  const QuickTagCloudSearchFilter({
    required this.field,
    required this.value,
    this.excluded = false,
    this.codexId = '',
  });

  final String field;
  final String value;
  final bool excluded;
  final String codexId;

  bool get isText => quickTagCloudTextFields.contains(field);
  bool get booleanValue => value == 'true' || value == 'image';
  String get normalizedValue => normalizeQuickTagCloudSearchText(value);
  String get identity =>
      '$field\u0000$excluded\u0000$normalizedValue\u0000'
      '${normalizeQuickTagCloudSearchText(codexId)}';

  /// A complete input-box token, including quoting for spaces and punctuation.
  String serialize() {
    if (field == 'directory') {
      return 'dir:${_quote('$codexId:$value')}';
    }
    return '${excluded ? '-' : ''}$field:${_quote(value)}';
  }

  static String _quote(String value) {
    value = normalizeQuickTagCloudSearchInput(value);
    if (!RegExp('[\\s"\'\\\\]').hasMatch(value)) return value;
    final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

class QuickTagCloudSearchPlan {
  QuickTagCloudSearchPlan({
    required this.raw,
    required Iterable<String> terms,
    required Iterable<QuickTagCloudSearchFilter> filters,
    required Iterable<QuickTagCloudSearchIssue> issues,
  }) : terms = List.unmodifiable(terms),
       filters = List.unmodifiable(filters),
       issues = List.unmodifiable(issues);

  final String raw;
  final List<String> terms;
  final List<QuickTagCloudSearchFilter> filters;
  final List<QuickTagCloudSearchIssue> issues;

  bool get hasErrors => issues.isNotEmpty;
  bool get usesFavorites => filters.any((filter) => filter.field == 'fav');
  bool get hasActiveSearch => raw.trim().isNotEmpty || filters.isNotEmpty;
  String get text => terms.join(' ');
}

class QuickTagCloudSearchException implements Exception {
  const QuickTagCloudSearchException(this.issues);

  final List<QuickTagCloudSearchIssue> issues;

  @override
  String toString() => issues.map((issue) => issue.message).join('; ');
}

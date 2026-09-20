import 'quick_tag_cloud_search_query.dart';

export 'quick_tag_cloud_search_query.dart';

/// Native query syntax shared by the engine and the visual search builder.
class QuickTagCloudSearchParser {
  static const _aliases = {
    'default': 'default', 'title': 'title', '标题': 'title',
    'prompt': 'prompt', 'prompts': 'prompt', 'tag': 'prompt', 'tags': 'prompt',
    '标签': 'prompt', '正向': 'prompt', '提示词': 'prompt',
    'negative': 'negative', 'neg': 'negative', '负面': 'negative',
    '负面词': 'negative', 'note': 'note', '备注': 'note',
    'raw': 'raw', 'rawtag': 'raw', 'rawtags': 'raw', '原始': 'raw', '原始词': 'raw',
    'author': 'author', '作者': 'author', 'codex': 'codex', 'book': 'codex',
    'source': 'codex', '法典': 'codex', '书': 'codex',
    'type': 'type', '类型': 'type', 'path': 'path', '路径': 'path', '目录': 'path',
    'has': 'has', 'image': 'has', '图片': 'has', 'fav': 'fav',
    'favorite': 'fav', 'favourite': 'fav', '收藏': 'fav',
    'dir': 'directory', 'directory': 'directory',
  };
  static const _hasValues = {
    'image': true, 'img': true, 'true': true, 'yes': true, '1': true,
    '有图': true, '有': true, '是': true,
    'noimage': false, 'none': false, 'false': false, 'no': false, '0': false,
    '无图': false, '无': false, '否': false,
  };
  static const _favValues = {
    'true': true, 'yes': true, '1': true, '收藏': true, '已收藏': true, '是': true,
    'false': false, 'no': false, '0': false, '未收藏': false, '否': false,
  };
  static const _types = {
    'codex': 'codex', '法典': 'codex', 'string': 'string', '画风': 'string',
    '画风串': 'string', 'composition': 'composition', '构图': 'composition',
    '服装': 'composition', '场景': 'composition', 'pack': 'pack',
    '图包': 'pack', '精选图包': 'pack',
  };

  static QuickTagCloudSearchPlan parse(
    String raw, {
    Iterable<String> filterValues = const [],
  }) {
    final terms = <String>{};
    final filters = <QuickTagCloudSearchFilter>[];
    final issues = <QuickTagCloudSearchIssue>[];
    for (final value in filterValues) {
      _consumeStandaloneFilter(value, terms, filters, issues);
    }
    for (final token in _scan(raw, issues)) {
      _consume(token, terms, filters, issues);
    }
    final textConditions = {
      for (final term in terms) 'default\u0000false\u0000$term',
      for (final filter in filters.where((filter) => filter.isText))
        '${filter.field}\u0000${filter.excluded}\u0000${filter.normalizedValue}',
    };
    if (textConditions.length > quickTagCloudTextConditionLimit) {
      issues.add(QuickTagCloudSearchIssue(
        'too_many_text_conditions',
        '最多添加 $quickTagCloudTextConditionLimit 个文本条件',
        '${textConditions.length}',
      ));
    }
    if (raw.trim().isNotEmpty && terms.isEmpty && filters.isEmpty && issues.isEmpty) {
      issues.add(const QuickTagCloudSearchIssue(
        'empty_search', '请输入至少一个有效关键词或筛选条件',
      ));
    }
    return QuickTagCloudSearchPlan(
      raw: raw, terms: terms, filters: filters, issues: issues,
    );
  }

  static void _consumeStandaloneFilter(
    String value,
    Set<String> terms,
    List<QuickTagCloudSearchFilter> filters,
    List<QuickTagCloudSearchIssue> issues,
  ) {
    // A repeated website f parameter owns its entire value, including spaces.
    final source = normalizeQuickTagCloudSearchInput(value).trim();
    final colon = source.indexOf(':');
    final remainder = colon < 0 ? '' : source.substring(colon + 1).trim();
    if (remainder.startsWith('"') || remainder.startsWith("'")) {
      final tokens = _scan(source, issues);
      if (tokens.length == 1) {
        _consume(tokens.single, terms, filters, issues, strict: true);
      } else {
        issues.add(QuickTagCloudSearchIssue(
          'invalid_filter', '筛选条件应为单个“字段:值”条件', value,
        ));
      }
      return;
    }
    _consume(
      _Token(source, false, false, '', false),
      terms,
      filters,
      issues,
      strict: true,
    );
  }

  static void _consume(
    _Token token,
    Set<String> terms,
    List<QuickTagCloudSearchFilter> filters,
    List<QuickTagCloudSearchIssue> issues, {
    bool strict = false,
  }) {
    if (token.unclosed) return;
    if (token.quotedAtStart && !strict) {
      _addTerms(token, terms, issues);
      return;
    }
    final excluded = token.value.startsWith('-');
    final body = excluded ? token.value.substring(1) : token.value;
    final colon = body.indexOf(':');
    if ((token.quoted && token.quotePrefix == '-') || colon < 0) {
      if (excluded && !strict) {
        _addTextFilter('default', body, true, filters, issues);
      } else if (strict) {
        issues.add(QuickTagCloudSearchIssue(
          'invalid_filter', '筛选条件应为“字段:值”', token.value,
        ));
      } else {
        _addTerms(token, terms, issues);
      }
      return;
    }
    final rawField = body.substring(0, colon);
    final field = _aliases[normalizeQuickTagCloudSearchText(rawField)];
    if (field == null) {
      if (strict) {
        issues.add(QuickTagCloudSearchIssue(
          'unknown_filter', '未知筛选字段：$rawField', rawField,
        ));
      } else {
        // The website treats unknown prefixes in q as literal search text.
        _addTerms(token, terms, issues);
      }
      return;
    }
    _addFieldFilter(field, body.substring(colon + 1).trim(), excluded, filters, issues);
  }

  static void _addTerms(
    _Token token, Set<String> terms, List<QuickTagCloudSearchIssue> issues,
  ) {
    if (token.quoted && token.value.trim().isEmpty) {
      issues.add(const QuickTagCloudSearchIssue(
        'empty_text_condition', '搜索短语不能为空',
      ));
    }
    final values = token.quoted
        ? [token.value]
        : token.value.split(RegExp(r'[\s,，、;；]+'));
    terms.addAll(values.map(normalizeQuickTagCloudSearchText).where((v) => v.isNotEmpty));
  }

  static void _addFieldFilter(
    String field, String value, bool excluded,
    List<QuickTagCloudSearchFilter> filters, List<QuickTagCloudSearchIssue> issues,
  ) {
    if (value.isEmpty) {
      issues.add(QuickTagCloudSearchIssue('empty_filter', '筛选条件缺少值', field));
      return;
    }
    if (excluded && {'has', 'fav', 'directory'}.contains(field)) {
      issues.add(QuickTagCloudSearchIssue(
        'invalid_operator', '$field 筛选不能使用排除操作', field,
      ));
      return;
    }
    if (field == 'directory') {
      final split = value.indexOf(':');
      if (split < 1 || value.substring(split + 1).trim().isEmpty) {
        issues.add(QuickTagCloudSearchIssue(
          'empty_filter', '精确目录筛选缺少法典或目录短码', value,
        ));
        return;
      }
      _append(QuickTagCloudSearchFilter(
        field: field, value: normalizeQuickTagCloudSearchText(value.substring(split + 1)),
        codexId: value.substring(0, split).trim(),
      ), filters, issues);
      return;
    }
    if (field == 'has' || field == 'fav') {
      final map = field == 'has' ? _hasValues : _favValues;
      final boolean = map[normalizeQuickTagCloudSearchText(value)];
      if (boolean == null) {
        issues.add(QuickTagCloudSearchIssue(
          'invalid_enum', field == 'has' ? '图片筛选只能是“有图”或“无图”' : '收藏筛选只能是“已收藏”或“未收藏”', value,
        ));
        return;
      }
      value = field == 'has' ? (boolean ? 'image' : 'noimage') : '$boolean';
    } else if (field == 'type') {
      final type = _types[normalizeQuickTagCloudSearchText(value)];
      if (type == null) {
        issues.add(QuickTagCloudSearchIssue(
          'invalid_enum', '类型只能是法典、画风、构图或图包', value,
        ));
        return;
      }
      value = type;
    }
    _addTextFilter(field, value, excluded, filters, issues);
  }

  static void _addTextFilter(
    String field, String value, bool excluded,
    List<QuickTagCloudSearchFilter> filters, List<QuickTagCloudSearchIssue> issues,
  ) {
    if (value.trim().isEmpty) {
      issues.add(QuickTagCloudSearchIssue('empty_filter', '筛选条件缺少值', field));
      return;
    }
    _append(QuickTagCloudSearchFilter(
      field: field, value: value.trim(), excluded: excluded,
    ), filters, issues);
  }

  static void _append(
    QuickTagCloudSearchFilter filter, List<QuickTagCloudSearchFilter> filters,
    List<QuickTagCloudSearchIssue> issues,
  ) {
    if (filters.any((item) => item.identity == filter.identity)) return;
    final exclusive = {'has', 'fav', 'directory'}.contains(filter.field);
    if (filters.any((item) => item.field == filter.field &&
        (exclusive || item.normalizedValue == filter.normalizedValue &&
            item.excluded != filter.excluded))) {
      issues.add(QuickTagCloudSearchIssue(
        'conflicting_filter', '筛选条件存在冲突', filter.serialize(),
      ));
    }
    filters.add(filter);
  }

  static List<_Token> _scan(String raw, List<QuickTagCloudSearchIssue> issues) {
    final source = normalizeQuickTagCloudSearchInput(raw);
    final tokens = <_Token>[];
    var buffer = StringBuffer();
    var quote = '';
    var quoted = false;
    var quotedAtStart = false;
    var quotePrefix = '';
    void flush({bool unclosed = false}) {
      if (buffer.isNotEmpty || quoted) {
        tokens.add(_Token(buffer.toString(), quoted, quotedAtStart, quotePrefix, unclosed));
      }
      buffer = StringBuffer();
      quoted = false;
      quotedAtStart = false;
      quotePrefix = '';
    }
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (quote.isNotEmpty) {
        if (char == '\\' && index + 1 < source.length &&
            (source[index + 1] == quote || source[index + 1] == '\\')) {
          buffer.write(source[++index]);
        } else if (char == quote) {
          quote = '';
        } else {
          buffer.write(char);
        }
      } else if (char == '"' || char == "'") {
        if (!quoted) {
          quotedAtStart = buffer.isEmpty;
          quotePrefix = buffer.toString();
        }
        quote = char;
        quoted = true;
      } else if (RegExp(r'\s').hasMatch(char)) {
        flush();
      } else {
        buffer.write(char);
      }
    }
    flush(unclosed: quote.isNotEmpty);
    if (quote.isNotEmpty) {
      issues.add(QuickTagCloudSearchIssue('unclosed_quote', '引号没有闭合，请补全后再搜索', raw));
    }
    return tokens;
  }
}

class _Token {
  const _Token(this.value, this.quoted, this.quotedAtStart, this.quotePrefix, this.unclosed);

  final String value;
  final bool quoted;
  final bool quotedAtStart;
  final String quotePrefix;
  final bool unclosed;
}

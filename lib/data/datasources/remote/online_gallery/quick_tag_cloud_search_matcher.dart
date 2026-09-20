import 'quick_tag_cloud_gallery_repository.dart';
import 'quick_tag_cloud_search_query.dart';

/// Lazily normalized search fields for a single catalog record.
class QuickTagCloudSearchDocument {
  QuickTagCloudSearchDocument(this.record);

  final QuickTagCloudGalleryRecord record;
  final Map<String, String> _fields = {};
  Set<String>? _directoryCodes;

  bool matches(
    QuickTagCloudSearchPlan plan, {
    Set<String> favoriteKeys = const {},
  }) => matchQuickTagCloudSearchPlan(
    plan,
    fieldText: field,
    hasImage: record.entry.hasImage,
    isFavorite: favoriteKeys.contains('quick_tag_cloud:${record.workId}'),
    matchesDirectory: _matchesDirectory,
  );

  /// Lower tiers rank first. Callers preserve catalog order within each tier.
  int relevanceTier(QuickTagCloudSearchPlan plan) {
    if (plan.terms.isEmpty) return 0;
    final title = field('title');
    if (title == plan.text) return 0;
    if (title.startsWith(plan.text)) return 1;
    if (plan.terms.every(title.contains)) return 2;
    final prompt = field('prompt');
    if (plan.terms.any(title.contains) &&
        plan.terms.any(prompt.contains) &&
        plan.terms.every(
          (term) => title.contains(term) || prompt.contains(term),
        )) {
      return 3;
    }
    if (plan.terms.every(prompt.contains)) return 4;
    return 5;
  }

  String field(String name) {
    final cached = _fields[name];
    if (cached != null) return cached;
    final raw = _buildField(name);
    final value = name == 'default'
        ? raw.split('\n').map(normalizeQuickTagCloudSearchText).join('\n')
        : normalizeQuickTagCloudSearchText(raw);
    _fields[name] = value;
    return value;
  }

  String _buildField(String name) {
    final entry = record.entry;
    final codex = record.codex;
    switch (name) {
      case 'title':
        return entry.title;
      case 'prompt':
        return [
          entry.tags,
          ...entry.characterPrompts.map((item) => item.prompt),
        ].join('\n');
      case 'negative':
        return [
          entry.negative,
          ...entry.characterPrompts.map((item) => item.negative),
        ].join('\n');
      case 'note':
        return entry.note;
      case 'raw':
        return [
          entry.rawTag,
          _raw(entry.raw, 'rawTags'),
          for (final image in entry.images) ...[
            image.rawTag,
            _raw(image.raw, 'rawTags'),
          ],
        ].join('\n');
      case 'path':
        return entry.path.join('/');
      case 'author':
        return [
          codex.author,
          codex.source,
          entry.author,
          entry.credit,
          for (final image in entry.images) ...[
            _raw(image.raw, 'author'),
            _raw(image.raw, 'credit'),
          ],
          ...record.meta.contributors.map(
            (item) => '${item.name} ${item.role}',
          ),
        ].join('\n');
      case 'codex':
        return [codex.id, codex.title, ...codex.aliases].join('\n');
      case 'type':
        return codex.type;
      case 'default':
        // Preserve native metadata recall while using website AND/field syntax.
        return [
          for (final key in [
            'title',
            'prompt',
            'negative',
            'note',
            'raw',
            'path',
            'author',
            'codex',
            'type',
          ])
            field(key),
          entry.rating,
          entry.path.join(' '),
          entry.updateBatches.join(' '),
          ...entry.characterPrompts.map((item) => item.label),
          _raw(entry.raw, 'author'),
          _raw(entry.raw, 'credit'),
          _raw(entry.raw, 'type'),
          codex.version,
          ...record.meta.links.map((item) => '${item.label} ${item.url}'),
        ].join('\n');
      default:
        return '';
    }
  }

  bool _matchesDirectory(QuickTagCloudSearchFilter filter) {
    if (normalizeQuickTagCloudSearchText(record.codex.id) !=
        normalizeQuickTagCloudSearchText(filter.codexId)) {
      return false;
    }
    final codes = _directoryCodes ??= {
      for (var length = 1; length <= record.entry.path.length; length++)
        quickTagCloudDirectoryCode(record.entry.path.take(length)),
    };
    return codes.contains(filter.normalizedValue);
  }

  static String _raw(Map<String, dynamic> raw, String key) {
    final value = raw[key];
    return value is Iterable ? value.join(' ') : value?.toString() ?? '';
  }
}

/// Shared predicate for live source records and offline favorite snapshots.
bool matchQuickTagCloudSearchPlan(
  QuickTagCloudSearchPlan plan, {
  required String Function(String) fieldText,
  required bool hasImage,
  required bool isFavorite,
  required bool Function(QuickTagCloudSearchFilter) matchesDirectory,
}) {
  if (plan.hasErrors) return false;
  if (plan.terms.isNotEmpty &&
      !plan.terms.every(fieldText('default').contains)) {
    return false;
  }
  return plan.filters.every((filter) {
    if (filter.field == 'has') return hasImage == filter.booleanValue;
    if (filter.field == 'fav') return isFavorite == filter.booleanValue;
    if (filter.field == 'directory') return matchesDirectory(filter);
    final contains = fieldText(filter.field).contains(filter.normalizedValue);
    return filter.excluded ? !contains : contains;
  });
}

/// Website-compatible UTF-16 FNV-1a directory short code, including ancestors.
String quickTagCloudDirectoryCode(Iterable<String> path) {
  final segments = path
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty);
  final text = segments.join('\u001f');
  if (text.isEmpty) return '';
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    for (final byte in [unit & 0xff, (unit >> 8) & 0xff]) {
      hash ^= byte;
      // Shift/add keeps the 32-bit result exact on Dart VM and web targets.
      hash =
          (hash +
              (hash << 1) +
              (hash << 4) +
              (hash << 7) +
              (hash << 8) +
              (hash << 24)) &
          0xffffffff;
    }
  }
  return hash.toRadixString(36);
}

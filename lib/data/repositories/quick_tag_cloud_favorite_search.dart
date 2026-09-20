import '../datasources/remote/online_gallery/quick_tag_cloud_search_matcher.dart';
import '../datasources/remote/online_gallery/quick_tag_cloud_search_parser.dart';
import '../models/online_gallery/gallery_item.dart';
import '../models/online_gallery/online_gallery_favorite_record.dart';

/// Applies the same native grammar to persisted Hive favorites, without I/O.
class QuickTagCloudFavoriteSearch {
  QuickTagCloudFavoriteSearch(String query)
    : plan = QuickTagCloudSearchParser.parse(query) {
    if (plan.hasErrors) throw QuickTagCloudSearchException(plan.issues);
  }

  final QuickTagCloudSearchPlan plan;

  bool matches(OnlineGalleryFavoriteRecord record) {
    final document = _FavoriteDocument(record.detail);
    return matchQuickTagCloudSearchPlan(
      plan,
      fieldText: document.field,
      hasImage: record.detail.media.any(
        (media) => media.previewUrl.isNotEmpty || media.displayUrl.isNotEmpty,
      ),
      isFavorite: true,
      matchesDirectory: document.matchesDirectory,
    );
  }
}

class _FavoriteDocument {
  _FavoriteDocument(this.detail);

  final GalleryDetail detail;
  final Map<String, String> _fields = {};
  late final metadata = {
    ...detail.item.rawSourceMetadata,
    ...detail.rawSourceMetadata,
  };
  late final Map<dynamic, dynamic> entry = metadata['entry'] is Map
      ? metadata['entry'] as Map
      : const {};

  String get codexId {
    final explicit = _text(metadata['codexId']);
    if (explicit.isNotEmpty) return explicit;
    final parts = detail.item.sourceWorkId.split('/');
    if (parts.length != 2) return '';
    try {
      return Uri.decodeComponent(parts.first);
    } on FormatException {
      return '';
    }
  }

  String field(String name) {
    final cached = _fields[name];
    if (cached != null) return cached;
    final raw = _rawField(name);
    final normalized = name == 'default'
        ? raw.split('\n').map(normalizeQuickTagCloudSearchText).join('\n')
        : normalizeQuickTagCloudSearchText(raw);
    _fields[name] = normalized;
    return normalized;
  }

  String _rawField(String name) {
    final item = detail.item;
    switch (name) {
      case 'title':
        return item.title ?? _text(entry['title']);
      case 'prompt':
        return [
          detail.prompt ?? item.tagString,
          ...detail.characterPrompts.map((character) => character.prompt),
        ].join('\n');
      case 'negative':
        return [
          detail.negativePrompt ?? _text(entry['negative']),
          ...detail.characterPrompts.map(
            (character) => character.negativePrompt,
          ),
        ].join('\n');
      case 'note':
        return detail.note ?? detail.description ?? _text(entry['note']);
      case 'path':
        return detail.categoryPath.join('/');
      case 'raw':
        return [
          ...detail.rawTags,
          _text(entry['rawTag']),
          _text(entry['rawTags']),
          for (final media in detail.media) ...[
            media.rawMetadata ?? '',
            _text(media.metadata['rawTag']),
            _text(media.metadata['rawTags']),
          ],
        ].join('\n');
      case 'author':
        return [
          item.author ?? '',
          for (final key in [
            'codexAuthor',
            'declaredSource',
            'entryAuthor',
            'entryCredit',
          ])
            _text(metadata[key]),
          _text(entry['author']),
          _text(entry['credit']),
          ...detail.contributors.map(
            (person) => '${person.name} ${person.role}',
          ),
          for (final media in detail.media) ...[
            _text(media.metadata['author']),
            _text(media.metadata['credit']),
          ],
        ].join('\n');
      case 'codex':
        return [
          codexId,
          _text(metadata['codexTitle']),
          _text(metadata['codexAliases']),
        ].join('\n');
      case 'type':
        // Older snapshots did not store this field; an unknown type stays empty.
        return _text(metadata['codexType']);
      case 'default':
        return [
          for (final fieldName in quickTagCloudTextFields)
            if (fieldName != 'default') field(fieldName),
          item.description ?? '',
          item.aiType ?? '',
          item.source,
          item.rating ?? '',
          item.tags.join(' '),
          item.tagStringGeneral,
          item.tagStringCharacter,
          item.tagStringCopyright,
          item.tagStringArtist,
          item.tagStringMeta,
          detail.categoryPath.join(' '),
          _text(metadata['codexVersion']),
          _text(entry['updateBatches']),
          ...detail.characterPrompts.map((character) => character.label),
        ].join('\n');
      default:
        return '';
    }
  }

  bool matchesDirectory(QuickTagCloudSearchFilter filter) {
    if (normalizeQuickTagCloudSearchText(codexId) !=
        normalizeQuickTagCloudSearchText(filter.codexId)) {
      return false;
    }
    for (var length = 1; length <= detail.categoryPath.length; length++) {
      if (quickTagCloudDirectoryCode(detail.categoryPath.take(length)) ==
          filter.normalizedValue) {
        return true;
      }
    }
    return false;
  }

  static String _text(Object? value) =>
      value is Iterable ? value.join(' ') : value?.toString() ?? '';
}

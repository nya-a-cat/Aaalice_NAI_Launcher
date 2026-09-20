import 'dart:async';

import 'package:hive/hive.dart';

import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../models/online_gallery/gallery_item.dart';
import '../models/online_gallery/gallery_source.dart';
import '../models/online_gallery/online_gallery_favorite_record.dart';
import 'online_gallery_favorites_replacement.dart';
import 'quick_tag_cloud_favorite_search.dart';
import 'quick_tag_cloud_favorites_migration.dart';

export 'online_gallery_favorites_replacement.dart'
    show
        OnlineGalleryFavoritesConflictException,
        OnlineGalleryFavoritesReplacementException;

class OnlineGalleryFavoriteQuery {
  const OnlineGalleryFavoriteQuery({
    this.sourceId,
    this.searchText = '',
    this.ratings = const {},
    this.blacklistTags = const {},
    this.codexId,
    this.categoryPath = const [],
    this.mediaFilter = 'all',
    this.offset = 0,
    this.limit = 50,
  }) : assert(offset >= 0),
       assert(limit > 0);

  final GallerySourceId? sourceId;
  final String searchText;
  final Set<String> ratings;
  final Set<String> blacklistTags;
  final String? codexId;
  final List<String> categoryPath;
  final String mediaFilter;
  final int offset;
  final int limit;
}

class OnlineGalleryFavoritePage {
  const OnlineGalleryFavoritePage({
    required this.records,
    required this.total,
    required this.offset,
    required this.limit,
  });

  final List<OnlineGalleryFavoriteRecord> records;
  final int total;
  final int offset;
  final int limit;

  List<GalleryDetail> get details =>
      records.map((record) => record.detail).toList(growable: false);
  List<GalleryItem> get items =>
      records.map((record) => record.item).toList(growable: false);
  bool get hasMore => offset + records.length < total;
  int? get nextOffset => hasMore ? offset + records.length : null;
}

/// Hive-backed source-neutral local favorites store.
///
/// Every favorite is persisted under its own stable key. The in-memory map is
/// only updated after Hive confirms the write, so failed writes never appear
/// successful to callers.
class OnlineGalleryLocalFavoritesRepository {
  OnlineGalleryLocalFavoritesRepository({
    required Box<dynamic> box,
    required LocalStorageService legacyStorage,
  }) : _box = box,
       _legacyStorage = legacyStorage;

  static const String quickTagCloudMigrationMarkerKey =
      QuickTagCloudFavoritesMigration.markerKey;

  final Box<dynamic> _box;
  final LocalStorageService _legacyStorage;
  final Map<String, OnlineGalleryFavoriteRecord> _records = {};
  final List<String> _sortedKeys = [];
  final Map<GallerySourceId, List<String>> _sortedKeysBySource = {};
  Future<void>? _initialization;

  bool get isInitialized => _initialization != null && _recordsLoaded;
  bool _recordsLoaded = false;
  int get count => _records.length;
  Set<String> get stableKeys => Set.unmodifiable(_records.keys);

  Future<void> ensureInitialized() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });

  Future<void> _initialize() =>
      OnlineGalleryFavoritesReplacement.serialize(_box, _loadRecords);

  Future<void> _loadRecords() async {
    await OnlineGalleryFavoritesReplacement.recoverPending(_box);
    await QuickTagCloudFavoritesMigration(_box, _legacyStorage).run();
    final loaded = <String, OnlineGalleryFavoriteRecord>{};
    for (final entry in _box.toMap().entries) {
      final key = entry.key.toString();
      if (key == quickTagCloudMigrationMarkerKey ||
          OnlineGalleryFavoritesReplacement.isReplacementIdKey(key)) {
        continue;
      }
      try {
        if (entry.value is! Map) {
          throw const FormatException('Favorite record is not a map');
        }
        final record = OnlineGalleryFavoriteRecord.fromMap(
          entry.value as Map<dynamic, dynamic>,
        );
        if (record.stableKey != key) {
          throw const FormatException('Hive key does not match stable key');
        }
        loaded[key] = record;
      } catch (error, stack) {
        AppLogger.w(
          'Ignored damaged online gallery favorite "$key": $error\n$stack',
          'OnlineGalleryFavorites',
        );
      }
    }
    _records
      ..clear()
      ..addAll(loaded);
    _rebuildIndexes();
    _recordsLoaded = true;
  }

  bool contains(String stableKey) => _records.containsKey(stableKey);

  OnlineGalleryFavoriteRecord? getByStableKey(String stableKey) =>
      _records[stableKey];

  /// Commit identifier of this source's last completed replacement.
  /// Ordinary favorite writes retain it; replacements without an ID clear it.
  String? lastSourceReplacementId(GallerySourceId sourceId) =>
      OnlineGalleryFavoritesReplacement.lastReplacementId(_box, sourceId);

  OnlineGalleryFavoritePage query(OnlineGalleryFavoriteQuery query) {
    if (!_recordsLoaded) {
      throw StateError('Online gallery favorites are not initialized');
    }
    if (query.offset < 0) {
      throw RangeError.range(query.offset, 0, null, 'offset');
    }
    if (query.limit <= 0) {
      throw RangeError.range(query.limit, 1, null, 'limit');
    }
    final ratings = query.ratings.map((value) => value.toLowerCase()).toSet();
    final blacklist = query.blacklistTags
        .map(_normalizeTag)
        .where((value) => value.isNotEmpty)
        .toSet();
    final nativeSearch = query.sourceId == GallerySourceId.quickTagCloud
        ? QuickTagCloudFavoriteSearch(query.searchText)
        : null;
    final terms = (nativeSearch == null ? query.searchText : '')
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final candidateKeys = query.sourceId == null
        ? _sortedKeys
        : (_sortedKeysBySource[query.sourceId!] ?? const <String>[]);
    final restrictsRatings =
        ratings.isNotEmpty && !ratings.containsAll(const {'g', 's', 'q', 'e'});
    final hasFilters =
        restrictsRatings ||
        blacklist.isNotEmpty ||
        (nativeSearch?.plan.hasActiveSearch ?? false) ||
        terms.isNotEmpty ||
        (query.codexId != null && query.codexId != 'all') ||
        query.categoryPath.isNotEmpty ||
        query.mediaFilter != 'all';
    if (!hasFilters) {
      final start = query.offset.clamp(0, candidateKeys.length);
      final end = (start + query.limit).clamp(start, candidateKeys.length);
      return OnlineGalleryFavoritePage(
        records: List.unmodifiable(
          candidateKeys.sublist(start, end).map((key) => _records[key]!),
        ),
        total: candidateKeys.length,
        offset: query.offset,
        limit: query.limit,
      );
    }
    final matches = candidateKeys.map((key) => _records[key]!).where((record) {
      if (query.sourceId != null && record.sourceId != query.sourceId) {
        return false;
      }
      if (query.codexId != null &&
          query.codexId != 'all' &&
          record.detail.rawSourceMetadata['codexId'] != query.codexId) {
        return false;
      }
      if (query.categoryPath.isNotEmpty) {
        final recordPath = record.detail.categoryPath;
        if (recordPath.length < query.categoryPath.length) return false;
        for (var index = 0; index < query.categoryPath.length; index++) {
          if (recordPath[index] != query.categoryPath[index]) {
            return false;
          }
        }
      }
      final hasMedia = record.detail.media.any(
        (media) => media.previewUrl.isNotEmpty || media.displayUrl.isNotEmpty,
      );
      if (query.mediaFilter == 'withImages' && !hasMedia) return false;
      if (query.mediaFilter == 'withoutImages' && hasMedia) {
        return false;
      }
      final rating = record.item.rating?.toLowerCase() ?? '';
      if (restrictsRatings && !ratings.contains(rating)) return false;
      if (blacklist.isNotEmpty && _recordTags(record).any(blacklist.contains)) {
        return false;
      }
      if (nativeSearch != null && !nativeSearch.matches(record)) return false;
      if (terms.isNotEmpty) {
        final haystack = _searchHaystack(record);
        if (!terms.every(haystack.contains)) return false;
      }
      return true;
    });
    var total = 0;
    final pageRecords = <OnlineGalleryFavoriteRecord>[];
    for (final record in matches) {
      if (total >= query.offset && pageRecords.length < query.limit) {
        pageRecords.add(record);
      }
      total++;
    }
    return OnlineGalleryFavoritePage(
      records: List.unmodifiable(pageRecords),
      total: total,
      offset: query.offset,
      limit: query.limit,
    );
  }

  Future<bool> toggle(GalleryDetail detail, {DateTime? savedAt}) async {
    await ensureInitialized();
    return _runSerialized(() async {
      final key = detail.item.stableKey;
      if (_records.containsKey(key)) {
        await _box.delete(key);
        _removeFromMemory(key);
        return false;
      }
      final record = OnlineGalleryFavoriteRecord.fromDetail(
        detail,
        savedAt: savedAt,
      );
      await _box.put(key, record.toMap());
      _upsertInMemory(record);
      return true;
    });
  }

  Future<void> upsert(GalleryDetail detail, {DateTime? savedAt}) async {
    await ensureInitialized();
    await _runSerialized(() async {
      final record = OnlineGalleryFavoriteRecord.fromDetail(
        detail,
        savedAt: savedAt,
      );
      await _box.put(record.stableKey, record.toMap());
      _upsertInMemory(record);
    });
  }

  Future<int> upsertAll(
    Iterable<GalleryDetail> details, {
    DateTime? savedAt,
  }) async {
    await ensureInitialized();
    return _runSerialized(() async {
      final records = <String, OnlineGalleryFavoriteRecord>{};
      var index = 0;
      final baseTime = (savedAt ?? DateTime.now()).toUtc();
      for (final detail in details) {
        final record = OnlineGalleryFavoriteRecord.fromDetail(
          detail,
          savedAt: baseTime.add(Duration(microseconds: index++)),
        );
        records[record.stableKey] = record;
      }
      if (records.isEmpty) return 0;
      await _box.putAll({
        for (final entry in records.entries) entry.key: entry.value.toMap(),
      });
      _records.addAll(records);
      _rebuildIndexes();
      return records.length;
    });
  }

  Future<bool> remove(String stableKey) async {
    await ensureInitialized();
    return _runSerialized(() async {
      if (!_records.containsKey(stableKey)) return false;
      await _box.delete(stableKey);
      _removeFromMemory(stableKey);
      return true;
    });
  }

  /// Replaces one source while preserving each record's original saved time.
  ///
  /// [expectedRecords] is compared by complete serialized value after queued
  /// writes finish. A mismatch throws [OnlineGalleryFavoritesConflictException]
  /// before persistence. Invalid identities, sources, or duplicate keys throw
  /// [FormatException]. Persistence errors roll back through a local journal;
  /// [OnlineGalleryFavoritesReplacementException.recoveryRequired] indicates
  /// that a fresh repository must recover it before further writes.
  /// [replacementId] is persisted with the records as a source-scoped commit
  /// identifier; ordinary favorite edits leave that identifier unchanged.
  Future<void> replaceSourceRecords(
    GallerySourceId sourceId,
    Iterable<OnlineGalleryFavoriteRecord> records, {
    Iterable<OnlineGalleryFavoriteRecord>? expectedRecords,
    String? replacementId,
  }) async {
    if (replacementId != null && replacementId.trim().isEmpty) {
      throw ArgumentError.value(
        replacementId,
        'replacementId',
        'Must not be empty',
      );
    }
    final next = OnlineGalleryFavoritesReplacement.validate(sourceId, records);
    final expected = expectedRecords == null
        ? null
        : OnlineGalleryFavoritesReplacement.validate(sourceId, expectedRecords);
    await ensureInitialized();
    await _runSerialized(() async {
      final previous = OnlineGalleryFavoritesReplacement.readSource(
        _box,
        sourceId,
      );
      if (expected != null &&
          !OnlineGalleryFavoritesReplacement.matches(previous, expected)) {
        throw const OnlineGalleryFavoritesConflictException();
      }
      await OnlineGalleryFavoritesReplacement.persist(
        box: _box,
        sourceId: sourceId,
        previous: previous,
        next: next,
        replacementId: replacementId,
      );
      _records.removeWhere((_, record) => record.sourceId == sourceId);
      _records.addAll(next);
      _rebuildIndexes();
    });
  }

  void _rebuildIndexes() {
    _sortedKeys
      ..clear()
      ..addAll(_records.keys)
      ..sort(_compareRecordKeys);
    _sortedKeysBySource.clear();
    for (final key in _sortedKeys) {
      final sourceId = _records[key]!.sourceId;
      (_sortedKeysBySource[sourceId] ??= <String>[]).add(key);
    }
  }

  void _upsertInMemory(OnlineGalleryFavoriteRecord record) {
    _removeFromMemory(record.stableKey);
    _records[record.stableKey] = record;
    _insertSorted(_sortedKeys, record.stableKey);
    _insertSorted(
      _sortedKeysBySource.putIfAbsent(record.sourceId, () => <String>[]),
      record.stableKey,
    );
  }

  void _removeFromMemory(String stableKey) {
    final previous = _records.remove(stableKey);
    if (previous == null) return;
    _sortedKeys.remove(stableKey);
    final sourceKeys = _sortedKeysBySource[previous.sourceId];
    sourceKeys?.remove(stableKey);
    if (sourceKeys?.isEmpty == true) {
      _sortedKeysBySource.remove(previous.sourceId);
    }
  }

  void _insertSorted(List<String> keys, String key) {
    var low = 0;
    var high = keys.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_compareRecordKeys(key, keys[middle]) < 0) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    keys.insert(low, key);
  }

  int _compareRecordKeys(String leftKey, String rightKey) {
    final left = _records[leftKey]!;
    final right = _records[rightKey]!;
    final savedOrder = right.savedAt.compareTo(left.savedAt);
    return savedOrder != 0 ? savedOrder : leftKey.compareTo(rightKey);
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) =>
      OnlineGalleryFavoritesReplacement.serialize(_box, () async {
        if (_box.isOpen &&
            _box.containsKey(OnlineGalleryFavoritesReplacement.journalKey)) {
          throw StateError(
            'Pending favorite replacement journal needs recovery',
          );
        }
        return operation();
      });
}

Set<String> _recordTags(OnlineGalleryFavoriteRecord record) {
  final item = record.item;
  final values = <String>{
    ...item.tags,
    ...item.generalTags,
    ...item.characterTags,
    ...item.copyrightTags,
    ...item.artistTags,
    ...item.metaTags,
    ...record.detail.rawTags,
  };
  return values.map(_normalizeTag).where((value) => value.isNotEmpty).toSet();
}

String _normalizeTag(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

String _searchHaystack(OnlineGalleryFavoriteRecord record) {
  final item = record.item;
  final detail = record.detail;
  return [
    item.title,
    item.author,
    item.description,
    item.aiType,
    item.source,
    item.rating,
    item.tags.join(' '),
    item.tagStringGeneral,
    item.tagStringCharacter,
    item.tagStringCopyright,
    item.tagStringArtist,
    item.tagStringMeta,
    detail.prompt,
    detail.negativePrompt,
    detail.description,
    detail.categoryPath.join(' '),
    detail.note,
    detail.rawTags.join(' '),
    detail.characterPrompts
        .map(
          (value) => '${value.label} ${value.prompt} ${value.negativePrompt}',
        )
        .join(' '),
    detail.contributors.map((value) => '${value.name} ${value.role}').join(' '),
  ].whereType<String>().join('\n').toLowerCase().replaceAll('_', ' ');
}

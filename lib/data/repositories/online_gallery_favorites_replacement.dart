import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import '../models/online_gallery/gallery_source.dart';
import '../models/online_gallery/online_gallery_favorite_record.dart';

/// The source changed after the caller captured its import preview.
class OnlineGalleryFavoritesConflictException implements Exception {
  const OnlineGalleryFavoritesConflictException();

  @override
  String toString() => 'Favorites changed after the restore preview';
}

/// A replacement failed. A non-null [rollbackError] requires journal recovery
/// before any further writes; a fresh repository retries that recovery.
class OnlineGalleryFavoritesReplacementException implements Exception {
  const OnlineGalleryFavoritesReplacementException({
    required this.cause,
    this.rollbackError,
  });

  final Object cause;
  final Object? rollbackError;
  bool get recoveryRequired => rollbackError != null;

  @override
  String toString() => recoveryRequired
      ? 'Favorite restore failed; pending journal recovery is required'
      : 'Favorite restore failed; previous favorites were restored';
}

/// Validates source snapshots and coordinates recoverable Hive writes.
///
/// Hive operations remain separate. The journal records the previous state so
/// initialization can roll back a write interrupted before journal removal.
class OnlineGalleryFavoritesReplacement {
  OnlineGalleryFavoritesReplacement._();

  static const journalKey = '__online_gallery_favorites_replacement_v1__';
  static const _replacementIdPrefix = '__online_gallery_source_replacement_v1__:';
  static const _equality = DeepCollectionEquality();
  static final _writeTails = Expando<Future<void>>();

  static String replacementIdKey(GallerySourceId sourceId) =>
      '$_replacementIdPrefix${sourceId.key}';

  static bool isReplacementIdKey(String key) =>
      GallerySourceId.values.any((source) => key == replacementIdKey(source));

  static String? lastReplacementId(Box<dynamic> box, GallerySourceId sourceId) {
    final journal = box.get(journalKey);
    final value = journal is Map && journal['sourceId'] == sourceId.key
        ? journal['previousReplacementId']
        : box.get(replacementIdKey(sourceId));
    if (value == null || value is String) return value as String?;
    throw const FormatException('Invalid source replacement identifier');
  }

  /// Serializes initialization and repository writes sharing the same Hive box.
  static Future<T> serialize<T>(Box<dynamic> box, Future<T> Function() action) {
    final result = (_writeTails[box] ?? Future<void>.value()).then((_) => action());
    _writeTails[box] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  static Map<String, OnlineGalleryFavoriteRecord> readSource(
    Box<dynamic> box,
    GallerySourceId sourceId,
  ) {
    final records = <OnlineGalleryFavoriteRecord>[];
    for (final entry in box.toMap().entries) {
      if (entry.key is! String ||
          !(entry.key as String).startsWith('${sourceId.key}:')) {
        continue;
      }
      final value = entry.value;
      if (value is! Map) {
        throw const FormatException('Invalid persisted source favorite');
      }
      final record = OnlineGalleryFavoriteRecord.fromMap(value);
      if (record.stableKey != entry.key) {
        throw const FormatException('Persisted favorite key mismatch');
      }
      records.add(record);
    }
    return validate(sourceId, records);
  }

  static Map<String, OnlineGalleryFavoriteRecord> validate(
    GallerySourceId sourceId,
    Iterable<OnlineGalleryFavoriteRecord> records,
  ) {
    final result = <String, OnlineGalleryFavoriteRecord>{};
    for (final record in records) {
      // JSON round-trip detaches nested mutable metadata from caller state.
      final map = jsonDecode(jsonEncode(record.toMap())) as Map;
      final validated = OnlineGalleryFavoriteRecord.fromMap(map);
      if (validated.sourceId != sourceId) {
        throw const FormatException('Favorite belongs to another source');
      }
      if (result.containsKey(validated.stableKey)) {
        throw const FormatException('Duplicate favorite stable key');
      }
      result[validated.stableKey] = validated;
    }
    return result;
  }

  static bool matches(
    Map<String, OnlineGalleryFavoriteRecord> left,
    Map<String, OnlineGalleryFavoriteRecord> right,
  ) => _equality.equals(_serialize(left), _serialize(right));

  static Future<void> persist({
    required Box<dynamic> box,
    required GallerySourceId sourceId,
    required Map<String, OnlineGalleryFavoriteRecord> previous,
    required Map<String, OnlineGalleryFavoriteRecord> next,
    String? replacementId,
  }) async {
    final idKey = replacementIdKey(sourceId);
    final journal = <String, dynamic>{
      'version': 1,
      'sourceId': sourceId.key,
      'previous': _serialize(previous),
      'newKeys': next.keys.where((key) => !previous.containsKey(key)).toList(),
      'hadReplacementId': box.containsKey(idKey),
      'previousReplacementId': lastReplacementId(box, sourceId),
    };
    try {
      await box.put(journalKey, journal);
      await box.putAll({..._serialize(next), idKey: replacementId});
      final removed = previous.keys.where((key) => !next.containsKey(key));
      if (removed.isNotEmpty) await box.deleteAll(removed);
      await box.delete(journalKey);
    } catch (error, stack) {
      Object? rollbackError;
      try {
        // Re-establish the journal if its final deletion applied before failing.
        await box.put(journalKey, journal);
        await _restore(box, journal);
      } catch (failure) {
        rollbackError = failure;
      }
      Error.throwWithStackTrace(
        OnlineGalleryFavoritesReplacementException(
          cause: error,
          rollbackError: rollbackError,
        ),
        stack,
      );
    }
  }

  static Future<void> recoverPending(Box<dynamic> box) async {
    final journal = box.get(journalKey);
    if (journal == null) return;
    if (journal is! Map) {
      throw const FormatException('Invalid favorite replacement journal');
    }
    await _restore(box, journal);
  }

  static Future<void> _restore(Box<dynamic> box, Map journal) async {
    final sourceId = GallerySourceId.values.cast<GallerySourceId?>().firstWhere(
      (source) => source?.key == journal['sourceId'],
      orElse: () => null,
    );
    final rawPrevious = journal['previous'];
    final rawNewKeys = journal['newKeys'];
    final hadReplacementId = journal['hadReplacementId'] ?? false;
    final previousReplacementId = journal['previousReplacementId'];
    if (journal['version'] != 1 ||
        sourceId == null ||
        rawPrevious is! Map ||
        rawNewKeys is! List ||
        hadReplacementId is! bool ||
        (previousReplacementId != null && previousReplacementId is! String)) {
      throw const FormatException('Invalid favorite replacement journal');
    }
    final previous = validate(sourceId, [
      for (final entry in rawPrevious.entries) _journalRecord(entry),
    ]);
    final newKeys = <String>[];
    for (final key in rawNewKeys) {
      if (key is! String ||
          !key.startsWith('${sourceId.key}:') ||
          key.length <= sourceId.key.length + 1 ||
          previous.containsKey(key)) {
        throw const FormatException('Invalid replacement journal key');
      }
      newKeys.add(key);
    }
    // Validate the complete journal before touching persisted favorites.
    final idKey = replacementIdKey(sourceId);
    final writes = {
      ..._serialize(previous),
      if (hadReplacementId) idKey: previousReplacementId,
    };
    if (writes.isNotEmpty) await box.putAll(writes);
    if (!hadReplacementId) newKeys.add(idKey);
    if (newKeys.isNotEmpty) await box.deleteAll(newKeys);
    await box.delete(journalKey);
  }

  static OnlineGalleryFavoriteRecord _journalRecord(MapEntry entry) {
    final value = entry.value;
    if (value is! Map) {
      throw const FormatException('Invalid replacement journal record');
    }
    final record = OnlineGalleryFavoriteRecord.fromMap(value);
    if (record.stableKey != entry.key) {
      throw const FormatException('Invalid replacement journal identity');
    }
    return record;
  }

  static Map<String, dynamic> _serialize(
    Map<String, OnlineGalleryFavoriteRecord> records,
  ) => {for (final entry in records.entries) entry.key: entry.value.toMap()};
}

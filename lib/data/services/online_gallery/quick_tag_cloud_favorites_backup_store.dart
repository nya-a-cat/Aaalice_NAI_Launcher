import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/local_storage_service.dart';
import '../../models/online_gallery/gallery_item.dart';
import '../../models/online_gallery/gallery_source.dart';
import '../../models/online_gallery/online_gallery_favorite_record.dart';
import '../../repositories/online_gallery_local_favorites_repository.dart';
import 'quick_tag_cloud_favorites_backup_codec.dart';
import 'quick_tag_cloud_favorites_backup_plan.dart';

typedef QuickTagCloudBackupEntryResolver = Future<GalleryDetail?> Function(
  String codexId, String entryId, CancelToken token,
);

typedef QuickTagCloudBackupCommunityResolver = Future<GalleryDetail?> Function(
  String entryId, CancelToken token,
);

class QuickTagCloudBackupPreview {
  QuickTagCloudBackupPreview({
    required this.previousRaw, required this.current,
    required this.incoming, required this.currentRecords,
    required this.mappings, required this.resolved,
  });
  final String? previousRaw;
  final Map<String, dynamic> current, incoming;
  final List<OnlineGalleryFavoriteRecord> currentRecords;
  final Map<String, String> mappings;
  final Map<String, OnlineGalleryFavoriteRecord> resolved;

  QuickTagCloudBackupPlan plan({required bool replace}) =>
      QuickTagCloudBackupPlan.create(current, incoming, replace: replace);

  Map<String, String> nextMappings(QuickTagCloudBackupPlan plan) {
    final keys = QuickTagCloudBackupPlan.keys(plan.document);
    return {
      for (final pair in mappings.entries)
        if (keys.contains(pair.key)) pair.key: pair.value,
      for (final pair in resolved.entries)
        if (keys.contains(pair.key)) pair.key: pair.value.stableKey,
    };
  }

  List<OnlineGalleryFavoriteRecord> records(QuickTagCloudBackupPlan plan) {
    final all = <String, OnlineGalleryFavoriteRecord>{
      for (final record in resolved.values) record.stableKey: record,
      // Preserve locally saved details/timestamps for existing identities.
      for (final record in currentRecords) record.stableKey: record,
    };
    final keys = nextMappings(plan).values.toSet();
    return [for (final key in keys) if (all[key] != null) all[key]!];
  }

  int mapped(QuickTagCloudBackupPlan plan) => nextMappings(plan).length;
}

/// Stores website-only metadata separately from the shared native favorites.
/// A small metadata journal repairs the cross-box handoff after interruption.
class QuickTagCloudFavoritesBackupStore {
  QuickTagCloudFavoritesBackupStore(this.storage, this.repository);
  static const storageKey = 'quick_tag_cloud_favorites_backup_library_v2';
  static const journalKey = 'quick_tag_cloud_favorites_backup_pending_v1';
  static Future<void> _tail = Future<void>.value();
  final LocalStorageService storage;
  final OnlineGalleryLocalFavoritesRepository repository;

  List<OnlineGalleryFavoriteRecord> _records() => repository.query(
    const OnlineGalleryFavoriteQuery(
      sourceId: GallerySourceId.quickTagCloud, limit: 30001,
    ),
  ).records;

  Future<QuickTagCloudBackupPreview> prepare(
    String text, {
    required QuickTagCloudBackupEntryResolver resolve,
    required CancelToken cancelToken,
    QuickTagCloudBackupCommunityResolver? resolveCommunity,
  }) async {
    final incoming = await QuickTagCloudFavoritesBackupCodec.decode(text);
    final current = await snapshot();
    final resolved = <String, OnlineGalleryFavoriteRecord>{};
    var index = 0;
    final visited = <String>{};
    for (final item in QuickTagCloudBackupPlan.atlas(incoming)) {
      if (++index % 128 == 0) await Future<void>.delayed(Duration.zero);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final key = QuickTagCloudFavoritesBackupCodec.keyOf(item);
      if (!visited.add(key)) continue;
      final detail = await resolve(
        item['codexId'] as String, item['entryId'] as String, cancelToken,
      );
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (detail == null) continue;
      if (detail.item.sourceId != GallerySourceId.quickTagCloud) {
        throw const QuickTagCloudBackupException('invalid');
      }
      resolved[key] = OnlineGalleryFavoriteRecord.fromDetail(detail,
        savedAt: DateTime.tryParse(item['addedAt']?.toString() ?? ''),
      );
    }
    if (resolveCommunity != null) {
      for (final id in QuickTagCloudBackupPlan.community(incoming)) {
        if (++index % 128 == 0) await Future<void>.delayed(Duration.zero);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        final key = QuickTagCloudBackupPlan.communityKey(id);
        if (!visited.add(key)) continue;
        final detail = await resolveCommunity(id, cancelToken);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (detail == null) continue;
        if (detail.item.sourceId != GallerySourceId.quickTagCloud ||
            detail.item.sourceWorkId != 'community:$id') {
          throw const QuickTagCloudBackupException('invalid');
        }
        resolved[key] = OnlineGalleryFavoriteRecord.fromDetail(detail);
      }
    }
    return QuickTagCloudBackupPreview(
      previousRaw: current.previousRaw, current: current.current,
      incoming: incoming, currentRecords: current.currentRecords,
      mappings: current.mappings, resolved: resolved,
    );
  }

  Future<QuickTagCloudBackupPreview> snapshot() => _exclusive(_snapshot);

  Future<QuickTagCloudBackupPreview> _snapshot() async {
    await repository.ensureInitialized();
    await _recoverMetadata();
    final records = _records();
    final raw = storage.getSetting<String>(storageKey);
    final envelope = raw == null ? <String, dynamic>{} :
        QuickTagCloudFavoritesBackupCodec.object(jsonDecode(raw));
    final document = envelope['document'] == null
        ? QuickTagCloudFavoritesBackupCodec.empty()
        : QuickTagCloudBackupPlan.clone(
            QuickTagCloudFavoritesBackupCodec.object(envelope['document']));
    QuickTagCloudFavoritesBackupCodec.validate(document);
    final oldMappings = Map<String, String>.from(envelope['mappings'] ?? {});
    final liveKeys = records.map((r) => r.stableKey).toSet();
    final items = <String, Map<String, dynamic>>{
      for (final item in QuickTagCloudBackupPlan.atlas(document))
        if (!oldMappings.containsKey(QuickTagCloudFavoritesBackupCodec.keyOf(item)) ||
            liveKeys.contains(oldMappings[QuickTagCloudFavoritesBackupCodec.keyOf(item)]))
          QuickTagCloudFavoritesBackupCodec.keyOf(item): item,
    };
    final community = <String>{
      for (final id in QuickTagCloudBackupPlan.community(document))
        if (!oldMappings.containsKey(QuickTagCloudBackupPlan.communityKey(id)) ||
            liveKeys.contains(oldMappings[QuickTagCloudBackupPlan.communityKey(id)]))
          id,
    };
    final itemKeys = {
      ...items.keys, ...community.map(QuickTagCloudBackupPlan.communityKey),
    };
    final mappings = <String, String>{
      for (final pair in oldMappings.entries)
        if (itemKeys.contains(pair.key)) pair.key: pair.value,
    };
    _appendNativeRecords(records, items, community, mappings);
    document['favorites']['atlas'] = items.values.toList();
    document['favorites']['community'] = community.toList();
    if (document['memberships'] is List) {
      document['memberships'] = (document['memberships'] as List)
          .where((m) => items.containsKey(m['itemKey'])).toList();
    }
    QuickTagCloudFavoritesBackupCodec.encode(document);
    return QuickTagCloudBackupPreview(
      previousRaw: raw, current: document,
      incoming: QuickTagCloudFavoritesBackupCodec.empty(),
      currentRecords: records, mappings: mappings, resolved: {},
    );
  }

  void _appendNativeRecords(
    List<OnlineGalleryFavoriteRecord> records,
    Map<String, Map<String, dynamic>> items,
    Set<String> community,
    Map<String, String> mappings,
  ) {
    final mappedNativeKeys = mappings.values.toSet();
    for (final record in records) {
      if (mappedNativeKeys.contains(record.stableKey)) continue;
      if (record.sourceWorkId.startsWith('community:')) {
        final id = record.sourceWorkId.substring('community:'.length);
        QuickTagCloudFavoritesBackupCodec.identifier(id, 256);
        community.add(id);
        mappings[QuickTagCloudBackupPlan.communityKey(id)] = record.stableKey;
        mappedNativeKeys.add(record.stableKey);
        continue;
      }
      final parts = record.sourceWorkId.split('/');
      if (parts.length != 2) throw const QuickTagCloudBackupException('invalid');
      final item = <String, dynamic>{
        'codexId': Uri.decodeComponent(parts[0]),
        'entryId': Uri.decodeComponent(parts[1]),
        'addedAt': record.savedAt.toUtc().toIso8601String(),
        'note': '',
      };
      final key = QuickTagCloudFavoritesBackupCodec.keyOf(item);
      items.putIfAbsent(key, () => item);
      mappings[key] = record.stableKey;
      mappedNativeKeys.add(record.stableKey);
    }
  }

  Future<void> commit(
    QuickTagCloudBackupPreview preview, {
    required bool replace,
  }) => _exclusive(() async {
      if (storage.getSetting<String>(storageKey) != preview.previousRaw) {
        throw const QuickTagCloudBackupException('stale');
      }
      final plan = preview.plan(replace: replace);
      final records = preview.records(plan);
      final next = jsonEncode({
        'document': plan.document, 'mappings': preview.nextMappings(plan),
      });
      final replacementId = const Uuid().v4();
      await storage.setSetting(journalKey, jsonEncode({
        'previous': preview.previousRaw, 'next': next,
        'replacementId': replacementId,
      }));
      var nativeCommitted = false;
      try {
        await repository.replaceSourceRecords(
          GallerySourceId.quickTagCloud, records,
          expectedRecords: preview.currentRecords,
          replacementId: replacementId,
        );
        nativeCommitted = true;
        await storage.setSetting(storageKey, next);
        await storage.deleteSetting(journalKey);
      } on OnlineGalleryFavoritesConflictException {
        await _recoverMetadata();
        throw const QuickTagCloudBackupException('stale');
      } catch (_) {
        // Keep the journal if recovery itself fails; never report success.
        await _recoverMetadata();
        if (nativeCommitted) return;
        rethrow;
      }
  });

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }

  Future<void> _recoverMetadata() async {
    final raw = storage.getSetting<String>(journalKey);
    if (raw == null) return;
    final pending = QuickTagCloudFavoritesBackupCodec.object(jsonDecode(raw));
    final useNext = pending['replacementId'] ==
        repository.lastSourceReplacementId(GallerySourceId.quickTagCloud);
    final value = pending[useNext ? 'next' : 'previous'] as String?;
    if (value == null) {
      await storage.deleteSetting(storageKey);
    } else {
      await storage.setSetting(storageKey, value);
    }
    await storage.deleteSetting(journalKey);
  }
}

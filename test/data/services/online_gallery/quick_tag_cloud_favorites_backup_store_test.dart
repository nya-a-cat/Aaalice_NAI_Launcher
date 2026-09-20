import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_item.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_source.dart';
import 'package:nai_launcher/data/models/online_gallery/online_gallery_favorite_record.dart';
import 'package:nai_launcher/data/repositories/online_gallery_local_favorites_repository.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_favorites_backup_codec.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_favorites_backup_store.dart';

const _source = GallerySourceId.quickTagCloud;
const _metadataKey = QuickTagCloudFavoritesBackupStore.storageKey;
const _journalKey = QuickTagCloudFavoritesBackupStore.journalKey;

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late LocalStorageService storage;
  late OnlineGalleryLocalFavoritesRepository repository;
  late QuickTagCloudFavoritesBackupStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quick_tag_backup_store_');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>(StorageKeys.settingsBox);
    box = await Hive.openBox<dynamic>(StorageKeys.localFavoritesBox);
    storage = LocalStorageService();
    repository = _repository(box, storage);
    await repository.ensureInitialized();
    store = QuickTagCloudFavoritesBackupStore(storage, repository);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('uses only trusted resolver details and preserves unresolved metadata', () async {
    final incoming = _document();
    final calls = <String>[];
    final preview = await store.prepare(
      jsonEncode(incoming),
      cancelToken: CancelToken(),
      resolve: (codexId, entryId, token) async {
        calls.add('$codexId:$entryId');
        return entryId == 'known' ? _detail('known') : null;
      },
    );

    expect(calls, ['book:known', 'book:missing']);
    expect(repository.count, 0);
    expect(storage.getSetting<String>(_metadataKey), isNull);
    expect(preview.mapped(preview.plan(replace: false)), 1);
    await store.commit(preview, replace: false);

    final native = repository.getByStableKey(_detail('known').item.stableKey)!;
    expect(native.item.title, 'Trusted known');
    expect(native.detail.prompt, 'trusted known prompt');
    expect(native.savedAt, DateTime.utc(2024, 2, 3));
    expect(repository.count, 1);
    expect(storage.getSetting<String>(_journalKey), isNull);
    expect(repository.lastSourceReplacementId(_source), isNotEmpty);

    final restarted = _repository(box, storage);
    final exported = (await QuickTagCloudFavoritesBackupStore(
      LocalStorageService(), restarted,
    ).snapshot()).current;
    final roundTrip = await QuickTagCloudFavoritesBackupCodec.decode(
      QuickTagCloudFavoritesBackupCodec.encode(exported),
    );
    expect(roundTrip['favorites'], incoming['favorites']);
    expect(roundTrip['folders'], incoming['folders']);
    expect(roundTrip['memberships'], incoming['memberships']);
    expect(roundTrip['libraryId'], 'website-library');
  });

  test('replace changes only QuickTagCloud and preserves other sources', () async {
    await repository.upsert(_detail('old'), savedAt: DateTime.utc(2020));
    final foreign = _detail('other', source: GallerySourceId.aiTag);
    await repository.upsert(foreign, savedAt: DateTime.utc(2021));
    final foreignBefore = repository.getByStableKey(foreign.item.stableKey)!.toMap();
    final preview = await _prepare(store);

    expect(preview.plan(replace: true).removed, 1);
    await store.commit(preview, replace: true);

    expect(repository.contains(_detail('old').item.stableKey), isFalse);
    expect(repository.contains(_detail('known').item.stableKey), isTrue);
    expect(repository.getByStableKey(foreign.item.stableKey)!.toMap(), foreignBefore);
    expect(repository.count, 2);
  });

  test('merge keeps existing native details and original saved time', () async {
    final original = _detail('known', title: 'Previously saved');
    await repository.upsert(original, savedAt: DateTime.utc(2019));
    final before = repository.getByStableKey(original.item.stableKey)!.toMap();
    final preview = await _prepare(store);
    await store.commit(preview, replace: false);

    expect(repository.getByStableKey(original.item.stableKey)!.toMap(), before);
    final exported = (await store.snapshot()).current;
    expect(exported['favorites']['atlas'], hasLength(2));
    expect(exported['favorites']['atlas'][1]['note'], 'Keep unresolved note');
  });

  test('rejects native changes after preview without changing favorites', () async {
    final preview = await _prepare(store);
    await repository.upsert(_detail('concurrent'), savedAt: DateTime.utc(2025));
    final before = box.toMap();

    await expectLater(store.commit(preview, replace: true), _throwsStale);

    expect(box.toMap(), before);
    expect(storage.getSetting<String>(_metadataKey), isNull);
    expect(storage.getSetting<String>(_journalKey), isNull);
  });

  test('rejects metadata changes after preview before creating a journal', () async {
    final preview = await _prepare(store);
    final concurrent = _envelope(_emptyDocument(community: ['concurrent']));
    await storage.setSetting(_metadataKey, concurrent);
    final before = box.toMap();

    await expectLater(store.commit(preview, replace: false), _throwsStale);

    expect(box.toMap(), before);
    expect(storage.getSetting<String>(_metadataKey), concurrent);
    expect(storage.getSetting<String>(_journalKey), isNull);
  });

  test('commit token recovers metadata after restart and later native writes', () async {
    const replacementId = 'completed-native-replacement';
    final record = OnlineGalleryFavoriteRecord.fromDetail(
      _detail('known'), savedAt: DateTime.utc(2024, 2, 3),
    );
    final previous = _envelope(_emptyDocument(community: ['old-community']));
    final next = _envelope(_document(), mappings: {'book:known': record.stableKey});
    await storage.setSetting(_metadataKey, previous);
    await storage.setSetting(_journalKey, jsonEncode({
      'previous': previous, 'next': next, 'replacementId': replacementId,
    }));
    await repository.replaceSourceRecords(
      _source, [record], expectedRecords: [], replacementId: replacementId,
    );

    final restarted = _repository(box, storage);
    await restarted.ensureInitialized();
    expect(restarted.lastSourceReplacementId(_source), replacementId);
    await restarted.upsert(_detail('later'), savedAt: DateTime.utc(2026));
    final exported = (await QuickTagCloudFavoritesBackupStore(
      LocalStorageService(), restarted,
    ).snapshot()).current;

    expect(storage.getSetting<String>(_metadataKey), next);
    expect(storage.getSetting<String>(_journalKey), isNull);
    expect(exported['favorites']['community'], ['community-unresolved']);
    final atlas = (exported['favorites']['atlas'] as List).cast<Map<String, dynamic>>();
    expect(atlas.map((item) => item['entryId']), containsAll(['known', 'missing', 'later']));
    expect(atlas.singleWhere((item) => item['entryId'] == 'missing')['note'],
      'Keep unresolved note');
    expect(exported['folders'], _document()['folders']);
    expect(exported['memberships'], _document()['memberships']);
  });

  test('uncommitted token restores previous metadata despite equal native sets', () async {
    final previous = _envelope(_emptyDocument(community: ['previous']));
    final next = _envelope(_emptyDocument(community: ['incoming']));
    await storage.setSetting(_metadataKey, next);
    await storage.setSetting(_journalKey, jsonEncode({
      'previous': previous, 'next': next, 'replacementId': 'never-committed',
    }));

    final exported = (await store.snapshot()).current;

    expect(exported['favorites']['community'], ['previous']);
    expect(storage.getSetting<String>(_metadataKey), previous);
    expect(storage.getSetting<String>(_journalKey), isNull);
    expect(repository.count, 0);
  });

  test('uncommitted first import restores absent metadata', () async {
    await storage.setSetting(_journalKey, jsonEncode({
      'previous': null, 'next': _envelope(_document()),
      'replacementId': 'never-committed',
    }));

    final exported = (await store.snapshot()).current;

    expect(exported['favorites']['atlas'], isEmpty);
    expect(exported['favorites']['community'], isEmpty);
    expect(storage.getSetting<String>(_metadataKey), isNull);
    expect(storage.getSetting<String>(_journalKey), isNull);
  });

  test('exports native community identities only in favorites.community', () async {
    final detail = _communityDetail('existing');
    await repository.upsert(detail, savedAt: DateTime.utc(2020));
    final before = repository.getByStableKey(detail.item.stableKey)!.toMap();

    final exported = (await store.snapshot()).current;

    expect(exported['favorites']['atlas'], isEmpty);
    expect(exported['favorites']['community'], ['existing']);
    expect(repository.getByStableKey(detail.item.stableKey)!.toMap(), before);
    expect(await QuickTagCloudFavoritesBackupCodec.decode(
      QuickTagCloudFavoritesBackupCodec.encode(exported)), exported);
  });

  test('merge keeps native community details and atlas folder memberships', () async {
    final detail = _communityDetail('existing');
    await repository.upsert(detail, savedAt: DateTime.utc(2018));
    final before = repository.getByStableKey(detail.item.stableKey)!.toMap();
    final initial = _document();
    initial['favorites']['community'] = ['existing'];
    final seeded = await store.prepare(
      jsonEncode(initial), cancelToken: CancelToken(),
      resolve: (codexId, entryId, token) async =>
        entryId == 'known' ? _detail('known') : null,
    );
    await store.commit(seeded, replace: false);
    final incoming = _emptyDocument(community: ['new-unresolved']);
    final preview = await store.prepare(
      jsonEncode(incoming), cancelToken: CancelToken(),
      resolve: (codexId, entryId, token) async => null,
    );

    await store.commit(preview, replace: false);
    final exported = (await store.snapshot()).current;

    expect(repository.getByStableKey(detail.item.stableKey)!.toMap(), before);
    expect(exported['favorites']['community'], ['existing', 'new-unresolved']);
    expect(exported['favorites']['atlas'], initial['favorites']['atlas']);
    expect(exported['folders'], initial['folders']);
    expect(exported['memberships'], initial['memberships']);
    expect(await QuickTagCloudFavoritesBackupCodec.decode(
      QuickTagCloudFavoritesBackupCodec.encode(exported)), exported);
  });

  test('replace keeps incoming community identities with original native details', () async {
    final keep = _communityDetail('keep', title: 'Previously saved community');
    final drop = _communityDetail('drop');
    final foreign = _detail('other', source: GallerySourceId.aiTag);
    await repository.upsert(keep, savedAt: DateTime.utc(2017));
    await repository.upsert(drop, savedAt: DateTime.utc(2018));
    await repository.upsert(_detail('old'), savedAt: DateTime.utc(2019));
    await repository.upsert(foreign, savedAt: DateTime.utc(2020));
    final keepBefore = repository.getByStableKey(keep.item.stableKey)!.toMap();
    final foreignBefore = repository.getByStableKey(foreign.item.stableKey)!.toMap();
    final preview = await store.prepare(
      jsonEncode(_emptyDocument(community: ['keep', 'unresolved'])),
      cancelToken: CancelToken(),
      resolve: (codexId, entryId, token) async => null,
      resolveCommunity: (entryId, token) async =>
        entryId == 'keep' ? _communityDetail('keep', title: 'Fresh detail') : null,
    );

    await store.commit(preview, replace: true);
    final exported = (await store.snapshot()).current;

    expect(repository.getByStableKey(keep.item.stableKey)!.toMap(), keepBefore);
    expect(repository.getByStableKey(foreign.item.stableKey)!.toMap(), foreignBefore);
    expect(repository.contains(drop.item.stableKey), isFalse);
    expect(repository.contains(_detail('old').item.stableKey), isFalse);
    expect(repository.count, 2);
    expect(exported['favorites']['atlas'], isEmpty);
    expect(exported['favorites']['community'], ['keep', 'unresolved']);
  });

  test('imports trusted community details and retains unresolved community IDs', () async {
    final calls = <String>[];
    final preview = await store.prepare(
      jsonEncode(_emptyDocument(community: ['trusted', 'unknown'])),
      cancelToken: CancelToken(),
      resolve: (codexId, entryId, token) async =>
        throw StateError('A community ID must not use the atlas resolver'),
      resolveCommunity: (entryId, token) async {
        calls.add(entryId);
        return entryId == 'trusted' ? _communityDetail(entryId) : null;
      },
    );
    expect(repository.count, 0);
    await store.commit(preview, replace: false);

    final native = repository.getByStableKey(_communityDetail('trusted').item.stableKey)!;
    expect(calls, ['trusted', 'unknown']);
    expect(native.sourceWorkId, 'community:trusted');
    expect(native.item.title, 'Trusted community trusted');
    expect(native.detail.prompt, 'trusted community trusted prompt');
    expect(repository.count, 1);
    final exported = (await store.snapshot()).current;
    expect(exported['favorites']['atlas'], isEmpty);
    expect(exported['favorites']['community'], ['trusted', 'unknown']);
  });
}

Matcher get _throwsStale => throwsA(isA<QuickTagCloudBackupException>()
  .having((error) => error.code, 'code', 'stale'));

Future<QuickTagCloudBackupPreview> _prepare(QuickTagCloudFavoritesBackupStore store) =>
  store.prepare(jsonEncode(_document()), cancelToken: CancelToken(),
    resolve: (codexId, entryId, token) async =>
      entryId == 'known' ? _detail('known') : null);

OnlineGalleryLocalFavoritesRepository _repository(
  Box<dynamic> box, LocalStorageService storage,
) => OnlineGalleryLocalFavoritesRepository(box: box, legacyStorage: storage);

GalleryDetail _detail(String entryId, {
  GallerySourceId source = _source, String? title,
}) => GalleryDetail(
  item: GalleryItem(id: 1, workId: 'book/$entryId', sourceId: source,
    site: source.key, title: title ?? 'Trusted $entryId'),
  media: const [], prompt: 'trusted $entryId prompt',
  rawSourceMetadata: const {'codexId': 'book'},
);

GalleryDetail _communityDetail(String entryId, {String? title}) => GalleryDetail(
  item: GalleryItem(id: 2, workId: 'community:$entryId', sourceId: _source,
    site: _source.key, title: title ?? 'Trusted community $entryId'),
  media: const [], prompt: 'trusted community $entryId prompt',
  rawSourceMetadata: {'communityEntryId': entryId},
);

String _envelope(Map<String, dynamic> document, {
  Map<String, String> mappings = const {},
}) => jsonEncode({'document': document, 'mappings': mappings});

Map<String, dynamic> _emptyDocument({List<String> community = const []}) => {
  'format': QuickTagCloudFavoritesBackupCodec.format, 'version': 2,
  'exportedAt': '2026-09-20T00:00:00Z',
  'favorites': {'atlas': <dynamic>[], 'community': community},
  'folders': <dynamic>[], 'memberships': <dynamic>[],
};

Map<String, dynamic> _document() => {
  ..._emptyDocument(), 'libraryId': 'website-library',
  'favorites': {
    'atlas': [
      {'codexId': 'book', 'entryId': 'known', 'addedAt': '2024-02-03T00:00:00Z',
        'note': 'Keep known note',
        'snap': {'title': 'Untrusted snapshot', 'prompt': 'untrusted prompt',
          'url': 'https://untrusted.invalid/do-not-fetch'}},
      {'codexId': 'book', 'entryId': 'missing', 'note': 'Keep unresolved note',
        'snap': {'title': 'Unresolved title'}},
    ],
    'community': ['community-unresolved'],
  },
  'folders': [{'id': 'folder_a', 'name': 'Saved styles', 'order': 0,
    'createdAt': '2024-01-01T00:00:00Z', 'coverItemId': 'book:missing'}],
  'memberships': [{'itemKey': 'book:missing', 'folderId': 'folder_a',
    'addedAt': '2024-03-01T00:00:00Z'}],
};

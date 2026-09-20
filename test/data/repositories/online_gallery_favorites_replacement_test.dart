import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_item.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_source.dart';
import 'package:nai_launcher/data/models/online_gallery/online_gallery_favorite_record.dart';
import 'package:nai_launcher/data/repositories/online_gallery_favorites_replacement.dart';
import 'package:nai_launcher/data/repositories/online_gallery_local_favorites_repository.dart';

const _source = GallerySourceId.quickTagCloud;

void main() {
  late _FaultBox box;
  late OnlineGalleryLocalFavoritesRepository repository;
  late List<OnlineGalleryFavoriteRecord> before;
  late List<OnlineGalleryFavoriteRecord> next;

  setUp(() async {
    before = [_record('a'), _record('b'), _record('c')];
    next = [
      _record('a', title: 'Updated', savedAt: DateTime.utc(2020)),
      _record('d', savedAt: DateTime.utc(2021)),
      _record('e', savedAt: DateTime.utc(2022)),
    ];
    box = _FaultBox({
      OnlineGalleryLocalFavoritesRepository.quickTagCloudMigrationMarkerKey:
          true,
      for (final record in before) record.stableKey: record.toMap(),
      'ai_tag:other': _record('other', source: GallerySourceId.aiTag).toMap(),
    });
    repository = _repository(box);
    await repository.ensureInitialized();
    box.calls.clear();
  });

  test(
    'replaces one source, preserves saved times, and can clear it',
    () async {
      final other = box.get('ai_tag:other');
      await repository.replaceSourceRecords(
        _source,
        next,
        expectedRecords: before.reversed,
      );

      expect(_snapshot(repository), _maps(next));
      expect(box.get('ai_tag:other'), other);
      expect(
        box.containsKey(OnlineGalleryFavoritesReplacement.journalKey),
        false,
      );
      expect(repository.count, 4);
      expect(
        repository
            .query(const OnlineGalleryFavoriteQuery(sourceId: _source))
            .records
            .map((record) => record.sourceWorkId),
        ['e', 'd', 'a'],
      );
      final restored = _repository(box);
      await restored.ensureInitialized();
      expect(_snapshot(restored), _maps(next));

      await repository.replaceSourceRecords(_source, [], expectedRecords: next);
      expect(repository.count, 1);
      expect(_snapshot(repository), isEmpty);
      expect(box.get('ai_tag:other'), other);
    },
  );

  test('commit ID survives a restart and ordinary favorite writes', () async {
    await repository.replaceSourceRecords(
      _source,
      next,
      replacementId: 'restore-committed',
    );
    final restarted = _repository(box);
    await restarted.ensureInitialized();
    await restarted.upsert(_record('ordinary-write').detail);
    await restarted.remove(next[1].stableKey);

    final reopened = _repository(box);
    await reopened.ensureInitialized();
    expect(reopened.lastSourceReplacementId(_source), 'restore-committed');
    expect(reopened.contains(_record('ordinary-write').stableKey), true);
    expect(reopened.count, 4);
    await reopened.replaceSourceRecords(_source, before);
    expect(reopened.lastSourceReplacementId(_source), isNull);
  });

  test(
    'rollback restores source commit ID and preserves other source ID',
    () async {
      await repository.replaceSourceRecords(
        _source,
        before,
        replacementId: 'previous',
      );
      await repository.replaceSourceRecords(GallerySourceId.aiTag, [
        _record('other', source: GallerySourceId.aiTag),
      ], replacementId: 'other-source');
      final diskBefore = box.toMap();
      box.calls.clear();
      box.failures['deleteAll:1'] = 1;
      await expectLater(
        repository.replaceSourceRecords(_source, next, replacementId: 'failed'),
        throwsA(isA<OnlineGalleryFavoritesReplacementException>()),
      );
      expect(box.toMap(), diskBefore);
      expect(repository.lastSourceReplacementId(_source), 'previous');
      expect(
        repository.lastSourceReplacementId(GallerySourceId.aiTag),
        'other-source',
      );
    },
  );

  for (final operation in ['put', 'delete']) {
    test(
      'rolls back an applied journal $operation that reports failure',
      () async {
        final diskBefore = box.toMap();
        box.failures['$operation:1'] = 1;
        await expectLater(
          repository.replaceSourceRecords(
            _source,
            next,
            replacementId: 'failed',
          ),
          throwsA(
            isA<OnlineGalleryFavoritesReplacementException>().having(
              (error) => error.recoveryRequired,
              'recovery',
              false,
            ),
          ),
        );
        expect(box.toMap(), diskBefore);
        expect(_snapshot(repository), _maps(before));
      },
    );
  }

  for (final operation in ['putAll', 'deleteAll']) {
    test('rolls back partially applied $operation and permits retry', () async {
      final diskBefore = box.toMap();
      box.failures['$operation:1'] = operation == 'putAll' ? 2 : 1;

      await expectLater(
        repository.replaceSourceRecords(_source, next),
        throwsA(
          isA<OnlineGalleryFavoritesReplacementException>()
              .having((error) => error.cause, 'cause', isA<StateError>())
              .having((error) => error.recoveryRequired, 'recovery', false),
        ),
      );

      expect(box.toMap(), diskBefore);
      expect(_snapshot(repository), _maps(before));
      final restored = _repository(box);
      await restored.ensureInitialized();
      expect(_snapshot(restored), _maps(before));
      await repository.replaceSourceRecords(_source, next);
      expect(_snapshot(repository), _maps(next));
    });
  }

  for (final rollbackOperation in ['putAll', 'deleteAll']) {
    test('retains journal when rollback $rollbackOperation fails', () async {
      final diskBefore = box.toMap();
      box.failures['deleteAll:1'] = 1;
      box.failures['$rollbackOperation:2'] = 1;

      await expectLater(
        repository.replaceSourceRecords(_source, next),
        throwsA(
          isA<OnlineGalleryFavoritesReplacementException>()
              .having((error) => error.cause, 'cause', isA<StateError>())
              .having(
                (error) => error.rollbackError,
                'rollback',
                isA<StateError>(),
              )
              .having((error) => error.recoveryRequired, 'recovery', true),
        ),
      );

      expect(
        box.containsKey(OnlineGalleryFavoritesReplacement.journalKey),
        true,
      );
      expect(_snapshot(repository), _maps(before));
      await expectLater(
        repository.upsert(_record('later').detail),
        throwsStateError,
      );
      final restored = _repository(box);
      await restored.ensureInitialized();
      expect(box.toMap(), diskBefore);
      expect(_snapshot(restored), _maps(before));
      await restored.replaceSourceRecords(_source, next);
      expect(_snapshot(restored), _maps(next));
    });
  }

  test(
    'validates every record before writing and rejects duplicate keys',
    () async {
      final valid = _record('valid');
      final invalid = OnlineGalleryFavoriteRecord(
        schemaVersion: valid.schemaVersion,
        stableKey: 'quick_tag_cloud:forged',
        sourceId: valid.sourceId,
        sourceWorkId: valid.sourceWorkId,
        savedAt: valid.savedAt,
        detail: valid.detail,
      );
      final invalidVersion = OnlineGalleryFavoriteRecord(
        schemaVersion: 999,
        stableKey: valid.stableKey,
        sourceId: valid.sourceId,
        sourceWorkId: valid.sourceWorkId,
        savedAt: valid.savedAt,
        detail: valid.detail,
      );
      final diskBefore = box.toMap();
      for (final records in [
        [valid, _record('foreign', source: GallerySourceId.aiTag)],
        [valid, invalid],
        [valid, invalidVersion],
        [valid, valid],
      ]) {
        await expectLater(
          repository.replaceSourceRecords(_source, records),
          throwsFormatException,
        );
        expect(box.calls, isEmpty);
        expect(box.toMap(), diskBefore);
        expect(_snapshot(repository), _maps(before));
      }
    },
  );

  test('expected snapshot detects changed details and saved time', () async {
    for (final changed in [
      _record('a', title: 'Concurrent update'),
      _record('a', savedAt: DateTime.utc(2024)),
    ]) {
      await repository.upsert(changed.detail, savedAt: changed.savedAt);
      final diskBefore = box.toMap();
      box.calls.clear();
      await expectLater(
        repository.replaceSourceRecords(_source, next, expectedRecords: before),
        throwsA(isA<OnlineGalleryFavoritesConflictException>()),
      );
      expect(box.calls, isEmpty);
      expect(box.toMap(), diskBefore);
    }
  });

  test(
    'changes in another source do not conflict with expected snapshot',
    () async {
      await repository.upsert(
        _record('foreign', source: GallerySourceId.aiTag).detail,
      );
      await repository.replaceSourceRecords(
        _source,
        next,
        expectedRecords: before,
      );
      expect(_snapshot(repository), _maps(next));
      expect(repository.contains('ai_tag:foreign'), true);
    },
  );

  test('expected snapshot detects writes from another repository', () async {
    final otherRepository = _repository(box);
    await otherRepository.ensureInitialized();
    await otherRepository.upsert(_record('a', title: 'Other writer').detail);
    final diskBefore = box.toMap();
    await expectLater(
      repository.replaceSourceRecords(_source, next, expectedRecords: before),
      throwsA(isA<OnlineGalleryFavoritesConflictException>()),
    );
    expect(box.toMap(), diskBefore);
  });

  test(
    'initialization waits for an in-flight replacement before recovery',
    () async {
      await repository.replaceSourceRecords(
        _source,
        before,
        replacementId: 'previous',
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      box.putAllEntered = entered;
      box.putAllRelease = release;
      final replacing = repository.replaceSourceRecords(
        _source,
        next,
        replacementId: 'next',
      );
      await entered.future;
      expect(
        box.get(OnlineGalleryFavoritesReplacement.replacementIdKey(_source)),
        'next',
      );
      expect(repository.lastSourceReplacementId(_source), 'previous');
      final restored = _repository(box);
      final initializing = restored.ensureInitialized();
      await Future<void>.value();
      release.complete();
      await replacing;
      await initializing;
      expect(restored.lastSourceReplacementId(_source), 'next');
      expect(_snapshot(repository), _maps(next));
      expect(_snapshot(restored), _maps(next));
      expect(
        OnlineGalleryFavoritesReplacement.readSource(
          box,
          _source,
        ).map((key, value) => MapEntry(key, value.toMap())),
        _maps(next),
      );
    },
  );

  test('checks expected snapshot after earlier queued writes finish', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    box.putEntered = entered;
    box.putRelease = release;
    final changed = _record('a', title: 'Queued update');
    final writing = repository.upsert(changed.detail, savedAt: changed.savedAt);
    await entered.future;
    final replacing = repository.replaceSourceRecords(
      _source,
      next,
      expectedRecords: before,
    );
    final assertion = expectLater(
      replacing,
      throwsA(isA<OnlineGalleryFavoritesConflictException>()),
    );
    release.complete();
    await writing;
    await assertion;
    expect(
      repository.getByStableKey(changed.stableKey)?.item.title,
      changed.item.title,
    );
    await repository.replaceSourceRecords(
      _source,
      next,
      expectedRecords: [changed, ...before.skip(1)],
    );
    expect(_snapshot(repository), _maps(next));
  });

  test('recovers an interrupted journal before loading favorites', () async {
    final diskBefore = box.toMap();
    await box.put(OnlineGalleryFavoritesReplacement.journalKey, {
      'version': 1,
      'sourceId': _source.key,
      'previous': _maps(before),
      'newKeys': [next[1].stableKey, next[2].stableKey],
    });
    await box.putAll(_maps(next));
    await box.delete(before[1].stableKey);

    final restored = _repository(box);
    await restored.ensureInitialized();
    expect(box.toMap(), diskBefore);
    expect(_snapshot(restored), _maps(before));
  });

  test('rejects a damaged journal before modifying any records', () async {
    await box.put(OnlineGalleryFavoritesReplacement.journalKey, {
      'version': 1,
      'sourceId': _source.key,
      'previous': _maps(before),
      'newKeys': ['ai_tag:other'],
    });
    final diskBefore = box.toMap();
    box.calls.clear();
    await expectLater(
      _repository(box).ensureInitialized(),
      throwsFormatException,
    );
    expect(box.calls, isEmpty);
    expect(box.toMap(), diskBefore);
  });
}

OnlineGalleryLocalFavoritesRepository _repository(_FaultBox box) =>
    OnlineGalleryLocalFavoritesRepository(
      box: box,
      legacyStorage: _MemoryStorage(),
    );

Map<String, dynamic> _snapshot(
  OnlineGalleryLocalFavoritesRepository repository,
) => _maps(
  repository.query(const OnlineGalleryFavoriteQuery(sourceId: _source)).records,
);

Map<String, dynamic> _maps(Iterable<OnlineGalleryFavoriteRecord> records) => {
  for (final record in records) record.stableKey: record.toMap(),
};

OnlineGalleryFavoriteRecord _record(
  String workId, {
  String title = 'Original',
  DateTime? savedAt,
  GallerySourceId source = _source,
}) => OnlineGalleryFavoriteRecord.fromDetail(
  GalleryDetail(
    item: GalleryItem(
      id: 1,
      workId: workId,
      sourceId: source,
      site: source.key,
      title: title,
    ),
    media: const [],
    prompt: '$title prompt',
    rawSourceMetadata: const {
      'codexId': 'book',
      'nested': {'label': 'snapshot'},
    },
  ),
  savedAt: savedAt ?? DateTime.utc(2023),
);

class _MemoryStorage extends LocalStorageService {
  @override
  T? getSetting<T>(String key, {T? defaultValue}) => defaultValue;
}

/// Applies an operation's first N writes before throwing the planned failure.
class _FaultBox extends Fake implements Box<dynamic> {
  _FaultBox(Map<String, dynamic> values) : _values = _clone(values) as Map;

  final Map<dynamic, dynamic> _values;
  final Map<String, int> failures = {};
  final Map<String, int> calls = {};
  Completer<void>? putEntered;
  Completer<void>? putRelease;
  Completer<void>? putAllEntered;
  Completer<void>? putAllRelease;

  static dynamic _clone(dynamic value) => jsonDecode(jsonEncode(value));

  @override
  bool get isOpen => true;

  @override
  bool containsKey(dynamic key) => _values.containsKey(key);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _clone(_values.containsKey(key) ? _values[key] : defaultValue);

  @override
  Map<dynamic, dynamic> toMap() => _clone(_values) as Map;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    final entered = putEntered;
    final release = putRelease;
    putEntered = null;
    putRelease = null;
    entered?.complete();
    if (release != null) await release.future;
    _apply('put', [MapEntry(key, value)], delete: false);
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    _apply('putAll', entries.entries, delete: false);
    final entered = putAllEntered;
    final release = putAllRelease;
    putAllEntered = null;
    putAllRelease = null;
    entered?.complete();
    if (release != null) await release.future;
  }

  @override
  Future<void> delete(dynamic key) async =>
      _apply('delete', [MapEntry(key, null)], delete: true);

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async =>
      _apply('deleteAll', keys.map((key) => MapEntry(key, null)), delete: true);

  void _apply(
    String operation,
    Iterable<MapEntry> entries, {
    required bool delete,
  }) {
    final call = calls.update(
      operation,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final failAfter = failures['$operation:$call'];
    var applied = 0;
    if (failAfter == 0) throw StateError('$operation:$call');
    for (final entry in entries) {
      if (delete) {
        _values.remove(entry.key);
      } else {
        _values[entry.key] = _clone(entry.value);
      }
      applied++;
      if (applied == failAfter) throw StateError('$operation:$call');
    }
  }
}

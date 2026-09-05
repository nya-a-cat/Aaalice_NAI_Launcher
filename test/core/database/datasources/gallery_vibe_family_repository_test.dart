import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nai_launcher/core/database/datasources/gallery_database_gateway.dart';
import 'package:nai_launcher/core/database/datasources/gallery_vibe_family_repository.dart';
import 'package:nai_launcher/data/models/vibe/vibe_family.dart';
import 'package:nai_launcher/data/services/vibe_style/vibe_style_corpus.dart';

class TestGalleryGateway implements GalleryDatabaseGateway {
  TestGalleryGateway(this.db);
  final Database db;
  @override
  Future<T> execute<T>(
    String name,
    Future<T> Function(Database) operation, {
    Duration? timeout,
    int? maxRetries,
  }) => operation(db);
  @override
  Future<T> executeTransaction<T>(
    String name,
    Future<T> Function(Transaction) operation, {
    Duration? timeout,
  }) => db.transaction(operation);
}

void main() {
  late Database db;
  late GalleryVibeFamilyRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repo = GalleryVibeFamilyRepository(TestGalleryGateway(db));
    await repo.initialize();
  });
  tearDown(() => db.close());
  test(
    'merge, rename and split persist and keep exact encoding records intact',
    () async {
      await db.execute(
        'CREATE TABLE gallery_image_vibes (vibe_hash TEXT, vibe_encoding TEXT)',
      );
      await db.insert('gallery_image_vibes', {
        'vibe_hash': 'a',
        'vibe_encoding': 'original bytes',
      });
      await repo.merge({'a', 'b'}, 'Ink');
      final family = (await repo.load()).familyOf('a')!;
      await repo.rename(family.id, 'Watercolor');
      await repo.merge({'b', 'c'}, 'Family');
      var state = await GalleryVibeFamilyRepository(
        TestGalleryGateway(db),
      ).load();
      expect(state.familyOf('a')!.members, {'a', 'b', 'c'});
      await repo.split('a');
      state = await repo.load();
      expect(state.familyOf('a'), isNull);
      expect(state.familyOf('b')!.members, {'b', 'c'});
      expect(state.excludes('a', 'c'), isTrue);
      expect(await db.query('gallery_image_vibes'), [
        {'vibe_hash': 'a', 'vibe_encoding': 'original bytes'},
      ]);
    },
  );
  test(
    'separation blocks transitive family merge atomically until restored',
    () async {
      await repo.merge({'a', 'b'}, 'A');
      await repo.merge({'c', 'd'}, 'B');
      await repo.separate('a', 'd');
      expect((await repo.load()).excludes('b', 'c'), isTrue);
      await expectLater(repo.merge({'b', 'c'}, 'Both'), throwsStateError);
      expect((await repo.load()).families.length, 2);
      await repo.restorePair(VibeFamilyState.pairKey('a', 'd'));
      await repo.merge({'b', 'c'}, 'Both');
      expect((await repo.load()).families.single.members, {'a', 'b', 'c', 'd'});
    },
  );
  test(
    'splitting two-member family removes empty family and remembers decision',
    () async {
      await repo.merge({'a', 'b'}, 'A');
      await repo.split('a');
      expect((await repo.load()).families, isEmpty);
      expect((await repo.load()).excludes('a', 'b'), isTrue);
      await repo.initialize();
      expect((await repo.load()).excludes('b', 'a'), isTrue);
    },
  );
  test('cache versions and malformed entries are isolated', () async {
    const sample = VibeStyleSample(
      imageId: 1,
      path: 'test',
      size: 10,
      modifiedAt: 100,
      hash: 'a',
      recipe: 'r',
      promptKey: 'p',
      seed: 1,
    );
    await repo.saveFeatures(sample, 1, [
      [0.5],
    ]);
    expect((await repo.cachedFeatures(1, [1]))[sample.cacheKey], [
      [0.5],
    ]);
    expect(await repo.cachedFeatures(2, [1]), isEmpty);
    expect(await repo.cachedFeatures(1, [2]), isEmpty);
    await db.update('gallery_vibe_style_features', {
      'features': 'invalid json',
    });
    expect(await repo.cachedFeatures(1, [1]), isEmpty);
  });
  test(
    'keyset corpus excludes large reference payloads and handles invalid JSON',
    () async {
      await db.execute(
        'CREATE TABLE gallery_images (id INTEGER PRIMARY KEY, file_path TEXT, '
        'file_size INTEGER, modified_at INTEGER, created_at INTEGER, is_deleted INTEGER)',
      );
      await db.execute(
        'CREATE TABLE gallery_metadata (image_id INTEGER, prompt TEXT, '
        'negative_prompt TEXT, model TEXT, seed INTEGER, sampler TEXT, steps INTEGER, '
        'cfg_scale REAL, width INTEGER, height INTEGER, is_img2img INTEGER, '
        'noise_schedule TEXT, cfg_rescale REAL, smea INTEGER, smea_dyn INTEGER, '
        'has_vibe INTEGER, raw_json TEXT)',
      );
      await db.execute(
        'CREATE TABLE gallery_image_vibes (image_id INTEGER, vibe_hash TEXT, '
        'strength REAL, info_extracted REAL, ordinal INTEGER)',
      );
      for (var id = 1; id <= 3; id++) {
        await db.insert('gallery_images', {
          'id': id,
          'file_path': '$id.png',
          'file_size': 10,
          'modified_at': 100,
          'created_at': id,
          'is_deleted': 0,
        });
        await db.insert('gallery_metadata', {
          'image_id': id,
          'prompt': 'test',
          'model': 'nai',
          'sampler': 'euler',
          'steps': 28,
          'cfg_scale': 5,
          'width': 832,
          'height': 1216,
          'is_img2img': 0,
          'has_vibe': 1,
          'raw_json': id == 3
              ? 'broken'
              : jsonEncode({
                  'reference_image_multiple': ['encoding'],
                  if (id == 2) 'director_reference_images': ['x' * 100000],
                }),
        });
        await db.insert('gallery_image_vibes', {
          'image_id': id,
          'vibe_hash': 'a',
          'strength': 1,
          'info_extracted': 0.7,
          'ordinal': 0,
        });
      }
      final first = await repo.corpusPage(0, limit: 1);
      expect(first.single['id'], 1);
      expect(VibeStyleCorpus.parse(first).single.recipe, isNotEmpty);
      final remaining = await repo.corpusPage(1);
      expect(remaining.map((r) => r['id']), [2, 3]);
      expect(remaining.map((r) => r['extra_controls']), everyElement(isNull));
      expect(jsonEncode(remaining).length, lessThan(5000));
      expect((await repo.summaries()).single.exampleCount, 3);
    },
  );
}

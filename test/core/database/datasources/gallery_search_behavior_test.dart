import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nai_launcher/core/database/connection_pool_holder.dart';
import 'package:nai_launcher/core/database/datasources/gallery_data_source.dart';
import 'package:nai_launcher/core/utils/app_logger.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/data/services/gallery/gallery_filter_service.dart';

void main() {
  group('Gallery Search Behavior', () {
    late GalleryDataSource dataSource;
    late String testDbPath;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await AppLogger.initialize(isTestEnvironment: true);

      final tempDir = Directory.systemTemp.createTempSync('gallery_search_');
      testDbPath = '${tempDir.path}/search_behavior.db';
    });

    tearDownAll(() async {
      await ConnectionPoolHolder.dispose();

      try {
        final dbFile = File(testDbPath);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }

        final tempDir = Directory(testDbPath).parent;
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    setUp(() async {
      if (ConnectionPoolHolder.isInitialized) {
        await ConnectionPoolHolder.dispose();
      }

      final dbFile = File(testDbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      await ConnectionPoolHolder.initialize(
        dbPath: testDbPath,
        maxConnections: 2,
      );

      dataSource = GalleryDataSource();
      await dataSource.initialize();
    });

    tearDown(() async {
      await dataSource.dispose();
      await ConnectionPoolHolder.dispose();

      final dbFile = File(testDbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

    test(
      'should find images by file name even when metadata is absent',
      () async {
        final now = DateTime.now();
        final imageId = await dataSource.upsertImage(
          filePath: '/test/special_character_pose.png',
          fileName: 'special_character_pose.png',
          fileSize: 2048,
          createdAt: now,
          modifiedAt: now,
        );

        final result = await dataSource.advancedSearch(
          textQuery: 'special_character',
          limit: 10,
        );

        expect(result, contains(imageId));
      },
    );

    test('should filter deterministic metadata-free images as non-NAI', () async {
      final now = DateTime.now();
      final nonNaiFile = File('/test/plain_photo.png');
      final naiFile = File('/test/novelai_output.png');

      await dataSource.upsertImage(
        filePath: nonNaiFile.path,
        fileName: 'plain_photo.png',
        fileSize: 1024,
        createdAt: now,
        modifiedAt: now,
        metadataStatus: MetadataStatus.failed,
      );
      final naiId = await dataSource.upsertImage(
        filePath: naiFile.path,
        fileName: 'novelai_output.png',
        fileSize: 2048,
        createdAt: now,
        modifiedAt: now,
        metadataStatus: MetadataStatus.success,
      );
      await dataSource.upsertMetadata(
        naiId,
        const NaiImageMetadata(prompt: '1girl', seed: 1),
      );

      final result = await GalleryFilterService(dataSource).applyFilters(
        [nonNaiFile, naiFile],
        const FilterCriteria(
          metadataStatuses: [FilterCriteria.nonNaiMetadataStatus],
        ),
      );

      expect(result.files.map((file) => file.path), [nonNaiFile.path]);
    });

    test('should support prompt queries that use comma separators', () async {
      final now = DateTime.now();
      final imageId = await dataSource.upsertImage(
        filePath: '/test/comma_query.png',
        fileName: 'comma_query.png',
        fileSize: 1024,
        createdAt: now,
        modifiedAt: now,
      );

      await dataSource.upsertMetadata(
        imageId,
        const NaiImageMetadata(
          prompt: '1girl solo blue_eyes',
          negativePrompt: '',
          seed: 1,
        ),
      );

      final result = await dataSource.searchFullText('1girl,solo', limit: 10);

      expect(result, contains(imageId));
    });

    test('groups an exact Vibe encoding with all local example images', () async {
      final firstSeen = DateTime(2026, 1, 2);
      final later = DateTime(2026, 2, 3);
      final firstId = await dataSource.upsertImage(
        filePath: '/test/vibe_first.png',
        fileName: 'vibe_first.png',
        fileSize: 1024,
        createdAt: firstSeen,
        modifiedAt: later.add(const Duration(days: 1)),
        metadataStatus: MetadataStatus.success,
      );
      final laterId = await dataSource.upsertImage(
        filePath: '/test/vibe_later.png',
        fileName: 'vibe_later.png',
        fileSize: 2048,
        createdAt: later,
        modifiedAt: later,
        metadataStatus: MetadataStatus.success,
      );

      const sharedEncoding = '  c2hhcmVkLXZpYmU=\n';
      await dataSource.upsertMetadata(
        firstId,
        const NaiImageMetadata(
          prompt: 'same subject',
          model: 'nai-diffusion-4-5-full',
          vibeReferences: [
            VibeReference(
              displayName: 'first',
              vibeEncoding: sharedEncoding,
              strength: 0.4,
              infoExtracted: 0.7,
              sourceType: VibeSourceType.png,
            ),
          ],
        ),
      );
      await dataSource.upsertMetadata(
        laterId,
        const NaiImageMetadata(
          prompt: 'same subject',
          model: 'nai-diffusion-4-5-full',
          vibeReferences: [
            VibeReference(
              displayName: 'later',
              vibeEncoding: 'c2hhcmVkLXZpYmU=',
              strength: 0.8,
              infoExtracted: 0.7,
              sourceType: VibeSourceType.png,
            ),
          ],
        ),
      );

      final groups = await dataSource.queryLocalGalleryVibeGroups();

      expect(groups, hasLength(1));
      expect(groups.single.vibeEncoding, 'c2hhcmVkLXZpYmU=');
      expect(groups.single.exampleCount, 2);
      expect(groups.single.firstSeenAt, firstSeen);
      expect(
        groups.single.examples.map((example) => example.filePath),
        ['/test/vibe_first.png', '/test/vibe_later.png'],
      );
      expect(groups.single.earliestExample?.strength, 0.4);
      expect(groups.single.encodingModels, ['nai-diffusion-4-5-full']);
    });

    test('keeps different Vibes on the same subject in separate groups', () async {
      final now = DateTime(2026, 4, 5);
      final firstId = await dataSource.upsertImage(
        filePath: '/test/same_subject_a.png',
        fileName: 'same_subject_a.png',
        fileSize: 1024,
        createdAt: now,
        modifiedAt: now,
        metadataStatus: MetadataStatus.success,
      );
      final secondId = await dataSource.upsertImage(
        filePath: '/test/same_subject_b.png',
        fileName: 'same_subject_b.png',
        fileSize: 1024,
        createdAt: now.add(const Duration(minutes: 1)),
        modifiedAt: now.add(const Duration(minutes: 1)),
        metadataStatus: MetadataStatus.success,
      );
      await dataSource.upsertMetadata(
        firstId,
        const NaiImageMetadata(
          prompt: 'same subject',
          vibeReferences: [
            VibeReference(
              displayName: 'style-a',
              vibeEncoding: 'c3R5bGUtYQ==',
            ),
            VibeReference(
              displayName: 'style-b',
              vibeEncoding: 'c3R5bGUtYg==',
            ),
          ],
        ),
      );
      await dataSource.upsertMetadata(
        secondId,
        const NaiImageMetadata(
          prompt: 'same subject',
          vibeReferences: [
            VibeReference(
              displayName: 'style-a',
              vibeEncoding: 'c3R5bGUtYQ==',
            ),
          ],
        ),
      );

      final groups = await dataSource.queryLocalGalleryVibeGroups();
      final counts = {
        for (final group in groups) group.vibeEncoding: group.exampleCount,
      };

      expect(counts, {'c3R5bGUtYQ==': 2, 'c3R5bGUtYg==': 1});
    });

    test('backfills legacy raw metadata in bounded background batches', () async {
      final modifiedAt = DateTime(2025, 12, 1);
      final imageId = await dataSource.upsertImage(
        filePath: '/test/legacy_vibe.png',
        fileName: 'legacy_vibe.png',
        fileSize: 4096,
        createdAt: modifiedAt,
        modifiedAt: modifiedAt,
        metadataStatus: MetadataStatus.success,
      );
      const rawJson = '''
        {
          "prompt": "legacy output",
          "reference_image_multiple": ["bGVnYWN5LXZpYmU="],
          "reference_strength_multiple": [0.55],
          "reference_information_extracted_multiple": [0.75]
        }
      ''';
      await dataSource.upsertMetadata(
        imageId,
        const NaiImageMetadata(
          prompt: 'legacy output',
          model: 'nai-diffusion-4-full',
          rawJson: rawJson,
        ),
      );

      final db = await ConnectionPoolHolder.instance.acquire();
      try {
        await db.update(
          'gallery_metadata',
          {'vibes_indexed': 0},
          where: 'image_id = ?',
          whereArgs: [imageId],
        );
      } finally {
        await ConnectionPoolHolder.instance.release(db);
      }

      final updates = <int>[];
      final progress = await dataSource.backfillLocalGalleryVibes(
        batchSize: 1,
        onProgress: (value) => updates.add(value.processed),
      );
      final groups = await dataSource.queryLocalGalleryVibeGroups();

      expect(progress.processed, 1);
      expect(progress.discoveredReferences, 1);
      expect(updates, [0, 1]);
      expect(groups, hasLength(1));
      expect(groups.single.vibeEncoding, 'bGVnYWN5LXZpYmU=');
      expect(groups.single.earliestExample?.strength, 0.55);
      expect(groups.single.earliestExample?.infoExtracted, 0.75);
    });

    test(
      'should refresh cached search results after metadata indexing updates the same tag query',
      () async {
        final now = DateTime.now();
        final file = File('/test/cache_refresh.png');
        final imageId = await dataSource.upsertImage(
          filePath: file.path,
          fileName: 'cache_refresh.png',
          fileSize: 1024,
          createdAt: now,
          modifiedAt: now,
        );

        final filterService = GalleryFilterService(dataSource);

        final initialBareSearch = await filterService.applyFilters([
          file,
        ], const FilterCriteria(searchQuery: 'shycocoa'));

        expect(initialBareSearch.files, isEmpty);

        await dataSource.upsertMetadata(
          imageId,
          const NaiImageMetadata(
            prompt: 'artist:shycocoa, 1girl, solo',
            negativePrompt: '',
            seed: 1,
          ),
        );

        final prefixedSearch = await filterService.applyFilters([
          file,
        ], const FilterCriteria(searchQuery: 'artist:shycocoa'));
        final bareSearch = await filterService.applyFilters([
          file,
        ], const FilterCriteria(searchQuery: 'shycocoa'));

        expect(
          prefixedSearch.files.map((item) => item.path),
          contains(file.path),
        );
        expect(bareSearch.files.map((item) => item.path), contains(file.path));
        expect(bareSearch.files.length, equals(prefixedSearch.files.length));
      },
    );

    test('batch upsert persists last scanned timestamp', () async {
      final now = DateTime.now();
      final lastScannedAt = DateTime.fromMillisecondsSinceEpoch(1712345678000);
      final ids = await dataSource.batchUpsertImages([
        GalleryImageRecord(
          filePath: '/test/batch_last_scanned.png',
          fileName: 'batch_last_scanned.png',
          fileSize: 1024,
          createdAt: now,
          modifiedAt: now,
          indexedAt: now,
          lastScannedAt: lastScannedAt,
          dateYmd: 20260421,
        ),
      ]);

      final record = await dataSource.getImageById(ids.single);

      expect(record?.lastScannedAt, lastScannedAt);
    });

    test(
      'should not truncate local gallery search results at 10000 items',
      () async {
        const totalImages = 10005;
        final now = DateTime.now();
        final imageRecords = List.generate(
          totalImages,
          (index) => GalleryImageRecord(
            filePath: '/test/search_limit_$index.png',
            fileName: 'search_limit_$index.png',
            fileSize: 1024 + index,
            createdAt: now,
            modifiedAt: now,
            indexedAt: now,
            dateYmd: 20260421,
          ),
        );

        final imageIds = await dataSource.batchUpsertImages(imageRecords);
        expect(imageIds.length, equals(totalImages));

        await dataSource.batchUpsertMetadata([
          for (var i = 0; i < imageIds.length; i++)
            MapEntry(
              imageIds[i],
              NaiImageMetadata(
                prompt: 'common search prompt $i',
                negativePrompt: '',
                seed: i,
              ),
            ),
        ]);

        final filterService = GalleryFilterService(dataSource);
        final result = await filterService.applyFilters([
          for (final record in imageRecords) File(record.filePath),
        ], const FilterCriteria(searchQuery: 'common'));

        expect(result.files.length, equals(totalImages));
      },
    );
  });
}

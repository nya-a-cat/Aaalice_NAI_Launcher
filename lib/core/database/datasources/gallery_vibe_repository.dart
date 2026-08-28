import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/models/gallery/local_gallery_vibe_group.dart';
import '../../../data/models/gallery/nai_image_metadata.dart';
import '../../../data/models/vibe/vibe_reference.dart';
import '../../utils/novelai_vibe_codec.dart';
import 'gallery_database_gateway.dart';
import 'gallery_store_context.dart';
import 'gallery_tables.dart';

abstract interface class GalleryVibeRepository {
  Future<void> replaceImageVibes(
    DatabaseExecutor executor,
    int imageId,
    NaiImageMetadata metadata,
  );
  Future<GalleryVibeBackfillProgress> backfill({
    int batchSize = 24,
    void Function(GalleryVibeBackfillProgress progress)? onProgress,
  });
  Future<int> countGroups({String searchQuery = ''});
  Future<List<LocalGalleryVibeGroup>> queryGroups({
    String searchQuery = '',
    int limit = 50,
    int offset = 0,
    int examplesPerGroup = 12,
  });
  Future<List<LocalGalleryVibeExample>> queryExamples(
    String fingerprint, {
    int limit = 100,
    int offset = 0,
  });
  Future<void> clear(DatabaseExecutor executor);
}

class SqliteGalleryVibeRepository implements GalleryVibeRepository {
  SqliteGalleryVibeRepository({required this.gateway, required this.context});

  final GalleryDatabaseGateway gateway;
  final GalleryStoreContext context;

  @override
  Future<void> replaceImageVibes(
    DatabaseExecutor executor,
    int imageId,
    NaiImageMetadata metadata,
  ) async {
    await executor.delete(
      GalleryTables.imageVibes,
      where: 'image_id = ?',
      whereArgs: [imageId],
    );

    final seen = <String>{};
    final batch = executor.batch();
    for (var index = 0; index < metadata.vibeReferences.length; index++) {
      final vibe = metadata.vibeReferences[index];
      final encoding = _normalizeEncoding(vibe.vibeEncoding);
      if (encoding.isEmpty) continue;
      final fingerprint = NovelAiVibeCodec.hashString(encoding);
      if (!seen.add(fingerprint)) continue;
      batch.insert(
        GalleryTables.imageVibes,
        {
          'image_id': imageId,
          'vibe_hash': fingerprint,
          'vibe_encoding': encoding,
          'ordinal': index,
          'strength': vibe.strength,
          'info_extracted': vibe.infoExtracted,
          'encoding_model': vibe.encodingModel ?? metadata.model,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<GalleryVibeBackfillProgress> backfill({
    int batchSize = 24,
    void Function(GalleryVibeBackfillProgress progress)? onProgress,
  }) async {
    final safeBatchSize = batchSize.clamp(1, 100).toInt();
    final total = await gateway.execute('countVibeBackfillRows', (db) async {
      final result = await db.rawQuery('''
        SELECT COUNT(*) AS count
        FROM ${GalleryTables.metadata}
        WHERE vibes_indexed = 0
          AND raw_json IS NOT NULL
          AND raw_json != ''
      ''');
      return (result.first['count'] as num?)?.toInt() ?? 0;
    });

    var processed = 0;
    var discoveredReferences = 0;
    var progress = GalleryVibeBackfillProgress(
      processed: 0,
      total: total,
      discoveredReferences: 0,
    );
    onProgress?.call(progress);

    while (processed < total) {
      final rows = await gateway.execute('loadVibeBackfillRows', (db) {
        return db.rawQuery(
          '''
          SELECT image_id, raw_json, model
          FROM ${GalleryTables.metadata}
          WHERE vibes_indexed = 0
            AND raw_json IS NOT NULL
            AND raw_json != ''
          ORDER BY image_id
          LIMIT ?
          ''',
          [safeBatchSize],
        );
      });
      if (rows.isEmpty) break;

      final parsedRows = await Isolate.run(
        () => _parseGalleryVibeBackfillRows(rows),
      );
      await gateway.executeTransaction('saveVibeBackfillRows', (transaction) async {
        for (final parsed in parsedRows) {
          final imageId = parsed.imageId;
          await transaction.delete(
            GalleryTables.imageVibes,
            where: 'image_id = ?',
            whereArgs: [imageId],
          );
          final batch = transaction.batch();
          for (var ordinal = 0; ordinal < parsed.vibes.length; ordinal++) {
            final vibe = parsed.vibes[ordinal];
            batch.insert(
              GalleryTables.imageVibes,
              {
                'image_id': imageId,
                'vibe_hash': vibe.fingerprint,
                'vibe_encoding': vibe.encoding,
                'ordinal': ordinal,
                'strength': vibe.strength,
                'info_extracted': vibe.infoExtracted,
                'encoding_model': vibe.encodingModel,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          batch.update(
            GalleryTables.metadata,
            {
              'vibes_indexed': 1,
              'has_vibe': parsed.vibes.isEmpty ? 0 : 1,
              'vibe_encoding': parsed.vibes.firstOrNull?.encoding,
              'vibe_strength': parsed.vibes.firstOrNull?.strength,
              'vibe_info_extracted': parsed.vibes.firstOrNull?.infoExtracted,
              'vibe_source_type': parsed.vibes.isEmpty
                  ? null
                  : VibeSourceType.png.name,
            },
            where: 'image_id = ?',
            whereArgs: [imageId],
          );
          await batch.commit(noResult: true);
          discoveredReferences += parsed.vibes.length;
        }
      }, timeout: const Duration(seconds: 30));

      processed += rows.length;
      progress = GalleryVibeBackfillProgress(
        processed: min(processed, total),
        total: total,
        discoveredReferences: discoveredReferences,
      );
      onProgress?.call(progress);
      await Future<void>.delayed(Duration.zero);
    }

    if (processed > 0) context.markDataChanged();
    return progress;
  }

  @override
  Future<int> countGroups({String searchQuery = ''}) async {
    final search = searchQuery.trim().toLowerCase();
    final like = '%${_escapeSqlLike(search)}%';
    return gateway.execute('countLocalGalleryVibeGroups', (db) async {
      final result = await db.rawQuery(
        '''
        SELECT COUNT(*) AS count
        FROM (
          SELECT v.vibe_hash
          FROM ${GalleryTables.imageVibes} v
          INNER JOIN ${GalleryTables.images} i ON i.id = v.image_id
          WHERE i.is_deleted = 0
          GROUP BY v.vibe_hash
          HAVING ? = ''
            OR v.vibe_hash LIKE ? ESCAPE '\\'
            OR MAX(
              CASE WHEN LOWER(i.file_name) LIKE ? ESCAPE '\\'
                OR LOWER(COALESCE(v.encoding_model, '')) LIKE ? ESCAPE '\\'
              THEN 1 ELSE 0 END
            ) = 1
        ) groups
        ''',
        [search, like, like, like],
      );
      return (result.first['count'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Future<List<LocalGalleryVibeGroup>> queryGroups({
    String searchQuery = '',
    int limit = 50,
    int offset = 0,
    int examplesPerGroup = 12,
  }) async {
    final safeLimit = limit.clamp(1, 100).toInt();
    final safeOffset = max(0, offset);
    final safeExampleLimit = examplesPerGroup.clamp(1, 48).toInt();
    final search = searchQuery.trim().toLowerCase();
    final like = '%${_escapeSqlLike(search)}%';

    return context.trackQuery('queryLocalGalleryVibeGroups', () async {
      return gateway.execute('queryLocalGalleryVibeGroups', (db) async {
        final groupRows = await db.rawQuery(
          '''
          SELECT v.vibe_hash, MIN(v.vibe_encoding) AS vibe_encoding,
            COUNT(*) AS example_count, MIN(i.created_at) AS first_seen_at,
            MAX(i.created_at) AS last_seen_at,
            GROUP_CONCAT(DISTINCT COALESCE(v.encoding_model, '')) AS models
          FROM ${GalleryTables.imageVibes} v
          INNER JOIN ${GalleryTables.images} i ON i.id = v.image_id
          WHERE i.is_deleted = 0
          GROUP BY v.vibe_hash
          HAVING ? = ''
            OR v.vibe_hash LIKE ? ESCAPE '\\'
            OR MAX(CASE WHEN LOWER(i.file_name) LIKE ? ESCAPE '\\'
              OR LOWER(COALESCE(v.encoding_model, '')) LIKE ? ESCAPE '\\'
              THEN 1 ELSE 0 END) = 1
          ORDER BY first_seen_at ASC, v.vibe_hash ASC
          LIMIT ? OFFSET ?
          ''',
          [search, like, like, like, safeLimit, safeOffset],
        );
        if (groupRows.isEmpty) return const <LocalGalleryVibeGroup>[];

        final fingerprints = groupRows
            .map((row) => row['vibe_hash']! as String)
            .toList(growable: false);
        final placeholders = List.filled(fingerprints.length, '?').join(',');
        final exampleRows = await db.rawQuery(
          '''
          WITH ranked_examples AS (
            SELECT v.vibe_hash, i.id AS image_id, i.file_path, i.created_at,
              v.strength, v.info_extracted, v.encoding_model,
              ROW_NUMBER() OVER (
                PARTITION BY v.vibe_hash
                ORDER BY i.created_at ASC, i.id ASC
              ) AS example_rank
            FROM ${GalleryTables.imageVibes} v
            INNER JOIN ${GalleryTables.images} i ON i.id = v.image_id
            WHERE i.is_deleted = 0 AND v.vibe_hash IN ($placeholders)
          )
          SELECT * FROM ranked_examples
          WHERE example_rank <= ?
          ORDER BY vibe_hash, created_at ASC, image_id ASC
          ''',
          [...fingerprints, safeExampleLimit],
        );
        final examples = _groupExamples(exampleRows);
        return groupRows
            .map((row) => _mapGroup(row, examples))
            .toList(growable: false);
      });
    }, details: 'query="$search", limit=$safeLimit, offset=$safeOffset');
  }

  @override
  Future<List<LocalGalleryVibeExample>> queryExamples(
    String fingerprint, {
    int limit = 100,
    int offset = 0,
  }) async {
    final safeLimit = limit.clamp(1, 200).toInt();
    final safeOffset = max(0, offset);
    return gateway.execute('queryLocalGalleryVibeExamples', (db) async {
      final rows = await db.rawQuery(
        '''
        SELECT i.id AS image_id, i.file_path, i.created_at,
          v.strength, v.info_extracted, v.encoding_model
        FROM ${GalleryTables.imageVibes} v
        INNER JOIN ${GalleryTables.images} i ON i.id = v.image_id
        WHERE i.is_deleted = 0 AND v.vibe_hash = ?
        ORDER BY i.created_at ASC, i.id ASC
        LIMIT ? OFFSET ?
        ''',
        [fingerprint, safeLimit, safeOffset],
      );
      return rows.map(_mapExample).toList(growable: false);
    });
  }

  @override
  Future<void> clear(DatabaseExecutor executor) =>
      executor.delete(GalleryTables.imageVibes);

  Map<String, List<LocalGalleryVibeExample>> _groupExamples(
    List<Map<String, Object?>> rows,
  ) {
    final result = <String, List<LocalGalleryVibeExample>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['vibe_hash']! as String, () => [])
          .add(_mapExample(row));
    }
    return result;
  }

  LocalGalleryVibeGroup _mapGroup(
    Map<String, Object?> row,
    Map<String, List<LocalGalleryVibeExample>> examples,
  ) {
    final fingerprint = row['vibe_hash']! as String;
    final models = (row['models'] as String? ?? '')
        .split(',')
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return LocalGalleryVibeGroup(
      fingerprint: fingerprint,
      vibeEncoding: row['vibe_encoding']! as String,
      exampleCount: (row['example_count'] as num).toInt(),
      firstSeenAt: _date(row['first_seen_at']),
      lastSeenAt: _date(row['last_seen_at']),
      examples: examples[fingerprint] ?? const [],
      encodingModels: models,
    );
  }

  LocalGalleryVibeExample _mapExample(Map<String, Object?> row) {
    return LocalGalleryVibeExample(
      imageId: (row['image_id'] as num).toInt(),
      filePath: row['file_path']! as String,
      createdAt: _date(row['created_at']),
      strength: VibeReference.sanitizeStrength(
        (row['strength'] as num?)?.toDouble() ?? 0.6,
      ),
      infoExtracted: VibeReference.sanitizeInfoExtracted(
        (row['info_extracted'] as num?)?.toDouble() ?? 0.7,
      ),
      encodingModel: row['encoding_model'] as String?,
    );
  }

  DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
  String _normalizeEncoding(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '');
  String _escapeSqlLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

List<_ParsedGalleryVibeRow> _parseGalleryVibeBackfillRows(
  List<Map<String, Object?>> rows,
) {
  return rows.map((row) {
    final rawJson = row['raw_json'] as String? ?? '';
    final fallbackModel = row['model'] as String?;
    final vibes = <_ParsedGalleryVibe>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        final decodedMap = Map<String, dynamic>.from(decoded);
        final metadata = decodedMap.containsKey('prompt')
            ? NaiImageMetadata.fromNaiComment(
                {'Comment': rawJson},
                rawJson: rawJson,
              )
            : NaiImageMetadata.fromNaiComment(decodedMap, rawJson: rawJson);
        final seen = <String>{};
        for (final vibe in metadata.vibeReferences) {
          final encoding = vibe.vibeEncoding
              .trim()
              .replaceAll(RegExp(r'\s+'), '');
          if (encoding.isEmpty) continue;
          final fingerprint = NovelAiVibeCodec.hashString(encoding);
          if (!seen.add(fingerprint)) continue;
          vibes.add(
            _ParsedGalleryVibe(
              fingerprint: fingerprint,
              encoding: encoding,
              strength: vibe.strength,
              infoExtracted: vibe.infoExtracted,
              encodingModel: vibe.encodingModel ?? fallbackModel,
            ),
          );
        }
      }
    } catch (_) {
      // Persist a deterministic no-Vibe result for malformed legacy metadata.
    }
    return _ParsedGalleryVibeRow(
      imageId: (row['image_id'] as num).toInt(),
      vibes: vibes,
    );
  }).toList(growable: false);
}

class _ParsedGalleryVibeRow {
  const _ParsedGalleryVibeRow({required this.imageId, required this.vibes});
  final int imageId;
  final List<_ParsedGalleryVibe> vibes;
}

class _ParsedGalleryVibe {
  const _ParsedGalleryVibe({
    required this.fingerprint,
    required this.encoding,
    required this.strength,
    required this.infoExtracted,
    this.encodingModel,
  });
  final String fingerprint;
  final String encoding;
  final double strength;
  final double infoExtracted;
  final String? encodingModel;
}

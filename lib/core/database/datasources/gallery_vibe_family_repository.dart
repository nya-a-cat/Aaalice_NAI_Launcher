import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/vibe/vibe_family.dart';
import 'gallery_database_gateway.dart';

/// Only application-owned index tables are writable through this repository.
class GalleryVibeFamilyRepository {
  GalleryVibeFamilyRepository(this.gateway);
  final GalleryDatabaseGateway gateway;

  Future<void> initialize() => gateway.execute('createVibeFamilyTables', (db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS gallery_vibe_families '
        '(id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS gallery_vibe_family_members '
        '(vibe_hash TEXT PRIMARY KEY, family_id TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS gallery_vibe_separations '
        '(pair_key TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE IF NOT EXISTS gallery_vibe_style_features '
        '(image_id INTEGER PRIMARY KEY, cache_key TEXT NOT NULL, '
        'version INTEGER NOT NULL, features TEXT NOT NULL)');
  });

  Future<List<VibeFamilySummary>> summaries() =>
      gateway.execute('queryVibeFamilySummaries', (db) async {
        final rows = await db.rawQuery('''
          SELECT v.vibe_hash, COUNT(*) AS count,
            (SELECT i2.file_path FROM gallery_image_vibes v2
             JOIN gallery_images i2 ON i2.id = v2.image_id
             WHERE v2.vibe_hash = v.vibe_hash AND i2.is_deleted = 0
             ORDER BY i2.created_at, i2.id LIMIT 1) AS preview_path
          FROM gallery_image_vibes v JOIN gallery_images i ON i.id = v.image_id
          WHERE i.is_deleted = 0 GROUP BY v.vibe_hash ORDER BY v.vibe_hash
        ''');
        return rows.map((r) => VibeFamilySummary(
          hash: r['vibe_hash']! as String,
          exampleCount: (r['count']! as num).toInt(),
          previewPath: r['preview_path'] as String?,
        )).toList();
      });

  Future<VibeFamilyState> load() => gateway.execute('loadVibeFamilies', _load);

  Future<VibeFamilyState> _load(DatabaseExecutor db) async {
    final families = await db.query('gallery_vibe_families', orderBy: 'name, id');
    final members = await db.query('gallery_vibe_family_members');
    final separated = await db.query('gallery_vibe_separations');
    return VibeFamilyState(
      families: families.map((f) => VibeFamily(
        id: f['id']! as String, name: f['name']! as String,
        members: members.where((m) => m['family_id'] == f['id'])
            .map((m) => m['vibe_hash']! as String).toSet(),
      )).toList(),
      separations: separated.map((r) => r['pair_key']! as String).toSet(),
    );
  }

  Future<void> merge(Set<String> hashes, String name) =>
      gateway.executeTransaction('mergeVibeFamilies', (txn) async {
        if (hashes.length < 2 || name.trim().isEmpty) throw ArgumentError('family');
        final state = await _load(txn);
        final members = <String>{...hashes};
        final oldIds = <String>{};
        for (final hash in hashes) {
          final family = state.familyOf(hash);
          if (family != null) {
            members.addAll(family.members);
            oldIds.add(family.id);
          }
        }
        final ordered = members.toList()..sort();
        for (var i = 0; i < ordered.length; i++) {
          for (var j = i + 1; j < ordered.length; j++) {
            if (state.separations.contains(VibeFamilyState.pairKey(ordered[i], ordered[j]))) {
              throw StateError('vibe_family_separation_conflict');
            }
          }
        }
        final id = oldIds.isEmpty ? const Uuid().v4() : (oldIds.toList()..sort()).first;
        for (final oldId in oldIds) {
          await txn.delete('gallery_vibe_family_members', where: 'family_id = ?', whereArgs: [oldId]);
          await txn.delete('gallery_vibe_families', where: 'id = ?', whereArgs: [oldId]);
        }
        await txn.insert('gallery_vibe_families', {'id': id, 'name': name.trim()});
        final batch = txn.batch();
        for (final hash in members) {
          batch.insert('gallery_vibe_family_members', {'vibe_hash': hash, 'family_id': id});
        }
        await batch.commit(noResult: true);
      });

  Future<void> rename(String id, String name) =>
      gateway.execute('renameVibeFamily', (db) async {
        if (name.trim().isEmpty) throw ArgumentError('name');
        await db.update('gallery_vibe_families', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
      });

  Future<void> separate(String a, String b) =>
      gateway.executeTransaction('separateVibes', (txn) async {
        if (a == b) return;
        final state = await _load(txn);
        if (state.familyOf(a)?.members.contains(b) ?? false) {
          throw StateError('vibe_family_split_first');
        }
        await txn.insert('gallery_vibe_separations',
          {'pair_key': VibeFamilyState.pairKey(a, b)},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      });

  Future<void> split(String hash) =>
      gateway.executeTransaction('splitVibeFamily', (txn) async {
        final family = (await _load(txn)).familyOf(hash);
        if (family == null) return;
        for (final other in family.members.where((m) => m != hash)) {
          await txn.insert('gallery_vibe_separations',
            {'pair_key': VibeFamilyState.pairKey(hash, other)},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await txn.delete('gallery_vibe_family_members', where: 'vibe_hash = ?', whereArgs: [hash]);
        if (family.members.length <= 2) {
          await txn.delete('gallery_vibe_family_members', where: 'family_id = ?', whereArgs: [family.id]);
          await txn.delete('gallery_vibe_families', where: 'id = ?', whereArgs: [family.id]);
        }
      });

  Future<void> restorePair(String pair) => gateway.execute('restoreVibePair',
    (db) async { await db.delete('gallery_vibe_separations', where: 'pair_key = ?', whereArgs: [pair]); });

  Future<Map<String, List<List<double>>>> cachedFeatures(int version, List<int> imageIds) =>
      gateway.execute('readVibeStyleFeatures', (db) async {
        final result = <String,List<List<double>>>{};
        for (var offset = 0; offset < imageIds.length; offset += 256) {
          final ids = imageIds.skip(offset).take(256).toList();
          final rows = await db.query('gallery_vibe_style_features',
            where: 'version = ? AND image_id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: [version, ...ids]);
          for (final r in rows) {
            try {
              result[r['cache_key']! as String] = (jsonDecode(r['features']! as String) as List)
                .map((g) => (g as List).map((v) => (v as num).toDouble()).toList()).toList();
            } catch (_) {
              // Malformed cache entries are recomputed; source records are unaffected.
            }
          }
        }
        return result;
      });

  Future<void> saveFeatures(VibeStyleSample sample, int version, List<List<double>> features) =>
      gateway.execute('saveVibeStyleFeatures', (db) async {
        await db.insert('gallery_vibe_style_features', {
          'image_id': sample.imageId, 'cache_key': sample.cacheKey,
          'version': version, 'features': jsonEncode(features),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  /// Bounded keyset pages. Encodings and source image bytes never enter this query.
  Future<List<Map<String, Object?>>> corpusPage(int afterId, {int limit = 128}) =>
      gateway.execute('queryVibeStyleCorpus', (db) => db.rawQuery(r'''
        SELECT i.id, i.file_path, i.file_size, i.modified_at,
          m.prompt, m.negative_prompt, m.model, m.seed, m.sampler, m.steps,
          m.cfg_scale, m.width, m.height, m.is_img2img, m.noise_schedule,
          m.cfg_rescale, m.smea, m.smea_dyn,
          CASE WHEN json_valid(m.raw_json) THEN CASE WHEN
            COALESCE(json_type(m.raw_json, '$.director_reference_images'), 'null') IN ('null','array') AND
            COALESCE(json_type(m.raw_json, '$.director_references'), 'null') IN ('null','array') AND
            COALESCE(json_array_length(m.raw_json, '$.director_reference_images'), 0) = 0 AND
            COALESCE(json_array_length(m.raw_json, '$.director_references'), 0) = 0 AND
            COALESCE(json_extract(m.raw_json, '$.controlnet_model'), '') = '' AND
            COALESCE(json_extract(m.raw_json, '$.image'), '') = '' AND
            COALESCE(json_extract(m.raw_json, '$.mask'), '') = ''
          THEN json_extract(m.raw_json,
            '$.v4_prompt', '$.v4_negative_prompt', '$.dynamic_thresholding',
            '$.skip_cfg_above_sigma', '$.skip_cfg_below_sigma',
            '$.deliberate_euler_ancestral_bug', '$.prefer_brownian',
            '$.uncond_scale', '$.qualityToggle', '$.ucPreset',
            '$.lora_unet_weights', '$.lora_clip_weights',
            '$.director_reference_images', '$.director_references',
            '$.controlnet_model', '$.image', '$.mask',
            '$.uncond_per_vibe', '$.wonky_vibe_correlation',
            '$.explike_fine_detail', '$.cfg_sched_eligibility',
            '$.dynamic_thresholding_mimic_scale',
            '$.dynamic_thresholding_percentile', '$.legacy_v3_extend',
            '$.minimize_sigma_inf', '$.normalize_reference_strength_multiple')
          ELSE NULL END ELSE NULL END AS extra_controls,
          (SELECT json_group_array(json_object('hash', v.vibe_hash,
            'strength', v.strength, 'info', v.info_extracted, 'ordinal', v.ordinal))
           FROM gallery_image_vibes v WHERE v.image_id = i.id) AS refs,
          CASE WHEN json_valid(m.raw_json) THEN
            json_array_length(m.raw_json, '$.reference_image_multiple')
          ELSE NULL END AS raw_ref_count
        FROM gallery_images i JOIN gallery_metadata m ON m.image_id = i.id
        WHERE i.is_deleted = 0 AND i.id > ? AND m.has_vibe = 1
        ORDER BY i.id LIMIT ?
      ''', [afterId, limit.clamp(1, 256)]));
}

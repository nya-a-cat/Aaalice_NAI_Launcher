import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/vibe/vibe_family.dart';

class VibeStyleCorpus {
  static List<VibeStyleSample> parse(List<Map<String, Object?>> rows) {
    final samples = <VibeStyleSample>[];
    for (final row in rows) {
      try {
        final refs = (jsonDecode(row['refs']! as String) as List).cast<Map>();
        if (refs.isEmpty || refs.length > 16) continue;
        final prompt = row['prompt'] as String? ?? '';
        if (prompt.trim().isEmpty) continue;
        final extra = row['extra_controls'] == null
            ? null
            : jsonDecode(row['extra_controls']! as String) as List;
        final promptKey = _hash([prompt, row['negative_prompt']]);
        // Match complete observed settings. Missing metadata is never strong evidence.
        final required = [
          'model',
          'sampler',
          'steps',
          'cfg_scale',
          'width',
          'height',
        ];
        final known = required.every((k) => row[k] != null) && extra != null;
        final noReference =
            extra != null &&
            [12, 13, 14, 15, 16].every(
              (i) =>
                  extra[i] == null ||
                  extra[i] == '' ||
                  (extra[i] is List && (extra[i] as List).isEmpty),
            );
        final complete =
            known &&
            noReference &&
            row['is_img2img'] != 1 &&
            row['raw_ref_count'] == refs.length &&
            refs.every(
              (r) =>
                  r['strength'] is num &&
                  r['info'] is num &&
                  r['ordinal'] is num,
            );
        final controls = [
          prompt,
          row['negative_prompt'],
          for (final key in required) row[key],
          row['noise_schedule'],
          row['cfg_rescale'],
          row['smea'],
          row['smea_dyn'],
          extra,
        ];
        for (final ref in refs) {
          // Order and values of the remaining Vibes must match for a controlled pair.
          final others = refs
              .where((r) => !identical(r, ref))
              .map((r) => [r['hash'], r['strength'], r['info'], r['ordinal']])
              .toList();
          final recipe = complete
              ? _hash([
                  controls,
                  ref['strength'],
                  ref['info'],
                  ref['ordinal'],
                  others,
                ])
              : '';
          samples.add(
            VibeStyleSample(
              imageId: (row['id']! as num).toInt(),
              path: row['file_path']! as String,
              size: (row['file_size']! as num).toInt(),
              modifiedAt: (row['modified_at']! as num).toInt(),
              hash: ref['hash'] as String,
              recipe: recipe,
              promptKey: promptKey,
              seed: (row['seed'] as num?)?.toInt(),
            ),
          );
        }
      } catch (_) {
        // A malformed row remains available in the exact Vibe browser.
      }
    }
    return samples;
  }

  static String _hash(Object? data) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(data)))).toString();
  static Object? _canonical(Object? data) {
    if (data is Map) {
      final keys = data.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonical(data[k])};
    }
    if (data is List) return data.map(_canonical).toList();
    return data;
  }

  /// Fair, deterministic sampling across codes and independent prompt recipes.
  /// Prefer matched controls, then fill with diverse existing outputs.
  static List<VibeStyleSample> select(
    List<VibeStyleSample> all, {
    int maxImages = 1600,
    int perCode = 16,
  }) {
    final recipeCodes = <String, Set<String>>{};
    for (final s in all.where((s) => s.recipe.isNotEmpty)) {
      recipeCodes.putIfAbsent(s.recipe, () => {}).add(s.hash);
    }
    final byCode = <String, List<VibeStyleSample>>{};
    for (final s in all) {
      byCode.putIfAbsent(s.hash, () => []).add(s);
    }
    for (final bucket in byCode.values) {
      bucket.sort((a, b) {
        final ac = (recipeCodes[a.recipe]?.length ?? 0) > 1 ? 0 : 1;
        final bc = (recipeCodes[b.recipe]?.length ?? 0) > 1 ? 0 : 1;
        return ac != bc ? ac.compareTo(bc) : a.imageId.compareTo(b.imageId);
      });
      final seen = <String>{};
      final diverse = bucket.where((s) => seen.add(s.promptKey)).toList();
      final selectedIds = diverse.map((s) => s.imageId).toSet();
      diverse.addAll(bucket.where((s) => !selectedIds.contains(s.imageId)));
      bucket
        ..clear()
        ..addAll(diverse.take(perCode));
    }
    final keys = byCode.keys.toList()
      ..sort((a, b) {
        final count = byCode[b]!.length.compareTo(byCode[a]!.length);
        return count != 0 ? count : a.compareTo(b);
      });
    final activeKeys = keys.take(300).toList()..sort();
    final selected = <VibeStyleSample>[];
    final imageIds = <int>{};
    for (var round = 0; round < perCode; round++) {
      for (final code in activeKeys) {
        final bucket = byCode[code]!;
        if (round >= bucket.length) continue;
        final s = bucket[round];
        if (!imageIds.contains(s.imageId) && imageIds.length >= maxImages) {
          continue;
        }
        imageIds.add(s.imageId);
        selected.add(s);
      }
    }
    return selected;
  }
}

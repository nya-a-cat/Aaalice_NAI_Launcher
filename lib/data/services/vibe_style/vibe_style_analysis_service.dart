import 'dart:io';
import 'dart:math' as math;

import '../../../core/database/datasources/gallery_vibe_family_repository.dart';
import '../../models/vibe/vibe_family.dart';
import 'vibe_style_features.dart';
import 'vibe_style_worker.dart';

class VibeStyleProgress {
  const VibeStyleProgress(this.phase, this.completed, this.total);
  final String phase;
  final int completed;
  final int total;
}

class VibeStyleAnalysisService {
  VibeStyleAnalysisService(this.repository);
  final GalleryVibeFamilyRepository repository;
  final _worker = VibeStyleWorker();
  bool _cancelled = false;
  bool _running = false;

  void cancel() { _cancelled = true; _worker.cancel(); }
  void _check() { if (_cancelled) throw VibeStyleCancelled(); }

  Future<VibeStyleAnalysis> analyze({
    required void Function(VibeStyleProgress progress) onProgress,
  }) async {
    if (_running) throw StateError('Vibe analysis already running');
    _running = true;
    _cancelled = false;
    try {
      final all = <VibeStyleSample>[];
      var afterId = 0, available = 0;
      const corpusLimit = 12000;
      while (available < corpusLimit) {
        _check();
        final rows = await repository.corpusPage(afterId, limit: math.min(128, corpusLimit - available));
        _check();
        if (rows.isEmpty) break;
        afterId = (rows.last['id']! as num).toInt();
        available += rows.length;
        all.addAll(await _worker.run<List<VibeStyleSample>>('parse', rows));
        onProgress(VibeStyleProgress('prepare', available, 0));
      }
      _check();
      final selected = await _worker.run<List<VibeStyleSample>>('select', all);
      final unique = <String,VibeStyleSample>{for (final s in selected) s.cacheKey: s};
      final cached = await repository.cachedFeatures(VibeStyleFeatures.version,
        unique.values.map((s) => s.imageId).toList());
      final features = <String,List<List<double>>>{};
      var completed = 0;
      for (final sample in unique.values) {
        _check();
        List<List<double>>? value = cached[sample.cacheKey];
        if (value != null) {
          try {
            if (!VibeStyleFeatures.isValid(value) ||
                !VibeStyleFeatures.matches(await File(sample.path).stat(), sample)) value = null;
          } catch (_) { value = null; }
        }
        if (value == null) {
          try {
            value = await _worker.run<List<List<double>>?>('features', sample,
              timeout: const Duration(seconds: 10));
          } on VibeStyleCancelled {
            rethrow;
          } catch (_) {
            // Temporary read/decode errors are retried next time; no failed cache entries.
          }
          _check();
          if (value != null) {
            await repository.saveFeatures(sample, VibeStyleFeatures.version, value);
          }
        }
        if (value != null) features[sample.cacheKey] = value;
        completed++;
        onProgress(VibeStyleProgress('features', completed, unique.length));
      }
      _check();
      onProgress(VibeStyleProgress('rank', completed, unique.length));
      final matches = await _worker.run<List<VibeStyleMatch>>('rank', [selected, features]);
      _check();
      return VibeStyleAnalysis(matches: matches, scanned: features.length,
        skipped: unique.length - features.length, available: available, selected: unique.length);
    } finally {
      _running = false;
    }
  }
}

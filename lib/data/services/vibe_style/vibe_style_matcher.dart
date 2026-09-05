import 'dart:math' as math;
import '../../models/vibe/vibe_family.dart';
import 'vibe_style_features.dart';

/// Heuristic ranking of existing outputs. No inferred identity is persisted.
class VibeStyleMatcher {
  static List<VibeStyleMatch> rank(List<VibeStyleSample> samples,
      Map<String, List<List<double>>> features) {
    final byCode = <String, List<VibeStyleSample>>{};
    for (final s in samples) {
      final f = features[s.cacheKey];
      if (f == null || !VibeStyleFeatures.isValid(f)) continue;
      byCode.putIfAbsent(s.hash, () => []).add(s);
    }
    final codes = byCode.keys.toList()..sort();
    final prototypes = {for (final code in codes)
      code: _medianFeatures(byCode[code]!.map((s) => features[s.cacheKey]!).toList())};
    // Rank within this gallery; feature weights favor dimensions stable within codes.
    final weights = _weights(byCode, features);
    final matches = <VibeStyleMatch>[];
    for (var i = 0; i < codes.length; i++) {
      for (var j = i + 1; j < codes.length; j++) {
        final a = codes[i], b = codes[j];
        final controls = <String, List<(VibeStyleSample,VibeStyleSample)>>{};
        for (final left in byCode[a]!) {
          for (final right in byCode[b]!) {
            if (left.imageId == right.imageId || left.recipe.isEmpty ||
                left.recipe != right.recipe) continue;
            controls.putIfAbsent(left.promptKey, () => []).add((left,right));
          }
        }
        final selected = <(VibeStyleSample,VibeStyleSample)>[];
        for (final pairs in controls.values) {
          pairs.sort((x,y) {
            int seedPriority((VibeStyleSample,VibeStyleSample) p) =>
              p.$1.seed != null && p.$1.seed == p.$2.seed ? 0 : 1;
            final order = seedPriority(x).compareTo(seedPriority(y));
            return order != 0 ? order : x.$1.imageId.compareTo(y.$1.imageId);
          });
          selected.add(pairs.first);
        }
        final groups = selected.map((p) =>
          _similarities(features[p.$1.cacheKey]!, features[p.$2.cacheKey]!)).toList();
        // Same-image examples in a multivibe setup cannot identify either code.
        if (groups.isEmpty && byCode[a]!.map((s) => s.imageId).toSet()
            .intersection(byCode[b]!.map((s) => s.imageId).toSet()).isNotEmpty) continue;
        final dims = groups.isEmpty ? _similarities(prototypes[a]!, prototypes[b]!) :
          List.generate(4, (d) => median(groups.map((g) => g[d]).toList()));
        final scores = groups.map((g) => _score(g, weights)).toList();
        final similarity = _score(dims, weights);
        final stability = scores.length < 2 ? 0.0 :
          (1 - (scores.reduce(math.max) - scores.reduce(math.min))).clamp(0.0,1.0);
        if (selected.isEmpty) {
          selected.add((byCode[a]!.first, byCode[b]!.first));
        }
        matches.add(VibeStyleMatch(left: a, right: b, similarity: similarity,
          dimensions: dims, recipeCount: controls.length,
          sameSeedCount: controls.isEmpty ? 0 : selected.where((p) =>
            p.$1.seed != null && p.$1.seed == p.$2.seed).length,
          stability: stability, examples: selected.take(3).toList()));
      }
    }
    matches.sort((a,b) {
      final score = b.similarity.compareTo(a.similarity);
      return score != 0 ? score : VibeFamilyState.pairKey(a.left,a.right)
          .compareTo(VibeFamilyState.pairKey(b.left,b.right));
    });
    final nearest = <String, String>{};
    for (final m in matches) {
      nearest.putIfAbsent(m.left, () => m.right);
      nearest.putIfAbsent(m.right, () => m.left);
    }
    // At most three neighbors per encoding; avoid all-pairs UI/memory growth.
    final used = <String,int>{};
    return matches.where((m) {
      if ((used[m.left] ?? 0) >= 3 || (used[m.right] ?? 0) >= 3) return false;
      used.update(m.left, (n) => n+1, ifAbsent: () => 1);
      used.update(m.right, (n) => n+1, ifAbsent: () => 1);
      return true;
    }).map((m) => VibeStyleMatch(
      left: m.left, right: m.right, similarity: m.similarity,
      dimensions: m.dimensions, recipeCount: m.recipeCount,
      sameSeedCount: m.sameSeedCount, stability: m.stability, examples: m.examples,
      mutual: nearest[m.left] == m.right && nearest[m.right] == m.left,
    )).toList()..sort((a,b) {
      final controlled = (b.hasControls ? 1 : 0).compareTo(a.hasControls ? 1 : 0);
      return controlled != 0 ? controlled : b.similarity.compareTo(a.similarity);
    });
  }

  static List<double> _similarities(List<List<double>> a, List<List<double>> b) =>
      List.generate(4, (g) {
        if (a[g].length != b[g].length) return 0.0;
        var distance = 0.0;
        for (var i = 0; i < a[g].length; i++) {
          // Root histograms preserve small bins without arbitrary per-bin scaling.
          final delta = math.sqrt(math.max(0,a[g][i])) - math.sqrt(math.max(0,b[g][i]));
          distance += delta * delta;
        }
        return (1 - math.sqrt(distance / a[g].length)).clamp(0.0,1.0);
      });

  static double _score(List<double> dimensions, List<double> weights) =>
      List.generate(4, (i) => dimensions[i] * weights[i]).reduce((a,b) => a+b);

  static List<double> _weights(Map<String,List<VibeStyleSample>> codes,
      Map<String,List<List<double>>> features) {
    const base = [0.3,0.3,0.3,0.1];
    final variability = <List<double>>[];
    for (final bucket in codes.values.where((b) => b.length >= 3)) {
      final center = _medianFeatures(bucket.map((s) => features[s.cacheKey]!).toList());
      for (final s in bucket) {
        variability.add(_similarities(center, features[s.cacheKey]!).map((v) => 1-v).toList());
      }
    }
    if (variability.isEmpty) return base;
    final adjusted = List.generate(4, (g) => base[g] /
      (0.1 + median(variability.map((v) => v[g]).toList())));
    final sum = adjusted.reduce((a,b) => a+b);
    return adjusted.map((v) => v / sum).toList();
  }

  static List<List<double>> _medianFeatures(List<List<List<double>>> features) =>
      List.generate(4, (g) => List.generate(features.first[g].length,
        (i) => median(features.map((f) => f[g][i]).toList())));

  static double median(List<double> values) {
    values.sort();
    final m = values.length ~/ 2;
    return values.length.isOdd ? values[m] : (values[m-1]+values[m])/2;
  }
}

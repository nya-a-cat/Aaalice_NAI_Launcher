import 'dart:math' as math;
import 'dart:typed_data';

/// Rotation-pooled gray-level co-occurrence and low-resolution DCT energy.
class VibeStyleTexture {
  static List<double> describe(Float64List pixels, int width, int height) {
    const levels = 16;
    final matrix = List<double>.filled(levels * levels, 0);
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final a = (pixels[y * width + x] * 15).round();
        for (final offset in [(1, 0), (0, 1), (1, 1), (-1, 1)]) {
          final xx = x + offset.$1, yy = y + offset.$2;
          if (xx < 0 || xx >= width || yy >= height) continue;
          final b = (pixels[yy * width + xx] * 15).round();
          matrix[a * levels + b]++;
          matrix[b * levels + a]++;
          count += 2;
        }
      }
    }
    var contrast = 0.0, homogeneity = 0.0, energy = 0.0, entropy = 0.0;
    for (var a = 0; a < levels; a++) {
      for (var b = 0; b < levels; b++) {
        final p = matrix[a * levels + b] / math.max(1, count);
        final delta = (a - b).abs();
        contrast += p * delta * delta / 225;
        homogeneity += p / (1 + delta * delta);
        energy += p * p;
        if (p > 0) entropy -= p * math.log(p) / math.log(256);
      }
    }
    // Fixed-size transform bounds CPU cost independently of original resolution.
    const side = 16;
    final low = List.generate(side * side, (i) {
      final x = math.min(width - 1, ((i % side + 0.5) * width / side).floor());
      final y = math.min(
        height - 1,
        ((i ~/ side + 0.5) * height / side).floor(),
      );
      return pixels[y * width + x];
    });
    final cosines = List.generate(
      side,
      (u) => List.generate(
        side,
        (x) => math.cos(math.pi * (2 * x + 1) * u / (2 * side)),
      ),
    );
    final bands = List<double>.filled(4, 0);
    for (var v = 0; v < side; v++) {
      for (var u = 0; u < side; u++) {
        if (u == 0 && v == 0) continue;
        var coefficient = 0.0;
        for (var y = 0; y < side; y++) {
          for (var x = 0; x < side; x++) {
            coefficient += low[y * side + x] * cosines[u][x] * cosines[v][y];
          }
        }
        final radial = u + v;
        final band = radial < 4
            ? 0
            : radial < 8
            ? 1
            : radial < 16
            ? 2
            : 3;
        bands[band] += coefficient * coefficient * (u == 0 || v == 0 ? 0.5 : 1);
      }
    }
    final total = bands.reduce((a, b) => a + b);
    if (total > 1e-12) {
      for (var i = 0; i < bands.length; i++) {
        bands[i] /= total;
      }
    } else {
      bands.fillRange(0, 4, 0);
    }
    return [
      contrast,
      homogeneity,
      energy,
      entropy,
      ...bands,
    ].map((v) => v.clamp(0.0, 1.0)).toList();
  }
}

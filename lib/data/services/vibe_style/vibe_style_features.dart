import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/vibe/vibe_family.dart';
import 'vibe_style_texture.dart';

/// Handcrafted descriptors. No network, inference, or source file writers.
class VibeStyleFeatures {
  static const version = 1;
  static const maximumBytes = 24 * 1024 * 1024;
  static const maximumPixels = 8 * 1024 * 1024;

  static Future<List<List<double>>?> read(VibeStyleSample sample) async {
    final file = File(sample.path);
    final before = await file.stat();
    if (!matches(before, sample) || before.size > maximumBytes) return null;
    // Read mode is explicit. Reads are bounded even if the source grows.
    final handle = await file.open(mode: FileMode.read);
    late final Uint8List bytes;
    try {
      bytes = await handle.read(maximumBytes + 1);
    } finally {
      await handle.close();
    }
    if (bytes.length != before.size || !matches(await file.stat(), sample)) {
      return null;
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > maximumPixels ||
        info.numFrames != 1) {
      return null;
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    final result = extract(img.bakeOrientation(decoded));
    return matches(await file.stat(), sample) ? result : null;
  }

  static bool matches(FileStat stat, VibeStyleSample s) =>
      stat.type == FileSystemEntityType.file &&
      stat.size == s.size &&
      stat.modified.millisecondsSinceEpoch == s.modifiedAt;

  static bool isValid(List<List<double>> features) {
    const dimensions = [40, 18, 10, 27];
    return features.length == 4 &&
        List.generate(
          4,
          (i) =>
              features[i].length == dimensions[i] &&
              features[i].every((v) => v.isFinite && v >= 0 && v <= 1),
        ).every((v) => v);
  }

  /// All resize and color operations target new in-memory images only.
  static List<List<double>> extract(img.Image source) {
    const longest = 256;
    final scale = math.min(
      1.0,
      longest / math.max(source.width, source.height),
    );
    final image = img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    final w = image.width, h = image.height, n = w * h;
    final luminance = Float64List(n);
    final color = List<double>.filled(40, 0);
    final spatial = List<double>.filled(27, 0);
    final cells = List<int>.filled(9, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final alpha = p.aNormalized.toDouble();
        final r = p.rNormalized * alpha + 1 - alpha;
        final g = p.gNormalized * alpha + 1 - alpha;
        final b = p.bNormalized * alpha + 1 - alpha;
        final high = math.max(r, math.max(g, b));
        final low = math.min(r, math.min(g, b));
        final delta = high - low;
        final sat = high == 0 ? 0.0 : delta / high;
        var hue = 0.0;
        if (delta > 0) {
          hue = high == r
              ? ((g - b) / delta) % 6
              : high == g
              ? (b - r) / delta + 2
              : (r - g) / delta + 4;
          hue = (hue / 6) % 1;
        }
        color[(hue * 24).floor().clamp(0, 23)] += sat;
        color[24 + (sat * 8).floor().clamp(0, 7)]++;
        color[32 + (high * 8).floor().clamp(0, 7)]++;
        final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b).toDouble();
        luminance[y * w + x] = lum;
        final cell = math.min<int>(2, y * 3 ~/ h) * 3 + math.min<int>(2, x * 3 ~/ w);
        cells[cell]++;
        spatial[cell * 3] += lum;
        spatial[cell * 3 + 1] += sat;
      }
    }
    _normalize(color, 0, 24);
    _normalize(color, 24, 32);
    _normalize(color, 32, 40);
    final edges = List<double>.filled(10, 0);
    final texture = List<double>.filled(10, 0, growable: true);
    const offsets = [
      (-1, -1),
      (0, -1),
      (1, -1),
      (1, 0),
      (1, 1),
      (0, 1),
      (-1, 1),
      (-1, 0),
    ];
    var interiors = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        interiors++;
        final i = y * w + x;
        final center = luminance[i];
        final dx = luminance[i + 1] - luminance[i - 1];
        final dy = luminance[i + w] - luminance[i - w];
        final magnitude = math.sqrt(dx * dx + dy * dy) / math.sqrt2;
        final direction = ((math.atan2(dy, dx) + math.pi) / (2 * math.pi) * 8)
            .floor()
            .clamp(0, 7);
        edges[direction] += magnitude;
        edges[8] += magnitude;
        if (magnitude > 0.12) edges[9]++;
        final bits = offsets
            .map((o) => luminance[(y + o.$2) * w + x + o.$1] >= center ? 1 : 0)
            .toList();
        var transitions = 0;
        for (var j = 0; j < 8; j++) {
          if (bits[j] != bits[(j + 1) % 8]) transitions++;
        }
        texture[transitions <= 2 ? bits.fold<int>(0, (a, b) => a + b) : 9]++;
        final cell = math.min<int>(2, y * 3 ~/ h) * 3 + math.min<int>(2, x * 3 ~/ w);
        spatial[cell * 3 + 2] += magnitude;
      }
    }
    _normalize(edges, 0, 8);
    edges[8] /= math.max(1, interiors);
    edges[9] /= math.max(1, interiors);
    _normalize(texture, 0, 10);
    texture.addAll(VibeStyleTexture.describe(luminance, w, h));
    for (var i = 0; i < 27; i++) {
      spatial[i] /= math.max(1, cells[i ~/ 3]);
    }
    // Layout deliberately receives a low weight: it is content-sensitive.
    return [color, texture, edges, spatial];
  }

  static void _normalize(List<double> x, int start, int end) {
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += x[i];
    }
    if (sum > 0) {
      for (var i = start; i < end; i++) {
        x[i] /= sum;
      }
    }
  }
}

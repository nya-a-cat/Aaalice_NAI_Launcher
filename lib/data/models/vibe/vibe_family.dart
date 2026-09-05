import 'dart:convert';

class VibeFamily {
  const VibeFamily({
    required this.id,
    required this.name,
    required this.members,
  });
  final String id;
  final String name;
  final Set<String> members;
}

/// Explicit user decisions. Analysis never modifies membership or separations.
class VibeFamilyState {
  const VibeFamilyState({
    this.families = const [],
    this.separations = const {},
  });
  final List<VibeFamily> families;
  final Set<String> separations;

  static String pairKey(String a, String b) {
    final sorted = [a, b]..sort();
    return jsonEncode(sorted);
  }

  VibeFamily? familyOf(String hash) {
    for (final family in families) {
      if (family.members.contains(hash)) return family;
    }
    return null;
  }

  bool excludes(String a, String b) {
    final left = familyOf(a)?.members ?? {a};
    final right = familyOf(b)?.members ?? {b};
    if (left.contains(b)) return true;
    return left.any(
      (x) => right.any((y) => separations.contains(pairKey(x, y))),
    );
  }
}

class VibeFamilySummary {
  const VibeFamilySummary({
    required this.hash,
    required this.exampleCount,
    required this.previewPath,
  });
  final String hash;
  final int exampleCount;
  final String? previewPath;
  String get shortHash => hash.length > 10 ? hash.substring(0, 10) : hash;
}

class VibeStyleSample {
  const VibeStyleSample({
    required this.imageId,
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.hash,
    required this.recipe,
    required this.promptKey,
    required this.seed,
  });
  final int imageId;
  final String path;
  final int size;
  final int modifiedAt;
  final String hash;

  /// All observed generation controls, including OTHER Vibes and target strength.
  final String recipe;
  final String promptKey;
  final int? seed;
  String get cacheKey => jsonEncode([imageId, path, size, modifiedAt]);
}

class VibeStyleMatch {
  const VibeStyleMatch({
    required this.left,
    required this.right,
    required this.similarity,
    required this.dimensions,
    required this.recipeCount,
    required this.sameSeedCount,
    required this.stability,
    required this.examples,
    this.mutual = false,
  });
  final String left;
  final String right;

  /// Relative visual similarity, never a probability of shared source identity.
  final double similarity;
  final List<double> dimensions;
  final int recipeCount;
  final int sameSeedCount;
  final double stability;
  final List<(VibeStyleSample, VibeStyleSample)> examples;
  final bool mutual;
  bool get hasControls => recipeCount >= 2 && stability >= 0.8 && mutual;
}

class VibeStyleAnalysis {
  const VibeStyleAnalysis({
    required this.matches,
    required this.scanned,
    required this.skipped,
    required this.available,
    required this.selected,
  });
  final List<VibeStyleMatch> matches;
  final int scanned;
  final int skipped;
  final int available;
  final int selected;
}

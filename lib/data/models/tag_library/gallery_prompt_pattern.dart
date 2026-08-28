enum GalleryPromptPatternType { artist, effect }

class GalleryPromptPatternCandidate {
  const GalleryPromptPatternCandidate({
    required this.type,
    required this.prompt,
    required this.tags,
    required this.imageCount,
    this.promptVariantCount = 1,
    required this.confidence,
    required this.cohesion,
    required this.examplePaths,
  });

  final GalleryPromptPatternType type;
  final String prompt;
  final List<String> tags;
  final int imageCount;
  final int promptVariantCount;
  final double confidence;
  final double cohesion;
  final List<String> examplePaths;

  String get id => '${type.name}:$prompt';
}

class GalleryPromptMiningResult {
  const GalleryPromptMiningResult({
    required this.scannedImageCount,
    required this.totalAvailableImageCount,
    required this.artistPatterns,
    required this.effectPatterns,
  });

  final int scannedImageCount;
  final int totalAvailableImageCount;
  final List<GalleryPromptPatternCandidate> artistPatterns;
  final List<GalleryPromptPatternCandidate> effectPatterns;

  bool get wasLimited => scannedImageCount < totalAvailableImageCount;
  bool get isEmpty => artistPatterns.isEmpty && effectPatterns.isEmpty;
}

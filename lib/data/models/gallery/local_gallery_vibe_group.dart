import '../vibe/vibe_reference.dart';

/// One local-gallery image that was generated with a discovered Vibe.
class LocalGalleryVibeExample {
  const LocalGalleryVibeExample({
    required this.imageId,
    required this.filePath,
    required this.createdAt,
    required this.strength,
    required this.infoExtracted,
    this.encodingModel,
  });

  final int imageId;
  final String filePath;
  final DateTime createdAt;
  final double strength;
  final double infoExtracted;
  final String? encodingModel;
}

/// Exact Vibe encoding grouped with the local outputs that used it.
///
/// The fingerprint is a SHA-256 digest of the normalized encoding. It is an
/// exact identity key; visually similar encodings remain separate groups.
class LocalGalleryVibeGroup {
  const LocalGalleryVibeGroup({
    required this.fingerprint,
    required this.vibeEncoding,
    required this.exampleCount,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.examples,
    this.encodingModels = const [],
  });

  final String fingerprint;
  final String vibeEncoding;
  final int exampleCount;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final List<LocalGalleryVibeExample> examples;
  final List<String> encodingModels;

  String get shortFingerprint => fingerprint.length <= 10
      ? fingerprint
      : fingerprint.substring(0, 10);

  String get displayName => 'Vibe $shortFingerprint';

  LocalGalleryVibeExample? get earliestExample =>
      examples.isEmpty ? null : examples.first;

  VibeReference toVibeReference({LocalGalleryVibeExample? example}) {
    final selected = example ?? earliestExample;
    return VibeReference(
      displayName: displayName,
      vibeEncoding: vibeEncoding,
      strength: VibeReference.sanitizeStrength(selected?.strength ?? 0.6),
      infoExtracted: VibeReference.sanitizeInfoExtracted(
        selected?.infoExtracted ?? 0.7,
      ),
      encodingModel: selected?.encodingModel ??
          (encodingModels.isEmpty ? null : encodingModels.first),
      sourceType: VibeSourceType.png,
    );
  }
}

class GalleryVibeBackfillProgress {
  const GalleryVibeBackfillProgress({
    required this.processed,
    required this.total,
    required this.discoveredReferences,
  });

  final int processed;
  final int total;
  final int discoveredReferences;

  double get fraction => total == 0 ? 1 : processed / total;
}

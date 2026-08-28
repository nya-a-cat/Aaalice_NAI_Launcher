import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autocomplete/completion_models.dart';
import '../../core/autocomplete/tag_catalog_repository.dart';
import '../../core/database/datasources/gallery_data_source.dart';
import '../models/tag_library/gallery_prompt_pattern.dart';
import 'gallery_prompt_pattern_analyzer.dart';

export 'gallery_prompt_pattern_analyzer.dart';

final galleryPromptPatternMiningServiceProvider = Provider((ref) {
  final service = GalleryPromptPatternMiningService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

class GalleryPromptPatternMiningService {
  GalleryPromptPatternMiningService({
    GalleryDataSource? galleryDataSource,
    TagCatalogRepository? tagCatalogRepository,
  }) : _galleryDataSource = galleryDataSource ?? GalleryDataSource(),
       _tagCatalogRepository = tagCatalogRepository ?? TagCatalogRepository();

  static const int defaultCorpusLimit = 20000;

  final GalleryDataSource _galleryDataSource;
  final TagCatalogRepository _tagCatalogRepository;

  /// Reads the gallery index and bundled tag catalog only.
  ///
  /// This feature must never write, rename, move, or otherwise mutate source
  /// image files or their embedded metadata.
  Future<GalleryPromptMiningResult> mine({
    int corpusLimit = defaultCorpusLimit,
  }) async {
    await _galleryDataSource.initialize();
    final snapshot = await _galleryDataSource.queryPromptCorpus(
      limit: corpusLimit,
    );
    if (snapshot.entries.isEmpty) {
      return GalleryPromptMiningResult(
        scannedImageCount: 0,
        totalAvailableImageCount: snapshot.totalCount,
        artistPatterns: const [],
        effectPatterns: const [],
      );
    }

    final lookupTerms = await Isolate.run(
      () => GalleryPromptPatternAnalyzer.collectLookupTerms(snapshot.entries),
    );
    final catalogRecords = await _tagCatalogRepository.resolveExactTags(
      lookupTerms,
    );
    final categoriesByTerm = <String, TagCategory>{};
    final canonicalTermsByTerm = <String, String>{};
    for (final entry in catalogRecords.entries) {
      categoriesByTerm[entry.key] = entry.value.category;
      categoriesByTerm[entry.value.canonicalTag] = entry.value.category;
      canonicalTermsByTerm[entry.key] = entry.value.canonicalTag;
      canonicalTermsByTerm[entry.value.canonicalTag] =
          entry.value.canonicalTag;
    }
    return Isolate.run(
      () => GalleryPromptPatternAnalyzer.analyze(
        snapshot,
        categoriesByTerm,
        canonicalTermsByTerm: canonicalTermsByTerm,
      ),
    );
  }

  Future<void> dispose() => _tagCatalogRepository.dispose();
}

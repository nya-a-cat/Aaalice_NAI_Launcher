import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autocomplete/completion_models.dart';
import '../../core/autocomplete/tag_catalog_repository.dart';
import '../../core/database/datasources/gallery_data_source.dart';
import '../../core/utils/prompt_tag_utils.dart';
import '../models/tag_library/gallery_prompt_pattern.dart';

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
    final categoriesByTerm = {
      for (final entry in catalogRecords.entries)
        entry.key: entry.value.category,
    };
    return Isolate.run(
      () => GalleryPromptPatternAnalyzer.analyze(
        snapshot,
        categoriesByTerm,
      ),
    );
  }

  Future<void> dispose() => _tagCatalogRepository.dispose();
}

abstract final class GalleryPromptPatternAnalyzer {
  static const int _maxArtistLength = 6;
  static const int _maxEffectLength = 8;
  static const int _maxResultsPerType = 80;
  static const int _maxExamples = 6;

  static final RegExp _outerWeightPrefix = RegExp(r'^[\{\[\(]+');
  static final RegExp _outerWeightSuffix = RegExp(r'[\}\]\)]+$');
  static final RegExp _numericWeight = RegExp(
    r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*::([\s\S]*)::$',
  );
  static final RegExp _suffixWeight = RegExp(r':\s*-?\d+(?:\.\d+)?$');
  static final RegExp _artistPrefix = RegExp(
    r'^artist\s*:\s*',
    caseSensitive: false,
  );
  static final RegExp _effectKeyword = RegExp(
    r'(^|_)(masterpiece|quality|aesthetic|absurdres|highres|resolution|'
    r'detailed|detail|sharp|focus|bokeh|lighting|light|shadow|glow|'
    r'cinematic|dramatic|volumetric|rimlight|backlight|ray|color|'
    r'palette|chromatic|contrast|saturation|monochrome|greyscale|pastel|'
    r'vibrant|render|realistic|photorealistic|anime|illustration|painting|'
    r'watercolor|sketch|lineart|shading|impasto|grain|lens|blur|fisheye|'
    r'perspective|composition|angle|portrait|landscape|atmosphere|fog|'
    r'mist|haze|sparkle|particle|texture|brushstroke|scenery|background)'
    r'(_|$)',
  );

  static Set<String> collectLookupTerms(
    List<GalleryPromptCorpusEntry> corpus,
  ) {
    final terms = <String>{};
    for (final entry in corpus) {
      for (final rawTag in PromptTagUtils.splitForDisplay(entry.prompt)) {
        final term = _parseTag(rawTag).lookupTerm;
        if (term.isNotEmpty) terms.add(term);
      }
    }
    return terms;
  }

  static GalleryPromptMiningResult analyze(
    GalleryPromptCorpusSnapshot snapshot,
    Map<String, TagCategory> categoriesByTerm,
  ) {
    final documentCount = snapshot.entries.length;
    final tagDocumentFrequency = <String, int>{};
    final pairDocumentFrequency = <String, int>{};
    final artistPatterns = <String, _PatternAccumulator>{};
    final effectPatterns = <String, _PatternAccumulator>{};

    for (final entry in snapshot.entries) {
      final tags = PromptTagUtils.splitForDisplay(entry.prompt)
          .map(_parseTag)
          .where((tag) => tag.lookupTerm.isNotEmpty)
          .map(
            (tag) => tag.withCategory(categoriesByTerm[tag.lookupTerm]),
          )
          .toList(growable: false);
      if (tags.length < 2) continue;

      for (final tag in tags.map((tag) => tag.patternToken).toSet()) {
        tagDocumentFrequency.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
      _collectRuns(
        tags,
        (tag) => tag.isArtist,
        GalleryPromptPatternType.artist,
        _maxArtistLength,
        entry,
        artistPatterns,
        pairDocumentFrequency,
      );
      _collectRuns(
        tags,
        (tag) => tag.isEffect,
        GalleryPromptPatternType.effect,
        _maxEffectLength,
        entry,
        effectPatterns,
        pairDocumentFrequency,
      );
    }

    return GalleryPromptMiningResult(
      scannedImageCount: documentCount,
      totalAvailableImageCount: snapshot.totalCount,
      artistPatterns: _rank(
        artistPatterns.values,
        tagDocumentFrequency,
        pairDocumentFrequency,
        documentCount,
        minimumSupport: 2,
      ),
      effectPatterns: _rank(
        effectPatterns.values,
        tagDocumentFrequency,
        pairDocumentFrequency,
        documentCount,
        minimumSupport: max(2, min(8, (documentCount * 0.001).ceil())),
      ),
    );
  }

  static void _collectRuns(
    List<_ParsedPromptTag> tags,
    bool Function(_ParsedPromptTag tag) accepts,
    GalleryPromptPatternType type,
    int maximumLength,
    GalleryPromptCorpusEntry source,
    Map<String, _PatternAccumulator> patterns,
    Map<String, int> pairDocumentFrequency,
  ) {
    final seenPatterns = <String>{};
    final seenPairs = <String>{};
    var runStart = 0;
    while (runStart < tags.length) {
      while (runStart < tags.length && !accepts(tags[runStart])) {
        runStart++;
      }
      if (runStart >= tags.length) break;
      var runEnd = runStart;
      while (runEnd < tags.length && accepts(tags[runEnd])) {
        runEnd++;
      }
      final run = tags.sublist(runStart, runEnd);
      for (var start = 0; start < run.length - 1; start++) {
        final maxLength = min(maximumLength, run.length - start);
        for (var length = 2; length <= maxLength; length++) {
          final slice = run.sublist(start, start + length);
          final key = slice.map((tag) => tag.patternToken).join('\u0001');
          if (!seenPatterns.add(key)) continue;
          patterns
              .putIfAbsent(
                key,
                () => _PatternAccumulator(
                  type: type,
                  prompt: slice.map((tag) => tag.displayToken).join(', '),
                  patternTokens: slice
                      .map((tag) => tag.patternToken)
                      .toList(growable: false),
                  displayTags: slice
                      .map((tag) => tag.displayToken)
                      .toList(growable: false),
                ),
              )
              .add(source.filePath);
        }
      }
      for (var index = 0; index < run.length - 1; index++) {
        final pairKey = '${run[index].patternToken}\u0001'
            '${run[index + 1].patternToken}';
        if (seenPairs.add(pairKey)) {
          pairDocumentFrequency.update(
            pairKey,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
      runStart = runEnd + 1;
    }
  }

  static List<GalleryPromptPatternCandidate> _rank(
    Iterable<_PatternAccumulator> values,
    Map<String, int> tagDocumentFrequency,
    Map<String, int> pairDocumentFrequency,
    int documentCount, {
    required int minimumSupport,
  }) {
    if (documentCount == 0) return const [];
    final candidates = values
        .where((value) => value.imageCount >= minimumSupport)
        .map((value) {
          final cohesion = _cohesion(
            value.patternTokens,
            tagDocumentFrequency,
            pairDocumentFrequency,
            documentCount,
          );
          final supportScore = 1 - exp(-value.imageCount / 3);
          final lengthScore = min(1.0, (value.patternTokens.length - 1) / 4);
          final confidence =
              0.5 * supportScore + 0.35 * cohesion + 0.15 * lengthScore;
          return GalleryPromptPatternCandidate(
            type: value.type,
            prompt: value.prompt,
            tags: value.displayTags,
            imageCount: value.imageCount,
            confidence: confidence.clamp(0.0, 1.0).toDouble(),
            cohesion: cohesion,
            examplePaths: List.unmodifiable(value.examplePaths),
          );
        })
        .toList();
    candidates.sort(_compareCandidates);
    final shortlist = candidates.take(_maxResultsPerType * 4).toList();
    final pruned = shortlist.where((candidate) {
      return !shortlist.any(
        (other) =>
            other.id != candidate.id &&
            other.tags.length > candidate.tags.length &&
            other.imageCount >= candidate.imageCount * 0.75 &&
            other.confidence >= candidate.confidence * 0.85 &&
            _containsSequence(other.tags, candidate.tags),
      );
    }).toList();
    pruned.sort(_compareCandidates);
    return List.unmodifiable(pruned.take(_maxResultsPerType));
  }

  static double _cohesion(
    List<String> tokens,
    Map<String, int> tagDocumentFrequency,
    Map<String, int> pairDocumentFrequency,
    int documentCount,
  ) {
    var total = 0.0;
    var pairs = 0;
    for (var index = 0; index < tokens.length - 1; index++) {
      final left = tagDocumentFrequency[tokens[index]] ?? 0;
      final right = tagDocumentFrequency[tokens[index + 1]] ?? 0;
      final together =
          pairDocumentFrequency['${tokens[index]}\u0001${tokens[index + 1]}'] ??
          0;
      if (left == 0 || right == 0 || together == 0) continue;
      final pLeft = left / documentCount;
      final pRight = right / documentCount;
      final pTogether = together / documentCount;
      if (pTogether >= 1) {
        total += 1;
      } else {
        final pmi = log(pTogether / (pLeft * pRight));
        total += (pmi / -log(pTogether)).clamp(0.0, 1.0).toDouble();
      }
      pairs++;
    }
    return pairs == 0 ? 0 : total / pairs;
  }

  static int _compareCandidates(
    GalleryPromptPatternCandidate left,
    GalleryPromptPatternCandidate right,
  ) {
    final confidence = right.confidence.compareTo(left.confidence);
    if (confidence != 0) return confidence;
    final support = right.imageCount.compareTo(left.imageCount);
    if (support != 0) return support;
    final length = right.tags.length.compareTo(left.tags.length);
    if (length != 0) return length;
    return left.prompt.compareTo(right.prompt);
  }

  static bool _containsSequence(List<String> values, List<String> sequence) {
    if (sequence.length > values.length) return false;
    for (var start = 0; start <= values.length - sequence.length; start++) {
      var matches = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (values[start + offset] != sequence[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  static _ParsedPromptTag _parseTag(String raw) {
    final display = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    var base = display;
    final numericMatch = _numericWeight.firstMatch(base);
    if (numericMatch != null) base = numericMatch.group(1) ?? base;
    base = base
        .replaceFirst(_outerWeightPrefix, '')
        .replaceFirst(_outerWeightSuffix, '')
        .replaceFirst(_suffixWeight, '')
        .trim();
    final explicitArtist = _artistPrefix.hasMatch(base);
    base = base.replaceFirst(_artistPrefix, '');
    final lookupTerm = base
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(r'\,', ',')
        .trim();
    final patternToken = display.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return _ParsedPromptTag(
      displayToken: display,
      patternToken: patternToken,
      lookupTerm: lookupTerm,
      explicitArtist: explicitArtist,
    );
  }
}

class _ParsedPromptTag {
  const _ParsedPromptTag({
    required this.displayToken,
    required this.patternToken,
    required this.lookupTerm,
    required this.explicitArtist,
    this.category,
  });

  final String displayToken;
  final String patternToken;
  final String lookupTerm;
  final bool explicitArtist;
  final TagCategory? category;

  bool get isArtist => explicitArtist || category == TagCategory.artist;
  bool get isEffect =>
      !isArtist &&
      category != TagCategory.character &&
      category != TagCategory.copyright &&
      category != TagCategory.species &&
      (category == TagCategory.meta ||
          GalleryPromptPatternAnalyzer._effectKeyword.hasMatch(lookupTerm));

  _ParsedPromptTag withCategory(TagCategory? value) {
    return _ParsedPromptTag(
      displayToken: displayToken,
      patternToken: patternToken,
      lookupTerm: lookupTerm,
      explicitArtist: explicitArtist,
      category: value,
    );
  }
}

class _PatternAccumulator {
  _PatternAccumulator({
    required this.type,
    required this.prompt,
    required this.patternTokens,
    required this.displayTags,
  });

  final GalleryPromptPatternType type;
  final String prompt;
  final List<String> patternTokens;
  final List<String> displayTags;
  final List<String> examplePaths = [];
  int imageCount = 0;

  void add(String filePath) {
    imageCount++;
    if (filePath.isNotEmpty &&
        examplePaths.length < GalleryPromptPatternAnalyzer._maxExamples) {
      examplePaths.add(filePath);
    }
  }
}

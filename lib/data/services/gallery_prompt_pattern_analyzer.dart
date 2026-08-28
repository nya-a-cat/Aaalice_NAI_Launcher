import 'dart:math';

import '../../core/autocomplete/completion_models.dart';
import '../../core/database/datasources/gallery_data_source.dart';
import '../models/tag_library/gallery_prompt_pattern.dart';
import 'gallery_prompt_mining_parser.dart';
import 'gallery_prompt_pattern_support.dart';

/// Mines semantic prompt sequences from a read-only gallery-index snapshot.
abstract final class GalleryPromptPatternAnalyzer {
  static const int _maxArtistLength = 8;
  static const int _maxEffectLength = 10;
  static const int _maxResultsPerType = 80;
  static const int _maxExamples = 6;

  static final RegExp _effectKeyword = RegExp(
    r'(^|_)(masterpiece|quality|aesthetic|absurdres|highres|resolution|'
    r'detailed|detail|sharp|focus|bokeh|lighting|light|highlight|shadow|'
    r'glow|cinematic|dramatic|volumetric|rimlight|backlight|ray|color|'
    r'palette|chromatic|contrast|saturation|monochrome|greyscale|pastel|'
    r'vibrant|render|realistic|photorealistic|anime|illustration|painting|'
    r'watercolor|sketch|lineart|shading|impasto|grain|noise|lens|blur|'
    r'fisheye|perspective|composition|angle|portrait|landscape|atmosphere|'
    r'fog|mist|haze|sparkle|particle|texture|brushstroke|scenery|background|'
    r'specular|scattering|fabric|glossy|oily|dewy|moist|hydrated|radiant|'
    r'luminous|pores|contour|outline|inking|style|official_art|cg|apathy|'
    r'passion|mood|emotion|text|2d|3d|4k|8k|16k)(_|$)',
  );

  static Set<String> collectLookupTerms(
    List<GalleryPromptCorpusEntry> corpus,
  ) {
    return {
      for (final entry in corpus)
        for (final tag in GalleryPromptMiningParser.parse(entry.prompt))
          if (tag.lookupTerm.isNotEmpty) tag.lookupTerm,
    };
  }

  static GalleryPromptMiningResult analyze(
    GalleryPromptCorpusSnapshot snapshot,
    Map<String, TagCategory> categoriesByTerm, {
    Map<String, String> canonicalTermsByTerm = const {},
  }) {
    final recipes = _groupRecipes(snapshot.entries);
    final inferredArtists = _inferArtistTerms(recipes, categoriesByTerm);
    final tagDocumentFrequency = <String, int>{};
    final artistPairFrequency = <String, int>{};
    final effectPairFrequency = <String, int>{};
    final artistPatterns = <String, GalleryPromptPatternAccumulator>{};
    final effectPatterns = <String, GalleryPromptPatternAccumulator>{};

    for (final recipe in recipes) {
      final tags = recipe.tags
          .map(
            (tag) => tag.withResolution(
              category:
                  categoriesByTerm[tag.lookupTerm] ??
                  (inferredArtists.containsKey(tag.lookupTerm)
                      ? TagCategory.artist
                      : null),
              patternToken:
                  canonicalTermsByTerm[tag.lookupTerm] ??
                  inferredArtists[tag.lookupTerm],
            ),
          )
          .toList(growable: false);
      final imageCount = recipe.filePaths.length;
      for (final token in tags.map((tag) => tag.patternToken).toSet()) {
        tagDocumentFrequency.update(
          token,
          (count) => count + imageCount,
          ifAbsent: () => imageCount,
        );
      }
      _collectProjectedSequences(
        tags,
        _isArtist,
        GalleryPromptPatternType.artist,
        _maxArtistLength,
        recipe,
        artistPatterns,
        artistPairFrequency,
      );
      _collectProjectedSequences(
        tags,
        _isEffect,
        GalleryPromptPatternType.effect,
        _maxEffectLength,
        recipe,
        effectPatterns,
        effectPairFrequency,
      );
    }

    final documentCount = snapshot.entries.length;
    return GalleryPromptMiningResult(
      scannedImageCount: documentCount,
      totalAvailableImageCount: snapshot.totalCount,
      artistPatterns: _rank(
        artistPatterns.values,
        tagDocumentFrequency,
        artistPairFrequency,
        documentCount,
        minimumSupport: 2,
      ),
      effectPatterns: _rank(
        effectPatterns.values,
        tagDocumentFrequency,
        effectPairFrequency,
        documentCount,
        minimumSupport: max(2, min(8, (documentCount * 0.001).ceil())),
      ),
    );
  }

  static List<GalleryPromptMiningRecipe> _groupRecipes(
    List<GalleryPromptCorpusEntry> entries,
  ) {
    final grouped = <String, GalleryPromptMiningRecipe>{};
    for (final entry in entries) {
      final recipeKey = entry.prompt
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
          .join('\n')
          .toLowerCase();
      grouped
          .putIfAbsent(
            recipeKey,
            () => GalleryPromptMiningRecipe(
              key: recipeKey,
              tags: GalleryPromptMiningParser.parse(entry.prompt),
            ),
          )
          .filePaths
          .add(entry.filePath);
    }
    return grouped.values.toList(growable: false);
  }

  static Map<String, String> _inferArtistTerms(
    List<GalleryPromptMiningRecipe> recipes,
    Map<String, TagCategory> categoriesByTerm,
  ) {
    final knownArtists = categoriesByTerm.entries
        .where((entry) => entry.value == TagCategory.artist)
        .map((entry) => entry.key)
        .toSet();
    if (knownArtists.isEmpty) return const {};

    final frequency = <String, int>{};
    final betweenArtists = <String, int>{};
    for (final recipe in recipes) {
      final weight = recipe.filePaths.length;
      final tags = recipe.tags;
      for (var index = 0; index < tags.length; index++) {
        final tag = tags[index];
        if (categoriesByTerm.containsKey(tag.lookupTerm) ||
            tag.explicitArtist ||
            _isEffectTerm(tag.lookupTerm, null)) {
          continue;
        }
        frequency.update(
          tag.lookupTerm,
          (count) => count + weight,
          ifAbsent: () => weight,
        );
        final previousArtist = tags
            .sublist(max(0, index - 3), index)
            .any(
              (other) =>
                  other.lineIndex == tag.lineIndex &&
                  knownArtists.contains(other.lookupTerm),
            );
        final nextArtist = tags
            .sublist(index + 1, min(tags.length, index + 4))
            .any(
              (other) =>
                  other.lineIndex == tag.lineIndex &&
                  knownArtists.contains(other.lookupTerm),
            );
        if (previousArtist && nextArtist) {
          betweenArtists.update(
            tag.lookupTerm,
            (count) => count + weight,
            ifAbsent: () => weight,
          );
        }
      }
    }

    final inferred = <String, String>{};
    for (final entry in frequency.entries) {
      if (entry.value < 2) continue;
      final knownVariant = _matchKnownArtistVariant(
        entry.key,
        knownArtists,
      );
      if (knownVariant != null) {
        inferred[entry.key] = knownVariant;
      } else if (_looksLikeArtistIdentifier(entry.key) &&
          (betweenArtists[entry.key] ?? 0) / entry.value >= 0.6) {
        inferred[entry.key] = entry.key;
      }
    }
    return inferred;
  }

  static void _collectProjectedSequences(
    List<GalleryPromptMiningTag> tags,
    bool Function(GalleryPromptMiningTag tag) accepts,
    GalleryPromptPatternType type,
    int maximumLength,
    GalleryPromptMiningRecipe recipe,
    Map<String, GalleryPromptPatternAccumulator> patterns,
    Map<String, int> pairDocumentFrequency,
  ) {
    final projected = <GalleryPromptMiningTag>[];
    for (final tag in tags.where(accepts)) {
      if (projected.lastOrNull?.patternToken != tag.patternToken) {
        projected.add(tag);
      }
    }
    if (projected.length < 2) return;

    final seenPatterns = <String>{};
    for (var start = 0; start < projected.length - 1; start++) {
      final maxLength = min(maximumLength, projected.length - start);
      for (var length = 2; length <= maxLength; length++) {
        final slice = projected.sublist(start, start + length);
        final key = slice.map((tag) => tag.patternToken).join('\u0001');
        if (!seenPatterns.add(key)) continue;
        patterns
            .putIfAbsent(
              key,
              () => GalleryPromptPatternAccumulator(
                type: type,
                patternTokens: slice
                    .map((tag) => tag.patternToken)
                    .toList(growable: false),
                maxExamples: _maxExamples,
              ),
            )
            .add(recipe, _render(slice));
      }
    }

    final seenPairs = <String>{};
    for (var index = 0; index < projected.length - 1; index++) {
      final pairKey = '${projected[index].patternToken}\u0001'
          '${projected[index + 1].patternToken}';
      if (seenPairs.add(pairKey)) {
        pairDocumentFrequency.update(
          pairKey,
          (count) => count + recipe.filePaths.length,
          ifAbsent: () => recipe.filePaths.length,
        );
      }
    }
  }

  static GalleryPromptPatternPresentation _render(
    List<GalleryPromptMiningTag> tags,
  ) {
    final buffer = StringBuffer(tags.first.displayToken);
    for (var index = 1; index < tags.length; index++) {
      buffer.write(
        tags[index].lineIndex > tags[index - 1].lineIndex ? '\n' : ', ',
      );
      buffer.write(tags[index].displayToken);
    }
    return GalleryPromptPatternPresentation(
      prompt: buffer.toString(),
      displayTags: tags.map((tag) => tag.displayToken).toList(growable: false),
    );
  }

  static List<GalleryPromptPatternCandidate> _rank(
    Iterable<GalleryPromptPatternAccumulator> values,
    Map<String, int> tagDocumentFrequency,
    Map<String, int> pairDocumentFrequency,
    int documentCount, {
    required int minimumSupport,
  }) {
    if (documentCount == 0) return const [];
    final ranked = values
        .where((value) => value.imageCount >= minimumSupport)
        .map((value) {
          final presentation = value.bestPresentation;
          final cohesion = _cohesion(
            value.patternTokens,
            tagDocumentFrequency,
            pairDocumentFrequency,
            documentCount,
          );
          final imageSupport = 1 - exp(-value.imageCount / 3);
          final recipeSupport = 1 - exp(-value.promptVariantCount / 2);
          final supportScore = 0.45 * imageSupport + 0.55 * recipeSupport;
          final lengthScore = min(1.0, (value.patternTokens.length - 1) / 5);
          final confidence =
              0.45 * supportScore + 0.4 * cohesion + 0.15 * lengthScore;
          return GalleryPromptRankedPattern(
            patternTokens: value.patternTokens,
            candidate: GalleryPromptPatternCandidate(
              type: value.type,
              prompt: presentation.prompt,
              tags: presentation.displayTags,
              imageCount: value.imageCount,
              promptVariantCount: value.promptVariantCount,
              confidence: confidence.clamp(0.0, 1.0).toDouble(),
              cohesion: cohesion,
              examplePaths: value.examplePaths,
            ),
          );
        })
        .toList();
    ranked.sort(_compareRanked);
    final shortlist = ranked.take(_maxResultsPerType * 4).toList();
    final pruned = shortlist.where((candidate) {
      return !shortlist.any(
        (other) =>
            other.candidate.id != candidate.candidate.id &&
            other.patternTokens.length > candidate.patternTokens.length &&
            other.candidate.imageCount >= candidate.candidate.imageCount * 0.75 &&
            other.candidate.confidence >= candidate.candidate.confidence * 0.85 &&
            _containsSequence(other.patternTokens, candidate.patternTokens),
      );
    }).toList();
    pruned.sort(_compareRanked);
    return List.unmodifiable(
      pruned.take(_maxResultsPerType).map((ranked) => ranked.candidate),
    );
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

  static bool _isEffectTerm(String term, TagCategory? category) {
    return category != TagCategory.character &&
        category != TagCategory.copyright &&
        category != TagCategory.species &&
        (category == TagCategory.meta ||
            _effectKeyword.hasMatch(term) ||
            RegExp(r'^year_?\d{4}$').hasMatch(term));
  }

  static String? _matchKnownArtistVariant(
    String term,
    Set<String> knownArtists,
  ) {
    final compact = _compactArtistTerm(term);
    if (compact.length < 5) return null;
    final sortedArtists = knownArtists.toList()..sort();
    for (final known in sortedArtists) {
      final knownCompact = _compactArtistTerm(known);
      if (compact == knownCompact ||
          _oneEditApart(compact, knownCompact) ||
          _artistSuffixVariant(compact, knownCompact)) {
        return known;
      }
      final homoglyph = compact.replaceAll('0', 'o');
      final knownHomoglyph = knownCompact.replaceAll('0', 'o');
      if (homoglyph == knownHomoglyph ||
          _oneEditApart(homoglyph, knownHomoglyph) ||
          _artistSuffixVariant(homoglyph, knownHomoglyph)) {
        return known;
      }
    }
    return null;
  }

  static String _compactArtistTerm(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _artistSuffixVariant(String left, String right) {
    const suffixes = {'gou', 'illu', 'illust', 'artist'};
    if (left.startsWith(right)) return suffixes.contains(left.substring(right.length));
    if (right.startsWith(left)) return suffixes.contains(right.substring(left.length));
    return false;
  }

  static bool _oneEditApart(String left, String right) {
    if ((left.length - right.length).abs() > 1 || min(left.length, right.length) < 6) {
      return false;
    }
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < left.length && j < right.length) {
      if (left[i] == right[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (left.length > right.length) {
        i++;
      } else if (right.length > left.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    if (i < left.length || j < right.length) edits++;
    return edits <= 1;
  }

  static bool _looksLikeArtistIdentifier(String term) {
    if (term.length < 4 || term.length > 48 || _effectKeyword.hasMatch(term)) {
      return false;
    }
    return RegExp(r'[0-9()]').hasMatch(term) ||
        term.split('_').length <= 3 && !term.contains(RegExp(r'[^a-z0-9_()]'));
  }

  static bool _containsSequence(List<String> values, List<String> sequence) {
    if (sequence.length > values.length) return false;
    for (var start = 0; start <= values.length - sequence.length; start++) {
      if ([
        for (var offset = 0; offset < sequence.length; offset++)
          values[start + offset] == sequence[offset],
      ].every((matches) => matches)) {
        return true;
      }
    }
    return false;
  }

  static bool _isArtist(GalleryPromptMiningTag tag) =>
      tag.explicitArtist || tag.category == TagCategory.artist;

  static bool _isEffect(GalleryPromptMiningTag tag) =>
      !_isArtist(tag) && _isEffectTerm(tag.lookupTerm, tag.category);

  static int _compareRanked(
    GalleryPromptRankedPattern left,
    GalleryPromptRankedPattern right,
  ) {
    final confidence = right.candidate.confidence.compareTo(left.candidate.confidence);
    if (confidence != 0) return confidence;
    final recipes = right.candidate.promptVariantCount.compareTo(left.candidate.promptVariantCount);
    if (recipes != 0) return recipes;
    final support = right.candidate.imageCount.compareTo(left.candidate.imageCount);
    if (support != 0) return support;
    return left.candidate.prompt.compareTo(right.candidate.prompt);
  }
}

import '../models/tag_library/gallery_prompt_pattern.dart';
import 'gallery_prompt_mining_parser.dart';

class GalleryPromptMiningRecipe {
  GalleryPromptMiningRecipe({required this.key, required this.tags});

  final String key;
  final List<GalleryPromptMiningTag> tags;
  final List<String> filePaths = [];
}

class GalleryPromptPatternPresentation {
  const GalleryPromptPatternPresentation({
    required this.prompt,
    required this.displayTags,
  });

  final String prompt;
  final List<String> displayTags;
}

class GalleryPromptPatternAccumulator {
  GalleryPromptPatternAccumulator({
    required this.type,
    required this.patternTokens,
    required this.maxExamples,
  });

  final GalleryPromptPatternType type;
  final List<String> patternTokens;
  final int maxExamples;
  final Map<String, int> _presentations = {};
  final Map<String, GalleryPromptPatternPresentation> _presentationValues = {};
  final Set<String> _recipeKeys = {};
  final List<String> _diverseExamplePaths = [];
  final List<String> _fallbackExamplePaths = [];
  int imageCount = 0;

  int get promptVariantCount => _recipeKeys.length;

  GalleryPromptPatternPresentation get bestPresentation {
    final keys = _presentations.keys.toList()
      ..sort((left, right) {
        final count = _presentations[right]!.compareTo(_presentations[left]!);
        return count != 0 ? count : left.compareTo(right);
      });
    return _presentationValues[keys.first]!;
  }

  List<String> get examplePaths {
    final combined = <String>{..._diverseExamplePaths};
    for (final path in _fallbackExamplePaths) {
      if (combined.length >= maxExamples) break;
      combined.add(path);
    }
    return List.unmodifiable(combined);
  }

  void add(
    GalleryPromptMiningRecipe recipe,
    GalleryPromptPatternPresentation presentation,
  ) {
    imageCount += recipe.filePaths.length;
    _recipeKeys.add(recipe.key);
    _presentations.update(
      presentation.prompt,
      (count) => count + recipe.filePaths.length,
      ifAbsent: () => recipe.filePaths.length,
    );
    _presentationValues[presentation.prompt] = presentation;
    final firstPath = recipe.filePaths.where((path) => path.isNotEmpty).firstOrNull;
    if (firstPath != null && _diverseExamplePaths.length < maxExamples) {
      _diverseExamplePaths.add(firstPath);
    }
    for (final path in recipe.filePaths.where((path) => path.isNotEmpty)) {
      if (_fallbackExamplePaths.length >= maxExamples) break;
      _fallbackExamplePaths.add(path);
    }
  }
}

class GalleryPromptRankedPattern {
  const GalleryPromptRankedPattern({
    required this.patternTokens,
    required this.candidate,
  });

  final List<String> patternTokens;
  final GalleryPromptPatternCandidate candidate;
}

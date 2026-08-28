import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/database/datasources/gallery_data_source.dart';
import 'package:nai_launcher/data/models/tag_library/gallery_prompt_pattern.dart';
import 'package:nai_launcher/data/services/gallery_prompt_pattern_mining_service.dart';

void main() {
  group('GalleryPromptPatternAnalyzer', () {
    test('mines repeated artist and effect sequences separately', () {
      const snapshot = GalleryPromptCorpusSnapshot(
        totalCount: 4,
        entries: [
          GalleryPromptCorpusEntry(
            imageId: 1,
            filePath: r'C:\gallery\one.png',
            prompt:
                'artist:alpha, artist:beta, 1girl, masterpiece, best quality, cinematic lighting',
          ),
          GalleryPromptCorpusEntry(
            imageId: 2,
            filePath: r'C:\gallery\two.png',
            prompt:
                'artist:alpha, artist:beta, 1boy, masterpiece, best quality, cinematic lighting',
          ),
          GalleryPromptCorpusEntry(
            imageId: 3,
            filePath: r'C:\gallery\three.png',
            prompt:
                'artist:gamma, artist:delta, 1girl, masterpiece, best quality, cinematic lighting',
          ),
          GalleryPromptCorpusEntry(
            imageId: 4,
            filePath: r'C:\gallery\four.png',
            prompt: 'solo, outdoors',
          ),
        ],
      );

      final result = GalleryPromptPatternAnalyzer.analyze(snapshot, const {
        'alpha': TagCategory.artist,
        'beta': TagCategory.artist,
        'gamma': TagCategory.artist,
        'delta': TagCategory.artist,
        'masterpiece': TagCategory.meta,
        'best_quality': TagCategory.meta,
      });

      expect(result.scannedImageCount, 4);
      expect(
        result.artistPatterns,
        contains(
          isA<GalleryPromptPatternCandidate>()
              .having(
                (candidate) => candidate.prompt,
                'prompt',
                'artist:alpha, artist:beta',
              )
              .having((candidate) => candidate.imageCount, 'imageCount', 2),
        ),
      );
      expect(
        result.effectPatterns,
        contains(
          isA<GalleryPromptPatternCandidate>()
              .having(
                (candidate) => candidate.prompt,
                'prompt',
                'masterpiece, best quality, cinematic lighting',
              )
              .having((candidate) => candidate.imageCount, 'imageCount', 3),
        ),
      );
      expect(
        result.effectPatterns.expand((candidate) => candidate.tags),
        isNot(contains('1girl')),
      );
    });

    test('normalizes weighted tags for catalog classification', () {
      const corpus = [
        GalleryPromptCorpusEntry(
          imageId: 1,
          filePath: 'weighted.png',
          prompt: '{artist:alpha}, 1.2::best quality::, [cinematic lighting]',
        ),
      ];

      expect(
        GalleryPromptPatternAnalyzer.collectLookupTerms(corpus),
        containsAll(<String>{
          'alpha',
          'best_quality',
          'cinematic_lighting',
        }),
      );
    });
  });
}

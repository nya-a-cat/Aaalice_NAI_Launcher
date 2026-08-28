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
              .having((candidate) => candidate.imageCount, 'imageCount', 2)
              .having(
                (candidate) => candidate.promptVariantCount,
                'promptVariantCount',
                2,
              ),
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
              .having((candidate) => candidate.imageCount, 'imageCount', 3)
              .having(
                (candidate) => candidate.promptVariantCount,
                'promptVariantCount',
                3,
              ),
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

    test('flattens weighted artist groups without damaging artist names', () {
      const corpus = [
        GalleryPromptCorpusEntry(
          imageId: 1,
          filePath: 'weighted-artists.png',
          prompt:
              '{{2::fte_(fifteen_199)::, rei_(sanbonzakura)}}, 1girl',
        ),
      ];

      expect(
        GalleryPromptPatternAnalyzer.collectLookupTerms(corpus),
        containsAll(<String>{
          'fte_(fifteen_199)',
          'rei_(sanbonzakura)',
        }),
      );
    });

    test('mines joint effects across lines and neutral prompt sections', () {
      const snapshot = GalleryPromptCorpusSnapshot(
        totalCount: 2,
        entries: [
          GalleryPromptCorpusEntry(
            imageId: 1,
            filePath: 'one.png',
            prompt:
                'masterpiece\n1girl, solo\ncinematic lighting\nsoft shading',
          ),
          GalleryPromptCorpusEntry(
            imageId: 2,
            filePath: 'two.png',
            prompt:
                'masterpiece\n1boy, portrait\ncinematic lighting\nsoft shading',
          ),
        ],
      );

      final result = GalleryPromptPatternAnalyzer.analyze(snapshot, const {
        'masterpiece': TagCategory.meta,
        '1girl': TagCategory.character,
        '1boy': TagCategory.character,
      });

      expect(
        result.effectPatterns,
        contains(
          isA<GalleryPromptPatternCandidate>()
              .having(
                (candidate) => candidate.prompt,
                'prompt',
                'masterpiece\ncinematic lighting\nsoft shading',
              )
              .having((candidate) => candidate.imageCount, 'imageCount', 2)
              .having(
                (candidate) => candidate.promptVariantCount,
                'promptVariantCount',
                2,
              ),
        ),
      );
    });

    test('joins artists separated by weighted groups and neutral tags', () {
      const snapshot = GalleryPromptCorpusSnapshot(
        totalCount: 2,
        entries: [
          GalleryPromptCorpusEntry(
            imageId: 1,
            filePath: 'one.png',
            prompt:
                '{{fte_(fifteen_199), rei_(sanbonzakura)}}, 1girl, masterpiece',
          ),
          GalleryPromptCorpusEntry(
            imageId: 2,
            filePath: 'two.png',
            prompt:
                'fte_(fifteen_199), blue_archive, rei_(sanbonzakura), 1boy',
          ),
        ],
      );

      final result = GalleryPromptPatternAnalyzer.analyze(snapshot, const {
        'fte_(fifteen_199)': TagCategory.artist,
        'rei_(sanbonzakura)': TagCategory.artist,
        'blue_archive': TagCategory.copyright,
        '1girl': TagCategory.character,
        '1boy': TagCategory.character,
        'masterpiece': TagCategory.meta,
      });

      expect(
        result.artistPatterns,
        contains(
          isA<GalleryPromptPatternCandidate>()
              .having(
                (candidate) => candidate.tags,
                'tags',
                ['fte_(fifteen_199)', 'rei_(sanbonzakura)'],
              )
              .having((candidate) => candidate.imageCount, 'imageCount', 2),
        ),
      );
    });
  });
}

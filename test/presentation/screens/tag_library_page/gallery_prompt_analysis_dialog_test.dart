import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/tag_library/gallery_prompt_pattern.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/gallery_prompt_analysis_dialog.dart';

void main() {
  testWidgets('reviews and saves mined patterns on a compact surface', (
    tester,
  ) async {
    final saved = <GalleryPromptPatternCandidate>[];
    const artist = GalleryPromptPatternCandidate(
      type: GalleryPromptPatternType.artist,
      prompt: 'artist:alpha, artist:beta',
      tags: ['artist:alpha', 'artist:beta'],
      imageCount: 12,
      promptVariantCount: 4,
      confidence: 0.91,
      cohesion: 0.88,
      examplePaths: ['assets/images/1.png', 'assets/images/2.png'],
    );
    const effect = GalleryPromptPatternCandidate(
      type: GalleryPromptPatternType.effect,
      prompt: 'masterpiece, best quality, cinematic lighting',
      tags: ['masterpiece', 'best quality', 'cinematic lighting'],
      imageCount: 28,
      promptVariantCount: 7,
      confidence: 0.86,
      cohesion: 0.81,
      examplePaths: [r'C:\gallery\effect-example.png'],
    );

    await tester.binding.setSurfaceSize(const Size(480, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<int>(
                context: context,
                builder: (_) => GalleryPromptAnalysisDialog(
                  load: () async => const GalleryPromptMiningResult(
                    scannedImageCount: 40,
                    totalAvailableImageCount: 40,
                    artistPatterns: [artist],
                    effectPatterns: [effect],
                  ),
                  save: (candidates) async {
                    saved.addAll(candidates);
                    return candidates.length;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(artist.prompt), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('gallery-prompt-example-0')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gallery-prompt-example-full-0')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gallery-prompt-example-full-1')),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('效果串 (1)'));
    await tester.pumpAndSettle();
    expect(find.text(effect.prompt), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('保存所选 (1)'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.id, effect.id);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/database/datasources/gallery_data_source.dart';
import 'package:nai_launcher/data/models/gallery/local_gallery_vibe_group.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_vibe_provider.dart';
import 'package:nai_launcher/presentation/providers/vibe_library_category_provider.dart';
import 'package:nai_launcher/presentation/providers/vibe_library_provider.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/widgets/vibe_library_source_workspace.dart';

void main() {
  for (final width in [360.0, 840.0, 1180.0]) {
    testWidgets(
      'local gallery Vibe groups remain usable at ${width.toInt()}px',
      (tester) async {
        final temporaryDirectory = Directory.systemTemp.createTempSync(
          'local_gallery_vibe_view_test_',
        );
        addTearDown(
          () => temporaryDirectory.deleteSync(recursive: true),
        );
        final imageFile = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}example.png',
        );
        final imageBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
          '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        imageFile.writeAsBytesSync(imageBytes);

        final firstSeen = DateTime(2025, 3, 4);
        final examples = [
          LocalGalleryVibeExample(
            imageId: 1,
            filePath: imageFile.path,
            createdAt: firstSeen,
            strength: 0.55,
            infoExtracted: 0.7,
            encodingModel: 'nai-diffusion-4-5-full',
          ),
          LocalGalleryVibeExample(
            imageId: 2,
            filePath: imageFile.path,
            createdAt: firstSeen.add(const Duration(days: 1)),
            strength: 0.8,
            infoExtracted: 0.65,
            encodingModel: 'nai-diffusion-4-5-full',
          ),
        ];
        final group = LocalGalleryVibeGroup(
          fingerprint:
              'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
          vibeEncoding: 'dGVzdC12aWJl',
          exampleCount: examples.length,
          firstSeenAt: firstSeen,
          lastSeenAt: firstSeen.add(const Duration(days: 1)),
          examples: examples,
          encodingModels: const ['nai-diffusion-4-5-full'],
        );
        final localNotifier = _TestLocalGalleryVibeNotifier(group, examples);
        final container = ProviderContainer(
          overrides: [
            vibeLibraryNotifierProvider.overrideWith(
              _TestVibeLibraryNotifier.new,
            ),
            vibeLibraryCategoryNotifierProvider.overrideWith(
              _TestVibeLibraryCategoryNotifier.new,
            ),
            localGalleryVibeProvider.overrideWith((ref) => localNotifier),
          ],
        );
        addTearDown(container.dispose);
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              locale: Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                body: VibeLibrarySourceWorkspace(
                  savedCount: 0,
                  savedWorkspace: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('本地图库 2'));
        await tester.pump();

        expect(find.text('2 张示例'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('2 张示例'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('相同编码的精确分组'), findsOneWidget);
        expect(find.text('最早的本地示例'), findsWidgets);
        expect(find.text('2025-03-04'), findsOneWidget);
        final selectedImage = tester.widget<Image>(
          find.byWidgetPredicate(
            (widget) => widget is Image && widget.fit == BoxFit.contain,
          ),
        );
        expect(selectedImage.cacheWidth, isNull);
        expect(selectedImage.cacheHeight, isNotNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(find.text('0.80'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.text('0.55'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TestLocalGalleryVibeNotifier extends LocalGalleryVibeNotifier {
  _TestLocalGalleryVibeNotifier(
    LocalGalleryVibeGroup group,
    this._examples,
  ) : super(GalleryDataSource()) {
    state = LocalGalleryVibeState(
      groups: [group],
      totalGroups: 2,
      isInitialized: true,
    );
  }

  final List<LocalGalleryVibeExample> _examples;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<LocalGalleryVibeExample>> loadExamples(
    String fingerprint, {
    int limit = 100,
    int offset = 0,
  }) async {
    return _examples.skip(offset).take(limit).toList(growable: false);
  }
}

class _TestVibeLibraryNotifier extends VibeLibraryNotifier {
  @override
  VibeLibraryState build() => const VibeLibraryState();

  @override
  Future<void> initialize() async {}
}

class _TestVibeLibraryCategoryNotifier extends VibeLibraryCategoryNotifier {
  @override
  VibeLibraryCategoryState build() => const VibeLibraryCategoryState();
}

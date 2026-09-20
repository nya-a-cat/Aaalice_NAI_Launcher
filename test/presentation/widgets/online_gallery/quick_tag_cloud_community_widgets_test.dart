import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_item.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/online_gallery/quick_tag_cloud_community/quick_tag_cloud_community_card.dart';
import 'package:nai_launcher/presentation/widgets/online_gallery/quick_tag_cloud_community/quick_tag_cloud_community_filters.dart';

void main() {
  for (final width in [360.0, 412.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('community filters and prompt card fit width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      addTearDown(tester.view.reset);
      final search = TextEditingController();
      addTearDown(search.dispose);
      var searchValue = '';
      var categoryValue = '';
      var favoriteValue = false;
      var popularValue = false;
      var openCount = 0;
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  QuickTagCloudCommunityFilters(
                    searchController: search,
                    category: '',
                    favoritesOnly: false,
                    popularFirst: false,
                    likesAvailable: true,
                    onSearch: (value) => searchValue = value,
                    onCategory: (value) => categoryValue = value,
                    onFavoritesOnly: (value) => favoriteValue = value,
                    onPopularFirst: (value) => popularValue = value,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 320,
                    height: 360,
                    child: QuickTagCloudCommunityCard(
                      detail: const GalleryDetail(
                        item: GalleryItem(id: 1, title: 'Community work'),
                        media: [],
                        prompt: 'blue sky, detailed landscape',
                        categoryPath: ['场景'],
                      ),
                      onOpen: () => openCount++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'sky');
      expect(searchValue, 'sky');
      await tester.tap(find.byTooltip('Clear'));
      expect(search.text, isEmpty);
      expect(searchValue, isEmpty);
      await tester.tap(find.text('画风'));
      expect(categoryValue, '画风');
      await tester.tap(find.text('Favorites'));
      await tester.tap(find.text('Popular'));
      expect(favoriteValue, isTrue);
      expect(popularValue, isTrue);
      await tester.tap(find.text('Community work'));
      expect(openCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('community prompt card supports enlarged text without networking', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 320,
              height: 460,
              child: QuickTagCloudCommunityCard(
                detail: const GalleryDetail(
                  item: GalleryItem(
                    id: 1,
                    title: 'A long community title for scaled text',
                    author: 'Contributor',
                  ),
                  media: [],
                  prompt: 'A detailed landscape with a long descriptive prompt',
                  categoryPath: ['场景'],
                ),
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

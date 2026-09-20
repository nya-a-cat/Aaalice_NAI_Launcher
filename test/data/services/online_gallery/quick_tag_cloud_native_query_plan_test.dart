import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_source.dart';
import 'package:nai_launcher/data/services/online_gallery/online_gallery_search_service.dart';

void main() {
  test(
    'native field and phrase query survives shared paging unchanged',
    () async {
      const input = 'title:"blue eyes" -note:hidden has:image fav:true';
      final plan = await OnlineGallerySearchService().buildPlan(
        sourceId: GallerySourceId.quickTagCloud,
        feedKind: GalleryFeedKind.search,
        serverTagLimit: 6,
        fuzzySearchEnabled: true,
        rawQuery: input,
        metadataLoader: (_) => throw StateError('No tag alias lookup expected'),
      );
      expect(plan.serverQuery, input);
      expect(plan.requiresLocalFiltering, isFalse);
      expect(plan.query.ordinaryClauses, isEmpty);
      expect(plan.matchesTags(const []), isTrue);
    },
  );
}

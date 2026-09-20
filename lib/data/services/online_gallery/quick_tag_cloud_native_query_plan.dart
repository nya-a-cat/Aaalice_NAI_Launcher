import '../../../core/online_gallery/gallery_tag_query.dart';

/// Preserves the source's phrase/field grammar through shared gallery paging.
/// QuickTagCloud performs its own text and field filtering before pagination.
class QuickTagCloudNativeQueryPlan extends GalleryTagQueryPlan {
  QuickTagCloudNativeQueryPlan(String input)
    : super(
        query: GalleryTagQuery(raw: input, clauses: const []),
        serverTagLimit: 10,
        pushdown: const [],
      );

  @override
  String get serverQuery => query.raw.trim();
}

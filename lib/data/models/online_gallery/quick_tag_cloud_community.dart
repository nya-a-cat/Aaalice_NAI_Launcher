import 'gallery_item.dart';

/// Published, read-only community entries, mapped to the shared gallery model.
class QuickTagCloudCommunity {
  const QuickTagCloudCommunity({
    required this.entries,
    this.likesAvailable = false,
    this.generatedAt = 0,
  });

  final List<GalleryDetail> entries;
  final bool likesAvailable;
  final int generatedAt;
}

class QuickTagCloudCommunityQuery {
  const QuickTagCloudCommunityQuery({
    this.search = '',
    this.category = '',
    this.favoritesOnly = false,
    this.popularFirst = false,
    this.ratings = const {'g'},
    this.allowNsfw = false,
    this.allowR18g = false,
  });

  final String search;
  final String category;
  final bool favoritesOnly;
  final bool popularFirst;
  final Set<String> ratings;
  final bool allowNsfw;
  final bool allowR18g;

  List<GalleryDetail> apply(
    Iterable<GalleryDetail> entries, {
    Set<String> favoriteKeys = const {},
  }) {
    final terms = search.toLowerCase().trim().split(RegExp(r'\s+'))
      ..removeWhere((term) => term.isEmpty);
    final filtered = entries
        .where((detail) {
          final item = detail.item;
          final rating = item.rating ?? 'q';
          if (rating == 'q' && !allowNsfw ||
              rating == 'e' && !(allowNsfw && allowR18g)) {
            return false;
          }
          if (!(ratings.contains(rating) ||
              rating == 'g' && ratings.contains('s'))) {
            return false;
          }
          if (category.isNotEmpty && !detail.categoryPath.contains(category)) {
            return false;
          }
          if (favoritesOnly && !favoriteKeys.contains(item.stableKey)) {
            return false;
          }
          if (terms.isEmpty) return true;
          final text = [
            item.title,
            item.author,
            detail.prompt,
            detail.negativePrompt,
            detail.note,
            ...item.tags,
            ...detail.categoryPath,
            for (final character in detail.characterPrompts)
              '${character.label} ${character.prompt} ${character.negativePrompt}',
          ].whereType<String>().join('\n').toLowerCase();
          return terms.every(text.contains);
        })
        .toList(growable: false);
    if (popularFirst) {
      filtered.sort((left, right) {
        final score = (right.item.score ?? 0).compareTo(left.item.score ?? 0);
        return score != 0
            ? score
            : right.item.createdAt.compareTo(left.item.createdAt);
      });
    }
    return filtered;
  }
}

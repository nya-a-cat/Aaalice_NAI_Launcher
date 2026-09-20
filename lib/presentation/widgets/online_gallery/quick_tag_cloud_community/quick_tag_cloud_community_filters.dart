import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_community_parser.dart';

class QuickTagCloudCommunityFilters extends StatelessWidget {
  const QuickTagCloudCommunityFilters({
    super.key,
    required this.searchController,
    required this.category,
    required this.favoritesOnly,
    required this.popularFirst,
    required this.likesAvailable,
    required this.onSearch,
    required this.onCategory,
    required this.onFavoritesOnly,
    required this.onPopularFirst,
  });

  final TextEditingController searchController;
  final String category;
  final bool favoritesOnly;
  final bool popularFirst;
  final bool likesAvailable;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onCategory;
  final ValueChanged<bool> onFavoritesOnly;
  final ValueChanged<bool> onPopularFirst;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('quick-tag-cloud-community-search'),
          controller: searchController,
          onChanged: onSearch,
          decoration: InputDecoration(
            labelText: l10n.common_search,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: l10n.common_clear,
              onPressed: () {
                searchController.clear();
                onSearch('');
              },
              icon: const Icon(Icons.clear),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final name in ['', ...QuickTagCloudCommunityParser.categories])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(name.isEmpty ? l10n.onlineGallery_all : name),
                    selected: name == category,
                    side: BorderSide.none,
                    onSelected: (_) => onCategory(name),
                  ),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: Text(l10n.onlineGallery_favorites),
              selected: favoritesOnly,
              side: BorderSide.none,
              onSelected: onFavoritesOnly,
            ),
            if (likesAvailable)
              FilterChip(
                label: Text(l10n.onlineGallery_popular),
                selected: popularFirst,
                side: BorderSide.none,
                onSelected: onPopularFirst,
              ),
          ],
        ),
      ],
    );
  }
}

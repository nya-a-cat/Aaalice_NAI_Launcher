import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/cache/online_gallery_image_cache_manager.dart';
import '../../../../core/cache/online_gallery_prefetch_coordinator.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/online_gallery/gallery_item.dart';
import '../../../../data/models/online_gallery/quick_tag_cloud_community.dart';
import '../../../../data/services/online_gallery/online_gallery_query.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_community_service.dart';
import '../../../providers/online_gallery_blacklist_provider.dart';
import '../../../providers/online_gallery_local_favorites_provider.dart';
import '../../../providers/online_gallery_provider.dart';
import '../../../providers/quick_tag_cloud_community_provider.dart';
import '../../../providers/quick_tag_cloud_gallery_provider.dart';
import '../../../screens/online_gallery/online_gallery_detail_launcher.dart';
import '../../../screens/online_gallery/online_gallery_overlay_exit.dart';
import '../../../screens/online_gallery/online_gallery_screen_controller.dart';
import '../../common/app_toast.dart';
import 'quick_tag_cloud_community_card.dart';
import 'quick_tag_cloud_community_filters.dart';

Future<void> showQuickTagCloudCommunity(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const QuickTagCloudCommunityDialog(),
);

class QuickTagCloudCommunityDialog extends ConsumerStatefulWidget {
  const QuickTagCloudCommunityDialog({super.key});

  @override
  ConsumerState<QuickTagCloudCommunityDialog> createState() =>
      _QuickTagCloudCommunityDialogState();
}

class _QuickTagCloudCommunityDialogState
    extends ConsumerState<QuickTagCloudCommunityDialog> {
  late final OnlineGalleryScreenController _controller;
  late final OnlineGalleryDetailLauncher _launcher;
  String _category = '';
  String _search = '';
  bool _favoritesOnly = false;
  bool _popularFirst = false;

  @override
  void initState() {
    super.initState();
    _controller = OnlineGalleryScreenController(
      prefetchCoordinator: OnlineGalleryPrefetchCoordinator(
        preloader: (request) => precacheImage(
          request.createImageProvider(OnlineGalleryImageCacheManager.instance),
          context,
        ),
      ),
    );
    _launcher = OnlineGalleryDetailLauncher(
      context: context, ref: ref, controller: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(quickTagCloudCommunityProvider);
    final ratings = ref.watch(
      onlineGalleryNotifierProvider.select((state) => state.selectedRatings),
    );
    final access = ref.watch(quickTagCloudFilterProvider);
    final favorites = ref.watch(onlineGalleryLocalFavoritesProvider);
    final favoriteStore = ref.read(onlineGalleryLocalFavoritesProvider.notifier);
    final blacklist = ref.watch(
      onlineGalleryBlacklistNotifierProvider.select((state) => state.tags),
    );
    final entries = data.valueOrNull?.entries ?? const <GalleryDetail>[];
    final favoriteKeys = {
      if (favorites.isInitialized)
        for (final detail in entries)
          if (favoriteStore.isFavorite(detail.item.stableKey))
            detail.item.stableKey,
    };
    final allowedKeys = const OnlineGalleryQuery().filterLocal(
      items: entries.map((entry) => entry.item),
      ratings: const {'g', 's', 'q', 'e'},
      blacklist: blacklist,
    ).map((item) => item.stableKey).toSet();
    final filtered = QuickTagCloudCommunityQuery(
      search: _search,
      category: _category,
      favoritesOnly: _favoritesOnly,
      popularFirst: _popularFirst,
      ratings: ratings,
      allowNsfw: access.allowNsfw,
      allowR18g: access.allowR18g,
    ).apply(
      entries.where((entry) => allowedKeys.contains(entry.item.stableKey)),
      favoriteKeys: favoriteKeys,
    );
    final content = SafeArea(
      child: _body(data, filtered, favoriteKeys),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 600
          ? Dialog.fullscreen(child: content)
          : Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 1120,
                height: constraints.maxHeight - 48,
                child: content,
              ),
            ),
    );
  }

  Widget _body(
    AsyncValue<QuickTagCloudCommunity> data,
    List<GalleryDetail> entries,
    Set<String> favoriteKeys,
  ) {
    final l10n = context.l10n;
    final likesAvailable = data.valueOrNull?.likesAvailable ?? false;
    return CustomScrollView(
      controller: _controller.scrollController,
      slivers: [
        SliverToBoxAdapter(child: _header(data, entries.length)),
        if (entries.isEmpty && !data.isLoading && !data.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(l10n.onlineGallery_communityEmpty)),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (constraints.crossAxisExtent / 280)
                    .floor().clamp(1, 4),
                mainAxisExtent: 340 +
                    (MediaQuery.textScalerOf(context).scale(100) - 100),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final detail = entries[index];
                return QuickTagCloudCommunityCard(
                  key: ValueKey(detail.item.stableKey),
                  detail: detail,
                  favorite: favoriteKeys.contains(detail.item.stableKey),
                  showLikes: likesAvailable,
                  onOpen: () => unawaited(_launcher.show(
                    context, detail.item, knownDetail: detail,
                    onLeaveDetail: galleryOwnedOverlayExit(this.context),
                  )),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(AsyncValue<QuickTagCloudCommunity> data, int count) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(l10n.onlineGallery_codexCommunity,
              style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: l10n.common_close,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ]),
          Text(l10n.onlineGallery_communityRatingNotice,
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          QuickTagCloudCommunityFilters(
            searchController: _controller.searchController,
            category: _category,
            favoritesOnly: _favoritesOnly,
            popularFirst: _popularFirst,
            likesAvailable: data.valueOrNull?.likesAvailable ?? false,
            onSearch: (value) => setState(() => _search = value),
            onCategory: (value) => setState(() => _category = value),
            onFavoritesOnly: (value) => setState(() => _favoritesOnly = value),
            onPopularFirst: (value) => setState(() => _popularFirst = value),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(l10n.onlineGallery_communityCount(count)),
              TextButton.icon(
                onPressed: data.isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.common_refresh),
              ),
              TextButton.icon(
                onPressed: _openWebsite,
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.onlineGallery_communitySubmit),
              ),
            ],
          ),
          if (data.isLoading) const LinearProgressIndicator(),
          if (data.hasError) ...[
            Text(l10n.onlineGallery_communityLoadFailed),
            TextButton(onPressed: _refresh, child: Text(l10n.common_retry)),
          ],
        ],
      ),
    );
  }

  void _refresh() => ref.invalidate(quickTagCloudCommunityProvider);

  Future<void> _openWebsite() async {
    try {
      if (await launchUrl(Uri.parse(QuickTagCloudCommunityService.website),
        mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The source site remains an explicit external action.
    }
    if (mounted) AppToast.error(context, context.l10n.cannotOpenUrl);
  }
}

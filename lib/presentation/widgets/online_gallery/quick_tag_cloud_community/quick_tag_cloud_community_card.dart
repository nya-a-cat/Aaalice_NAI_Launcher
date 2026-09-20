import 'package:flutter/material.dart';

import '../../../../core/cache/gallery_image_request.dart';
import '../../../../core/cache/online_gallery_image_cache_manager.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/online_gallery/gallery_item.dart';
import '../../../themes/theme_extension.dart';
import '../../common/image_card_hover_motion.dart';

class QuickTagCloudCommunityCard extends StatefulWidget {
  const QuickTagCloudCommunityCard({
    super.key,
    required this.detail,
    required this.onOpen,
    this.favorite = false,
    this.showLikes = false,
  });

  final GalleryDetail detail;
  final VoidCallback onOpen;
  final bool favorite;
  final bool showLikes;

  @override
  State<QuickTagCloudCommunityCard> createState() =>
      _QuickTagCloudCommunityCardState();
}

class _QuickTagCloudCommunityCardState
    extends State<QuickTagCloudCommunityCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.detail.item;
    return ImageCardHoverMotion(
      hovered: _hovered,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          onHover: (value) => setState(() => _hovered = value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _image(context, item)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title?.isNotEmpty == true
                          ? item.title! : context.l10n.onlineGallery_codexUntitled,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        ...widget.detail.categoryPath,
                        if (item.author?.isNotEmpty == true) item.author!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.detail.prompt ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context, GalleryItem item) => Stack(
    fit: StackFit.expand,
    children: [
      if (item.previewUrl.isEmpty)
        Center(child: Text(context.l10n.onlineGallery_codexNoImage))
      else
        LayoutBuilder(
          builder: (context, constraints) => Image(
            image: GalleryImageRequest.forUrl(
              sourceId: item.sourceId,
              url: item.previewUrl,
              tier: GalleryImageTier.thumbnail,
              targetDecodeWidth: GalleryImageSizing.gridTargetWidth(
                layoutWidth: constraints.maxWidth,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                naturalWidth: item.width,
                naturalHeight: item.height,
              ),
            ).createImageProvider(OnlineGalleryImageCacheManager.instance),
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null
                ? child : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, _, _) => Center(
              child: Tooltip(
                message: context.l10n.detail_imageLoadFailed,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      Positioned(
        top: 8, right: 8,
        child: Wrap(
          spacing: 4,
          children: [
            if (item.mediaCount > 1) _badge(context, '${item.mediaCount}'),
            if (item.rating != 'g')
              _badge(context, item.rating == 'e' ? 'R18G' : 'NSFW'),
            if (widget.favorite) _badge(context, '★'),
            if (widget.showLikes && (item.score ?? 0) > 0)
              _badge(context, '♡ ${item.score}'),
          ],
        ),
      ),
    ],
  );

  Widget _badge(BuildContext context, String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(
        Theme.of(context).appTheme.controlRadius,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

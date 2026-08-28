import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/gallery/local_gallery_vibe_group.dart';
import '../../../widgets/common/image_card_hover_motion.dart';

class LocalGalleryVibeCard extends StatefulWidget {
  const LocalGalleryVibeCard({
    super.key,
    required this.group,
    required this.width,
    required this.isSaved,
    required this.onTap,
  });

  final LocalGalleryVibeGroup group;
  final double width;
  final bool isSaved;
  final VoidCallback onTap;

  @override
  State<LocalGalleryVibeCard> createState() => _LocalGalleryVibeCardState();
}

class _LocalGalleryVibeCardState extends State<LocalGalleryVibeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstExample = widget.group.earliestExample;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ImageCardHoverMotion(
        hovered: _hovered,
        child: Semantics(
          button: true,
          label: context.l10n.vibeLibrary_localGalleryVibeSemantics(
            widget.group.exampleCount,
          ),
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (firstExample != null)
                    Image.file(
                      File(firstExample.filePath),
                      fit: BoxFit.cover,
                      cacheWidth: (widget.width * pixelRatio).round(),
                      errorBuilder: (_, _, _) => _imageFallback(theme),
                    )
                  else
                    _imageFallback(theme),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _OverlayBadge(
                      icon: Icons.collections_outlined,
                      label: context.l10n.vibeLibrary_exampleCount(
                        widget.group.exampleCount,
                      ),
                    ),
                  ),
                  if (widget.isSaved)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _OverlayBadge(
                        icon: Icons.bookmark_added_outlined,
                        label: context.l10n.vibeLibrary_saved,
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.group.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.vibeLibrary_firstSeen(
                            formatLocalVibeDate(widget.group.firstSeenAt),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageFallback(ThemeData theme) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.auto_awesome_outlined,
      size: 48,
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );
}

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatLocalVibeDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}

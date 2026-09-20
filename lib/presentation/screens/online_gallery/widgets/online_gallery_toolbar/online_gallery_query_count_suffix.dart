import 'package:flutter/material.dart';

import '../../../../../core/online_gallery/gallery_tag_query.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/datasources/remote/online_gallery/quick_tag_cloud_search_parser.dart';

Widget buildOnlineGalleryQueryCountSuffix(
  BuildContext context,
  ThemeData theme,
  TextEditingController controller, {
  required VoidCallback onClear,
  required bool codex,
}) {
  final plan = codex ? QuickTagCloudSearchParser.parse(controller.text) : null;
  final count = plan == null
      ? GalleryTagQueryParser.parse(controller.text).ordinaryTagCount
      : plan.terms.length + plan.filters.where((filter) => filter.isText).length;
  final limit = codex ? quickTagCloudTextConditionLimit : maxGallerySearchTags;
  final exceeded = count > limit;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$count/$limit',
        key: const ValueKey('online-gallery-tag-count'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: exceeded
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (controller.text.isNotEmpty)
        IconButton(
          tooltip: context.l10n.common_clear,
          icon: Icon(
            Icons.close,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          onPressed: onClear,
        ),
    ],
  );
}

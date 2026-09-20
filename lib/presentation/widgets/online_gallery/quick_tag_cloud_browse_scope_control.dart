import 'package:flutter/material.dart';

import '../../../data/datasources/remote/online_gallery/quick_tag_cloud_gallery_source_adapter.dart';
import '../../../l10n/app_localizations.dart';

/// Keeps scope selection touch-accessible when the source panel wraps.
class QuickTagCloudBrowseScopeControl extends StatelessWidget {
  const QuickTagCloudBrowseScopeControl({
    super.key,
    required this.scope,
    required this.wrap,
    required this.onChanged,
  });

  final QuickTagCloudBrowseScope scope;
  final bool wrap;
  final ValueChanged<QuickTagCloudBrowseScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      QuickTagCloudBrowseScope.catalog: l10n.onlineGallery_codexBrowse,
      QuickTagCloudBrowseScope.latest: l10n.onlineGallery_codexLatest,
      QuickTagCloudBrowseScope.recent: l10n.onlineGallery_codexRecent,
    };
    const icons = {
      QuickTagCloudBrowseScope.catalog: Icons.auto_stories_outlined,
      QuickTagCloudBrowseScope.latest: Icons.new_releases_outlined,
      QuickTagCloudBrowseScope.recent: Icons.history,
    };
    if (wrap) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in labels.entries)
            ChoiceChip(
              label: Text(entry.value),
              avatar: Icon(icons[entry.key], size: 16),
              selected: scope == entry.key,
              showCheckmark: false,
              onSelected: (_) => onChanged(entry.key),
              side: BorderSide.none,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      );
    }
    return SegmentedButton<QuickTagCloudBrowseScope>(
      segments: [
        for (final entry in labels.entries)
          ButtonSegment(
            value: entry.key,
            label: Text(entry.value),
            icon: Icon(icons[entry.key], size: 16),
          ),
      ],
      selected: {scope},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

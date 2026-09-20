import 'package:flutter/material.dart';

import '../../../data/datasources/remote/online_gallery/quick_tag_cloud_gallery_source_adapter.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_catalog.dart';
import '../../../l10n/app_localizations.dart';

class QuickTagCloudFilterSelection {
  const QuickTagCloudFilterSelection(this.mediaFilter, this.updateFilterId);

  final QuickTagCloudMediaFilter mediaFilter;
  final String updateFilterId;
}

Future<QuickTagCloudFilterSelection?> showQuickTagCloudFilterPicker(
  BuildContext context,
  QuickTagCloudCodexMeta? meta,
  QuickTagCloudGalleryQuery query,
) async {
  final l10n = AppLocalizations.of(context)!;
  var mediaFilter = query.mediaFilter;
  var updateFilterId = query.updateFilterId;
  var changed = false;
  final apply = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.common_filter),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onlineGallery_codexMediaFilter,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in {
                      QuickTagCloudMediaFilter.all:
                          l10n.onlineGallery_codexAllEntries,
                      QuickTagCloudMediaFilter.withImages:
                          l10n.onlineGallery_codexWithImages,
                      QuickTagCloudMediaFilter.withoutImages:
                          l10n.onlineGallery_codexWithoutImages,
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: mediaFilter == entry.key,
                        side: BorderSide.none,
                        onSelected: (_) {
                          changed = true;
                          setDialogState(() => mediaFilter = entry.key);
                        },
                      ),
                  ],
                ),
                if (meta != null && meta.updateFilters.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    l10n.onlineGallery_codexUpdateBatch,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: updateFilterId,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l10n.onlineGallery_codexAllEntries),
                      ),
                      for (final filter in meta.updateFilters)
                        DropdownMenuItem(
                          value: filter.id,
                          child: Text(
                            filter.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      changed = true;
                      setDialogState(() => updateFilterId = value ?? '');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.common_apply),
          ),
        ],
      ),
    ),
  );
  if (apply != true || !changed) return null;
  return QuickTagCloudFilterSelection(mediaFilter, updateFilterId);
}

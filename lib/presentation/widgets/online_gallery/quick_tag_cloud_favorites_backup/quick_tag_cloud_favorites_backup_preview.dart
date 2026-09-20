import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_plan.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_store.dart';

class QuickTagCloudFavoritesBackupPreview extends StatelessWidget {
  const QuickTagCloudFavoritesBackupPreview({
    required this.preview,
    required this.plan,
    required this.replace,
    required this.mergeAvailable,
    required this.replaceAvailable,
    required this.busy,
    required this.onReplaceChanged,
    super.key,
  });

  final QuickTagCloudBackupPreview preview;
  final QuickTagCloudBackupPlan plan;
  final bool replace;
  final bool mergeAvailable;
  final bool replaceAvailable;
  final bool busy;
  final ValueChanged<bool> onReplaceChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mapped = preview.mapped(plan);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.quickTagBackupCounts(
          (plan.document['favorites']['atlas'] as List).length,
          (plan.document['favorites']['community'] as List).length,
          (plan.document['folders'] as List).length,
          mapped,
          QuickTagCloudBackupPlan.keys(plan.document).length - mapped,
          plan.duplicates,
          plan.removed,
          plan.conflicts,
        )),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              enabled: mergeAvailable,
              label: Text(l.quickTagBackupMerge),
            ),
            ButtonSegment(
              value: true,
              enabled: replaceAvailable,
              label: Text(l.quickTagBackupReplace),
            ),
          ],
          selected: {replace},
          onSelectionChanged: busy
              ? null
              : (value) => onReplaceChanged(value.single),
        ),
        if (replace)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.quickTagBackupReplaceWarning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

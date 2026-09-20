import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_codec.dart';

class QuickTagCloudFavoritesBackupInput extends StatelessWidget {
  const QuickTagCloudFavoritesBackupInput({
    required this.controller,
    required this.busy,
    required this.onChanged,
    required this.onImportFile,
    required this.onPrepare,
    this.onCancel,
    super.key,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onImportFile;
  final VoidCallback onPrepare;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.quickTagBackupHelp),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          enabled: !busy,
          minLines: 3,
          maxLines: 7,
          maxLength: QuickTagCloudFavoritesBackupCodec.maximumInputBytes,
          decoration: InputDecoration(labelText: l.quickTagBackupInputHint),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: busy ? null : onImportFile,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l.quickTagBackupImportFile),
            ),
            FilledButton.tonal(
              onPressed: busy ? null : onPrepare,
              child: Text(l.quickTagBackupPreview),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              child: Text(l.common_cancel),
            ),
        ],
      ],
    );
  }
}

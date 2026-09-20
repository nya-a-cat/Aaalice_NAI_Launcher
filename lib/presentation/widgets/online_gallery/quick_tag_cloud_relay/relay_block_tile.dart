import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/online_gallery/quick_tag_cloud_relay.dart';

class RelayBlockTile extends StatelessWidget {
  const RelayBlockTile({
    super.key,
    required this.block,
    required this.locked,
    required this.busy,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });
  final QuickTagCloudRelayBlock block;
  final bool locked, busy, canMoveUp, canMoveDown;
  final VoidCallback onToggle, onEdit, onDelete, onMoveUp, onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    locked
                        ? l.qtcRelay_locked
                        : (block.title.isEmpty
                              ? l.common_default
                              : block.title),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Semantics(
                  label: l.characterEditor_enabled,
                  child: Switch(
                    value: block.enabled,
                    onChanged: busy || locked ? null : (_) => onToggle(),
                  ),
                ),
              ],
            ),
            if (!locked) ...[
              if (block.positive.isNotEmpty)
                Text(
                  block.positive,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              if (block.negative.isNotEmpty)
                Text(
                  '${l.prompt_negative}: ${block.negative}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              if (block.characters.isNotEmpty)
                Text(
                  '${l.prompt_characterPrompts}: ${block.characters.length}',
                ),
              Text('${l.qtcRelay_weight}: ${block.weight}'),
            ],
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: l.qtcRelay_moveUp,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: busy || !canMoveUp ? null : onMoveUp,
                ),
                IconButton(
                  tooltip: l.qtcRelay_moveDown,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: busy || !canMoveDown ? null : onMoveDown,
                ),
                TextButton.icon(
                  onPressed: busy || locked ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l.common_edit),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.common_delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

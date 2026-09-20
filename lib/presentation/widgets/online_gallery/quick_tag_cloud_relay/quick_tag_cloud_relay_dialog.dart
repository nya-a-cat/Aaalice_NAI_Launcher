import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/online_gallery/quick_tag_cloud_relay.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../providers/quick_tag_cloud_relay_provider.dart';
import '../../../router/app_routes.dart';
import '../../common/app_toast.dart';
import '../../common/themed_confirm_dialog.dart';
import '../../common/themed_input.dart';
import 'relay_block_editor.dart';
import 'relay_block_tile.dart';
import 'relay_output_panel.dart';

/// Shared entry point for the native gallery toolbar and detail actions.
Future<void> showQuickTagCloudRelay(BuildContext context) async {
  final router = GoRouter.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final hostRoute = ModalRoute.of(context);
  final openGeneration = await AdaptivePresenter.showPanel<bool>(
    context: context,
    titleBuilder: (context) => Text(context.l10n.qtcRelay_title),
    sideSheetWidth: 840,
    initialChildSize: 0.90,
    minChildSize: 0.6,
    builder: (context, scrollController) => QuickTagCloudRelayPanel(
      scrollController: scrollController,
      onSent: () => Navigator.of(context).pop(true),
    ),
  );
  if (openGeneration == true && rootNavigator.mounted) {
    // Compact source filters can own the relay entry. Only close that captured
    // host; unrelated popup routes and page routes retain their own lifecycle.
    if (hostRoute is PopupRoute && hostRoute.isActive &&
        identical(hostRoute.navigator, rootNavigator)) {
      rootNavigator.removeRoute(hostRoute);
    }
    router.go(AppRoutes.home);
  }
}

class QuickTagCloudRelayPanel extends ConsumerWidget {
  const QuickTagCloudRelayPanel({
    super.key, required this.scrollController, required this.onSent,
  });
  final ScrollController scrollController;
  final VoidCallback onSent;

  Future<void> _run(BuildContext context, Future<void> operation) async {
    try { await operation; } catch (_) {
      if (context.mounted) AppToast.error(context, context.l10n.qtcRelay_saveFailed);
    }
  }

  Future<void> _planAction(
    BuildContext context, WidgetRef ref, String action,
  ) async {
    final doc = ref.read(quickTagCloudRelayProvider).document;
    final controller = ref.read(quickTagCloudRelayProvider.notifier);
    final l = context.l10n;
    if (action == 'delete') {
      final confirmed = await ThemedConfirmDialog.showDelete(
        context: context,
        itemName: doc.activePlan.name.isEmpty ? l.common_default : doc.activePlan.name,
      );
      if (confirmed && context.mounted) await _run(context, controller.deletePlan(doc.activePlanId));
      return;
    }
    final name = await _askPlanName(
      context, title: action == 'new' ? l.qtcRelay_newPlan : l.qtcRelay_renamePlan,
      initial: action == 'new' ? '' : doc.activePlan.name,
    );
    if (name == null || !context.mounted) return;
    await _run(context, action == 'new'
      ? controller.createPlan(name) : controller.renamePlan(doc.activePlanId, name));
  }

  Future<void> _deleteBlock(
    BuildContext context, WidgetRef ref, String planId, QuickTagCloudRelayBlock block,
    bool locked,
  ) async {
    final confirmed = await ThemedConfirmDialog.showDelete(
      context: context,
      itemName: locked ? context.l10n.qtcRelay_locked : block.title,
    );
    if (confirmed && context.mounted) {
      await _run(context, ref.read(quickTagCloudRelayProvider.notifier).removeBlock(planId, block.id));
    }
  }

  Widget _plans(BuildContext context, WidgetRef ref, QuickTagCloudRelayState state) {
    final doc = state.document;
    final l = context.l10n;
    return Row(children: [
      Expanded(child: InputDecorator(
        decoration: InputDecoration(labelText: l.qtcRelay_plan),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: doc.activePlanId,
        isExpanded: true,
        items: [
          for (final plan in doc.plans)
            DropdownMenuItem(value: plan.id, child: Text(
              plan.name.isEmpty ? l.common_default : plan.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
        ],
        onChanged: state.isSaving ? null : (id) {
          if (id != null) _run(context, ref.read(quickTagCloudRelayProvider.notifier).selectPlan(id));
        },
      )))),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        enabled: !state.isSaving,
        tooltip: l.qtcRelay_plan,
        onSelected: (action) => _planAction(context, ref, action),
        itemBuilder: (context) => [
          PopupMenuItem(value: 'new', child: Text(l.qtcRelay_newPlan)),
          PopupMenuItem(value: 'rename', child: Text(l.qtcRelay_renamePlan)),
          PopupMenuItem(value: 'delete', enabled: doc.plans.length > 1, child: Text(l.qtcRelay_deletePlan)),
        ],
      ),
    ]);
  }

  Widget _recovery(BuildContext context, WidgetRef ref, bool busy) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.qtcRelay_corrupt),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: busy ? null : () async {
            final confirmed = await ThemedConfirmDialog.show(
              context: context, title: context.l10n.qtcRelay_recover,
              content: context.l10n.qtcRelay_recoverConfirm,
            );
            if (confirmed && context.mounted) {
              await _run(context, ref.read(quickTagCloudRelayProvider.notifier).recoverWithBackup());
            }
          },
          child: Text(context.l10n.qtcRelay_recover),
        ),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickTagCloudRelayProvider);
    final ratings = ref.watch(quickTagCloudRelayAllowedRatingsProvider);
    final controller = ref.read(quickTagCloudRelayProvider.notifier);
    final plan = state.document.activePlan;
    final l = context.l10n;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (state.isSaving) const LinearProgressIndicator(),
        if (state.saveFailed) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(l.qtcRelay_saveFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        if (state.isCorrupt) _recovery(context, ref, state.isSaving)
        else ...[
          _plans(context, ref, state),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: state.isSaving ? null : () => showRelayBlockEditor(context, planId: plan.id),
            icon: const Icon(Icons.add), label: Text(l.qtcRelay_addBlock),
          )),
          if (plan.blocks.isEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 24), child: Text(l.qtcRelay_empty),
          ),
          for (var index = 0; index < plan.blocks.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RelayBlockTile(
                key: ValueKey(plan.blocks[index].id),
                block: plan.blocks[index], locked: !plan.blocks[index].allowedBy(ratings),
                busy: state.isSaving, canMoveUp: index > 0, canMoveDown: index + 1 < plan.blocks.length,
                onToggle: () => _run(context, controller.toggleBlock(plan.id, plan.blocks[index].id)),
                onEdit: () => showRelayBlockEditor(context, planId: plan.id, block: plan.blocks[index]),
                onDelete: () => _deleteBlock(context, ref, plan.id, plan.blocks[index], !plan.blocks[index].allowedBy(ratings)),
                onMoveUp: () => _run(context, controller.moveBlock(plan.id, plan.blocks[index].id, -1)),
                onMoveDown: () => _run(context, controller.moveBlock(plan.id, plan.blocks[index].id, 1)),
              ),
            ),
          const SizedBox(height: 12),
          RelayOutputPanel(onSent: onSent),
        ],
      ],
    );
  }
}

Future<String?> _askPlanName(
  BuildContext context, {required String title, required String initial},
) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: ThemedInput(
        controller: controller, maxLength: 60, autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.qtcRelay_name),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.common_cancel)),
        TextButton(onPressed: () {
          if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
        }, child: Text(context.l10n.common_save)),
      ],
    ));
  } finally {
    controller.dispose();
  }
}

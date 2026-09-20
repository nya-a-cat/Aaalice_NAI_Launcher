import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/model_capabilities.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/character/character_prompt.dart';
import '../../../../data/models/online_gallery/quick_tag_cloud_relay.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_relay_service.dart';
import '../../../providers/character_prompt_provider.dart';
import '../../../providers/generation/generation_params_notifier.dart';
import '../../../providers/pending_prompt_provider.dart';
import '../../../providers/quick_tag_cloud_relay_provider.dart';
import '../../common/app_toast.dart';
import '../../common/themed_confirm_dialog.dart';

class RelayOutputPanel extends ConsumerWidget {
  const RelayOutputPanel({super.key, required this.onSent});
  final VoidCallback onSent;

  QuickTagCloudRelayOutput _output(
    WidgetRef ref, {
    bool forGeneration = false,
  }) {
    final state = ref.read(quickTagCloudRelayProvider);
    if (state.isCorrupt || state.isSaving) {
      throw StateError('Relay unavailable');
    }
    final document = state.document;
    return const QuickTagCloudRelayService().compile(
      document.activePlan,
      format: forGeneration ? QuickTagCloudRelayFormat.nai : document.format,
      join: document.join,
      allowedRatings: ref.read(quickTagCloudRelayAllowedRatingsProvider),
    );
  }

  Future<void> _copy(BuildContext context, WidgetRef ref, int channel) async {
    try {
      final output = _output(ref);
      final text = switch (channel) {
        0 => output.positive,
        1 => output.negative,
        _ => output.allText,
      };
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        AppToast.success(context, context.l10n.common_copied);
      }
    } catch (_) {
      if (context.mounted) AppToast.error(context, context.l10n.common_error);
    }
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: context.l10n.qtcRelay_send,
      content: context.l10n.qtcRelay_sendConfirm,
    );
    if (!confirmed || !context.mounted) return;
    try {
      // Recompile after confirmation so current rating restrictions still apply.
      final output = _output(ref, forGeneration: true);
      if (output.isEmpty) return;
      final model = ref.read(generationParamsNotifierProvider).model;
      final existing = ref
          .read(characterPromptNotifierProvider)
          .characters
          .length;
      final limit = ModelCapabilityRegistry.of(model).maxCharacters;
      if (output.characters.isNotEmpty &&
          (limit <= 0 || existing + output.characters.length > limit)) {
        AppToast.error(context, context.l10n.qtcRelay_characterLimit);
        return;
      }
      final characters = ref.read(characterPromptNotifierProvider.notifier);
      for (final character in output.characters) {
        characters.addCharacter(
          CharacterGender.other,
          name: character.label,
          prompt: character.positive,
          negativePrompt: character.negative,
        );
      }
      ref
          .read(pendingPromptNotifierProvider.notifier)
          .set(
            prompt: output.positive.isEmpty ? null : output.positive,
            negativePrompt: output.negative.isEmpty ? null : output.negative,
            targetType: SendTargetType.mainPrompt,
          );
      AppToast.success(context, context.l10n.qtcRelay_sent);
      onSent();
    } catch (_) {
      if (context.mounted) AppToast.error(context, context.l10n.common_error);
    }
  }

  Future<void> _setting(BuildContext context, Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.qtcRelay_saveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickTagCloudRelayProvider);
    final ratings = ref.watch(quickTagCloudRelayAllowedRatingsProvider);
    final doc = state.document;
    final l = context.l10n;
    QuickTagCloudRelayOutput? output;
    try {
      output = const QuickTagCloudRelayService().compile(
        doc.activePlan,
        format: doc.format,
        join: doc.join,
        allowedRatings: ratings,
      );
    } catch (_) {
      // Unsupported or excessively nested syntax remains in the saved plan.
    }
    final busy = state.isSaving || state.isCorrupt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings(context, ref, doc, busy),
        if (doc.format == QuickTagCloudRelayFormat.plain)
          Text(l.qtcRelay_plainHint),
        _preview(context, output),
        _actions(context, ref, output, busy),
        const SizedBox(height: 8),
        Text(l.qtcRelay_sendHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _settings(
    BuildContext context,
    WidgetRef ref,
    QuickTagCloudRelayDocument doc,
    bool busy,
  ) {
    final controller = ref.read(quickTagCloudRelayProvider.notifier);
    final l = context.l10n;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        DropdownButton<QuickTagCloudRelayFormat>(
          value: doc.format,
          items: [
            const DropdownMenuItem(
              value: QuickTagCloudRelayFormat.nai,
              child: Text('NAI'),
            ),
            const DropdownMenuItem(
              value: QuickTagCloudRelayFormat.sd,
              child: Text('SD'),
            ),
            DropdownMenuItem(
              value: QuickTagCloudRelayFormat.plain,
              child: Text(l.qtcRelay_plain),
            ),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) {
                    _setting(context, controller.setFormat(value));
                  }
                },
        ),
        DropdownButton<QuickTagCloudRelayJoin>(
          value: doc.join,
          items: [
            DropdownMenuItem(
              value: QuickTagCloudRelayJoin.comma,
              child: Text(l.qtcRelay_comma),
            ),
            DropdownMenuItem(
              value: QuickTagCloudRelayJoin.newline,
              child: Text(l.qtcRelay_newline),
            ),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) {
                    _setting(context, controller.setJoin(value));
                  }
                },
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, QuickTagCloudRelayOutput? output) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (output == null)
          Text(
            l.common_error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if ((output?.lockedCount ?? 0) > 0)
          Text('${l.qtcRelay_locked}: ${output!.lockedCount}'),
        if ((output?.mergedCount ?? 0) > 0)
          Text('${l.qtcRelay_merged}: ${output!.mergedCount}'),
        if (output?.characters.isNotEmpty ?? false)
          Text(l.qtcRelay_charactersNote),
        if (output != null && !output.isEmpty)
          ExpansionTile(
            title: Text(l.prompt_finalPrompt),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(output.allText),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    QuickTagCloudRelayOutput? output,
    bool busy,
  ) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: busy || (output?.positive.isEmpty ?? true)
              ? null
              : () => _copy(context, ref, 0),
          icon: const Icon(Icons.copy_outlined),
          label: Text(l.qtcRelay_copyPositive),
        ),
        TextButton.icon(
          onPressed: busy || (output?.negative.isEmpty ?? true)
              ? null
              : () => _copy(context, ref, 1),
          icon: const Icon(Icons.copy_outlined),
          label: Text(l.qtcRelay_copyNegative),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || (output?.isEmpty ?? true)
              ? null
              : () => _copy(context, ref, 2),
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(l.qtcRelay_copyAll),
        ),
        FilledButton.icon(
          onPressed: busy || (output?.isEmpty ?? true)
              ? null
              : () => _send(context, ref),
          icon: const Icon(Icons.north_east),
          label: Text(l.qtcRelay_send),
        ),
      ],
    );
  }
}

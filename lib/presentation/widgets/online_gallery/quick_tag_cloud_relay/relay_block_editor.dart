import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/online_gallery/quick_tag_cloud_relay.dart';
import '../../../providers/quick_tag_cloud_relay_provider.dart';
import '../../common/themed_input.dart';

Future<void> showRelayBlockEditor(
  BuildContext context, {
  required String planId,
  QuickTagCloudRelayBlock? block,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RelayBlockEditor(planId: planId, block: block),
);

class _RelayBlockEditor extends ConsumerStatefulWidget {
  const _RelayBlockEditor({required this.planId, this.block});
  final String planId;
  final QuickTagCloudRelayBlock? block;
  @override
  ConsumerState<_RelayBlockEditor> createState() => _RelayBlockEditorState();
}

class _RelayBlockEditorState extends ConsumerState<_RelayBlockEditor> {
  late final _title = TextEditingController(text: widget.block?.title ?? '');
  late final _positive = TextEditingController(
    text: widget.block?.positive ?? '',
  );
  late final _negative = TextEditingController(
    text: widget.block?.negative ?? '',
  );
  late final _weight = TextEditingController(
    text: '${widget.block?.weight ?? 1}',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _positive.dispose();
    _negative.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weight.text.trim());
    if (weight == null ||
        !weight.isFinite ||
        weight < QuickTagCloudRelayBlock.minimumWeight ||
        weight > QuickTagCloudRelayBlock.maximumWeight) {
      setState(() => _error = context.l10n.qtcRelay_invalidWeight);
      return;
    }
    final original = widget.block;
    if (original != null &&
        !original.allowedBy(
          ref.read(quickTagCloudRelayAllowedRatingsProvider),
        )) {
      setState(() => _error = context.l10n.qtcRelay_locked);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final block =
        (original ?? QuickTagCloudRelayBlock(id: const Uuid().v4(), title: ''))
            .copyWith(
              title: _title.text.trim(),
              positive: _positive.text,
              negative: _negative.text,
              weight: weight,
            );
    try {
      final controller = ref.read(quickTagCloudRelayProvider.notifier);
      if (original == null) {
        await controller.addBlock(widget.planId, block);
      } else {
        await controller.updateBlock(widget.planId, block);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.qtcRelay_saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool multiline = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        ThemedInput(
          controller: controller,
          enabled: !_saving,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          maxLength: multiline ? 100000 : 60,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final characters =
        widget.block?.characters ?? const <QuickTagCloudRelayCharacter>[];
    final ratings = ref.watch(quickTagCloudRelayAllowedRatingsProvider);
    final locked = widget.block != null && !widget.block!.allowedBy(ratings);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.block == null ? l.qtcRelay_addBlock : l.common_edit),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: locked
                  ? [Text(l.qtcRelay_locked)]
                  : [
                      _field(l.qtcRelay_blockTitle, _title),
                      _field(
                        l.prompt_positivePrompt,
                        _positive,
                        multiline: true,
                      ),
                      _field(
                        l.prompt_negativePrompt,
                        _negative,
                        multiline: true,
                      ),
                      Text(
                        l.qtcRelay_weight,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ThemedInput(
                        controller: _weight,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        helperText: l.qtcRelay_weightHint,
                      ),
                      if (characters.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(l.qtcRelay_charactersNote),
                        for (final character in characters)
                          ExpansionTile(
                            title: Text(
                              character.label.isEmpty
                                  ? l.prompt_characterPrompts
                                  : character.label,
                            ),
                            children: [
                              ListTile(
                                title: Text(l.prompt_positive),
                                subtitle: SelectableText(character.positive),
                              ),
                              ListTile(
                                title: Text(l.prompt_negative),
                                subtitle: SelectableText(character.negative),
                              ),
                            ],
                          ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: _saving || locked ? null : _save,
            child: Text(_saving ? l.common_loading : l.common_save),
          ),
        ],
      ),
    );
  }
}

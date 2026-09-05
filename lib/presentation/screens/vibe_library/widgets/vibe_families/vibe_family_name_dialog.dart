import 'package:flutter/material.dart';
import '../../../../../core/utils/localization_extension.dart';

class VibeFamilyNameDialog extends StatefulWidget {
  const VibeFamilyNameDialog({super.key, required this.initial});
  final String initial;
  @override
  State<VibeFamilyNameDialog> createState() => _VibeFamilyNameDialogState();
}

class _VibeFamilyNameDialogState extends State<VibeFamilyNameDialog> {
  late final _text = TextEditingController(text: widget.initial);
  void _submit() {
    final name = _text.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.vibeFamily_name),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: 100,
      decoration: InputDecoration(labelText: context.l10n.vibeFamily_name),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.vibeFamily_cancel),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(context.l10n.vibeFamily_confirm),
      ),
    ],
  );
}

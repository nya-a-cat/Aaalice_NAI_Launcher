import 'package:flutter/material.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/vibe/vibe_family.dart';
import 'vibe_family_preview.dart';

class VibeStyleSuggestionCard extends StatefulWidget {
  const VibeStyleSuggestionCard({super.key, required this.match, required this.onOpen,
    required this.onMerge, required this.onSeparate, required this.enabled});
  final VibeStyleMatch match;
  final void Function(String hash) onOpen;
  final VoidCallback onMerge, onSeparate;
  final bool enabled;
  @override
  State<VibeStyleSuggestionCard> createState() => _VibeStyleSuggestionCardState();
}
class _VibeStyleSuggestionCardState extends State<VibeStyleSuggestionCard> {
  int _example = 0;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = widget.match;
    final pair = m.examples[_example.clamp(0, m.examples.length-1)];
    String short(String value) => value.length > 10 ? value.substring(0,10) : value;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.hasControls ? l.vibeFamily_controlled : l.vibeFamily_visualOnly,
          style: Theme.of(context).textTheme.titleSmall),
        Text(l.vibeFamily_evidence(m.recipeCount, m.sameSeedCount)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: VibeFamilyPreview(path: pair.$1.path, label: 'Vibe ${short(m.left)}',
            onTap: () => widget.onOpen(m.left))),
          const SizedBox(width: 12),
          Expanded(child: VibeFamilyPreview(path: pair.$2.path, label: 'Vibe ${short(m.right)}',
            onTap: () => widget.onOpen(m.right))),
        ]),
        if (m.examples.length > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: l.vibeFamily_previousPair,
              onPressed: _example > 0 ? () => setState(() => _example--) : null,
              icon: const Icon(Icons.chevron_left)),
            Text('${_example+1} / ${m.examples.length}'),
            IconButton(tooltip: l.vibeFamily_nextPair,
              onPressed: _example+1 < m.examples.length ? () => setState(() => _example++) : null,
              icon: const Icon(Icons.chevron_right)),
          ]),
        // An uncalibrated distance must never appear as a percentage probability.
        Text(l.vibeFamily_dimensions(
          m.dimensions[0].toStringAsFixed(2), m.dimensions[1].toStringAsFixed(2),
          m.dimensions[2].toStringAsFixed(2), m.dimensions[3].toStringAsFixed(2))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton.tonal(onPressed: widget.enabled ? widget.onMerge : null,
            child: Text(l.vibeFamily_merge)),
          TextButton(onPressed: widget.enabled ? widget.onSeparate : null,
            child: Text(l.vibeFamily_keepSeparate)),
        ]),
      ]));
  }
}

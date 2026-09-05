import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/vibe/vibe_family.dart';
import '../../../../providers/vibe_family_provider.dart';
import 'vibe_family_preview.dart';

class VibeFamilyCollection extends StatelessWidget {
  const VibeFamilyCollection({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onRename,
    required this.separated,
  });
  final VibeFamilyController controller;
  final void Function(String hash) onOpen;
  final void Function(VibeFamily family) onRename;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = controller.decisions;
    final summaries = {for (final s in controller.summaries) s.hash: s};
    if (separated) {
      final pairs = state.separations.toList()..sort();
      if (pairs.isEmpty) return Center(child: Text(l.vibeFamily_noSeparations));
      return ListView.builder(
        itemCount: pairs.length,
        itemBuilder: (context, i) {
          final hashes = (jsonDecode(pairs[i]) as List).cast<String>();
          String short(String h) => h.length > 10 ? h.substring(0, 10) : h;
          return ListTile(
            title: Text(hashes.map((h) => 'Vibe ${short(h)}').join(' / ')),
            trailing: IconButton(
              tooltip: l.vibeFamily_restore,
              onPressed: controller.saving
                  ? null
                  : () => controller.restore(pairs[i]),
              icon: const Icon(Icons.undo),
            ),
          );
        },
      );
    }
    if (state.families.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.vibeFamily_noFamilies),
        ),
      );
    }
    return ListView.builder(
      itemCount: state.families.length,
      itemBuilder: (context, index) {
        final family = state.families[index];
        return ExpansionTile(
          key: PageStorageKey(family.id),
          initiallyExpanded: true,
          title: Text(family.name),
          subtitle: Text(l.vibeFamily_memberCount(family.members.length)),
          trailing: IconButton(
            tooltip: l.vibeFamily_rename,
            onPressed: controller.saving ? null : () => onRename(family),
            icon: const Icon(Icons.edit_outlined),
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 190).floor().clamp(
                  1,
                  6,
                );
                final width = (constraints.maxWidth - 32) / columns;
                final members = family.members.toList()..sort();
                return Wrap(
                  children: members.map((hash) {
                    final summary = summaries[hash];
                    return SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            VibeFamilyPreview(
                              path: summary?.previewPath,
                              label:
                                  'Vibe ${summary?.shortHash ?? (hash.length > 10 ? hash.substring(0, 10) : hash)}',
                              onTap: () => onOpen(hash),
                            ),
                            TextButton(
                              onPressed: controller.saving
                                  ? null
                                  : () => controller.split(hash),
                              child: Text(l.vibeFamily_split),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

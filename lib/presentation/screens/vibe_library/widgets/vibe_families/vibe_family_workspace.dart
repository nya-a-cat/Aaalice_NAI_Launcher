import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/database/datasources/gallery_data_source.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/vibe/vibe_family.dart';
import '../../../../providers/vibe_family_provider.dart';
import '../../../../providers/vibe_library_provider.dart';
import '../../../../widgets/common/app_toast.dart';
import '../local_gallery_vibe_content_view.dart';
import 'vibe_family_collection.dart';
import 'vibe_family_preview.dart';
import 'vibe_family_name_dialog.dart';
import 'vibe_style_suggestion_card.dart';

class VibeFamilyWorkspace extends ConsumerStatefulWidget {
  const VibeFamilyWorkspace({super.key});
  @override
  ConsumerState<VibeFamilyWorkspace> createState() =>
      _VibeFamilyWorkspaceState();
}

class _VibeFamilyWorkspaceState extends ConsumerState<VibeFamilyWorkspace> {
  final _selected = <String>{};
  int _view = 0, _page = 0;
  static const _pageSize = 12;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(ref.read(vibeFamilyProvider).initialize());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vibeFamilyProvider);
    final l = context.l10n;
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final matches = controller.suggestions;
    final total = _view == 0 ? matches.length : controller.summaries.length;
    final pages = (total / _pageSize).ceil().clamp(1, 100000);
    final page = _page.clamp(0, pages - 1);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_view < 2 && page > 0) setState(() => _page = page - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_view < 2 && page + 1 < pages) setState(() => _page = page + 1);
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final item in [
                    (0, l.vibeFamily_suggestions),
                    (1, l.vibeFamily_allCodes),
                    (2, l.vibeFamily_confirmed),
                    (3, l.vibeFamily_separated),
                  ])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: _view == item.$1,
                      onSelected: (_) => setState(() {
                        _view = item.$1;
                        _page = 0;
                      }),
                    ),
                  FilledButton.tonal(
                    onPressed: controller.analyzing
                        ? controller.cancel
                        : controller.analyze,
                    child: Text(
                      controller.analyzing
                          ? l.vibeFamily_cancel
                          : l.vibeFamily_analyze,
                    ),
                  ),
                  if (_view == 1)
                    TextButton(
                      onPressed: _selected.length >= 2 && !controller.saving
                          ? () => _merge(controller, _selected)
                          : null,
                      child: Text(l.vibeFamily_merge),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                l.vibeFamily_hint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  children: [
                    Text(
                      controller.error == 'conflict'
                          ? l.vibeFamily_conflict
                          : l.vibeFamily_error,
                    ),
                    if (controller.error == 'load')
                      TextButton(
                        onPressed: controller.retry,
                        child: Text(l.vibeFamily_retry),
                      ),
                  ],
                ),
              ),
            if (controller.analyzing) ...[
              LinearProgressIndicator(
                value:
                    controller.progress?.phase == 'features' &&
                        (controller.progress?.total ?? 0) > 0
                    ? controller.progress!.completed /
                          controller.progress!.total
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  controller.progress?.phase == 'features'
                      ? l.vibeFamily_progress(
                          controller.progress!.completed,
                          controller.progress!.total,
                        )
                      : controller.progress?.phase == 'rank'
                      ? l.vibeFamily_ranking
                      : l.vibeFamily_preparing,
                ),
              ),
            ],
            if (controller.cancelled) Text(l.vibeFamily_cancelled),
            if (controller.result != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  l.vibeFamily_result(
                    controller.result!.scanned,
                    controller.result!.skipped,
                    controller.result!.selected,
                    controller.result!.available,
                  ),
                ),
              ),
            Expanded(
              child: switch (_view) {
                0 =>
                  matches.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              controller.result == null
                                  ? l.vibeFamily_startHint
                                  : l.vibeFamily_noMatches,
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey('suggestions-$page'),
                          itemCount: (matches.length - page * _pageSize).clamp(
                            0,
                            _pageSize,
                          ),
                          itemBuilder: (context, index) {
                            final m = matches[page * _pageSize + index];
                            return ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 840),
                              child: VibeStyleSuggestionCard(
                                key: ValueKey(
                                  VibeFamilyState.pairKey(m.left, m.right),
                                ),
                                match: m,
                                enabled: !controller.saving,
                                onOpen: _open,
                                onMerge: () =>
                                    _merge(controller, {m.left, m.right}),
                                onSeparate: () =>
                                    controller.separate(m.left, m.right),
                              ),
                            );
                          },
                        ),
                1 => _allCodes(controller, page),
                _ => VibeFamilyCollection(
                  controller: controller,
                  separated: _view == 3,
                  onOpen: _open,
                  onRename: (family) => _rename(controller, family),
                ),
              },
            ),
            if (_view < 2)
              SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: l.vibeFamily_previousPage,
                      onPressed: page > 0
                          ? () => setState(() => _page = page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(l.vibeLibrary_pageIndicator(page + 1, pages)),
                    IconButton(
                      tooltip: l.vibeFamily_nextPage,
                      onPressed: page + 1 < pages
                          ? () => setState(() => _page = page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _allCodes(VibeFamilyController controller, int page) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 230).floor().clamp(1, 6);
        final codes = controller.summaries
            .skip(page * _pageSize)
            .take(_pageSize)
            .toList();
        return GridView.builder(
          key: ValueKey('codes-$page'),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 280,
          ),
          itemCount: codes.length,
          itemBuilder: (context, i) {
            final s = codes[i];
            return Column(
              children: [
                Expanded(
                  child: VibeFamilyPreview(
                    path: s.previewPath,
                    label: 'Vibe ${s.shortHash}',
                    onTap: () => _open(s.hash),
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(s.hash),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(s.hash);
                    } else {
                      _selected.remove(s.hash);
                    }
                  }),
                  title: Text(
                    controller.decisions.familyOf(s.hash)?.name ??
                        context.l10n.vibeFamily_ungrouped,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _open(String hash) async {
    if (_opening) return;
    _opening = true;
    try {
      final groups = await GalleryDataSource().queryLocalGalleryVibeGroups(
        searchQuery: hash,
        limit: 1,
      );
      if (!mounted) return;
      if (groups.isEmpty || groups.first.fingerprint != hash) {
        AppToast.warning(context, context.l10n.vibeFamily_missing);
        return;
      }
      final saved = ref
          .read(vibeLibraryNotifierProvider)
          .entries
          .any((e) => e.tags.contains('vibe:$hash'));
      await LocalGalleryVibeContentView.showDetail(
        context,
        ref,
        groups.first,
        isSaved: saved,
      );
    } catch (_) {
      if (mounted) AppToast.error(context, context.l10n.vibeFamily_error);
    } finally {
      _opening = false;
    }
  }

  Future<String?> _name(String initial) async {
    return showDialog<String>(
      context: context,
      builder: (_) => VibeFamilyNameDialog(initial: initial),
    );
  }

  Future<void> _merge(VibeFamilyController c, Set<String> hashes) async {
    final chosen = {...hashes};
    final name = await _name(context.l10n.vibeFamily_defaultName);
    if (name == null || !mounted) return;
    await c.merge(chosen, name);
    if (mounted && c.error == null) setState(() => _selected.clear());
  }

  Future<void> _rename(VibeFamilyController c, VibeFamily family) async {
    final name = await _name(family.name);
    if (name != null && mounted) await c.rename(family.id, name);
  }
}

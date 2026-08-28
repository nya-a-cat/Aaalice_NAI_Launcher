import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/gallery_prompt_pattern.dart';

typedef GalleryPromptAnalysisLoader = Future<GalleryPromptMiningResult>
    Function();
typedef GalleryPromptAnalysisSaver = Future<int> Function(
  List<GalleryPromptPatternCandidate> candidates,
);

class GalleryPromptAnalysisDialog extends StatefulWidget {
  const GalleryPromptAnalysisDialog({
    super.key,
    required this.load,
    required this.save,
  });

  final GalleryPromptAnalysisLoader load;
  final GalleryPromptAnalysisSaver save;

  @override
  State<GalleryPromptAnalysisDialog> createState() =>
      _GalleryPromptAnalysisDialogState();
}

class _GalleryPromptAnalysisDialogState
    extends State<GalleryPromptAnalysisDialog> {
  GalleryPromptMiningResult? _result;
  Object? _error;
  var _type = GalleryPromptPatternType.artist;
  final Set<String> _selectedIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result.artistPatterns.isEmpty && result.effectPatterns.isNotEmpty) {
          _type = GalleryPromptPatternType.effect;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: Column(
          children: [
            _buildHeader(theme),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme)),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
      child: Row(
        children: [
          Icon(Icons.query_stats_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tagLibrary_promptAnalysisTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.tagLibrary_promptAnalysisDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.common_close,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final result = _result;
    if (result == null) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _error.toString(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.common_retry),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.tagLibrary_promptAnalysisLoading),
          ],
        ),
      );
    }
    if (result.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.manage_search_rounded, size: 48),
              const SizedBox(height: 12),
              Text(context.l10n.tagLibrary_promptAnalysisEmpty),
            ],
          ),
        ),
      );
    }

    final candidates = _type == GalleryPromptPatternType.artist
        ? result.artistPatterns
        : result.effectPatterns;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<GalleryPromptPatternType>(
                segments: [
                  ButtonSegment(
                    value: GalleryPromptPatternType.artist,
                    icon: const Icon(Icons.brush_outlined),
                    label: Text(
                      '${context.l10n.tagLibrary_artistPatterns} '
                      '(${result.artistPatterns.length})',
                    ),
                  ),
                  ButtonSegment(
                    value: GalleryPromptPatternType.effect,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      '${context.l10n.tagLibrary_effectPatterns} '
                      '(${result.effectPatterns.length})',
                    ),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() => _type = selection.single);
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '${context.l10n.tagLibrary_scannedImages}: '
                    '${result.scannedImageCount} / '
                    '${result.totalAvailableImageCount}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (result.wasLimited)
                    Text(
                      context.l10n.tagLibrary_promptAnalysisLimited,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: candidates.isEmpty
              ? Center(
                  child: Text(context.l10n.tagLibrary_promptAnalysisEmpty),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    return _buildCandidate(theme, candidate);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCandidate(
    ThemeData theme,
    GalleryPromptPatternCandidate candidate,
  ) {
    final selected = _selectedIds.contains(candidate.id);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggle(candidate.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => _toggle(candidate.id),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      candidate.prompt,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _metricChip(
                          Icons.photo_library_outlined,
                          '${candidate.imageCount} '
                          '${context.l10n.tagLibrary_images}',
                        ),
                        _metricChip(
                          Icons.verified_outlined,
                          '${context.l10n.tagLibrary_confidence} '
                          '${(candidate.confidence * 100).round()}%',
                        ),
                        for (final example in candidate.examplePaths.take(3))
                          Tooltip(
                            message: example,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  path.basename(example),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: candidate.confidence,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricChip(IconData icon, String label) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _buildFooter() {
    final result = _result;
    final allCandidates = result == null
        ? const <GalleryPromptPatternCandidate>[]
        : [...result.artistPatterns, ...result.effectPatterns];
    final selected = allCandidates
        .where((candidate) => _selectedIds.contains(candidate.id))
        .toList(growable: false);
    final selectAllButton = result != null && !result.isEmpty
        ? TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      if (_selectedIds.length == allCandidates.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds
                          ..clear()
                          ..addAll(
                            allCandidates.map((candidate) => candidate.id),
                          );
                      }
                    });
                  },
            child: Text(context.l10n.tagLibrary_selectAll),
          )
        : const SizedBox.shrink();
    final cancelButton = TextButton(
      onPressed: _saving ? null : () => Navigator.of(context).pop(),
      child: Text(context.l10n.common_cancel),
    );
    final saveButton = FilledButton.icon(
      onPressed: selected.isEmpty || _saving ? null : () => _save(selected),
      icon: _saving
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.library_add_outlined),
      label: Text(
        '${context.l10n.tagLibrary_saveSelected} (${selected.length})',
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: selectAllButton),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [cancelButton, const SizedBox(width: 8), saveButton],
                ),
              ],
            );
          }
          return Row(
            children: [
              selectAllButton,
              const Spacer(),
              cancelButton,
              const SizedBox(width: 8),
              saveButton,
            ],
          );
        },
      ),
    );
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  Future<void> _save(List<GalleryPromptPatternCandidate> selected) async {
    setState(() => _saving = true);
    try {
      final saved = await widget.save(selected);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/gallery/local_gallery_vibe_group.dart';
import 'local_gallery_vibe_card.dart';

class LocalGalleryVibeDetailDialog extends StatefulWidget {
  const LocalGalleryVibeDetailDialog({
    super.key,
    required this.group,
    required this.initiallySaved,
    required this.loadExamples,
    required this.onSend,
    required this.onSave,
  });

  final LocalGalleryVibeGroup group;
  final bool initiallySaved;
  final Future<List<LocalGalleryVibeExample>> Function({
    required int limit,
    required int offset,
  })
  loadExamples;
  final Future<void> Function(LocalGalleryVibeExample example) onSend;
  final Future<bool> Function(LocalGalleryVibeExample example) onSave;

  @override
  State<LocalGalleryVibeDetailDialog> createState() =>
      _LocalGalleryVibeDetailDialogState();
}

class _LocalGalleryVibeDetailDialogState
    extends State<LocalGalleryVibeDetailDialog> {
  late List<LocalGalleryVibeExample> _examples;
  LocalGalleryVibeExample? _selected;
  bool _loadingExamples = false;
  bool _saving = false;
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _examples = [...widget.group.examples];
    _selected = _examples.firstOrNull;
    _saved = widget.initiallySaved;
    unawaited(_loadMore(replace: true));
  }

  Future<void> _loadMore({bool replace = false}) async {
    if (_loadingExamples) return;
    setState(() => _loadingExamples = true);
    try {
      final offset = replace ? 0 : _examples.length;
      final loaded = await widget.loadExamples(limit: 100, offset: offset);
      if (!mounted) return;
      setState(() {
        _examples = replace ? loaded : [..._examples, ...loaded];
        _selected ??= _examples.firstOrNull;
      });
    } finally {
      if (mounted) setState(() => _loadingExamples = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactWindow = MediaQuery.sizeOf(context).width < 700;
    return SafeArea(
      child: Dialog(
        insetPadding: compactWindow
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactContent = constraints.maxWidth < 700;
              return Column(
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  Expanded(
                    child: compactContent
                        ? _buildCompactBody(context)
                        : _buildDesktopBody(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.displayName,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  context.l10n.vibeLibrary_exactEncodingGroup,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBody(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildSelectedImage(context)),
              _buildExampleStrip(context),
            ],
          ),
        ),
        SizedBox(width: 320, child: _buildInfoPanel(context)),
      ],
    );
  }

  Widget _buildCompactBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 1,
            child: _buildSelectedImage(context),
          ),
        ),
        SliverToBoxAdapter(child: _buildExampleStrip(context)),
        SliverToBoxAdapter(child: _buildInfoPanel(context)),
      ],
    );
  }

  Widget _buildSelectedImage(BuildContext context) {
    final selected = _selected;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: selected == null
          ? const Center(child: Icon(Icons.image_not_supported_outlined))
          : LayoutBuilder(
              builder: (context, constraints) {
                final ratio = MediaQuery.devicePixelRatioOf(context);
                return Image.file(
                  File(selected.filePath),
                  fit: BoxFit.contain,
                  cacheWidth: _cacheDimension(constraints.maxWidth, ratio),
                  cacheHeight: _cacheDimension(constraints.maxHeight, ratio),
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                );
              },
            ),
    );
  }

  int? _cacheDimension(double extent, double ratio) {
    if (!extent.isFinite || extent <= 0) return null;
    return (extent * ratio).round().clamp(1, 8192).toInt();
  }

  Widget _buildExampleStrip(BuildContext context) {
    final canLoadMore = _examples.length < widget.group.exampleCount;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        scrollDirection: Axis.horizontal,
        itemCount: _examples.length + (canLoadMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _examples.length) {
            return SizedBox(
              width: 92,
              child: FilledButton.tonal(
                onPressed: _loadingExamples ? null : _loadMore,
                child: _loadingExamples
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.vibeLibrary_loadMore),
              ),
            );
          }
          return _buildExample(context, index, _examples[index]);
        },
      ),
    );
  }

  Widget _buildExample(
    BuildContext context,
    int index,
    LocalGalleryVibeExample example,
  ) {
    final selected = example.imageId == _selected?.imageId;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: index == 0
          ? context.l10n.vibeLibrary_earliestLocalExample
          : p.basename(example.filePath),
      child: InkWell(
        onTap: () => setState(() => _selected = example),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 92,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            File(example.filePath),
            fit: BoxFit.cover,
            cacheWidth: 184,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _InfoRow(
              label: context.l10n.vibeLibrary_examples,
              value: '${widget.group.exampleCount}',
            ),
            _InfoRow(
              label: context.l10n.vibeLibrary_earliestLocalExample,
              value: formatLocalVibeDate(widget.group.firstSeenAt),
            ),
            _InfoRow(
              label: context.l10n.vibe_strength,
              value: selected?.strength.toStringAsFixed(2) ?? '—',
            ),
            _InfoRow(
              label: context.l10n.vibe_infoExtracted,
              value: selected?.infoExtracted.toStringAsFixed(2) ?? '—',
            ),
            _InfoRow(
              label: context.l10n.vibeLibrary_model,
              value: selected?.encodingModel ??
                  (widget.group.encodingModels.isEmpty
                      ? '—'
                      : widget.group.encodingModels.join(', ')),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.vibeLibrary_encodingFingerprint),
              subtitle: SelectableText(widget.group.fingerprint),
              trailing: IconButton(
                tooltip: context.l10n.common_copy,
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: widget.group.fingerprint),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Text(
                p.basename(selected.filePath),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: selected == null ? null : () => widget.onSend(selected),
              icon: const Icon(Icons.send_outlined),
              label: Text(context.l10n.vibeLibrary_sendToGeneration),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: selected == null || _saved || _saving
                  ? null
                  : () => _save(selected),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _saved
                          ? Icons.bookmark_added_outlined
                          : Icons.bookmark_add_outlined,
                    ),
              label: Text(
                _saved
                    ? context.l10n.vibeLibrary_saved
                    : context.l10n.vibeLibrary_saveToLibrary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(LocalGalleryVibeExample example) async {
    setState(() => _saving = true);
    final saved = await widget.onSave(example);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved;
    });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

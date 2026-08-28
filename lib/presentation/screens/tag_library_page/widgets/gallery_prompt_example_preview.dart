import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Read-only previews for images that support a mined prompt pattern.
class GalleryPromptExampleStrip extends StatelessWidget {
  const GalleryPromptExampleStrip({
    super.key,
    required this.examplePaths,
  });

  final List<String> examplePaths;

  @override
  Widget build(BuildContext context) {
    if (examplePaths.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: examplePaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final imagePath = examplePaths[index];
          return Tooltip(
            message: imagePath,
            child: Semantics(
              button: true,
              label: path.basename(imagePath),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('gallery-prompt-example-$index'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _GalleryPromptExampleDialog(
                      examplePaths: examplePaths,
                      initialIndex: index,
                    ),
                  ),
                  child: SizedBox(
                    width: 82,
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      cacheWidth: 164,
                      cacheHeight: 164,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryPromptExampleDialog extends StatefulWidget {
  const _GalleryPromptExampleDialog({
    required this.examplePaths,
    required this.initialIndex,
  });

  final List<String> examplePaths;
  final int initialIndex;

  @override
  State<_GalleryPromptExampleDialog> createState() =>
      _GalleryPromptExampleDialogState();
}

class _GalleryPromptExampleDialogState
    extends State<_GalleryPromptExampleDialog> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.examplePaths[_index];
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          path.basename(imagePath),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text('${_index + 1} / ${widget.examplePaths.length}'),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerLowest,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final ratio = MediaQuery.devicePixelRatioOf(
                              context,
                            );
                            final cacheHeight = constraints.maxHeight.isFinite
                                ? (constraints.maxHeight * ratio)
                                      .round()
                                      .clamp(1, 4096)
                                      .toInt()
                                : null;
                            return Image.file(
                              File(imagePath),
                              key: ValueKey(
                                'gallery-prompt-example-full-$_index',
                              ),
                              fit: BoxFit.contain,
                              cacheHeight: cacheHeight,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                        if (_index > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton.filledTonal(
                              onPressed: () => _move(-1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                          ),
                        if (_index + 1 < widget.examplePaths.length)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton.filledTonal(
                              onPressed: () => _move(1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _move(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.examplePaths.length) return;
    setState(() => _index = next);
  }
}

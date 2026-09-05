import 'dart:io';
import 'package:flutter/material.dart';

/// Capped, aspect-preserving, read-only preview. Full detail opens on activation.
class VibeFamilyPreview extends StatelessWidget {
  const VibeFamilyPreview({
    super.key,
    required this.path,
    required this.label,
    required this.onTap,
  });
  final String? path;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(
      Icons.image_not_supported_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: onTap,
              child: path == null
                  ? placeholder
                  : Image.file(
                      File(path!),
                      fit: BoxFit.contain,
                      cacheHeight: 256,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

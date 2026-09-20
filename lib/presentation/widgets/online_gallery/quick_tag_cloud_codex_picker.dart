import 'package:flutter/material.dart';

import '../../../data/datasources/remote/online_gallery/quick_tag_cloud_gallery_source_adapter.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_catalog.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_codex.dart';
import '../../../l10n/app_localizations.dart';

Future<String?> showQuickTagCloudCodexPicker(
  BuildContext context,
  QuickTagCloudCatalog catalog,
  QuickTagCloudGalleryQuery query,
  QuickTagCloudCodex? selectedCodex, {
  required bool allowNsfw,
}) async {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.onlineGallery_codexSelect),
      content: SizedBox(
        width: 620,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                selected: query.codexId == 'all',
                leading: const Icon(Icons.library_books_outlined),
                title: Text(l10n.onlineGallery_codexAll),
                onTap: () => Navigator.pop(dialogContext, 'all'),
              ),
              const Divider(),
              for (final meta in catalog.codexes)
                Builder(
                  builder: (context) {
                    final displayed = selectedCodex?.id == meta.id
                        ? selectedCodex!.asMediaMeta()
                        : meta;
                    return ListTile(
                      selected: query.codexId == meta.id,
                      leading: Icon(
                        meta.nsfw
                            ? Icons.lock_outline
                            : Icons.menu_book_outlined,
                      ),
                      title: Text(displayed.title),
                      subtitle: Text(
                        '${displayed.author.isEmpty ? displayed.id : displayed.author}\n'
                        '${l10n.onlineGallery_codexEntryCount(displayed.entryCount, displayed.imagedCount)}',
                      ),
                      isThreeLine: true,
                      trailing: Text(displayed.version),
                      onTap: meta.nsfw && !allowNsfw
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.onlineGallery_codexBookLocked,
                                  ),
                                ),
                              );
                            }
                          : () => Navigator.pop(dialogContext, meta.id),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

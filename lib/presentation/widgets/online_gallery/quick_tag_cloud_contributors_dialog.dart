import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/app_logger.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_catalog.dart';
import '../../../l10n/app_localizations.dart';

Future<void> _openContributorLink(
  BuildContext context,
  String value,
) async {
  final uri = Uri.tryParse(value.trim());
  try {
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
        await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (error, stackTrace) {
    AppLogger.e(
      'Failed to open QuickTagCloud codex origin: $uri',
      error,
      stackTrace,
      'QuickTagCloudToolbar',
    );
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.cannotOpenUrl)),
    );
  }
}

Future<void> showQuickTagCloudContributors(
  BuildContext context,
  QuickTagCloudCodexMeta meta,
) async {
  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(meta.title),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(meta.author),
                subtitle: Text(
                  l10n.onlineGallery_codexEntryCount(
                    meta.entryCount,
                    meta.imagedCount,
                  ),
                ),
                trailing: Text(meta.version),
              ),
              if (meta.source.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dataset_outlined),
                  title: Text(l10n.onlineGallery_codexDeclaredSource),
                  subtitle: SelectableText(meta.source.trim()),
                ),
              const Divider(),
              for (final contributor in meta.contributors)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(contributor.name),
                  subtitle: contributor.role.isEmpty
                      ? null
                      : Text(contributor.role),
                ),
              for (final link in meta.links)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.open_in_new),
                  title: Text(link.label.isEmpty ? link.url : link.label),
                  subtitle: Text(link.url),
                  onTap: () => _openContributorLink(dialogContext, link.url),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('quick-tag-cloud-open-origin'),
          onPressed: () => _openContributorLink(dialogContext,
              Uri.https('novelai.quicktagcloud.com', '/', {'codex': meta.id}).toString()),
          icon: const Icon(Icons.open_in_new, size: 17),
          label: Text(l10n.onlineGallery_codexOpenOrigin),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.common_close),
        ),
      ],
    ),
  );
}

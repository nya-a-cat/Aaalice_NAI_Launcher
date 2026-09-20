import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/cache/online_gallery_image_cache_manager.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../core/utils/media_mime_type.dart';
import '../../../data/models/online_gallery/gallery_item.dart';
import '../../providers/reverse_prompt_provider.dart';
import '../../widgets/common/app_toast.dart';
import 'online_gallery_utils.dart';

/// Media export and reverse-prompt commands for an opened gallery entry.
class OnlineGalleryDetailMediaActions {
  const OnlineGalleryDetailMediaActions({
    required this.context,
    required this.ref,
    required this.item,
    required this.closeForNavigation,
  });

  final BuildContext context;
  final WidgetRef ref;
  final GalleryItem item;
  final VoidCallback closeForNavigation;

  Future<void> sendToReverse(GalleryMedia media) async {
    final url = media.displayUrl.isNotEmpty
        ? media.displayUrl
        : (media.downloadUrl.isNotEmpty ? media.downloadUrl : media.previewUrl);
    if (url.isEmpty) {
      AppToast.info(context, context.l10n.onlineGallery_noImageUrl);
      return;
    }
    try {
      final file = await OnlineGalleryImageCacheManager.instance.getSingleFile(
        url,
        key: onlineGalleryImageCacheKeyForUrl(url),
        headers: onlineGalleryImageHeadersForUrl(url),
      );
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await ref
          .read(reversePromptProvider.notifier)
          .addImage(
            bytes,
            name: '${item.sourceId.key}_${item.sourceWorkId}',
          );
      if (!context.mounted) return;
      final router = GoRouter.of(context);
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      final message = context.l10n.onlineGallery_sentToReversePrompt;
      closeForNavigation();
      router.go('/');
      AppToast.successOnOverlay(overlay, message);
    } catch (error) {
      if (context.mounted) {
        AppToast.error(
          context,
          context.l10n.onlineGallery_reversePromptSendFailed('$error'),
        );
      }
    }
  }

  Future<void> downloadAll(List<GalleryMedia> mediaItems) async {
    final directory = await FileExportService.pickExportDirectory(
      dialogTitle: context.l10n.onlineGallery_chooseDownloadDirectory,
    );
    if (directory == null) return;
    try {
      for (final media in mediaItems) {
        final url = media.downloadUrl.isNotEmpty
            ? media.downloadUrl
            : (media.displayUrl.isNotEmpty
                  ? media.displayUrl
                  : media.previewUrl);
        if (url.isEmpty) continue;
        final file = await OnlineGalleryImageCacheManager.instance.getSingleFile(
          url,
          key: onlineGalleryImageCacheKeyForUrl(url),
          headers: onlineGalleryImageHeadersForUrl(url),
        );
        final extension = resolveGalleryDownloadExtension(media, url);
        await FileExportService.writeFileToDirectory(
          directory: directory,
          sourcePath: file.path,
          fileName: _fileName(media, extension),
          mimeType: mediaMimeTypeForExtension(extension),
        );
      }
      if (context.mounted) {
        AppToast.success(
          context,
          context.l10n.onlineGallery_savedFiles(mediaItems.length),
        );
      }
    } catch (error) {
      _showDownloadError(error);
    }
  }

  Future<void> downloadOriginal(GalleryMedia media) async {
    final url = media.downloadUrl;
    try {
      final file = await OnlineGalleryImageCacheManager.instance.getSingleFile(
        url,
        key: onlineGalleryImageCacheKeyForUrl(url),
        headers: onlineGalleryImageHeadersForUrl(url),
      );
      if (!context.mounted) return;
      final extension = resolveGalleryDownloadExtension(media, url);
      final savedLocation = await FileExportService.saveFileFromPath(
        sourcePath: file.path,
        fileName: _fileName(media, extension),
        dialogTitle: context.l10n.onlineGallery_chooseDownloadDirectory,
        mimeType: mediaMimeTypeForExtension(extension),
        allowedExtensions: [extension],
      );
      if (savedLocation == null) return;
      if (context.mounted) {
        AppToast.success(context, context.l10n.onlineGallery_savedFiles(1));
      }
    } catch (error) {
      _showDownloadError(error);
    }
  }

  String _fileName(GalleryMedia media, String extension) {
    final safeWorkId = item.sourceWorkId.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    final safeMediaId = media.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return '${item.sourceId.key}_${safeWorkId}_$safeMediaId.$extension';
  }

  void _showDownloadError(Object error) {
    if (context.mounted) {
      AppToast.error(context, context.l10n.onlineGallery_downloadFailed('$error'));
    }
  }
}

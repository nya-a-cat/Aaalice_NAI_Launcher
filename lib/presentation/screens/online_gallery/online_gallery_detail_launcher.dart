import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/online_gallery/danbooru_post.dart';
import '../../providers/online_gallery_local_favorites_provider.dart';
import '../../providers/online_gallery_output_filter_provider.dart';
import '../../providers/online_gallery_prompt_tag_settings_provider.dart';
import '../../providers/online_gallery_provider.dart';
import '../../services/gallery_prompt_projection_service.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/online_gallery/gallery_detail_dialog.dart';
import 'online_gallery_detail_actions.dart';
import 'online_gallery_detail_labels.dart';
import 'online_gallery_detail_media_actions.dart';
import 'online_gallery_overlay_exit.dart';
import 'online_gallery_screen_controller.dart';

class OnlineGalleryDetailLauncher {
  OnlineGalleryDetailLauncher({
    required this.context,
    required this.ref,
    required this.controller,
  });

  final BuildContext context;
  final WidgetRef ref;
  final OnlineGalleryScreenController controller;

  OnlineGalleryNotifier get _galleryNotifier =>
      ref.read(onlineGalleryNotifierProvider.notifier);

  Future<void> show(
    BuildContext context,
    GalleryItem item, {
    GalleryDetail? knownDetail,
    VoidCallback? onLeaveDetail,
  }) async {
    if (!controller.pendingGalleryDetails.add(item.stableKey)) return;
    try {
      final detail =
          knownDetail ?? await _loadGalleryDetailWithProgress(context, item);
      if (detail == null) return;
      if (knownDetail == null) {
        await _recordViewed(item);
      } else {
        await ref
            .read(onlineGalleryLocalFavoritesProvider.notifier)
            .initialize();
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _buildDetailDialog(
          dialogContext,
          item,
          detail,
          useKnownDetail: knownDetail != null,
          closeForNavigation: galleryOwnedOverlayExit(
            dialogContext,
            onExit: onLeaveDetail,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        AppToast.error(
          context,
          '${context.l10n.onlineGallery_loadFailed}: $error',
        );
      }
    } finally {
      controller.pendingGalleryDetails.remove(item.stableKey);
    }
  }

  Future<void> _recordViewed(GalleryItem item) async {
    if (item.sourceId != GallerySourceId.quickTagCloud) return;
    try {
      await _galleryNotifier.recordQuickTagCloudViewed(item);
    } catch (error, stack) {
      AppLogger.e(
        'Failed to record QuickTagCloud history',
        error,
        stack,
        'OnlineGallery',
      );
    }
  }

  GalleryDetailDialog _buildDetailDialog(
    BuildContext context,
    GalleryItem item,
    GalleryDetail detail, {
    required bool useKnownDetail,
    required VoidCallback closeForNavigation,
  }) {
    final galleryState = ref.read(onlineGalleryNotifierProvider);
    final projection = const GalleryPromptProjectionService().project(
      item: item,
      detail: detail,
      promptTagSettings: ref.read(onlineGalleryPromptTagSettingsProvider),
      outputFilter: ref.read(onlineGalleryOutputFilterProvider),
    );
    final actions = OnlineGalleryDetailActions(
      context: context,
      ref: ref,
      item: item,
      detail: detail,
      projection: projection,
      closeForNavigation: closeForNavigation,
    );
    final mediaActions = OnlineGalleryDetailMediaActions(
      context: context,
      ref: ref,
      item: item,
      closeForNavigation: closeForNavigation,
    );
    final hasFocusedAiTagMedia =
        item.sourceId == GallerySourceId.aiTag && item.focusedMediaId != null;
    return GalleryDetailDialog(
      item: item,
      detail: detail,
      isFavorited: useKnownDetail
          ? ref
                .read(onlineGalleryLocalFavoritesProvider.notifier)
                .isFavorite(item.stableKey)
          : _galleryNotifier.isFavorited(item),
      favoriteLoading: galleryState.favoriteLoadingPostKeys.contains(
        item.stableKey,
      ),
      canToggleFavorite: true,
      labels: onlineGalleryDetailLabels(context.l10n, item.sourceId),
      onCopyPrompt: actions.copyPositivePrompt,
      onCopyNegativePrompt: actions.copyNegativePrompt,
      onCopyCharacter: actions.copyCharacterPrompt,
      onCopyAll: actions.copyAllPrompts,
      onToggleFavorite: useKnownDetail
          ? () => _toggleKnownFavorite(context, detail)
          : () => toggleFavorite(context, item),
      onOpenSource: () => unawaited(actions.openSource()),
      onSendToGenerate: actions.sendToGeneration,
      onAddToQueue: actions.addToQueue,
      onAddToRelay: item.sourceId == GallerySourceId.quickTagCloud
          ? actions.addToRelay
          : null,
      onDownloadCurrentOriginal: mediaActions.downloadOriginal,
      onTagSearch: (tag) {
        controller.searchController.text = tag;
        _galleryNotifier.search(tag);
      },
      onCloseForNavigation: closeForNavigation,
      onBlacklistChanged: () => _galleryNotifier.refresh(),
      onCopyMetadata: actions.copyMetadata,
      onDownloadAll: mediaActions.downloadAll,
      onSendToReverse: mediaActions.sendToReverse,
      onCopyArtistChain: hasFocusedAiTagMedia ? actions.copyArtistChain : null,
      onCopyFullPrompt: hasFocusedAiTagMedia ? actions.copyFullPrompt : null,
      onCopyRawArtistFragments: hasFocusedAiTagMedia
          ? actions.copyRawArtistFragments
          : null,
      hasArtistChain: hasFocusedAiTagMedia ? actions.hasArtistChain : null,
    );
  }

  Future<bool> _toggleKnownFavorite(
    BuildContext context,
    GalleryDetail detail,
  ) async {
    try {
      final isFavorited = await ref
          .read(onlineGalleryLocalFavoritesProvider.notifier)
          .toggle(detail);
      if (context.mounted) {
        AppToast.info(
          context,
          isFavorited
              ? context.l10n.onlineGallery_favorited
              : context.l10n.onlineGallery_unfavorited,
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        AppToast.error(
          context,
          context.l10n.onlineGallery_actionFailed('$error'),
        );
      }
      return false;
    }
  }

  Future<GalleryDetail?> _loadGalleryDetailWithProgress(
    BuildContext context,
    GalleryItem item,
  ) async {
    final shown = Completer<BuildContext>();
    final cancelled = Completer<void>();
    var dismissRequested = false;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!shown.isCompleted) shown.complete(dialogContext);
        return AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Text(context.l10n.common_loading),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!cancelled.isCompleted) cancelled.complete();
                dismissRequested = true;
                Navigator.of(dialogContext, rootNavigator: true).pop();
              },
              child: Text(context.l10n.common_cancel),
            ),
          ],
        );
      },
    );
    unawaited(
      dialogFuture.whenComplete(() {
        if (!cancelled.isCompleted) cancelled.complete();
      }),
    );

    final dialogContext = await shown.future;
    try {
      final detail = await Future.any<GalleryDetail?>([
        _galleryNotifier.loadDetail(item),
        cancelled.future.then<GalleryDetail?>((_) => null),
      ]);
      if (detail == null) _galleryNotifier.cancelDetail(item);
      return detail;
    } finally {
      if (!dismissRequested && dialogContext.mounted) {
        dismissRequested = true;
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
      await dialogFuture;
    }
  }

  /// 处理收藏切换
  Future<bool> toggleFavorite(BuildContext context, DanbooruPost post) async {
    final wasFavorited = _galleryNotifier.isFavorited(post);
    try {
      final success = await _galleryNotifier.toggleFavorite(post);
      if (context.mounted) {
        if (success) {
          AppToast.info(
            context,
            wasFavorited
                ? context.l10n.onlineGallery_unfavorited
                : context.l10n.onlineGallery_favorited,
          );
        } else {
          AppToast.error(
            context,
            context.l10n.onlineGallery_actionFailed(
              context.l10n.onlineGallery_sourceRequestFailed,
            ),
          );
        }
      }
      return success;
    } catch (error, stack) {
      AppLogger.e(
        'Failed to toggle online gallery favorite',
        error,
        stack,
        'OnlineGallery',
      );
      if (context.mounted) {
        AppToast.error(
          context,
          context.l10n.onlineGallery_actionFailed('$error'),
        );
      }
      return false;
    }
  }
}

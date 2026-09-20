import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/online_gallery/gallery_item.dart';
import '../../../data/models/online_gallery/gallery_prompt_projection.dart';
import '../../../data/models/queue/replication_task.dart';
import '../../../data/services/online_gallery/artist_chain_parser.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/online_gallery_output_filter_provider.dart';
import '../../providers/online_gallery_prompt_tag_settings_provider.dart';
import '../../providers/pending_prompt_provider.dart';
import '../../providers/quick_tag_cloud_relay_provider.dart';
import '../../providers/replication_queue_provider.dart';
import '../../services/gallery_prompt_projection_service.dart';
import '../../widgets/common/app_toast.dart';

/// Prompt and source commands for an opened gallery entry.
class OnlineGalleryDetailActions {
  const OnlineGalleryDetailActions({
    required this.context,
    required this.ref,
    required this.item,
    required this.detail,
    required this.projection,
    required this.closeForNavigation,
  });

  final BuildContext context;
  final WidgetRef ref;
  final GalleryItem item;
  final GalleryDetail detail;
  final GalleryPromptProjection projection;
  final VoidCallback closeForNavigation;

  void copyPositivePrompt() => unawaited(
    _copyText(
      projection.positivePrompt,
      context.l10n.onlineGallery_codexCopyPositive,
    ),
  );

  void copyNegativePrompt() => unawaited(
    _copyText(
      projection.negativePrompt,
      context.l10n.onlineGallery_codexCopyNegative,
    ),
  );

  void copyCharacterPrompt(GalleryCharacterPrompt character) {
    final index = detail.characterPrompts.indexOf(character);
    final projected = index >= 0 && index < projection.characterPrompts.length
        ? projection.characterPrompts[index]
        : character;
    unawaited(
      _copyText(
        _characterCopyText(projected),
        context.l10n.onlineGallery_codexCopyCharacter,
      ),
    );
  }

  void copyAllPrompts() => unawaited(
    _copyText(
      _promptCopyText(projection),
      context.l10n.onlineGallery_codexCopyAll,
    ),
  );

  void copyMetadata(GalleryMedia media) {
    final raw = media.rawMetadata?.trim() ?? '';
    unawaited(
      _copyText(
        raw.isNotEmpty
            ? raw
            : const JsonEncoder.withIndent('  ').convert(media.metadata),
        context.l10n.onlineGallery_copyFullMetadata,
      ),
    );
  }

  void copyArtistChain(GalleryMedia media) => unawaited(
    _copyText(
      ArtistChainParser.parse(media.prompt).formattedText,
      context.l10n.onlineGallery_copyArtistChain,
    ),
  );

  void copyRawArtistFragments(GalleryMedia media) => unawaited(
    _copyText(
      ArtistChainParser.parse(media.prompt).rawText,
      context.l10n.onlineGallery_copyRawArtistFragments,
    ),
  );

  bool hasArtistChain(GalleryMedia media) =>
      ArtistChainParser.parse(media.prompt).isNotEmpty;

  void copyFullPrompt(GalleryMedia media) {
    final currentProjection = const GalleryPromptProjectionService().project(
      item: item,
      detail: detail,
      currentMedia: media,
      promptTagSettings: ref.read(onlineGalleryPromptTagSettingsProvider),
      outputFilter: ref.read(onlineGalleryOutputFilterProvider),
    );
    unawaited(
      _copyText(
        _promptCopyText(
          currentProjection,
          negativeLabel: context.l10n.onlineGallery_negativePromptCopyHeading,
        ),
        context.l10n.onlineGallery_copyFullPrompt,
      ),
    );
  }

  Future<void> openSource() async {
    final rawUrl = detail.sourceUrl?.trim().isNotEmpty == true
        ? detail.sourceUrl
        : item.postUrl;
    final url = rawUrl == null ? null : Uri.tryParse(rawUrl.trim());
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      _showOpenSourceError();
      return;
    }
    try {
      final opened = await launchUrl(url);
      if (!opened) _showOpenSourceError();
    } catch (error, stack) {
      AppLogger.e(
        'Failed to open QuickTagCloud source',
        error,
        stack,
        'OnlineGallery',
      );
      _showActionError(error);
    }
  }

  void sendToGeneration() {
    final router = GoRouter.of(context);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final message = context.l10n.onlineGallery_sentToTextToImage;
    ref.read(characterPromptNotifierProvider.notifier).replaceAll([
      for (var index = 0; index < projection.characterPrompts.length; index++)
        CharacterPrompt(
          id: 'codex-${item.stableKey}-$index',
          name: projection.characterPrompts[index].label,
          prompt: projection.characterPrompts[index].prompt,
          negativePrompt: projection.characterPrompts[index].negativePrompt,
          positionMode: CharacterPositionMode.aiChoice,
        ),
    ]);
    ref
        .read(pendingPromptNotifierProvider.notifier)
        .set(
          prompt: projection.positivePrompt,
          negativePrompt: projection.negativePrompt,
        );
    closeForNavigation();
    router.go('/');
    AppToast.successOnOverlay(overlay, message);
  }

  Future<void> addToQueue() async {
    final prompt = projection.positivePrompt.trim();
    final negativePrompt = projection.negativePrompt.trim();
    final hasCharacterPrompt = projection.characterPrompts.any(
      (character) =>
          character.prompt.trim().isNotEmpty ||
          character.negativePrompt.trim().isNotEmpty,
    );
    if (prompt.isEmpty && negativePrompt.isEmpty && !hasCharacterPrompt) return;
    try {
      final success = await ref
          .read(replicationQueueNotifierProvider.notifier)
          .add(
            ReplicationTask.create(
              prompt: prompt,
              negativePrompt: negativePrompt,
              applyNegativePrompt: negativePrompt.isNotEmpty,
              thumbnailUrl: item.previewUrl,
              source: ReplicationTaskSource.online,
              characterPrompts: [
                for (final character in projection.characterPrompts)
                  ReplicationCharacterPromptSnapshot(
                    prompt: character.prompt,
                    negativePrompt: character.negativePrompt,
                  ),
              ],
            ),
          );
      if (!context.mounted) return;
      if (success) {
        final count = ref.read(
          replicationQueueNotifierProvider.select((state) => state.count),
        );
        AppToast.success(
          context,
          context.l10n.onlineGallery_addedToQueueWithCount(count),
        );
      } else {
        AppToast.warning(context, context.l10n.onlineGallery_queueFullMax);
      }
    } catch (error, stack) {
      AppLogger.e(
        'Failed to add QuickTagCloud entry to queue',
        error,
        stack,
        'OnlineGallery',
      );
      _showActionError(error);
    }
  }

  Future<void> addToRelay() async {
    try {
      await ref.read(quickTagCloudRelayProvider.notifier).addFromDetail(detail);
      if (context.mounted) AppToast.success(context, context.l10n.common_added);
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _copyText(String text, String label) async {
    final value = text.trim();
    if (value.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) AppToast.success(context, '$label ✓');
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.gallery_copyFailed('$error'));
      }
    }
  }

  String _characterCopyText(GalleryCharacterPrompt character) {
    final blocks = <String>[];
    final prompt = character.prompt.trim();
    final negative = character.negativePrompt.trim();
    if (prompt.isNotEmpty) blocks.add(prompt);
    if (negative.isNotEmpty) {
      blocks.add(
        '${context.l10n.onlineGallery_codexNegativePrompt}:\n$negative',
      );
    }
    return blocks.join('\n\n');
  }

  String _promptCopyText(
    GalleryPromptProjection projection, {
    String? negativeLabel,
  }) {
    final blocks = <String>[];
    final prompt = projection.positivePrompt.trim();
    final negative = projection.negativePrompt.trim();
    if (prompt.isNotEmpty) blocks.add(prompt);
    final l10n = context.l10n;
    final resolvedNegativeLabel =
        negativeLabel ?? l10n.onlineGallery_codexNegativePrompt;
    if (negative.isNotEmpty) blocks.add('$resolvedNegativeLabel:\n$negative');
    for (var index = 0; index < projection.characterPrompts.length; index++) {
      final character = projection.characterPrompts[index];
      final content = <String>[
        if (character.prompt.trim().isNotEmpty) character.prompt.trim(),
        if (character.negativePrompt.trim().isNotEmpty)
          '$resolvedNegativeLabel: ${character.negativePrompt.trim()}',
      ].join('\n');
      if (content.isNotEmpty) {
        blocks.add(
          '${character.label.isEmpty ? '${l10n.onlineGallery_codexCharacterPrompts} ${index + 1}' : character.label}:\n$content',
        );
      }
    }
    return blocks.join('\n\n');
  }

  void _showOpenSourceError() {
    if (context.mounted) {
      AppToast.error(context, context.l10n.onlineGallery_codexOpenSourceFailed);
    }
  }

  void _showActionError(Object error) {
    if (context.mounted) {
      AppToast.error(
        context,
        context.l10n.onlineGallery_actionFailed('$error'),
      );
    }
  }
}

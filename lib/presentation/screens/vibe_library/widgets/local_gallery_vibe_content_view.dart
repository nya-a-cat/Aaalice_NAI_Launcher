import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/display_thumbnail_utils.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/gallery/local_gallery_vibe_group.dart';
import '../../../../data/models/vibe/vibe_library_entry.dart';
import '../../../providers/generation/generation_params_notifier.dart';
import '../../../providers/local_gallery_vibe_provider.dart';
import '../../../providers/vibe_library_provider.dart';
import '../../../router/app_routes.dart';
import '../../../widgets/common/app_toast.dart';
import 'local_gallery_vibe_card.dart';
import 'local_gallery_vibe_detail_dialog.dart';
import 'vibe_library_empty_view.dart';

class LocalGalleryVibeContentView extends ConsumerWidget {
  const LocalGalleryVibeContentView({
    super.key,
    required this.columns,
    required this.itemWidth,
  });

  final int columns;
  final double itemWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localGalleryVibeProvider);
    if (state.isLoading && state.groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.groups.isEmpty) {
      return VibeLibraryEmptyView(
        title: context.l10n.vibeLibrary_localGalleryEmpty,
        subtitle: context.l10n.vibeLibrary_localGalleryEmptyHint,
        iconName: state.searchQuery.isEmpty
            ? 'auto_awesome_outlined'
            : 'search_off',
      );
    }

    final savedEntries = ref.watch(vibeLibraryNotifierProvider).entries;
    return GridView.builder(
      key: const PageStorageKey<String>('local_gallery_vibe_grid'),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: state.groups.length,
      itemBuilder: (context, index) {
        final group = state.groups[index];
        final isSaved = savedEntries.any(
          (entry) => entry.tags.contains('vibe:${group.fingerprint}'),
        );
        return LocalGalleryVibeCard(
          group: group,
          width: itemWidth,
          isSaved: isSaved,
          onTap: () => _showDetail(context, ref, group, isSaved: isSaved),
        );
      },
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    WidgetRef ref,
    LocalGalleryVibeGroup group, {
    required bool isSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (dialogContext) => LocalGalleryVibeDetailDialog(
        group: group,
        initiallySaved: isSaved,
        loadExamples: ({required limit, required offset}) => ref
            .read(localGalleryVibeProvider.notifier)
            .loadExamples(group.fingerprint, limit: limit, offset: offset),
        onSend: (example) =>
            _sendToGeneration(dialogContext, ref, group, example),
        onSave: (example) =>
            _saveToLibrary(dialogContext, ref, group, example),
      ),
    );
  }

  Future<void> _sendToGeneration(
    BuildContext context,
    WidgetRef ref,
    LocalGalleryVibeGroup group,
    LocalGalleryVibeExample example,
  ) async {
    final params = ref.read(generationParamsNotifierProvider);
    if (params.vibeReferencesV4.length >= 16) {
      AppToast.warning(context, context.l10n.vibeLibrary_maxVibesReached);
      return;
    }
    ref
        .read(generationParamsNotifierProvider.notifier)
        .addVibeReferences(
          [group.toVibeReference(example: example)],
          recordUsage: false,
        );
    AppToast.success(
      context,
      context.l10n.toast_sentVibeToGeneration(group.displayName),
    );
    if (context.mounted) context.go(AppRoutes.home);
  }

  Future<bool> _saveToLibrary(
    BuildContext context,
    WidgetRef ref,
    LocalGalleryVibeGroup group,
    LocalGalleryVibeExample example,
  ) async {
    try {
      final sourceBytes = await File(example.filePath).readAsBytes();
      final thumbnail = await DisplayThumbnailUtils.normalize(sourceBytes);
      final reference = group.toVibeReference(example: example).copyWith(
        thumbnail: thumbnail,
      );
      final entry = VibeLibraryEntry.fromVibeReference(
        name: p.basenameWithoutExtension(example.filePath),
        vibeData: reference,
        thumbnail: thumbnail,
        tags: ['local-gallery', 'vibe:${group.fingerprint}'],
      );
      final saved = await ref
          .read(vibeLibraryNotifierProvider.notifier)
          .saveEntry(entry);
      if (saved == null) return false;
      if (context.mounted) {
        AppToast.success(
          context,
          context.l10n.vibeLibrary_savedFromLocalGallery,
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.localGallery_loadFailed(error));
      }
      return false;
    }
  }
}

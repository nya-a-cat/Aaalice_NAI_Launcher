import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../../../data/datasources/remote/online_gallery/quick_tag_cloud_gallery_source_adapter.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_catalog.dart';
import '../../../data/models/online_gallery/quick_tag_cloud_codex.dart';
import '../../../data/services/online_gallery/quick_tag_cloud_access.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers/online_gallery_provider.dart';
import '../../providers/quick_tag_cloud_gallery_provider.dart';
import 'quick_tag_cloud_category_picker.dart';
import 'quick_tag_cloud_codex_picker.dart';
import 'quick_tag_cloud_contributors_dialog.dart';
import 'quick_tag_cloud_filter_picker.dart';
import 'quick_tag_cloud_search_dialog.dart';
import 'quick_tag_cloud_browse_scope_control.dart';
import 'quick_tag_cloud_relay/quick_tag_cloud_relay_dialog.dart';
import 'quick_tag_cloud_favorites_backup/quick_tag_cloud_favorites_backup_dialog.dart';
import 'quick_tag_cloud_community/quick_tag_cloud_community_dialog.dart';

class QuickTagCloudToolbar extends ConsumerStatefulWidget {
  const QuickTagCloudToolbar({
    super.key,
    required this.onFiltersChanged,
    required this.selectedRatings,
    this.favoritesMode = false,
    this.wrapControls = false,
  });

  final Future<void> Function() onFiltersChanged;
  final Set<String> selectedRatings;
  final bool favoritesMode;
  final bool wrapControls;

  @override
  ConsumerState<QuickTagCloudToolbar> createState() =>
      _QuickTagCloudToolbarState();
}

class _QuickTagCloudToolbarState extends ConsumerState<QuickTagCloudToolbar> {
  bool _normalizingCodex = false;
  bool _normalizingFilters = false;
  bool _openingCategoryPicker = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final notifier = ref.read(quickTagCloudFilterProvider.notifier);
      var changed = await notifier.initializeContentAccess();
      if (!mounted) return;
      final query = ref.read(quickTagCloudFilterProvider);
      final allowNsfw = QuickTagCloudAccess.allowsNsfw(widget.selectedRatings);
      final allowR18g = QuickTagCloudAccess.allowsR18g(widget.selectedRatings);
      if (query.allowNsfw != allowNsfw || query.allowR18g != allowR18g) {
        await notifier.setContentAccess(
          allowNsfw: allowNsfw,
          allowR18g: allowR18g,
        );
        changed = true;
      }
      if (mounted && changed) await widget.onFiltersChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(quickTagCloudFilterProvider);
    final catalogValue = ref.watch(quickTagCloudCatalogProvider);
    final catalog = catalogValue.valueOrNull;
    final selectedMeta = catalog?.findCodex(query.codexId);
    if (catalog != null &&
        query.codexId != 'all' &&
        selectedMeta == null &&
        !_normalizingCodex) {
      final fallback =
          catalog.findCodex('suozhang') ??
          (catalog.codexes.isEmpty ? null : catalog.codexes.first);
      if (fallback != null) {
        _normalizingCodex = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            ref
                .read(quickTagCloudFilterProvider.notifier)
                .selectCodex(fallback.id);
            await widget.onFiltersChanged();
          } finally {
            if (mounted) _normalizingCodex = false;
          }
        });
      }
    }
    final allowNsfw = QuickTagCloudAccess.allowsNsfw(widget.selectedRatings);
    final selectedCodexLocked = selectedMeta?.nsfw == true && !allowNsfw;
    final codexValue = query.codexId == 'all' || selectedCodexLocked
        ? null
        : ref.watch(quickTagCloudCodexProvider(query.codexId));
    final codex = codexValue?.valueOrNull;
    final invalidCategory =
        codex != null &&
        query.categoryPath.isNotEmpty &&
        !quickTagCloudContainsCategoryPath(codex.tree, query.categoryPath);
    final availableUpdateFilters =
        (codex?.asMediaMeta() ?? selectedMeta)?.updateFilters
            .map((filter) => filter.id)
            .toSet() ??
        const <String>{};
    final invalidUpdateFilter =
        codex != null &&
        query.updateFilterId.isNotEmpty &&
        !availableUpdateFilters.contains(query.updateFilterId);
    if ((invalidCategory || invalidUpdateFilter) && !_normalizingFilters) {
      _normalizingFilters = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final notifier = ref.read(quickTagCloudFilterProvider.notifier);
          if (invalidCategory) notifier.selectCategory(const []);
          if (invalidUpdateFilter) notifier.selectUpdateFilter('');
          await widget.onFiltersChanged();
        } finally {
          if (mounted) _normalizingFilters = false;
        }
      });
    }

    final filterControls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!widget.favoritesMode)
          QuickTagCloudBrowseScopeControl(
            scope: query.scope,
            wrap: widget.wrapControls,
            onChanged: (scope) async {
              ref.read(quickTagCloudFilterProvider.notifier).selectScope(scope);
              await widget.onFiltersChanged();
            },
          ),
        _ToolbarButton(
          icon: Icons.menu_book_outlined,
          label: selectedMeta?.title ?? l10n.onlineGallery_codexAll,
          loading: catalogValue.isLoading,
          onPressed: catalog == null
              ? null
              : () => _showCodexPicker(
                  context,
                  catalog,
                  query,
                  codexValue?.valueOrNull,
                  allowNsfw: allowNsfw,
                ),
        ),
        _ToolbarButton(
          icon: Icons.account_tree_outlined,
          label: query.categoryPath.isEmpty
              ? l10n.onlineGallery_codexAllCategories
              : query.categoryPath.join(' / '),
          loading: (codexValue?.isLoading ?? false) || _openingCategoryPicker,
          onPressed: query.codexId == 'all' || selectedCodexLocked
              ? null
              : () => _openCategoryPicker(query.codexId, query.categoryPath),
        ),
        _ToolbarButton(
          icon: Icons.tune,
          label: l10n.common_filter,
          onPressed: catalog == null
              ? null
              : () => _showFilterDialog(context, selectedMeta, query),
        ),
        _ToolbarButton(
          key: const ValueKey('quick-tag-cloud-advanced-search'),
          icon: Icons.manage_search,
          label: l10n.onlineGallery_codexAdvancedSearch,
          onPressed: _openAdvancedSearch,
        ),
        _ToolbarButton(
          key: const ValueKey('quick-tag-cloud-relay'),
          icon: Icons.playlist_add_check_outlined,
          label: l10n.onlineGallery_codexRelay,
          onPressed: () => showQuickTagCloudRelay(context),
        ),
        _ToolbarButton(
          key: const ValueKey('quick-tag-cloud-favorites-backup'),
          icon: Icons.import_export,
          label: l10n.onlineGallery_codexFavoritesBackup,
          onPressed: () => showQuickTagCloudFavoritesBackup(context),
        ),
        _ToolbarButton(
          key: const ValueKey('quick-tag-cloud-community'),
          icon: Icons.groups_outlined,
          label: l10n.onlineGallery_codexCommunity,
          onPressed: () => showQuickTagCloudCommunity(context),
        ),
        if (catalog?.isOffline == true)
          Tooltip(
            message: catalog!.refreshError?.toString() ?? '',
            child: Chip(
              avatar: const Icon(Icons.cloud_off_outlined, size: 16),
              label: Text(l10n.onlineGallery_codexOffline),
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (codexValue?.valueOrNull?.loadSource ==
                QuickTagCloudCodexLoadSource.fallback ||
            codexValue?.valueOrNull?.loadSource ==
                QuickTagCloudCodexLoadSource.previousRelease)
          Tooltip(
            message:
                codexValue?.valueOrNull?.loadSource ==
                    QuickTagCloudCodexLoadSource.previousRelease
                ? l10n.onlineGallery_codexPreviousRelease
                : l10n.onlineGallery_codexExternalFallback,
            child: Semantics(
              label:
                  codexValue?.valueOrNull?.loadSource ==
                      QuickTagCloudCodexLoadSource.previousRelease
                  ? l10n.onlineGallery_codexPreviousRelease
                  : l10n.onlineGallery_codexExternalFallback,
              child: Icon(
                Icons.cached_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
        if (catalogValue.hasError)
          Tooltip(
            message: catalogValue.error.toString(),
            child: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );

    final contributorsButton = selectedMeta == null
        ? null
        : IconButton(
            key: const ValueKey('quick-tag-cloud-contributors'),
            tooltip: l10n.onlineGallery_codexContributors,
            visualDensity: VisualDensity.compact,
            onPressed: () => showQuickTagCloudContributors(
              context,
              codexValue?.valueOrNull?.asMediaMeta() ?? selectedMeta,
            ),
            icon: const Icon(Icons.group_outlined, size: 20),
          );
    if (widget.wrapControls) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            filterControls,
            if (contributorsButton != null) contributorsButton,
          ],
        ),
      );
    }
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        filterControls,
        if (contributorsButton != null) ...[
          const SizedBox(width: 8),
          contributorsButton,
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return content;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: content,
        );
      },
    );
  }

  Future<void> _showCodexPicker(
    BuildContext context,
    QuickTagCloudCatalog catalog,
    QuickTagCloudGalleryQuery query,
    QuickTagCloudCodex? selectedCodex, {
    required bool allowNsfw,
  }) async {
    final selected = await showQuickTagCloudCodexPicker(
      context,
      catalog,
      query,
      selectedCodex,
      allowNsfw: allowNsfw,
    );
    if (!mounted || selected == null || selected == query.codexId) return;
    ref.read(quickTagCloudFilterProvider.notifier).selectCodex(selected);
    await widget.onFiltersChanged();
  }

  Future<void> _openCategoryPicker(
    String codexId,
    List<String> selectedPath,
  ) async {
    if (_openingCategoryPicker) return;
    setState(() => _openingCategoryPicker = true);
    try {
      final codex = await ref.read(quickTagCloudCodexProvider(codexId).future);
      if (!mounted) return;
      setState(() => _openingCategoryPicker = false);
      final selected = await showQuickTagCloudCategoryPicker(
        context,
        codex,
        selectedPath,
      );
      if (!mounted || selected == null) return;
      ref.read(quickTagCloudFilterProvider.notifier).selectCategory(selected);
      await widget.onFiltersChanged();
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to load QuickTagCloud categories for $codexId',
        error,
        stackTrace,
        'QuickTagCloudToolbar',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.onlineGallery_loadFailed,
            ),
          ),
        );
      }
    } finally {
      if (mounted && _openingCategoryPicker) {
        setState(() => _openingCategoryPicker = false);
      }
    }
  }

  Future<void> _showFilterDialog(
    BuildContext context,
    QuickTagCloudCodexMeta? meta,
    QuickTagCloudGalleryQuery query,
  ) async {
    final selected = await showQuickTagCloudFilterPicker(context, meta, query);
    if (!mounted || selected == null) return;
    final allowNsfw = QuickTagCloudAccess.allowsNsfw(widget.selectedRatings);
    final lockedSelection = !allowNsfw && meta?.nsfw == true;
    await ref
        .read(quickTagCloudFilterProvider.notifier)
        .applyFilters(
          codexId: lockedSelection ? 'all' : query.codexId,
          updateFilterId: lockedSelection ? '' : selected.updateFilterId,
          scope: query.scope,
          mediaFilter: selected.mediaFilter,
          allowNsfw: allowNsfw,
          allowR18g: QuickTagCloudAccess.allowsR18g(widget.selectedRatings),
        );
    if (mounted) await widget.onFiltersChanged();
  }

  Future<void> _openAdvancedSearch() async {
    final state = ref.read(onlineGalleryNotifierProvider);
    final query = await showQuickTagCloudSearch(
      context,
      initialQuery: widget.favoritesMode
          ? state.favoriteSearchQuery
          : state.searchQuery,
    );
    if (!mounted || query == null) return;
    final notifier = ref.read(onlineGalleryNotifierProvider.notifier);
    if (widget.favoritesMode) {
      await notifier.searchFavorites(query);
    } else {
      await notifier.search(query);
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 17),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        backgroundColor: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        minimumSize: const Size(44, 44),
      ),
    );
  }
}

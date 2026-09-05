import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/local_gallery_vibe_provider.dart';
import '../../../providers/vibe_library_selection_provider.dart';
import '../../../widgets/common/input_surface_container.dart';
import '../../../widgets/gallery/gallery_state_views.dart';
import 'local_gallery_vibe_content_view.dart';
import 'vibe_families/vibe_family_workspace.dart';

enum VibeLibrarySourceView { saved, localGallery, families }

class VibeLibrarySourceWorkspace extends ConsumerStatefulWidget {
  const VibeLibrarySourceWorkspace({
    super.key,
    required this.savedCount,
    required this.savedWorkspace,
  });

  final int savedCount;
  final Widget savedWorkspace;

  @override
  ConsumerState<VibeLibrarySourceWorkspace> createState() =>
      _VibeLibrarySourceWorkspaceState();
}

class _VibeLibrarySourceWorkspaceState
    extends ConsumerState<VibeLibrarySourceWorkspace> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  VibeLibrarySourceView _view = VibeLibrarySourceView.saved;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localState = ref.watch(localGalleryVibeProvider);
    return Column(
      children: [
        _SourceSwitcher(
          selected: _view,
          savedCount: widget.savedCount,
          localCount: localState.totalGroups,
          onChanged: _setView,
        ),
        Expanded(
          child: switch (_view) {
            VibeLibrarySourceView.saved => widget.savedWorkspace,
            VibeLibrarySourceView.localGallery => _buildLocalWorkspace(localState),
            VibeLibrarySourceView.families => const VibeFamilyWorkspace(),
          },
        ),
      ],
    );
  }

  void _setView(VibeLibrarySourceView next) {
    if (next == _view) return;
    ref.read(vibeLibrarySelectionNotifierProvider.notifier).exit();
    setState(() => _view = next);
    if (next == VibeLibrarySourceView.localGallery) {
      unawaited(ref.read(localGalleryVibeProvider.notifier).initialize());
    }
  }

  Widget _buildLocalWorkspace(LocalGalleryVibeState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 32.0;
        const spacing = 16.0;
        final availableWidth = (constraints.maxWidth - padding).clamp(
          0.0,
          double.infinity,
        );
        final columns = ((availableWidth + spacing) / (180 + spacing))
            .floor()
            .clamp(1, 8);
        final itemWidth =
            (availableWidth - spacing * (columns - 1)) / columns;
        final content = Column(
          children: [
            _LocalToolbar(
              state: state,
              searchController: _searchController,
              compact: constraints.maxWidth < 760,
              onSearchChanged: _searchChanged,
              onSearchSubmitted: _searchSubmitted,
              onSearchCleared: _clearSearch,
              onRefresh: () => ref
                  .read(localGalleryVibeProvider.notifier)
                  .reload(runBackfill: true),
            ),
            Expanded(child: _buildLocalBody(state, columns, itemWidth)),
            if (!state.isLoading && state.totalPages > 0)
              _LocalPaginationBar(
                state: state,
                compact: constraints.maxWidth < 620,
                onPage: (page) => ref
                    .read(localGalleryVibeProvider.notifier)
                    .loadPage(page),
                onPageSize: (size) => ref
                    .read(localGalleryVibeProvider.notifier)
                    .setPageSize(size),
              ),
          ],
        );
        return _withLocalPageShortcuts(state, child: content);
      },
    );
  }

  Widget _withLocalPageShortcuts(
    LocalGalleryVibeState state, {
    required Widget child,
  }) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (state.currentPage > 0) {
            unawaited(
              ref
                  .read(localGalleryVibeProvider.notifier)
                  .loadPage(state.currentPage - 1),
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (state.currentPage < state.totalPages - 1) {
            unawaited(
              ref
                  .read(localGalleryVibeProvider.notifier)
                  .loadPage(state.currentPage + 1),
            );
          }
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  Widget _buildLocalBody(
    LocalGalleryVibeState state,
    int columns,
    double itemWidth,
  ) {
    if (state.error != null) {
      return GalleryErrorView(
        error: state.error,
        onRetry: () => ref
            .read(localGalleryVibeProvider.notifier)
            .reload(runBackfill: true),
      );
    }
    if (!state.isInitialized && state.groups.isEmpty) {
      return const GalleryLoadingView();
    }
    return LocalGalleryVibeContentView(
      columns: columns,
      itemWidth: itemWidth,
    );
  }

  void _searchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _view != VibeLibrarySourceView.localGallery) return;
      unawaited(
        ref.read(localGalleryVibeProvider.notifier).setSearchQuery(value),
      );
    });
  }

  void _searchSubmitted(String value) {
    _searchDebounce?.cancel();
    unawaited(
      ref.read(localGalleryVibeProvider.notifier).setSearchQuery(value),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {});
    unawaited(
      ref.read(localGalleryVibeProvider.notifier).setSearchQuery(''),
    );
  }
}

class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({
    required this.selected,
    required this.savedCount,
    required this.localCount,
    required this.onChanged,
  });

  final VibeLibrarySourceView selected;
  final int savedCount;
  final int localCount;
  final ValueChanged<VibeLibrarySourceView> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<VibeLibrarySourceView>(
            key: const ValueKey('vibe-library-view-switcher'),
            segments: [
              ButtonSegment(
                value: VibeLibrarySourceView.saved,
                icon: const Icon(Icons.bookmarks_outlined),
                label: Text(
                  '${context.l10n.vibeLibrary_savedView} $savedCount',
                ),
              ),
              ButtonSegment(
                value: VibeLibrarySourceView.localGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  '${context.l10n.vibeLibrary_localGalleryView} $localCount',
                ),
              ),
              ButtonSegment(
                value: VibeLibrarySourceView.families,
                icon: const Icon(Icons.hub_outlined),
                label: Text(context.l10n.vibeFamily_title),
              ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ),
    );
  }
}

class _LocalToolbar extends StatelessWidget {
  const _LocalToolbar({
    required this.state,
    required this.searchController,
    required this.compact,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchCleared,
    required this.onRefresh,
  });

  final LocalGalleryVibeState state;
  final TextEditingController searchController;
  final bool compact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onSearchCleared;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      context.l10n.vibeLibrary_localGalleryDiscovery,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final search = InputSurfaceContainer(
      height: compact ? 48 : 36,
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          hintText: context.l10n.vibeLibrary_localGallerySearchHint,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onSearchCleared,
                  icon: const Icon(Icons.close, size: 18),
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
        ),
        onChanged: onSearchChanged,
        onSubmitted: onSearchSubmitted,
      ),
    );
    final refresh = IconButton(
      tooltip: context.l10n.vibeLibrary_rescanLocalGalleryVibes,
      onPressed: state.isLoading || state.isBackfilling ? null : onRefresh,
      icon: state.isLoading || state.isBackfilling
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: compact
                ? Column(
                    children: [
                      Row(children: [Expanded(child: title), refresh]),
                      const SizedBox(height: 8),
                      search,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 2, child: title),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: search),
                      const SizedBox(width: 8),
                      refresh,
                    ],
                  ),
          ),
          if (state.isBackfilling) ...[
            LinearProgressIndicator(
              value: state.backfillProgress?.fraction,
              minHeight: 2,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.vibeLibrary_indexingLocalGallery(
                    state.backfillProgress?.processed ?? 0,
                    state.backfillProgress?.total ?? 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalPaginationBar extends StatelessWidget {
  const _LocalPaginationBar({
    required this.state,
    required this.compact,
    required this.onPage,
    required this.onPageSize,
  });

  final LocalGalleryVibeState state;
  final bool compact;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: state.currentPage > 0
            ? () => onPage(state.currentPage - 1)
            : null,
      ),
      Text(
        context.l10n.vibeLibrary_pageIndicator(
          state.currentPage + 1,
          state.totalPages,
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: state.currentPage < state.totalPages - 1
            ? () => onPage(state.currentPage + 1)
            : null,
      ),
      if (!compact) Text(context.l10n.vibeLibrary_itemsPerPage),
      DropdownButton<int>(
        value: state.pageSize,
        underline: const SizedBox(),
        items: const [20, 30, 50, 100]
            .map((size) => DropdownMenuItem(value: size, child: Text('$size')))
            .toList(),
        onChanged: (value) {
          if (value != null) onPageSize(value);
        },
      ),
      if (!compact)
        Text(
          context.l10n.vibeLibrary_totalCount(state.totalGroups.toString()),
        ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: controls,
        ),
      ),
    );
  }
}

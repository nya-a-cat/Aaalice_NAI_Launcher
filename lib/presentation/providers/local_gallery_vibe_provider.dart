import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/datasources/gallery_data_source.dart';
import '../../core/utils/app_logger.dart';
import '../../data/models/gallery/local_gallery_vibe_group.dart';

class LocalGalleryVibeState {
  const LocalGalleryVibeState({
    this.groups = const [],
    this.searchQuery = '',
    this.currentPage = 0,
    this.pageSize = 30,
    this.totalGroups = 0,
    this.isInitialized = false,
    this.isLoading = false,
    this.isBackfilling = false,
    this.backfillProgress,
    this.error,
  });

  final List<LocalGalleryVibeGroup> groups;
  final String searchQuery;
  final int currentPage;
  final int pageSize;
  final int totalGroups;
  final bool isInitialized;
  final bool isLoading;
  final bool isBackfilling;
  final GalleryVibeBackfillProgress? backfillProgress;
  final Object? error;

  int get totalPages => totalGroups == 0 ? 0 : (totalGroups / pageSize).ceil();

  LocalGalleryVibeState copyWith({
    List<LocalGalleryVibeGroup>? groups,
    String? searchQuery,
    int? currentPage,
    int? pageSize,
    int? totalGroups,
    bool? isInitialized,
    bool? isLoading,
    bool? isBackfilling,
    GalleryVibeBackfillProgress? backfillProgress,
    bool clearBackfillProgress = false,
    Object? error,
    bool clearError = false,
  }) {
    return LocalGalleryVibeState(
      groups: groups ?? this.groups,
      searchQuery: searchQuery ?? this.searchQuery,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalGroups: totalGroups ?? this.totalGroups,
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      isBackfilling: isBackfilling ?? this.isBackfilling,
      backfillProgress: clearBackfillProgress
          ? null
          : backfillProgress ?? this.backfillProgress,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final localGalleryVibeProvider = StateNotifierProvider<
  LocalGalleryVibeNotifier,
  LocalGalleryVibeState
>((ref) => LocalGalleryVibeNotifier(GalleryDataSource()));

class LocalGalleryVibeNotifier extends StateNotifier<LocalGalleryVibeState> {
  LocalGalleryVibeNotifier(this._dataSource)
    : super(const LocalGalleryVibeState());

  final GalleryDataSource _dataSource;
  Future<void>? _activeLoad;
  int _pageRequestSerial = 0;

  Future<void> initialize() async {
    if (state.isInitialized) return;
    await _load(runBackfill: true);
  }

  Future<void> reload({bool runBackfill = false}) =>
      _load(runBackfill: runBackfill);

  Future<void> setSearchQuery(String query) async {
    final normalized = query.trim();
    if (normalized == state.searchQuery) return;
    state = state.copyWith(searchQuery: normalized, currentPage: 0);
    if (!state.isInitialized) {
      await _load(runBackfill: true);
      return;
    }
    await _loadPage(0);
  }

  Future<void> loadPage(int page) async {
    final totalPages = state.totalPages;
    if (page < 0 || (totalPages > 0 && page >= totalPages)) return;
    await _loadPage(page);
  }

  Future<void> setPageSize(int pageSize) async {
    final normalized = pageSize.clamp(10, 100).toInt();
    if (normalized == state.pageSize) return;
    state = state.copyWith(pageSize: normalized, currentPage: 0);
    if (!state.isInitialized) {
      await _load(runBackfill: true);
      return;
    }
    await _loadPage(0);
  }

  Future<List<LocalGalleryVibeExample>> loadExamples(
    String fingerprint, {
    int limit = 100,
    int offset = 0,
  }) {
    return _dataSource.queryLocalGalleryVibeExamples(
      fingerprint,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> _load({required bool runBackfill}) async {
    final active = _activeLoad;
    if (active != null) return active;

    final operation = _performLoad(runBackfill: runBackfill);
    _activeLoad = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    }
  }

  Future<void> _performLoad({required bool runBackfill}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _dataSource.initialize();
      if (runBackfill) {
        if (!mounted) return;
        state = state.copyWith(isBackfilling: true);
        await _dataSource.backfillLocalGalleryVibes(
          onProgress: (progress) {
            if (!mounted) return;
            state = state.copyWith(backfillProgress: progress);
          },
        );
      }
      if (!mounted) return;
      state = state.copyWith(isBackfilling: false);
      await _loadPage(0, markInitialized: true);
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to load local gallery Vibes',
        error,
        stackTrace,
        'LocalGalleryVibe',
      );
      if (!mounted) return;
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        isBackfilling: false,
        error: error,
      );
    }
  }

  Future<void> _loadPage(int page, {bool markInitialized = false}) async {
    final requestSerial = ++_pageRequestSerial;
    final searchQuery = state.searchQuery;
    final pageSize = state.pageSize;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final total = await _dataSource.countLocalGalleryVibeGroups(
        searchQuery: searchQuery,
      );
      final totalPages = total == 0 ? 0 : (total / pageSize).ceil();
      final safePage = totalPages == 0 ? 0 : min(page, totalPages - 1);
      final groups = await _dataSource.queryLocalGalleryVibeGroups(
        searchQuery: searchQuery,
        limit: pageSize,
        offset: safePage * pageSize,
      );
      if (!mounted || requestSerial != _pageRequestSerial) return;
      state = state.copyWith(
        groups: groups,
        totalGroups: total,
        currentPage: safePage,
        isInitialized: markInitialized || state.isInitialized,
        isLoading: false,
      );
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to query local gallery Vibes',
        error,
        stackTrace,
        'LocalGalleryVibe',
      );
      if (!mounted || requestSerial != _pageRequestSerial) return;
      state = state.copyWith(
        isInitialized: markInitialized || state.isInitialized,
        isLoading: false,
        error: error,
      );
    }
  }
}

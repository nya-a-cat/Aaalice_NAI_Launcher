import 'package:dio/dio.dart';

import '../../../services/online_gallery/quick_tag_cloud_access.dart';
import '../../../services/online_gallery/quick_tag_cloud_user_service.dart';
import 'quick_tag_cloud_gallery_query.dart';
import 'quick_tag_cloud_gallery_repository.dart';
import 'quick_tag_cloud_search_matcher.dart';
import 'quick_tag_cloud_search_parser.dart';

class QuickTagCloudQueryEngine {
  QuickTagCloudQueryEngine({
    required QuickTagCloudGalleryRepository repository,
    required QuickTagCloudUserService userService,
    Future<Set<String>> Function()? favoriteKeysLoader,
  }) : _repository = repository,
       _userService = userService,
       _favoriteKeysLoader = favoriteKeysLoader;

  final QuickTagCloudGalleryRepository _repository;
  final QuickTagCloudUserService _userService;
  final Future<Set<String>> Function()? _favoriteKeysLoader;
  final Map<String, List<QuickTagCloudGalleryRecord>> _matchingRecordSets = {};
  final Map<String, QuickTagCloudSearchDocument> _searchDocuments = {};
  int _observedRepositoryRevision = -1;

  void clearCaches() {
    _matchingRecordSets.clear();
    _searchDocuments.clear();
    _observedRepositoryRevision = _repository.cacheRevision;
  }

  Future<List<QuickTagCloudGalleryRecord>> matchingRecords(
    QuickTagCloudGalleryQuery query, {
    required String searchText,
    required Set<String> selectedRatings,
    CancelToken? cancelToken,
    bool sortByRelevance = true,
  }) async {
    _synchronizeRevision();
    QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
    final searchPlan = QuickTagCloudSearchParser.parse(searchText);
    if (searchPlan.hasErrors) {
      throw QuickTagCloudSearchException(searchPlan.issues);
    }
    final favoriteKeys = await _loadFavoriteKeys(searchPlan);
    QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
    final records = await _candidateRecords(query, cancelToken);
    _synchronizeRevision();
    final cacheRevision = _repository.cacheRevision;
    final normalizedSearch = normalizeQuickTagCloudSearchInput(searchText)
        .trim()
        .toLowerCase();
    final ratingsKey = (selectedRatings.toList()..sort()).join();
    final usesSaved =
        query.favoritesOnly ||
        query.scope == QuickTagCloudBrowseScope.recent;
    final matchingCacheKey = !usesSaved && !searchPlan.usesFavorites
        ? '${_repository.currentCatalog?.release ?? ''}|${query.stableKey}|$ratingsKey|$normalizedSearch|sort:$sortByRelevance'
        : null;
    final cachedMatches = matchingCacheKey == null
        ? null
        : _matchingRecordSets[matchingCacheKey];
    if (cachedMatches != null) {
      QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
      return cachedMatches;
    }
    final filtered = await _filterRecords(
      records,
      query: query,
      searchPlan: searchPlan,
      selectedRatings: selectedRatings,
      favoriteKeys: favoriteKeys,
      cancelToken: cancelToken,
    );
    QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
    if (sortByRelevance && searchPlan.terms.isNotEmpty) {
      _sortByRelevance(filtered, searchPlan, cache: records.length <= 5000);
    }
    final result = List<QuickTagCloudGalleryRecord>.unmodifiable(filtered);
    if (matchingCacheKey != null && cacheRevision == _repository.cacheRevision) {
      _matchingRecordSets.remove(matchingCacheKey);
      _matchingRecordSets[matchingCacheKey] = result;
      while (_matchingRecordSets.length > 4) {
        _matchingRecordSets.remove(_matchingRecordSets.keys.first);
      }
    }
    return result;
  }

  Future<List<QuickTagCloudGalleryRecord>> _candidateRecords(
    QuickTagCloudGalleryQuery query,
    CancelToken? cancelToken,
  ) async {
    await _userService.ensureInitialized();
    QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
    final saved = query.favoritesOnly
        ? _userService.favorites
        : query.scope == QuickTagCloudBrowseScope.recent
        ? _userService.recent
        : null;
    if (saved == null) {
      return _repository.loadCatalogRecords(
        query,
        cancelToken: cancelToken,
      );
    }
    final records = <QuickTagCloudGalleryRecord>[];
    for (var index = 0; index < saved.length; index++) {
      if (index > 0 && index % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
        QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
      }
      final item = saved[index];
      records.add(
        QuickTagCloudGalleryRecord(item.meta, item.codex, item.entry, item.media),
      );
    }
    return records;
  }

  Future<List<QuickTagCloudGalleryRecord>> _filterRecords(
    List<QuickTagCloudGalleryRecord> records, {
    required QuickTagCloudGalleryQuery query,
    required QuickTagCloudSearchPlan searchPlan,
    required Set<String> selectedRatings,
    required Set<String> favoriteKeys,
    CancelToken? cancelToken,
  }) async {
    final filtered = <QuickTagCloudGalleryRecord>[];
    final cacheSearchDocuments = records.length <= 5000;
    for (var index = 0; index < records.length; index++) {
      if (index % 256 == 0) {
        QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
        if (index > 0) await Future<void>.delayed(Duration.zero);
        QuickTagCloudGalleryRepository.throwIfCancelled(cancelToken);
      }
      final record = records[index];
      if (!_isAccessible(record, query, selectedRatings)) continue;
      if (!_matchesCodex(record, query.codexId)) continue;
      if (!_matchesCategory(record.entry.path, query.categoryPath)) continue;
      if (query.scope == QuickTagCloudBrowseScope.latest &&
          !_matchesLatest(record)) {
        continue;
      }
      if (query.updateFilterId.isNotEmpty &&
          !_matchesUpdateFilter(record, query.updateFilterId)) {
        continue;
      }
      if (query.mediaFilter == QuickTagCloudMediaFilter.withImages &&
          !record.entry.hasImage) {
        continue;
      }
      if (query.mediaFilter == QuickTagCloudMediaFilter.withoutImages &&
          record.entry.hasImage) {
        continue;
      }
      if (!_searchDocument(
        record,
        cache: cacheSearchDocuments,
      ).matches(searchPlan, favoriteKeys: favoriteKeys)) {
        continue;
      }
      filtered.add(record);
    }
    return filtered;
  }

  void _synchronizeRevision() {
    if (_observedRepositoryRevision == _repository.cacheRevision) return;
    _matchingRecordSets.clear();
    _searchDocuments.clear();
    _observedRepositoryRevision = _repository.cacheRevision;
  }

  bool _isAccessible(
    QuickTagCloudGalleryRecord record,
    QuickTagCloudGalleryQuery query,
    Set<String> selectedRatings,
  ) {
    if (QuickTagCloudAccess.isCodexLocked(
      record.codex,
      allowNsfw: query.allowNsfw,
    )) {
      return false;
    }
    if (QuickTagCloudAccess.isEntryAccessBlocked(
      record.entry,
      allowNsfw: query.allowNsfw,
      allowR18g: query.allowR18g,
    )) {
      return false;
    }
    return QuickTagCloudAccess.matchesGalleryRatings(
      record.entry,
      codex: record.codex,
      selectedRatings: selectedRatings,
    );
  }

  bool _matchesCodex(QuickTagCloudGalleryRecord record, String selectedId) {
    if (selectedId == 'all' || record.codex.id == selectedId) return true;
    if (record.codex.aliases.contains(selectedId)) return true;
    final selected = _repository.currentCatalog?.findCodex(selectedId);
    if (selected == null) return false;
    final savedIdentities = {record.codex.id, ...record.codex.aliases};
    return selected.aliases.any(savedIdentities.contains);
  }

  bool _matchesCategory(List<String> path, List<String> selected) {
    if (selected.isEmpty) return true;
    if (path.length < selected.length) return false;
    for (var index = 0; index < selected.length; index++) {
      if (path[index] != selected[index]) return false;
    }
    return true;
  }

  bool _matchesLatest(QuickTagCloudGalleryRecord record) {
    if (record.entry.isNew) return true;
    final latestIds = record.meta.updateFilters
        .where((filter) => filter.latest)
        .map((filter) => filter.id)
        .toSet();
    return record.entry.updateBatches.any(latestIds.contains);
  }

  bool _matchesUpdateFilter(
    QuickTagCloudGalleryRecord record,
    String filterId,
  ) =>
      record.entry.updateBatches.contains(filterId) ||
      filterId == 'latest' && _matchesLatest(record);

  QuickTagCloudSearchDocument _searchDocument(
    QuickTagCloudGalleryRecord record, {
    required bool cache,
  }) {
    if (!cache) return QuickTagCloudSearchDocument(record);
    final cached = _searchDocuments[record.workId];
    if (cached != null && identical(cached.record, record)) return cached;
    final document = QuickTagCloudSearchDocument(record);
    _searchDocuments.remove(record.workId);
    _searchDocuments[record.workId] = document;
    while (_searchDocuments.length > 5000) {
      _searchDocuments.remove(_searchDocuments.keys.first);
    }
    return document;
  }

  Future<Set<String>> _loadFavoriteKeys(QuickTagCloudSearchPlan plan) async {
    if (!plan.usesFavorites) return const {};
    final loader = _favoriteKeysLoader;
    if (loader == null) {
      throw const QuickTagCloudSearchException([
        QuickTagCloudSearchIssue(
          'favorites_unavailable',
          '本地收藏尚未连接，暂时无法按收藏筛选',
        ),
      ]);
    }
    return Set<String>.unmodifiable(await loader());
  }

  void _sortByRelevance(
    List<QuickTagCloudGalleryRecord> records,
    QuickTagCloudSearchPlan plan, {
    required bool cache,
  }) {
    final ranked = [
      for (final (index, record) in records.indexed)
        (
          record: record,
          index: index,
          tier: _searchDocument(record, cache: cache).relevanceTier(plan),
        ),
    ];
    ranked.sort((left, right) {
      final tierOrder = left.tier.compareTo(right.tier);
      return tierOrder != 0 ? tierOrder : left.index.compareTo(right.index);
    });
    records
      ..clear()
      ..addAll(ranked.map((item) => item.record));
  }
}

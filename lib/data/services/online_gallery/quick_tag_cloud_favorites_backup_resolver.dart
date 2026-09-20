import 'package:dio/dio.dart';

import '../../datasources/remote/online_gallery/quick_tag_cloud_gallery_adapter.dart';
import '../../datasources/remote/online_gallery/quick_tag_cloud_gallery_mapper.dart';
import '../../datasources/remote/online_gallery/quick_tag_cloud_gallery_repository.dart';
import '../../models/online_gallery/gallery_item.dart';
import '../../models/online_gallery/quick_tag_cloud_community.dart';
import 'quick_tag_cloud_access.dart';
import 'quick_tag_cloud_community_service.dart';
import 'quick_tag_cloud_remote_catalog_service.dart';

/// One preview owns one resolver and cancel token. Network requests use only
/// the fixed official catalog; imported URLs/snapshots are never fetched.
class QuickTagCloudBackupResolver {
  QuickTagCloudBackupResolver(this.adapter, {
    required this.allowNsfw,
    required this.allowR18g,
    this.communityService,
  });
  final QuickTagCloudGallerySourceAdapter adapter;
  final QuickTagCloudCommunityService? communityService;
  final bool allowNsfw, allowR18g;
  Future<QuickTagCloudCatalog>? _catalog;
  final _books = <String, Future<QuickTagCloudCodex>>{};
  final _entries = <String, Map<String, QuickTagCloudEntry>>{};
  Future<Map<String, GalleryDetail>>? _community;

  Future<GalleryDetail?> resolveCommunity(String id, CancelToken token) async {
    final service = communityService;
    if (service == null) return null;
    try {
      final entries = await (_community ??= service.load(cancelToken: token)
          .then((value) => {
            for (final detail in QuickTagCloudCommunityQuery(
              ratings: const {'g', 's', 'q', 'e'},
              allowNsfw: allowNsfw, allowR18g: allowR18g,
            ).apply(value.entries))
              detail.item.sourceWorkId: detail,
          }));
      return entries['community:$id'];
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    } catch (_) {
      if (token.isCancelled) throw token.cancelError!;
      return null;
    }
  }

  Future<GalleryDetail?> resolve(
    String codexId, String entryId, CancelToken token,
  ) async {
    try {
      final catalog = await (_catalog ??= adapter.getCatalog(cancelToken: token));
      final (meta, canonicalEntry) = _canonical(catalog, codexId, entryId);
      if (meta == null ||
          QuickTagCloudAccess.isCodexLocked(meta, allowNsfw: allowNsfw)) {
        return null;
      }
      final book = await _books.putIfAbsent(meta.id,
          () => adapter.getCodex(meta.id, cancelToken: token));
      final entries = _entries.putIfAbsent(meta.id,
          () => {for (final item in book.entries) item.id: item});
      final entry = entries[canonicalEntry];
      if (entry == null ||
          QuickTagCloudAccess.isCodexLocked(book, allowNsfw: allowNsfw) ||
          QuickTagCloudAccess.isEntryAccessBlocked(entry,
              allowNsfw: allowNsfw, allowR18g: allowR18g)) return null;
      return const QuickTagCloudGalleryMapper().toGalleryDetail(
        QuickTagCloudGalleryRecord(meta, book, entry,
            book.mediaOverride ?? catalog.media),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    } catch (_) {
      if (token.isCancelled) throw token.cancelError!;
      return null;
    }
  }

  /// Exact owner migrations and one-hop aliases from upstream backup core.
  (QuickTagCloudCodexMeta?, String) _canonical(
    QuickTagCloudCatalog catalog, String codexId, String entryId,
  ) {
    String? target;
    if (codexId == 'mengshen_pack' &&
        RegExp(r'^mengshen_pack-\d{4}$').hasMatch(entryId)) {
      final number = int.parse(entryId.substring('mengshen_pack-'.length));
      if (number >= 1 && number <= 258) target = 'artist_nai45_strings';
      if (number >= 259 && number <= 1944) target = 'nai45_community_pack';
    }
    if (codexId == 'community_ai_misc' &&
        entryId.startsWith('community_ai_misc-')) target = 'nai45_community_pack';
    if ({'codex_6e699406', 'codex_8489ac52'}.contains(codexId) &&
        entryId.startsWith('$codexId-')) target = 'suozhang_r18';
    final migrated = target == null ? null : catalog.findCodex(target);
    final meta = migrated ?? catalog.findCodex(codexId);
    if (meta == null) return (null, entryId);
    var canonical = entryId;
    if (migrated == null && meta.id != codexId &&
        entryId.startsWith('$codexId-')) {
      canonical = '${meta.id}${entryId.substring(codexId.length)}';
    }
    final aliases = meta.raw['entryAliases'];
    if (aliases is Map && aliases[canonical] is String) {
      final next = aliases[canonical] as String;
      if (next.isNotEmpty && next.trim() == next && next.length <= 128 &&
          !aliases.containsKey(next) &&
          !RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(next)) {
        canonical = next;
      }
    }
    return (meta, canonical);
  }
}

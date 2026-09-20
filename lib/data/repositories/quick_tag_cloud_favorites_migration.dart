import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/prompt_tag_utils.dart';
import '../models/online_gallery/gallery_item.dart';
import '../models/online_gallery/gallery_source.dart';
import '../models/online_gallery/online_gallery_favorite_record.dart';
import '../services/online_gallery/quick_tag_cloud_access.dart';
import '../services/online_gallery/quick_tag_cloud_media_resolver.dart';
import '../services/online_gallery/quick_tag_cloud_user_service.dart';

/// Migrates the legacy QuickTagCloud JSON without discarding its only copy.
class QuickTagCloudFavoritesMigration {
  QuickTagCloudFavoritesMigration(this._box, this._legacyStorage);

  static const markerKey = '__migration_quick_tag_cloud_favorites_v1__';

  final Box<dynamic> _box;
  final LocalStorageService _legacyStorage;

  Future<void> run() async {
    if (_box.get(markerKey) == true) {
      if (_legacyStorage.getSetting<String>(
            StorageKeys.quickTagCloudFavoritesV1,
          ) !=
          null) {
        await _legacyStorage.deleteSetting(
          StorageKeys.quickTagCloudFavoritesV1,
        );
      }
      return;
    }

    final encoded = _legacyStorage.getSetting<String>(
      StorageKeys.quickTagCloudFavoritesV1,
    );
    final migrated = _decodeRecords(encoded);
    if (migrated == null) return;

    final writes = <String, dynamic>{};
    for (final entry in migrated.entries) {
      final current = _box.get(entry.key);
      if (current is Map) {
        try {
          OnlineGalleryFavoriteRecord.fromMap(current);
          continue;
        } catch (_) {
          // A valid legacy snapshot is preferable to a damaged current entry.
        }
      }
      writes[entry.key] = entry.value.toMap();
    }
    if (writes.isNotEmpty) await _box.putAll(writes);
    for (final key in migrated.keys) {
      final stored = _box.get(key);
      if (stored is! Map ||
          OnlineGalleryFavoriteRecord.fromMap(stored).stableKey != key) {
        throw StateError(
          'QuickTagCloud favorite migration verification failed',
        );
      }
    }
    await _box.put(markerKey, true);
    if (encoded != null) {
      await _legacyStorage.deleteSetting(StorageKeys.quickTagCloudFavoritesV1);
    }
  }

  Map<String, OnlineGalleryFavoriteRecord>? _decodeRecords(String? encoded) {
    final migrated = <String, OnlineGalleryFavoriteRecord>{};
    var sourceIsValid = true;
    if (encoded != null && encoded.isNotEmpty) {
      Object? decoded;
      var decodedSuccessfully = true;
      try {
        decoded = jsonDecode(encoded);
      } catch (error, stack) {
        sourceIsValid = false;
        decodedSuccessfully = false;
        AppLogger.w(
          'Ignored damaged QuickTagCloud favorites migration source: '
              '$error\n$stack',
          'OnlineGalleryFavorites',
        );
      }
      if (decoded is! List) {
        sourceIsValid = false;
        if (decodedSuccessfully) {
          AppLogger.w(
            'Ignored QuickTagCloud favorites migration source that is not a '
                'list',
            'OnlineGalleryFavorites',
          );
        }
      } else {
        for (var index = 0; index < decoded.length; index++) {
          try {
            final value = decoded[index];
            if (value is! Map) {
              throw const FormatException('Legacy favorite is not a map');
            }
            final saved = QuickTagCloudSavedEntry.fromJson(
              Map<String, dynamic>.from(value),
            );
            final record = _quickTagCloudRecord(saved);
            // Round-trip validation prevents deleting the only legacy copy
            // when a newly added snapshot field cannot be restored.
            final validated = OnlineGalleryFavoriteRecord.fromMap(
              record.toMap(),
            );
            migrated[validated.stableKey] = validated;
          } catch (error, stack) {
            sourceIsValid = false;
            AppLogger.w(
              'Ignored damaged QuickTagCloud favorite at index $index: '
                  '$error\n$stack',
              'OnlineGalleryFavorites',
            );
          }
        }
      }
    }

    return sourceIsValid ? migrated : null;
  }
}

OnlineGalleryFavoriteRecord _quickTagCloudRecord(
  QuickTagCloudSavedEntry saved,
) {
  final codex = saved.codex;
  final entry = saved.entry;
  final workId = saved.stableKey;
  final media = _legacyMedia(saved);
  final cover = media.isEmpty
      ? const GalleryMedia(id: 'no-image')
      : media.first;
  final attribution = <String>[];
  for (final value in [entry.credit, entry.author, codex.author]) {
    final normalized = value.trim();
    if (normalized.isNotEmpty && !attribution.contains(normalized)) {
      attribution.add(normalized);
    }
  }
  final sourceUrl =
      <String>[
        ...saved.links.map((link) => link.url),
        codex.source,
        codex.sourceDataUrl,
      ].firstWhere((value) {
        final uri = Uri.tryParse(value);
        return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
      }, orElse: () => '');
  final metadata = <String, dynamic>{
    'codexId': codex.id,
    'codexTitle': codex.title,
    'codexVersion': codex.version,
    'codexAuthor': codex.author,
    'codexNsfw': codex.nsfw,
    'entryId': entry.id,
    'entryAuthor': entry.author,
    'entryCredit': entry.credit,
    'prompt': entry.tags,
    'negativePrompt': entry.negative,
    'note': entry.note,
    'categoryPath': entry.path,
    'rawTag': entry.rawTag,
    'entry': entry.raw,
  };
  final item = GalleryItem(
    id: _stableNumericId(workId),
    workId: workId,
    sourceId: GallerySourceId.quickTagCloud,
    site: GallerySourceId.quickTagCloud.key,
    title: entry.title,
    author: attribution.join(' · '),
    description: entry.note,
    createdAt: codex.version,
    source: sourceUrl,
    rating: QuickTagCloudAccess.galleryRating(entry, codex: codex),
    imageWidth: cover.width,
    imageHeight: cover.height,
    tagString: entry.tags,
    tags: PromptTagUtils.parseForDisplay(entry.tags),
    fileExt: cover.extension,
    fileUrl: cover.downloadUrl.isEmpty ? null : cover.downloadUrl,
    largeFileUrl: cover.displayUrl.isEmpty ? null : cover.displayUrl,
    previewFileUrl: cover.previewUrl.isEmpty ? null : cover.previewUrl,
    cover: cover,
    mediaCount: media.length,
    rawSourceMetadata: metadata,
  );
  return OnlineGalleryFavoriteRecord.fromDetail(
    GalleryDetail(
      item: item,
      media: List.unmodifiable(media),
      prompt: entry.tags,
      negativePrompt: entry.negative,
      description: entry.note,
      categoryPath: entry.path,
      note: entry.note,
      rawTags: entry.rawTag.isEmpty ? const [] : [entry.rawTag],
      characterPrompts: [
        for (final character in entry.characterPrompts)
          GalleryCharacterPrompt(
            label: character.label,
            prompt: character.prompt,
            negativePrompt: character.negative,
          ),
      ],
      contributors: [
        for (final contributor in saved.contributors)
          GalleryContributor(name: contributor.name, role: contributor.role),
      ],
      sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
      rawSourceMetadata: metadata,
    ),
    savedAt: saved.savedAt,
  );
}

List<GalleryMedia> _legacyMedia(QuickTagCloudSavedEntry saved) {
  final codex = saved.codex;
  final entry = saved.entry;
  final workId = saved.stableKey;
  final resolver = QuickTagCloudMediaResolver(media: saved.media);
  final media = <GalleryMedia>[];
  for (var index = 0; index < entry.images.length; index++) {
    final image = entry.images[index];
    final preview = resolver.imageItemUrl(
      QuickTagCloudMediaKind.image,
      entry,
      image,
      codex,
    );
    final hasOriginal = codex.hasOriginal && image.hasOriginal;
    final download = hasOriginal
        ? resolver.imageItemUrl(
            QuickTagCloudMediaKind.original,
            entry,
            image,
            codex,
          )
        : preview;
    final dimensions = image.dimensions.isKnown
        ? image.dimensions
        : entry.dimensions;
    final extension = p
        .extension(Uri.tryParse(download)?.path ?? '')
        .replaceFirst('.', '')
        .toLowerCase();
    media.add(
      GalleryMedia(
        id: '$workId:$index',
        previewUrl: preview,
        displayUrl: preview,
        downloadUrl: download,
        width: dimensions.width,
        height: dimensions.height,
        extension: extension.isEmpty ? null : extension,
        rawMetadata: image.rawTag.isEmpty ? entry.rawTag : image.rawTag,
        prompt: entry.tags,
        negativePrompt: entry.negative,
        metadata: {...image.raw, 'hasOriginal': hasOriginal},
      ),
    );
  }
  return media;
}

int _stableNumericId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

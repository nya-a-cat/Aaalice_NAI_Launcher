import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Interoperates with AgIzT/NovelAI-Tag at ec95f2b98542e5fac0a48586e0fa2ad100eb3569:
/// favorites-backup-core.js, favorites-library-core.js, favorites-transfer.js.
/// User metadata is retained verbatim; website snapshots never authorize media.
class QuickTagCloudFavoritesBackupCodec {
  static const maximumBytes = 2 * 1024 * 1024;
  static const maximumItems = 30000;
  static const format = 'novelai-tag-favorites';
  static const transferPrefix = 'NAITAG1.';
  static const maximumCompressedBytes = maximumBytes + 64 * 1024;
  static const maximumInputBytes = (maximumCompressedBytes * 4 + 2) ~/ 3 + 128;

  static Future<Map<String, dynamic>> decode(String text) async {
    if (text.length > maximumInputBytes) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    var source = text.trim();
    if (source.startsWith(transferPrefix)) {
      final encoded = source.substring(transferPrefix.length)
          .replaceAll(RegExp(r'\s+'), '');
      if (encoded.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
        throw const QuickTagCloudBackupException('invalid');
      }
      try {
        final bytes = base64Url.decode(base64Url.normalize(encoded));
        if (bytes.length > maximumCompressedBytes) {
          throw const QuickTagCloudBackupException('tooLarge');
        }
        final output = BytesBuilder(copy: false);
        final chunks = Stream<List<int>>.fromIterable([
          for (var offset = 0; offset < bytes.length; offset += 4096)
            bytes.sublist(offset, (offset + 4096).clamp(0, bytes.length)),
        ]);
        await for (final chunk in gzip.decoder.bind(chunks)) {
          if (output.length + chunk.length > maximumBytes) {
            throw const QuickTagCloudBackupException('tooLarge');
          }
          output.add(chunk);
        }
        source = utf8.decode(output.takeBytes()).trim();
      } on QuickTagCloudBackupException {
        rethrow;
      } catch (_) {
        throw const QuickTagCloudBackupException('invalid');
      }
    }
    if (utf8.encode(source).length > maximumBytes) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const QuickTagCloudBackupException('invalid');
      }
      validate(decoded);
      return decoded;
    } on QuickTagCloudBackupException {
      rethrow;
    } catch (_) {
      throw const QuickTagCloudBackupException('invalid');
    }
  }

  static String encode(Map<String, dynamic> document) {
    validate(document);
    final json = jsonEncode(document);
    if (utf8.encode(json).length > maximumBytes) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    return json;
  }

  static String transfer(Map<String, dynamic> document) {
    final compressed = gzip.encode(utf8.encode(encode(document)));
    return '$transferPrefix${base64Url.encode(compressed).replaceAll('=', '')}';
  }

  static void validate(Map<String, dynamic> raw) {
    if (raw['format'] != format || ![1, 2].contains(raw['version'])) {
      throw const QuickTagCloudBackupException('invalid');
    }
    if (raw['exportedAt'] != null &&
        (raw['exportedAt'] is! String ||
         DateTime.tryParse(raw['exportedAt'] as String) == null)) {
      throw const QuickTagCloudBackupException('invalid');
    }
    final favorites = object(raw['favorites']);
    final atlas = array(favorites['atlas']);
    final community = array(favorites['community']);
    if (atlas.length + community.length > maximumItems) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    final keys = <String>{};
    for (final value in atlas) {
      final item = object(value);
      identifier(item['codexId'], 128);
      identifier(item['entryId'], 128);
      keys.add(keyOf(item));
      if (item['note'] != null && item['note'] is! String) {
        throw const QuickTagCloudBackupException('invalid');
      }
      if (item['snap'] != null) object(item['snap']);
    }
    for (final id in community) { identifier(id, 256); }
    if (raw['version'] == 2) _validateLibrary(raw, keys);
  }

  static void _validateLibrary(Map<String, dynamic> raw, Set<String> keys) {
    final folders = array(raw['folders']);
    if (folders.length > 100) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    final ids = <String>{};
    for (final value in folders) {
      final folder = object(value);
      final id = identifier(folder['id'], 128);
      final name = identifier(folder['name'], 80);
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || id == '_unsorted' ||
          !ids.add(id) || name.trim().runes.length > 20) {
        throw const QuickTagCloudBackupException('invalid');
      }
    }
    for (final value in array(raw['memberships'])) {
      final relation = object(value);
      if (!ids.contains(relation['folderId']) ||
          !keys.contains(relation['itemKey'])) {
        throw const QuickTagCloudBackupException('invalid');
      }
    }
  }

  static String identifier(Object? value, int maximum) {
    if (value is! String || value.trim().isEmpty || value.length > maximum ||
        RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(value)) {
      throw const QuickTagCloudBackupException('invalid');
    }
    return value;
  }

  static String keyOf(Map<String, dynamic> item) =>
      '${item['codexId']}:${item['entryId']}';

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const QuickTagCloudBackupException('invalid');
    }
    return value;
  }

  static List<dynamic> array(Object? value) {
    if (value is! List) throw const QuickTagCloudBackupException('invalid');
    return value;
  }

  static Map<String, dynamic> empty() => {
    'format': format, 'version': 2,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'favorites': {'atlas': <dynamic>[], 'community': <dynamic>[]},
    'folders': <dynamic>[], 'memberships': <dynamic>[],
  };
}

class QuickTagCloudBackupException implements Exception {
  const QuickTagCloudBackupException(this.code);
  final String code;
  @override
  String toString() => 'QuickTagCloudBackupException($code)';
}

import 'dart:convert';

import 'quick_tag_cloud_favorites_backup_codec.dart';

/// A lossless website-format merge. Conflicting metadata remains in an explicit
/// extension understood by this app and harmless to the upstream importer.
class QuickTagCloudBackupPlan {
  QuickTagCloudBackupPlan({
    required this.document,
    required this.incoming,
    required this.duplicates,
    required this.removed,
    required this.conflicts,
    required this.replace,
  });
  final Map<String, dynamic> document;
  final int incoming, duplicates, removed, conflicts;
  final bool replace;

  static List<Map<String, dynamic>> atlas(Map<String, dynamic> document) =>
      (document['favorites']['atlas'] as List).cast<Map<String, dynamic>>();

  static List<String> community(Map<String, dynamic> document) =>
      (document['favorites']['community'] as List).cast<String>();

  // Internal sidecar key; control characters cannot occur in atlas identities.
  static String communityKey(String id) => '\u0000community:$id';

  static Set<String> keys(Map<String, dynamic> document) => {
    ...atlas(document).map(_key),
    ...community(document).map(communityKey),
  };

  static Map<String, dynamic> clone(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  static QuickTagCloudBackupPlan create(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming, {
    required bool replace,
  }) {
    QuickTagCloudFavoritesBackupCodec.validate(current);
    QuickTagCloudFavoritesBackupCodec.validate(incoming);
    final oldKeys = keys(current);
    final incomingKeys = keys(incoming);
    final next = clone(replace ? incoming : current);
    final preserved = _preservedConflicts(next, incoming, replace);
    final initialConflicts = preserved.length;
    final items = _mergeAtlas(current, incoming, replace, preserved);
    final (folders, folderIds) = _mergeFolders(
      current,
      incoming,
      replace,
      preserved,
    );
    final memberships = _mergeMemberships(
      current,
      incoming,
      folderIds,
      replace,
      preserved,
    );
    final favorites = clone(next['favorites'] as Map<String, dynamic>);
    if (!replace) {
      _mergeMetadata(
        next,
        incoming,
        'document',
        preserved,
        ignore: {
          'favorites',
          'folders',
          'memberships',
          'version',
          'exportedAt',
          'aaalicePreservedConflicts',
        },
      );
      _mergeMetadata(
        favorites,
        incoming['favorites'] as Map<String, dynamic>,
        'favorites',
        preserved,
        ignore: {'atlas', 'community'},
      );
    }
    next.addAll({
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'favorites': {
        ...favorites,
        'atlas': items.values.toList(),
        'community': <dynamic>{
          if (!replace) ...current['favorites']['community'] as List,
          ...incoming['favorites']['community'] as List,
        }.toList(),
      },
      'folders': folders,
      'memberships': memberships,
      if (preserved.isNotEmpty) 'aaalicePreservedConflicts': preserved,
    });
    QuickTagCloudFavoritesBackupCodec.encode(next);
    return QuickTagCloudBackupPlan(
      document: next,
      incoming: incomingKeys.length,
      duplicates: incomingKeys.intersection(oldKeys).length,
      removed: replace ? oldKeys.difference(incomingKeys).length : 0,
      conflicts: preserved.length - initialConflicts,
      replace: replace,
    );
  }

  static String _key(Map<String, dynamic> item) =>
      QuickTagCloudFavoritesBackupCodec.keyOf(item);

  static List<dynamic> _preservedConflicts(
    Map<String, dynamic> next,
    Map<String, dynamic> incoming,
    bool replace,
  ) {
    final preserved = <dynamic>[];
    final seen = <String>{};
    for (final conflict in [
      ...?(next['aaalicePreservedConflicts'] as List?),
      if (!replace) ...?(incoming['aaalicePreservedConflicts'] as List?),
    ]) {
      if (seen.add(jsonEncode(conflict))) preserved.add(conflict);
    }
    return preserved;
  }

  static Map<String, Map<String, dynamic>> _mergeAtlas(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
    bool replace,
    List<dynamic> preserved,
  ) {
    final items = <String, Map<String, dynamic>>{};
    for (final item in [if (!replace) ...atlas(current), ...atlas(incoming)]) {
      final key = _key(item);
      final existing = items[key];
      if (existing == null) {
        items[key] = clone(item);
      } else {
        _mergeMetadata(existing, item, 'item:$key', preserved);
      }
    }
    return items;
  }

  static (List<Map<String, dynamic>>, Map<String, String>) _mergeFolders(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
    bool replace,
    List<dynamic> preserved,
  ) {
    final folders = <Map<String, dynamic>>[
      if (!replace)
        for (final value in (current['folders'] as List? ?? []))
          clone(value as Map<String, dynamic>),
    ];
    final folderIds = <String, String>{};
    final source = (incoming['folders'] as List? ?? []).indexed.toList()
      ..sort((a, b) {
        int order((int, dynamic) row) =>
            row.$2['order'] is int && (row.$2['order'] as int) >= 0
            ? row.$2['order'] as int
            : row.$1;
        final rank = order(a).compareTo(order(b));
        return rank == 0 ? a.$1.compareTo(b.$1) : rank;
      });
    for (final (_, value) in source) {
      final folder = clone(value as Map<String, dynamic>);
      final sameName = folders.where((f) => f['name'] == folder['name']);
      if (sameName.isNotEmpty) {
        folderIds[folder['id'] as String] = sameName.first['id'] as String;
        _mergeMetadata(
          sameName.first,
          folder,
          'folder',
          preserved,
          ignore: {'id', 'order'},
        );
        continue;
      }
      final originalId = folder['id'] as String;
      var id = originalId;
      var counter = 1;
      while (folders.any((f) => f['id'] == id)) {
        id = 'fd_aaalice_${counter++}';
      }
      folderIds[originalId] = id;
      folder['id'] = id;
      folder['order'] = folders.length;
      folders.add(folder);
    }
    return (folders, folderIds);
  }

  static List<Map<String, dynamic>> _mergeMemberships(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
    Map<String, String> folderIds,
    bool replace,
    List<dynamic> preserved,
  ) {
    final memberships = <String, Map<String, dynamic>>{};
    for (final value in [
      if (!replace) ...(current['memberships'] as List? ?? []),
      for (final raw in (incoming['memberships'] as List? ?? []))
        {
          ...raw as Map<String, dynamic>,
          'folderId': folderIds[raw['folderId']],
        },
    ]) {
      final relation = clone(value as Map<String, dynamic>);
      final key = jsonEncode([relation['itemKey'], relation['folderId']]);
      final existing = memberships[key];
      if (existing == null) {
        memberships[key] = relation;
      } else {
        _mergeMetadata(existing, relation, 'membership:$key', preserved);
      }
    }
    return memberships.values.toList();
  }

  static void _mergeMetadata(
    Map<String, dynamic> target,
    Map<String, dynamic> incoming,
    String scope,
    List<dynamic> preserved, {
    Set<String> ignore = const {},
  }) {
    for (final field in incoming.entries) {
      if (ignore.contains(field.key)) continue;
      final existing = target[field.key];
      if (existing == null || existing == '') {
        target[field.key] = field.value;
      } else if (field.value != null &&
          field.value != '' &&
          jsonEncode(existing) != jsonEncode(field.value)) {
        final conflict = {
          'scope': scope,
          'field': field.key,
          'value': field.value,
        };
        final encoded = jsonEncode(conflict);
        if (!preserved.any((item) => jsonEncode(item) == encoded)) {
          preserved.add(conflict);
        }
      }
    }
  }
}

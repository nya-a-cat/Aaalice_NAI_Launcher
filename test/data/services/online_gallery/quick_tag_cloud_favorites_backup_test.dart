import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_favorites_backup_codec.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_favorites_backup_plan.dart';

void main() {
  test('accepts website V1 without inventing snapshots or source details', () async {
    final original = _document(version: 1);
    final result = await QuickTagCloudFavoritesBackupCodec.decode(
      '\uFEFF${jsonEncode(original)}',
    );
    expect(result, original);
    expect(QuickTagCloudBackupPlan.atlas(result).single.containsKey('snap'), isFalse);
  });

  test('V2 JSON and NAITAG1 gzip round trip all library metadata', () async {
    final original = _document();
    original['libraryId'] = 'library-from-site';
    original['favorites']['atlas'][0].addAll({
      'note': 'handwritten note',
      'snap': {'title': 'snapshot only', 'rating': 'restricted', 'w': 832},
      'addedAt': '2026-09-20T01:02:03Z',
      'customFutureField': {'preserve': true},
    });
    original['folders'] = [
      {'id': 'fd_style', 'name': '画风', 'order': 0,
        'createdAt': '2026-09-20T01:02:03Z', 'coverItemId': 'book:entry'},
    ];
    original['memberships'] = [
      {'itemKey': 'book:entry', 'folderId': 'fd_style',
        'addedAt': '2026-09-20T01:02:03Z'},
    ];
    final encoded = QuickTagCloudFavoritesBackupCodec.transfer(original);
    expect(encoded, startsWith('NAITAG1.'));
    expect(await QuickTagCloudFavoritesBackupCodec.decode(encoded), original);
    expect(await QuickTagCloudFavoritesBackupCodec.decode(
      QuickTagCloudFavoritesBackupCodec.encode(original)), original);
  });

  test('rejects oversized decoded gzip and invalid UTF8', () async {
    final bytes = gzip.encode(List.filled(
      QuickTagCloudFavoritesBackupCodec.maximumBytes + 1, 32));
    await expectLater(QuickTagCloudFavoritesBackupCodec.decode(
      'NAITAG1.${base64Url.encode(bytes).replaceAll('=', '')}'),
      throwsA(isA<QuickTagCloudBackupException>()
        .having((e) => e.code, 'code', 'tooLarge')));
    await expectLater(QuickTagCloudFavoritesBackupCodec.decode(
      'NAITAG1.${base64Url.encode(gzip.encode([255])).replaceAll('=', '')}'),
      throwsA(isA<QuickTagCloudBackupException>()));
  });

  test('rejects invalid items, versions, duplicate folder IDs and orphan relations', () async {
    for (final change in <void Function(Map<String, dynamic>)>[
      (d) => d['version'] = 3,
      (d) => d['favorites']['atlas'][0]['codexId'] = '\u0000',
      (d) => d['favorites']['community'] = [1],
      (d) => d['folders'] = [
        {'id': 'same', 'name': 'A'}, {'id': 'same', 'name': 'B'}],
      (d) => d['memberships'] = [
        {'itemKey': 'book:entry', 'folderId': 'missing'}],
    ]) {
      final value = _document();
      change(value);
      await expectLater(QuickTagCloudFavoritesBackupCodec.decode(jsonEncode(value)),
        throwsA(isA<QuickTagCloudBackupException>()));
    }
  });

  test('merges by identity and preserves conflicting notes for export', () {
    final old = _document();
    old['favorites']['atlas'][0]['note'] = 'local note';
    old['folders'] = [{'id': 'local', 'name': '画风', 'order': 0}];
    final incoming = _document();
    incoming['favorites']['atlas'][0]['note'] = 'website note';
    incoming['favorites']['community'] = ['community-2'];
    incoming['folders'] = [{'id': 'web', 'name': '画风', 'order': 0}];
    incoming['memberships'] = [{'itemKey': 'book:entry', 'folderId': 'web'}];
    final plan = QuickTagCloudBackupPlan.create(old, incoming, replace: false);
    expect(plan.duplicates, 1);
    expect(plan.conflicts, 1);
    expect(plan.document['favorites']['atlas'][0]['note'], 'local note');
    expect(plan.document['aaalicePreservedConflicts'], contains({
      'scope': 'item:book:entry', 'field': 'note', 'value': 'website note',
    }));
    expect(plan.document['memberships'][0]['folderId'], 'local');
    expect(plan.document['favorites']['community'], ['community-1', 'community-2']);
    expect(incoming['memberships'][0]['folderId'], 'web');
    final second = QuickTagCloudBackupPlan.create(plan.document, incoming, replace: false);
    expect(second.document['aaalicePreservedConflicts'].length, 1);
    final selfImport = QuickTagCloudBackupPlan.create(
      second.document, second.document, replace: false);
    expect(selfImport.document['aaalicePreservedConflicts'].length, 1);
  });

  test('replace removes only items absent from incoming backup document', () {
    final old = _document();
    old['favorites']['atlas'].add({'codexId': 'book', 'entryId': 'old'});
    final incoming = _document();
    final plan = QuickTagCloudBackupPlan.create(old, incoming, replace: true);
    expect(plan.removed, 1);
    expect(plan.document['favorites']['atlas'], incoming['favorites']['atlas']);
  });

  test('replace remains valid when merged folder count would exceed the limit', () {
    final old = _document();
    old['folders'] = [for (var i = 0; i < 100; i++)
      {'id': 'old_$i', 'name': 'Folder $i', 'order': i}];
    final incoming = _document();
    incoming['folders'] = [{'id': 'new', 'name': 'New folder', 'order': 0}];
    expect(() => QuickTagCloudBackupPlan.create(old, incoming, replace: false),
      throwsA(isA<QuickTagCloudBackupException>()));
    expect(QuickTagCloudBackupPlan.create(old, incoming, replace: true)
      .document['folders'].length, 1);
  });
}

Map<String, dynamic> _document({int version = 2}) => {
  'format': 'novelai-tag-favorites', 'version': version,
  'exportedAt': '2026-09-20T00:00:00Z',
  'favorites': {
    'atlas': <Map<String, dynamic>>[{'codexId': 'book', 'entryId': 'entry'}],
    'community': ['community-1'],
  },
  if (version == 2) 'folders': <dynamic>[],
  if (version == 2) 'memberships': <dynamic>[],
};

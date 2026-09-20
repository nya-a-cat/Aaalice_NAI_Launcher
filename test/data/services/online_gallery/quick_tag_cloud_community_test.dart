import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_item.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_source.dart';
import 'package:nai_launcher/data/models/online_gallery/quick_tag_cloud_community.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_community_parser.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_community_service.dart';

void main() {
  _serviceTests();
  group('QuickTagCloudCommunityParser', () {
    _identityTests();
    _imageUrlTests();
    _mediaTests();
    _ratingTests();
  });
  _queryTests();
}

void _serviceTests() {
  group('QuickTagCloudCommunityService', () {
    late Dio dio;
    late _CommunityAdapter adapter;
    late QuickTagCloudCommunityService service;

    setUp(() {
      adapter = _CommunityAdapter();
      dio = Dio()..httpClientAdapter = adapter;
      service = QuickTagCloudCommunityService(dio: dio);
    });

    tearDown(() {
      service.dispose();
      dio.close(force: true);
    });

    test('loads only the fixed public GET endpoint without redirects', () async {
      adapter.body = {
        'entries': [_entry('first')],
        'features': {'likes': true},
        'generatedAt': 1234,
      };
      final result = await service.load();
      final request = adapter.requests.single;

      expect(request.method, 'GET');
      expect(request.uri.toString(),
        'https://novelai.quicktagcloud.com/api/community');
      expect(request.followRedirects, isFalse);
      expect(request.data, isNull);
      expect(request.queryParameters, isEmpty);
      expect(request.headers['Cache-Control'], 'no-cache');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.sendTimeout, const Duration(seconds: 15));
      expect(request.receiveTimeout, const Duration(seconds: 30));
      expect(result.entries.single.item.workId, 'community:first');
      expect(result.likesAvailable, isTrue);
      expect(result.generatedAt, 1234);
    });

    test('propagates an already cancelled request without dispatch', () async {
      final token = CancelToken()..cancel('test cancellation');
      await expectLater(service.load(cancelToken: token), throwsA(
        isA<DioException>().having((error) => error.type, 'type',
          DioExceptionType.cancel),
      ));
      expect(adapter.requests, isEmpty);
    });

    test('forwards cancellation to an in-flight public request', () async {
      final token = CancelToken();
      adapter.pending = Completer<ResponseBody>();
      final result = service.load(cancelToken: token);
      final expectation = expectLater(result, throwsA(
        isA<DioException>().having((error) => error.type, 'type',
          DioExceptionType.cancel),
      ));
      try {
        await adapter.started.future;
        expect(adapter.requests.single.cancelToken, same(token));
        token.cancel('closed community view');
        await expectation;
      } finally {
        token.cancel('test cleanup');
        adapter.pending!.complete(adapter.response());
      }
    });

    test('propagates server errors and malformed public data', () async {
      adapter.statusCode = 503;
      await expectLater(service.load(), throwsA(isA<DioException>().having(
        (error) => error.response?.statusCode, 'status', 503,
      )));
      adapter.statusCode = 200;
      adapter.body = {'error': 'invalid schema'};
      await expectLater(service.load(), throwsFormatException);
    });

    test('accepts JSON returned as text and preserves injected Dio ownership',
      () async {
        adapter.contentType = Headers.textPlainContentType;
        final result = await service.load();
        expect(result.entries, isEmpty);
        service.dispose();
        expect(adapter.closed, isFalse);
        expect((await service.load()).entries, isEmpty);
      },
    );
  });
}

void _identityTests() {
  test('validates schema, skips malformed/duplicate IDs and freezes entries',
    () {
      for (final value in [null, [], {}, {'entries': 'bad'}]) {
        expect(() => QuickTagCloudCommunityParser.parse(value),
          throwsFormatException);
      }
      final result = QuickTagCloudCommunityParser.parse({
        'entries': [null, 'bad', {}, _entry('one'), _entry('one')],
      });
      expect(result.entries, hasLength(1));
      expect(result.likesAvailable, isFalse);
      expect(() => result.entries.clear(), throwsUnsupportedError);
    },
  );

  test('keeps stable community identity and an encoded source link', () {
    const id = 'a b/&?';
    final first = _parse([_entry(id)]).single;
    final revised = _parse([_entry(id, {'title': 'Changed'})]).single;
    expect(first.item.workId, 'community:$id');
    expect(first.item.sourceId, GallerySourceId.quickTagCloud);
    expect(first.item.stableKey, revised.item.stableKey);
    expect(first.item.id, revised.item.id);
    expect(first.item.detailStableKey, isNot(revised.item.detailStableKey));
    final source = Uri.parse(first.sourceUrl!);
    expect(source.scheme, 'https');
    expect(source.host, 'novelai.quicktagcloud.com');
    expect(source.path, '/strings.html');
    expect(source.queryParameters, {'entry': id});
    expect(first.item.source, first.sourceUrl);
  });

  test('normalizes published category aliases and defaults unknown values', () {
    final cases = <Object?, String>{
      'style': '画风', '角色': '人物', 'face': '人物',
      'outfit': '服装', 'clothing': '服装', '衣服': '服装',
      'pose': '动作', 'composition': '构图', 'background': '场景',
      'environment': '场景', '场景/室内': '场景',
      null: '随手分享', 'other': '随手分享',
    };
    for (final entry in cases.entries) {
      expect(QuickTagCloudCommunityParser.normalizeCategory(entry.key),
        entry.value, reason: '${entry.key}');
    }
    expect(QuickTagCloudCommunityParser.normalizeCategory(['人物', '服装']),
      '人物');
  });
}

void _imageUrlTests() {
  test('accepts only trusted HTTPS images and approved relative paths', () {
    final imageUrl = QuickTagCloudCommunityParser.imageUrl;
    expect(imageUrl('cover.webp'),
      'https://pub-a66b6b5ffa0d44a89eb7dd6fa1070b58.r2.dev/images/strings/cover.webp');
    expect(imageUrl('/images/example.png'),
      'https://novelai.quicktagcloud.com/images/example.png');
    for (final host in [
      'novelai.quicktagcloud.com', 'novelai-strings.quicktagcloud.com',
      'pub-a66b6b5ffa0d44a89eb7dd6fa1070b58.r2.dev',
    ]) {
      expect(imageUrl('https://$host/image.png'), 'https://$host/image.png');
    }
  });

  test('rejects unsafe image schemes, hosts, credentials and traversal', () {
    for (final value in [
      '', 'http://novelai.quicktagcloud.com/image.png',
      '//novelai.quicktagcloud.com/image.png',
      'https://arbitrary.example/image.png',
      'https://novelai.quicktagcloud.com.evil.example/image.png',
      'https://user:password@novelai.quicktagcloud.com/image.png',
      'https://novelai.quicktagcloud.com:8443/image.png',
      'https://novelai.quicktagcloud.com/image.png#fragment',
      'data:image/png;base64,AAAA', 'file:///tmp/image.png',
      '../image.png', 'nested/../../image.png', './image.png',
      '%2e%2e/image.png', 'nested/%2e%2e/image.png',
      'https://novelai.quicktagcloud.com/nested/../image.png',
      'https://novelai.quicktagcloud.com/%2e%2e/image.png',
      r'nested\image.png',
    ]) {
      expect(QuickTagCloudCommunityParser.imageUrl(value), isEmpty,
        reason: value);
    }
  });
}

void _mediaTests() {
  test('maps prompts, characters, images, parameters and chosen cover', () {
    final detail = _parse([_entry('multi', {
      'title': 'Title', 'submitter': 'Creator', 'comment': 'Notes',
      'prompt': 'base prompt', 'negative': 'base negative',
      'category': 'outfit', 'tags': ['blue', 'dress'], 'likeCount': 7,
      'createdAt': 1700000000000, 'coverIndex': 1,
      'characterPrompts': [
        {'label': 'Alice', 'positive': 'blue hair', 'uc': 'red hair'},
        'green eyes',
      ],
      'images': [
        'first.webp',
        {'file': 'second.webp', 'original': 'second.png',
          'width': 832, 'height': 1216,
          'params': {'prompt': 'image prompt', 'negative': 'image negative',
            'seed': 123}},
      ],
    })]).single;
    expect(detail.prompt, 'base prompt');
    expect(detail.negativePrompt, 'base negative');
    expect(detail.note, 'Notes');
    expect(detail.categoryPath, ['服装']);
    expect(detail.characterPrompts.map((item) => item.label), ['Alice', 'char2']);
    expect(detail.characterPrompts.first.prompt, 'blue hair');
    expect(detail.characterPrompts.first.negativePrompt, 'red hair');
    expect(detail.media, hasLength(2));
    expect(detail.media.first.prompt, 'base prompt');
    expect(detail.media.first.negativePrompt, 'base negative');
    expect(detail.media.last.prompt, 'image prompt');
    expect(detail.media.last.negativePrompt, 'image negative');
    expect(jsonDecode(detail.media.last.rawMetadata!)['seed'], 123);
    expect(detail.media.last.metadata['hasOriginal'], isTrue);
    expect(detail.item.cover, same(detail.media.last));
    expect(detail.item.focusedMediaIndex, 1);
    expect(detail.item.width, 832);
    expect(detail.item.height, 1216);
    expect(detail.item.fileExt, 'png');
    expect(detail.item.author, 'Creator');
    expect(detail.item.score, 7);
    expect(detail.item.tags, containsAll(['blue', 'dress']));
    expect(detail.item.createdAt, '2023-11-14T22:13:20.000Z');
  });

  test('drops untrusted images, clamps covers and handles text-only entries',
    () {
      final detail = _parse([_entry('images', {
        'images': [null, {'file': 'https://arbitrary.example/image.png'},
          {'file': 'ok.webp', 'original': 'http://arbitrary.example/a.png'}],
        'coverIndex': 99,
      })]).single;
      expect(detail.media, hasLength(1));
      expect(detail.media.single.downloadUrl, endsWith('/ok.webp'));
      expect(detail.media.single.metadata['hasOriginal'], isFalse);
      expect(detail.item.focusedMediaIndex, 0);
      final textOnly = _parse([_entry('text')]).single;
      expect(textOnly.media, isEmpty);
      expect(textOnly.item.mediaCount, 0);
      expect(textOnly.item.cover.previewUrl, isEmpty);
    },
  );
}

void _ratingTests() {
  test('uses conservative ratings and ignores negative-prompt markers', () {
    final rate = QuickTagCloudCommunityParser.ratingFor;
    expect(rate({}), 'q');
    expect(rate({'nsfw': true}), 'q');
    expect(rate({'nsfw': false}), 'g');
    expect(rate({'nsfw': false, 'rating': 'q'}), 'q');
    expect(rate({'nsfw': false, 'rating': 'e'}), 'e');
    expect(rate({'nsfw': false, 'negative': 'nsfw, nude, gore, r18g',
      'characterPrompts': [{'prompt': 'portrait', 'negative': 'guro, sex'}]}),
      'g');
    for (final field in ['title', 'prompt', 'rating']) {
      expect(rate({'nsfw': false, field: 'explicit'}), 'q');
    }
    expect(rate({'nsfw': false, 'tags': ['nude']}), 'q');
    expect(rate({'nsfw': false, 'tags': ['nude_body']}), 'q');
    expect(rate({'nsfw': false,
      'characterPrompts': [{'prompt': 'naked'}]}), 'q');
    for (final marker in ['R18G', 'r-18g', 'gore', 'guro', '重口']) {
      expect(rate({'nsfw': false, 'prompt': marker}), 'e', reason: marker);
    }
  });
}

void _queryTests() {
  group('QuickTagCloudCommunityQuery', () {
    test('intersects search terms, category, favorites and selected ratings', () {
      final entries = _parse([
        _entry('one', {'title': 'Ocean', 'category': '场景', 'submitter': 'Alice',
          'comment': 'sunrise', 'prompt': 'blue water', 'negative': 'rain',
          'characterPrompts': [{'label': 'Sailor', 'prompt': 'red hat'}]}),
        _entry('two', {'title': 'Ocean', 'category': '人物'}),
        _entry('three', {'title': 'Ocean', 'category': '场景', 'nsfw': true}),
      ]);
      const query = QuickTagCloudCommunityQuery(
        search: ' OCEAN alice Sunrise BLUE rain SAILOR hat ', category: '场景',
        favoritesOnly: true,
      );
      expect(query.apply(entries, favoriteKeys: {entries.first.item.stableKey}),
        [entries.first]);
      expect(query.apply(entries), isEmpty);
      expect(const QuickTagCloudCommunityQuery(category: '构图').apply(entries),
        isEmpty);
      expect(const QuickTagCloudCommunityQuery(search: 'missing').apply(entries),
        isEmpty);
    });

    test('requires both global and source access gates for restricted content',
      () {
        final entries = _parse([
          _entry('safe'), {'id': 'unknown'},
          _entry('r18g', {'prompt': 'gore'}),
        ]);
        List<String?> ids(QuickTagCloudCommunityQuery query) =>
          query.apply(entries).map((detail) => detail.item.workId).toList();
        expect(ids(const QuickTagCloudCommunityQuery()), ['community:safe']);
        expect(ids(const QuickTagCloudCommunityQuery(ratings: {'s'})),
          ['community:safe']);
        expect(ids(const QuickTagCloudCommunityQuery(ratings: {'g', 'q', 'e'})),
          ['community:safe']);
        expect(ids(const QuickTagCloudCommunityQuery(
          ratings: {'g', 'q', 'e'}, allowNsfw: true,
        )), ['community:safe', 'community:unknown']);
        expect(ids(const QuickTagCloudCommunityQuery(
          ratings: {'e'}, allowR18g: true,
        )), isEmpty);
        expect(ids(const QuickTagCloudCommunityQuery(
          ratings: {'e'}, allowNsfw: true, allowR18g: true,
        )), ['community:r18g']);
        expect(ids(const QuickTagCloudCommunityQuery(
          ratings: {}, allowNsfw: true, allowR18g: true,
        )), isEmpty);
      },
    );

    test('sorts popularity with newest-first ties without mutating source', () {
      final entries = _parse([
        _entry('low', {'likeCount': 1, 'createdAt': '2026-09-20'}),
        _entry('older', {'likeCount': 3, 'createdAt': '2026-09-18'}),
        _entry('newer', {'likeCount': 3, 'createdAt': '2026-09-19'}),
      ]);
      final sorted = const QuickTagCloudCommunityQuery(popularFirst: true)
        .apply(entries);
      expect(sorted.map((detail) => detail.item.workId),
        ['community:newer', 'community:older', 'community:low']);
      expect(const QuickTagCloudCommunityQuery().apply(entries), entries);
      expect(entries.first.item.workId, 'community:low');
    });
  });
}

Map<String, Object?> _entry(String id, [Map<String, Object?> values = const {}]) =>
  {'id': id, 'nsfw': false, ...values};

List<GalleryDetail> _parse(List<Map<String, Object?>> entries) =>
  QuickTagCloudCommunityParser.parse({'entries': entries}).entries;

class _CommunityAdapter implements HttpClientAdapter {
  Object body = {'entries': []};
  int statusCode = 200;
  String contentType = Headers.jsonContentType;
  bool closed = false;
  final requests = <RequestOptions>[];
  final started = Completer<void>();
  Completer<ResponseBody>? pending;

  ResponseBody response() => ResponseBody.fromString(jsonEncode(body), statusCode,
    headers: {Headers.contentTypeHeader: [contentType]});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
    Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    if (pending != null) return pending!.future;
    return response();
  }

  @override
  void close({bool force = false}) => closed = true;
}

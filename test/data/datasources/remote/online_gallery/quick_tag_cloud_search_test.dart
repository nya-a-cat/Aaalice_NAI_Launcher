import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/datasources/remote/online_gallery/quick_tag_cloud_gallery_query.dart';
import 'package:nai_launcher/data/datasources/remote/online_gallery/quick_tag_cloud_gallery_repository.dart';
import 'package:nai_launcher/data/datasources/remote/online_gallery/quick_tag_cloud_query_engine.dart';
import 'package:nai_launcher/data/datasources/remote/online_gallery/quick_tag_cloud_search_matcher.dart';
import 'package:nai_launcher/data/datasources/remote/online_gallery/quick_tag_cloud_search_parser.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_parser.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_remote_catalog_service.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_user_service.dart';

void main() {
  test(
    'search grammar preserves phrases, exclusions, aliases and invalid input',
    () {
      final plan = QuickTagCloudSearchParser.parse(
        'ＨＥＲＯ "red hair" -"blue eyes" 标题:"Moon Knight" has:有图 fav:否',
      );
      expect(plan.hasErrors, isFalse);
      expect(plan.terms, ['hero', 'red hair']);
      expect(plan.filters.map((filter) => filter.field), [
        'default',
        'title',
        'has',
        'fav',
      ]);
      expect(plan.filters.first.excluded, isTrue);
      expect(plan.usesFavorites, isTrue);
      expect(QuickTagCloudSearchParser.parse('"path:foo"').terms, ['path:foo']);
      expect(QuickTagCloudSearchParser.parse('unknown:foo').terms, [
        'unknown:foo',
      ]);
      for (final query in [
        'title:',
        'title:"unfinished',
        'has:maybe',
        '-fav:true',
        'fav:true fav:false',
        'title:a -title:a',
        'type:unknown',
        '""',
        List.generate(11, (index) => 'term$index').join(' '),
      ]) {
        expect(
          QuickTagCloudSearchParser.parse(query).hasErrors,
          isTrue,
          reason: query,
        );
      }
      expect(
        QuickTagCloudSearchParser.parse(
          '',
          filterValues: ['unknown:foo'],
        ).hasErrors,
        isTrue,
      );
      final repeatedFilter = QuickTagCloudSearchParser.parse(
        '',
        filterValues: ['title:Moon Knight'],
      );
      expect(repeatedFilter.hasErrors, isFalse);
      expect(repeatedFilter.filters.single.value, 'Moon Knight');
      const filter = QuickTagCloudSearchFilter(
        field: 'title',
        value: 'Moon "Knight" \\ example',
        excluded: true,
      );
      final restored = QuickTagCloudSearchParser.parse(filter.serialize());
      expect(restored.hasErrors, isFalse);
      expect(restored.filters.single.value, filter.value);
      expect(restored.filters.single.excluded, isTrue);
    },
  );

  test(
    'AND and explicit fields match complete source metadata and exact directories',
    () {
      final document = QuickTagCloudSearchDocument(_records().first);
      bool matches(String query) =>
          document.matches(QuickTagCloudSearchParser.parse(query));
      expect(matches('hero curator "red hair"'), isTrue);
      expect(matches('hero missing'), isFalse);
      expect(matches('hero -"red hair"'), isFalse);
      expect(
        matches(
          'title:hero tag:"red hair" negative:lowres note:curator '
          'author:photographer codex:book type:画风 path:People has:image raw:original',
        ),
        isTrue,
      );
      expect(matches('title:curator'), isFalse);
      expect(matches('-negative:lowres'), isFalse);
      expect(matches('has:noimage'), isFalse);
      final code = quickTagCloudDirectoryCode(['People']);
      expect(matches('dir:book:$code'), isTrue);
      expect(matches('dir:other:$code'), isFalse);
      expect(matches('dir:book:missing'), isFalse);
      expect(matches('fav:maybe'), isFalse);
    },
  );

  test(
    'engine reads fresh unified favorite keys and keeps category and rating boundaries',
    () async {
      final user = QuickTagCloudUserService(_MemoryStorage());
      final records = _records();
      final repository = _Repository(user, records);
      var favorites = {'quick_tag_cloud:${records.first.workId}'};
      final engine = QuickTagCloudQueryEngine(
        repository: repository,
        userService: user,
        favoriteKeysLoader: () async => favorites,
      );
      Future<List<QuickTagCloudGalleryRecord>> search(String query) =>
          engine.matchingRecords(
            const QuickTagCloudGalleryQuery(codexId: 'book'),
            searchText: query,
            selectedRatings: {'g'},
          );
      expect((await search('fav:true')).map((item) => item.entry.id), ['hero']);
      favorites = {'quick_tag_cloud:${records[1].workId}'};
      expect((await search('fav:true')).map((item) => item.entry.id), [
        'concept',
      ]);
      expect((await search('fav:false')).map((item) => item.entry.id), [
        'hero',
      ]);
      expect(
        await engine.matchingRecords(
          const QuickTagCloudGalleryQuery(
            codexId: 'book',
            categoryPath: ['People'],
          ),
          searchText: 'fav:true',
          selectedRatings: {'g'},
        ),
        isEmpty,
      );
    },
  );

  test(
    'invalid and cancelled queries stop before catalog work or favorite loading',
    () async {
      final user = QuickTagCloudUserService(_MemoryStorage());
      final repository = _Repository(user, _records());
      var favoriteLoads = 0;
      final engine = QuickTagCloudQueryEngine(
        repository: repository,
        userService: user,
        favoriteKeysLoader: () async {
          favoriteLoads++;
          return {};
        },
      );
      await expectLater(
        engine.matchingRecords(
          const QuickTagCloudGalleryQuery(codexId: 'book'),
          searchText: 'has:maybe',
          selectedRatings: {'g'},
        ),
        throwsA(isA<QuickTagCloudSearchException>()),
      );
      final cancelled = CancelToken()..cancel('test');
      await expectLater(
        engine.matchingRecords(
          const QuickTagCloudGalleryQuery(codexId: 'book'),
          searchText: 'fav:true',
          selectedRatings: {'g'},
          cancelToken: cancelled,
        ),
        throwsA(isA<DioException>()),
      );
      expect(repository.loads, 0);
      expect(favoriteLoads, 0);
    },
  );
}

List<QuickTagCloudGalleryRecord> _records() {
  final meta = QuickTagCloudParser.parseCodexes(const [
    {'id': 'book', 'title': 'Book', 'type': 'string', 'author': 'Author'},
  ]).single;
  final codex = QuickTagCloudParser.parseCodex(const {
    'id': 'book',
    'entries': [
      {
        'id': 'hero',
        'title': 'Moon Hero',
        'path': ['People', 'Fantasy'],
        'tags': 'cinematic lighting',
        'note': 'curator details',
        'images': [
          {'path': 'hero.webp', 'author': 'Photographer', 'rawTag': 'original'},
        ],
        'characterPrompts': [
          {'prompt': 'red hair', 'negative': 'lowres'},
        ],
      },
      {
        'id': 'concept',
        'title': 'Text concept',
        'path': ['Concepts'],
        'tags': 'design',
      },
      {
        'id': 'adult',
        'title': 'Adult',
        'path': ['NSFW'],
        'tags': 'design',
      },
    ],
  }, meta);
  final media = QuickTagCloudParser.parseMedia(const {});
  return codex.entries
      .map((entry) => QuickTagCloudGalleryRecord(meta, codex, entry, media))
      .toList();
}

class _Repository extends QuickTagCloudGalleryRepository {
  _Repository(QuickTagCloudUserService user, this.records)
    : super(
        catalogService: QuickTagCloudRemoteCatalogService(),
        userService: user,
      );

  final List<QuickTagCloudGalleryRecord> records;
  int loads = 0;

  @override
  Future<List<QuickTagCloudGalleryRecord>> loadCatalogRecords(
    QuickTagCloudGalleryQuery query, {
    CancelToken? cancelToken,
  }) async {
    loads++;
    return records;
  }
}

class _MemoryStorage extends LocalStorageService {
  @override
  T? getSetting<T>(String key, {T? defaultValue}) => defaultValue;
}

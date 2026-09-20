import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/online_gallery/quick_tag_cloud_relay.dart';
import 'package:nai_launcher/data/services/online_gallery/quick_tag_cloud_relay_service.dart';

void main() {
  const service = QuickTagCloudRelayService();

  QuickTagCloudRelayBlock block(
    String id, {
    String positive = '',
    String negative = '',
    bool enabled = true,
    String rating = 'g',
  }) => QuickTagCloudRelayBlock(
    id: id, title: id, positive: positive, negative: negative,
    enabled: enabled, rating: rating,
  );

  QuickTagCloudRelayPlan plan(List<QuickTagCloudRelayBlock> blocks) =>
      QuickTagCloudRelayPlan(id: 'plan', name: 'Example', blocks: blocks);

  test('NAI block weights preserve whole comma groups', () {
    expect(
      service.compileBlock(' , cat, dog, ', QuickTagCloudRelayFormat.nai, 1.2),
      '1.2::cat, dog::',
    );
    expect(
      service.compileBlock('cat', QuickTagCloudRelayFormat.nai, 1), 'cat',
    );
  });

  test('NAI inline numeric weights receive outer bracket layers', () {
    expect(
      service.compileBlock('1.2::cat::', QuickTagCloudRelayFormat.nai, 1.05),
      '{1.2::cat::}',
    );
    expect(
      service.compileBlock('1.2::cat::', QuickTagCloudRelayFormat.nai, 1 / 1.05),
      '[1.2::cat::]',
    );
  });

  test('SD converts bracket powers and numeric groups to three decimals', () {
    expect(
      QuickTagCloudRelayService.naiToSd(
        '{{{cat}}}, [dog], 1.23456::tree, sky::',
      ),
      '(cat:1.158), (dog:0.952), (tree, sky:1.235)',
    );
    expect(
      service.compileBlock('{cat}, dog', QuickTagCloudRelayFormat.sd, 1.2),
      '((cat:1.05), dog:1.2)',
    );
  });

  test('plain preserves inline syntax and ignores outer block weight', () {
    expect(
      service.compileBlock(
        '{{cat}}, 1.25::sky::', QuickTagCloudRelayFormat.plain, 2,
      ),
      '{{cat}}, 1.25::sky::',
    );
  });

  test('empty numeric segments retain following delimiters and content', () {
    expect(QuickTagCloudRelayService.naiToSd('1::, cat, 2::dog::'),
        ', cat, (dog:2)');
    expect(QuickTagCloudRelayService.naiToSd('1::\ncat'), '\ncat');
    expect(QuickTagCloudRelayService.naiToSd('cat, 1::'), 'cat, ');
    final digits = '7' * 10000;
    expect(QuickTagCloudRelayService.naiToSd(digits), digits);
  });

  test('top-level splitting protects weighted and bracket comma groups', () {
    expect(
      QuickTagCloudRelayService.splitTopLevel(
        '1.2::cat, dog::, {tree, sky}, (water, cloud:1.1), bird',
      ),
      ['1.2::cat, dog::', '{tree, sky}', '(water, cloud:1.1)', 'bird'],
    );
    expect(
      QuickTagCloudRelayService.splitTopLevel('1.2::cat, dog, tree'),
      ['1.2::cat', 'dog', 'tree'],
    );
  });

  test('deduplication normalizes case and spaces independently per channel', () {
    final source = plan([
      block('a', positive: 'Blue  Sky, cat', negative: 'Blur'),
      block('b', positive: 'blue sky, CAT, dog', negative: 'blur, cat'),
    ]);
    final comma = service.compile(source);
    expect(comma.positive, 'Blue  Sky, cat, dog');
    expect(comma.negative, 'Blur, cat');
    expect(comma.mergedCount, 3);
    final newline = service.compile(source, join: QuickTagCloudRelayJoin.newline);
    expect(newline.positive, 'Blue  Sky,\ncat,\ndog');
    expect(newline.negative, 'Blur,\ncat');
    expect(newline.mergedCount, 3);
  });

  test('disabled and locked blocks are excluded and unknown ratings fail closed', () {
    final source = plan([
      block('safe', positive: 'safe'),
      block('disabled', positive: 'hidden', rating: 'e', enabled: false),
      block('restricted', positive: 'restricted', negative: 'hidden', rating: 'e'),
      block('unknown', positive: 'unknown', rating: 'future'),
    ]);
    final output = service.compile(source);
    expect(output.positive, 'safe');
    expect(output.negative, isEmpty);
    expect(output.lockedCount, 2);
    final unrestricted = service.compile(
      source, allowedRatings: {'g', 's', 'q', 'e', 'future'},
    );
    expect(unrestricted.positive, 'safe, restricted');
    expect(unrestricted.lockedCount, 1);
  });

  test('characters retain independent positive and negative text', () {
    final output = service.compile(plan([
      QuickTagCloudRelayBlock(
        id: 'a', title: 'Characters', positive: 'scene', weight: 1.2,
        characters: const [
          QuickTagCloudRelayCharacter(
            label: 'Alice', positive: 'cat', negative: 'tired',
          ),
          QuickTagCloudRelayCharacter(
            label: 'Bob', positive: 'cat', negative: 'angry',
          ),
        ],
      ),
    ]));
    expect(output.positive, '1.2::scene::');
    expect(output.negative, isEmpty);
    expect(output.characters.map((value) => value.label), ['Alice', 'Bob']);
    expect(output.characters.map((value) => value.positive),
        ['1.2::cat::', '1.2::cat::']);
    expect(output.characters.map((value) => value.negative),
        ['1.2::tired::', '1.2::angry::']);
    expect(output.mergedCount, 0);
    expect(output.allText, contains('Character 1: Alice\n1.2::cat::\nNegative:\n1.2::tired::'));
    expect(output.allText, contains('Character 2: Bob\n1.2::cat::\nNegative:\n1.2::angry::'));
  });

  test('stored restricted blocks obey current source access switches', () {
    final source = plan([
      block('safe', positive: 'safe'),
      block('nsfw', positive: 'restricted', negative: 'hidden', rating: 'q'),
      block('r18g', positive: 'restricted2', rating: 'e'),
    ]);
    final closed = QuickTagCloudRelayService.effectiveRatings(
      {'g', 'q', 'e'}, allowNsfw: false, allowR18g: true,
    );
    final output = service.compile(source, allowedRatings: closed);
    expect(output.positive, 'safe');
    expect(output.negative, isEmpty);
    expect(output.lockedCount, 2);
    expect(QuickTagCloudRelayService.effectiveRatings(
      {'g', 'q', 'e'}, allowNsfw: true, allowR18g: false,
    ), {'g', 'q'});
    expect(QuickTagCloudRelayService.effectiveRatings(
      {'g'}, allowNsfw: true, allowR18g: true,
    ), {'g'});
  });

  test('JSON roundtrip retains plans, source metadata and character negatives', () {
    final document = QuickTagCloudRelayDocument(
      plans: [plan([
        QuickTagCloudRelayBlock(
          id: 'a', title: 'Source', positive: 'sky', negative: 'blur',
          weight: 1.25, enabled: false, rating: 'q', sourceKey: 'source:a',
          characters: const [QuickTagCloudRelayCharacter(
            label: 'Alice', positive: 'cat', negative: 'tired',
          )],
        ),
      ])],
      activePlanId: 'plan', format: QuickTagCloudRelayFormat.sd,
      join: QuickTagCloudRelayJoin.newline,
    );
    final restored = QuickTagCloudRelayDocument.fromJson(
      jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), document.toJson());
    expect(restored.activePlan.id, 'plan');
  });

  test('invalid and nonfinite block weights are rejected', () {
    for (final weight in [0.0, 0.049, 10.001, double.nan, double.infinity,
      double.negativeInfinity]) {
      expect(
        () => service.compileBlock('cat', QuickTagCloudRelayFormat.nai, weight),
        throwsFormatException,
      );
      expect(
        () => QuickTagCloudRelayBlock.fromJson({
          ...block('a').toJson(), 'weight': weight,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => QuickTagCloudRelayBlock.fromJson({...block('a').toJson(), 'weight': 'bad'}),
      throwsA(isA<Object>()),
    );
  });

  test('unknown document schema, format and join values are rejected', () {
    for (final override in [
      {'version': 2}, {'format': 'future'}, {'join': 'future'},
    ]) {
      expect(
        () => QuickTagCloudRelayDocument.fromJson({
          ...QuickTagCloudRelayDocument.empty().toJson(), ...override,
        }),
        throwsA(isA<Object>()),
      );
    }
  });
}

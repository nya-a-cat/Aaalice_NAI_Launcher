import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/data/models/vibe/vibe_family.dart';
import 'package:nai_launcher/data/services/vibe_style/vibe_style_corpus.dart';
import 'package:nai_launcher/data/services/vibe_style/vibe_style_features.dart';
import 'package:nai_launcher/data/services/vibe_style/vibe_style_matcher.dart';
import 'package:nai_launcher/data/services/vibe_style/vibe_style_worker.dart';

Map<String,Object?> row(int id, String hash, {String prompt = 'test', int seed = 1,
    String? other, double strength = 1}) => {
  'id': id,'file_path': 'test-$id.png','file_size': 20,'modified_at': 100,
  'prompt': prompt,'negative_prompt': 'bad','model': 'nai-diffusion-4-5-full',
  'sampler': 'k_euler','steps': 28,'cfg_scale': 5.0,'width': 832,'height': 1216,
  'is_img2img': 0,'seed': seed,'extra_controls': jsonEncode(List.filled(26,null)),
  'raw_ref_count': other == null ? 1 : 2,
  'refs': jsonEncode([
    {'hash':hash,'strength':strength,'info':0.7,'ordinal':0},
    if (other != null) {'hash':other,'strength':1.0,'info':0.7,'ordinal':1},
  ]),
};

void main() {
  test('controlled recipes include other Vibes, strength and full settings', () {
    final values = VibeStyleCorpus.parse([
      row(1,'a',other:'c'),row(2,'b',other:'c',seed:2),row(3,'b',other:'d'),
      row(4,'b',other:'c',strength:0.8),
      {...row(5,'b',other:'c'),'steps':30},
    ]).where((s) => s.hash == 'a' || s.hash == 'b').toList();
    expect(values[0].recipe,isNotEmpty);
    expect(values[1].recipe,values[0].recipe);
    for (final s in values.skip(2)) { expect(s.recipe,isNot(values[0].recipe)); }
  });
  test('missing, duplicate, img2img and character controls stay conservative', () {
    final rows = [
      {...row(1,'a'),'extra_controls':null},
      {...row(2,'a'),'raw_ref_count':2},
      {...row(3,'a'),'is_img2img':1},
      {...row(4,'a'),'raw_ref_count':null},
    ];
    expect(VibeStyleCorpus.parse(rows).map((s) => s.recipe),everyElement(isEmpty));
    final extra = List<Object?>.filled(26,null)..[0] = {'character_prompts':['different']};
    final variants = VibeStyleCorpus.parse([row(5,'a'),
      {...row(6,'b'),'extra_controls':jsonEncode(extra)}]);
    expect(variants[0].recipe,isNot(variants[1].recipe));
    expect(VibeStyleCorpus.parse([{'refs':'broken'}]),isEmpty);
  });
  test('sampler selects diverse prompts within strict image and per-code budgets', () {
    final corpus = VibeStyleCorpus.parse(List.generate(800,(i) =>
      row(i+1,'code-${i%20}',prompt:'prompt-${i~/20}')));
    final selected = VibeStyleCorpus.select(corpus,maxImages:50,perCode:4);
    expect(selected.map((s) => s.imageId).toSet().length,lessThanOrEqualTo(50));
    for (final code in selected.map((s) => s.hash).toSet()) {
      final bucket = selected.where((s) => s.hash == code);
      expect(bucket.length,lessThanOrEqualTo(4));
      expect(bucket.map((s) => s.promptKey).toSet().length,bucket.length);
    }
  });
  test('traditional descriptors are bounded, deterministic and input-preserving', () {
    final image = img.Image(width:32,height:48,numChannels:4);
    for (final pixel in image) { pixel.setRgba(200,30,40,255); }
    final before = image.getBytes().toList();
    final feature = VibeStyleFeatures.extract(image);
    expect(VibeStyleFeatures.isValid(feature),isTrue);
    expect(VibeStyleFeatures.extract(image),feature);
    expect(image.getBytes(),before);
    final other = img.Image.from(image);
    for (final p in other) { p.setRgba(20,150,250,255); }
    expect(VibeStyleFeatures.extract(other).first,isNot(feature.first));
    expect(VibeStyleFeatures.isValid(VibeStyleFeatures.extract(img.Image(width:1,height:1))),isTrue);
  });
  test('multiple seeds of one prompt do not inflate independent evidence', () {
    final samples = VibeStyleCorpus.parse([
      row(1,'a'),row(2,'b'),row(3,'a',seed:2),row(4,'b',seed:2),
    ]);
    final feature = VibeStyleFeatures.extract(img.Image(width:16,height:16));
    final features = {for (final s in samples) s.cacheKey:feature};
    var result = VibeStyleMatcher.rank(samples,features).single;
    expect(result.recipeCount,1);
    expect(result.hasControls,isFalse);
    final extra = VibeStyleCorpus.parse([row(5,'a',prompt:'second'),row(6,'b',prompt:'second')]);
    samples.addAll(extra);
    for (final s in extra) { features[s.cacheKey] = feature; }
    result = VibeStyleMatcher.rank(samples,features).single;
    expect(result.recipeCount,2);
    expect(result.sameSeedCount,2);
    expect(result.hasControls,isTrue);
  });
  test('co-used codes in one output and corrupt cached features do not match', () {
    final samples = VibeStyleCorpus.parse([row(1,'a',other:'b')]);
    final feature = VibeStyleFeatures.extract(img.Image(width:16,height:16));
    expect(VibeStyleMatcher.rank(samples,{samples.first.cacheKey:feature}),isEmpty);
    expect(VibeStyleMatcher.rank(samples,{samples.first.cacheKey:[[double.nan]]}),isEmpty);
  });
  test('feature worker reads sources without changing bytes, metadata or timestamps', () async {
    final temporary = await Directory.systemTemp.createTemp('vibe_style_readonly_');
    addTearDown(() => temporary.delete(recursive:true));
    final image = img.Image(width:32,height:48);
    image.textData = {'Comment':'preserve source metadata'};
    final file = File('${temporary.path}/source.png');
    await file.writeAsBytes(img.encodePng(image));
    final before = await file.stat();
    final bytes = await file.readAsBytes();
    final sample = VibeStyleSample(imageId:1,path:file.path,size:before.size,
      modifiedAt:before.modified.millisecondsSinceEpoch,hash:'a',recipe:'',promptKey:'',seed:1);
    final worker = VibeStyleWorker();
    final feature = await worker.run<List<List<double>>?>('features',sample);
    expect(VibeStyleFeatures.isValid(feature!),isTrue);
    expect(sha256.convert(await file.readAsBytes()),sha256.convert(bytes));
    final after = await file.stat();
    expect(after.modified,before.modified);
    expect(after.size,before.size);
    expect(img.decodePng(await file.readAsBytes())!.textData!['Comment'],'preserve source metadata');
  });
  test('timeouts and cancellation release worker and permit retry', () async {
    final worker = VibeStyleWorker();
    final timeout = worker.run<List<VibeStyleSample>>('parse',<Map<String,Object?>>[],
      timeout:Duration.zero);
    await expectLater(timeout,throwsA(isA<TimeoutException>()));
    final cancelled = worker.run<List<VibeStyleSample>>('parse',<Map<String,Object?>>[]);
    worker.cancel();
    await expectLater(cancelled,throwsA(isA<VibeStyleCancelled>()));
    expect(await worker.run<List<VibeStyleSample>>('parse',<Map<String,Object?>>[]),isEmpty);
  });
}

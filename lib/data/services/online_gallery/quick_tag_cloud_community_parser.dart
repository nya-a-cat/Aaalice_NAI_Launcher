import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/utils/prompt_tag_utils.dart';
import '../../models/online_gallery/gallery_item.dart';
import '../../models/online_gallery/gallery_source.dart';
import '../../models/online_gallery/quick_tag_cloud_community.dart';
import 'quick_tag_cloud_parser.dart';

/// Source schema: AgIzT/NovelAI-Tag ec95f2b9, functions/api/community.js.
class QuickTagCloudCommunityParser {
  const QuickTagCloudCommunityParser._();

  static const categories = ['随手分享', '画风', '人物', '服装', '动作', '构图', '场景'];
  static const _imageHosts = {
    'novelai.quicktagcloud.com',
    'novelai-strings.quicktagcloud.com',
    'pub-a66b6b5ffa0d44a89eb7dd6fa1070b58.r2.dev',
  };
  static const _r2Base =
      'https://pub-a66b6b5ffa0d44a89eb7dd6fa1070b58.r2.dev/images/strings/';

  static QuickTagCloudCommunity parse(Object? value) {
    if (value is! Map || value['entries'] is! List) {
      throw const FormatException('Invalid QuickTagCloud community response');
    }
    final ids = <String>{};
    final entries = <GalleryDetail>[];
    for (final raw in value['entries'] as List) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final id = _text(entry['id']);
      if (id.isEmpty || !ids.add(id)) continue;
      entries.add(_detail(entry, id));
    }
    final features = value['features'];
    return QuickTagCloudCommunity(
      entries: List.unmodifiable(entries),
      likesAvailable: features is Map && features['likes'] == true,
      generatedAt: _integer(value['generatedAt']),
    );
  }

  static GalleryDetail _detail(Map<String, dynamic> entry, String id) {
    final workId = 'community:$id';
    final prompt = _text(entry['prompt']);
    final negative = _text(entry['negative']);
    final category = normalizeCategory(entry['category']);
    final tags = entry['tags'] is List
        ? (entry['tags'] as List).whereType<String>().toList(growable: false)
        : const <String>[];
    final sourceUrl = Uri.https('novelai.quicktagcloud.com', '/strings.html', {
      'entry': id,
    }).toString();
    final media = _media(entry, workId, prompt, negative);
    final characters = [
      for (final character in QuickTagCloudParser.normalizeCharacterPrompts(
        entry['characterPrompts'],
      ))
        GalleryCharacterPrompt(
          label: character.label,
          prompt: character.prompt,
          negativePrompt: character.negative,
        ),
    ];
    final metadata = _metadata(entry, id, category, sourceUrl);
    final coverIndex = _integer(
      entry['coverIndex'],
    ).clamp(0, media.isEmpty ? 0 : media.length - 1);
    final cover = media.isEmpty
        ? const GalleryMedia(id: 'no-image')
        : media[coverIndex];
    final item = GalleryItem(
      id: int.parse(
        sha256.convert(utf8.encode(workId)).toString().substring(0, 7),
        radix: 16,
      ),
      workId: workId,
      sourceId: GallerySourceId.quickTagCloud,
      site: GallerySourceId.quickTagCloud.key,
      title: _text(entry['title']),
      author: _text(entry['submitter']),
      description: _text(entry['comment']),
      createdAt: _createdAt(entry['createdAt']),
      source: sourceUrl,
      rating: ratingFor(entry),
      score: _integer(entry['likeCount']).clamp(0, 1 << 31),
      tagString: prompt,
      tags: List.unmodifiable({
        ...tags,
        ...PromptTagUtils.parseForDisplay(prompt),
        for (final character in characters)
          ...PromptTagUtils.parseForDisplay(character.prompt),
      }),
      cover: cover,
      imageWidth: cover.width,
      imageHeight: cover.height,
      fileUrl: cover.downloadUrl,
      previewFileUrl: cover.previewUrl,
      largeFileUrl: cover.displayUrl,
      fileExt: cover.extension,
      mediaCount: media.length,
      focusedMediaIndex: coverIndex,
      rawSourceMetadata: metadata,
    );
    return GalleryDetail(
      item: item,
      media: List.unmodifiable(media),
      prompt: prompt,
      negativePrompt: negative,
      description: _text(entry['comment']),
      note: _text(entry['comment']),
      categoryPath: [category],
      characterPrompts: characters,
      sourceUrl: sourceUrl,
      rawSourceMetadata: metadata,
    );
  }

  static Map<String, dynamic> _metadata(
    Map<String, dynamic> entry,
    String id,
    String category,
    String sourceUrl,
  ) => {
    'communityId': id,
    'entryId': id,
    'prompt': _text(entry['prompt']),
    'negativePrompt': _text(entry['negative']),
    'note': _text(entry['comment']),
    'categoryPath': [category],
    'characterPrompts': entry['characterPrompts'] ?? const [],
    'sourceUrl': sourceUrl,
    'entry': entry,
    'detailRevision': sha256.convert(utf8.encode(jsonEncode(entry))).toString(),
  };

  static List<GalleryMedia> _media(
    Map<String, dynamic> entry,
    String workId,
    String prompt,
    String negative,
  ) {
    final media = <GalleryMedia>[];
    if (entry['images'] is! List) return media;
    for (final value in entry['images'] as List) {
      final image = value is String
          ? <String, dynamic>{'file': value}
          : value is Map
          ? Map<String, dynamic>.from(value)
          : null;
      if (image == null) continue;
      final preview = imageUrl(image['file']);
      if (preview.isEmpty) continue;
      final original = imageUrl(image['original']);
      final params = image['params'] is Map
          ? Map<String, dynamic>.from(image['params'] as Map)
          : const <String, dynamic>{};
      final extension = Uri.parse(
        original.isEmpty ? preview : original,
      ).path.split('.').last.toLowerCase();
      media.add(
        GalleryMedia(
          id: '$workId:${media.length}',
          previewUrl: preview,
          displayUrl: original.isEmpty ? preview : original,
          downloadUrl: original.isEmpty ? preview : original,
          width: _integer(image['width']).clamp(0, 100000),
          height: _integer(image['height']).clamp(0, 100000),
          extension: RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)
              ? extension
              : null,
          prompt: _text(params['prompt']).isEmpty
              ? prompt
              : _text(params['prompt']),
          negativePrompt: _text(params['negative']).isEmpty
              ? negative
              : _text(params['negative']),
          rawMetadata: params.isEmpty ? null : jsonEncode(params),
          metadata: {...image, 'hasOriginal': original.isNotEmpty},
        ),
      );
    }
    return media;
  }

  /// No arbitrary hosts, credentials, insecure URLs or path traversal.
  static String imageUrl(Object? value) {
    final raw = _text(value);
    if (raw.isEmpty || raw.contains(r'\')) return '';
    if (RegExp(
      r'(^|/|%2f)(\.|%2e){1,2}(/|%2f|$|[?#])',
      caseSensitive: false,
    ).hasMatch(raw)) {
      return '';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return '';
    if (uri.pathSegments.any(
      (segment) =>
          segment.contains('%') ||
          segment.contains(r'\') ||
          segment.split('/').any((part) => part == '..' || part == '.') ||
          segment.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f),
    )) {
      return '';
    }
    final resolved = uri.hasScheme || raw.startsWith('//')
        ? uri
        : raw.startsWith('/')
        ? Uri.https('novelai.quicktagcloud.com', '/').resolveUri(uri)
        : Uri.parse(_r2Base).resolveUri(uri);
    if (resolved.scheme != 'https' ||
        !_imageHosts.contains(resolved.host.toLowerCase()) ||
        resolved.userInfo.isNotEmpty ||
        resolved.hasFragment ||
        resolved.hasPort && resolved.port != 443) {
      return '';
    }
    return resolved.toString();
  }

  static String normalizeCategory(Object? value) {
    final raw = value is List ? (value.isEmpty ? '' : value.first) : value;
    final name = _text(raw).split('/').first.trim();
    if (categories.contains(name)) return name;
    return switch (name.toLowerCase().replaceAll(RegExp(r'\s+'), '')) {
      'style' => '画风',
      '角色' || '面部' || 'face' => '人物',
      '穿搭' || '衣服' || 'outfit' || 'clothing' => '服装',
      'pose' => '动作',
      'composition' => '构图',
      '背景' || '环境' || 'scene' || 'background' || 'environment' => '场景',
      _ => categories.first,
    };
  }

  /// Published labels are supplemented with explicit positive-prompt markers.
  /// Negative prompts are deliberately excluded from this classification.
  static String ratingFor(Map<String, dynamic> entry) {
    final declared = _text(entry['rating']).toLowerCase();
    if (declared == 'e' || declared == 'r18g') return 'e';
    final text = [
      entry['rating'],
      entry['title'],
      entry['prompt'],
      if (entry['tags'] is List) ...(entry['tags'] as List),
      for (final character in QuickTagCloudParser.normalizeCharacterPrompts(
        entry['characterPrompts'],
      ))
        character.prompt,
    ].whereType<String>().join(' ').toLowerCase().replaceAll('_', ' ');
    if (RegExp(r'\br[-_ ]?18g\b|重口|\bgore\b|\bguro\b').hasMatch(text)) {
      return 'e';
    }
    if (entry['nsfw'] != false ||
        declared == 'q' ||
        RegExp(
          r'\b(nsfw|r[-_ ]?18|restricted|explicit|nude|naked|nipples|penis|pussy|sex|intercourse)\b',
        ).hasMatch(text)) {
      return 'q';
    }
    return 'g';
  }

  static String _createdAt(Object? value) {
    final number = _integer(value);
    if (number > 0 && number < 8640000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(
        number,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(_text(value))?.toUtc().toIso8601String() ?? '';
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int _integer(Object? value) => value is num && value.isFinite
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;
}

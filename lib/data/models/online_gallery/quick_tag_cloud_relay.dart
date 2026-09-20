/// Local, independent prompt plans. Source snapshots never edit gallery data.
enum QuickTagCloudRelayFormat { nai, sd, plain }

enum QuickTagCloudRelayJoin { comma, newline }

class QuickTagCloudRelayCharacter {
  const QuickTagCloudRelayCharacter({
    required this.label,
    required this.positive,
    required this.negative,
  });

  final String label;
  final String positive;
  final String negative;

  Map<String, Object?> toJson() => {
    'label': label,
    'positive': positive,
    'negative': negative,
  };

  factory QuickTagCloudRelayCharacter.fromJson(Map<String, dynamic> json) =>
      QuickTagCloudRelayCharacter(
        label: _text(json['label']),
        positive: _text(json['positive']),
        negative: _text(json['negative']),
      );
}

class QuickTagCloudRelayBlock {
  QuickTagCloudRelayBlock({
    required this.id,
    required this.title,
    this.positive = '',
    this.negative = '',
    this.weight = 1,
    this.enabled = true,
    this.rating = 'g',
    this.sourceKey,
    List<QuickTagCloudRelayCharacter> characters = const [],
  }) : characters = List.unmodifiable(characters);

  static const minimumWeight = 0.05;
  static const maximumWeight = 10.0;
  final String id;
  final String title;
  final String positive;
  final String negative;
  final double weight;
  final bool enabled;

  /// Unknown source ratings remain locked until the original source is known.
  final String rating;
  final String? sourceKey;
  final List<QuickTagCloudRelayCharacter> characters;

  bool allowedBy(Set<String> ratings) => switch (rating) {
    'g' || 's' => ratings.contains('g') || ratings.contains('s'),
    'q' => ratings.contains('q'),
    'e' => ratings.contains('e'),
    _ => false,
  };

  QuickTagCloudRelayBlock copyWith({
    String? title,
    String? positive,
    String? negative,
    double? weight,
    bool? enabled,
  }) => QuickTagCloudRelayBlock(
    id: id,
    title: title ?? this.title,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    weight: weight ?? this.weight,
    enabled: enabled ?? this.enabled,
    rating: rating,
    sourceKey: sourceKey,
    characters: characters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'positive': positive,
    'negative': negative,
    'weight': weight,
    'enabled': enabled,
    'rating': rating,
    'sourceKey': sourceKey,
    'characters': characters.map((value) => value.toJson()).toList(),
  };

  factory QuickTagCloudRelayBlock.fromJson(Map<String, dynamic> json) {
    final weight = (json['weight'] as num?)?.toDouble();
    if (weight == null ||
        !weight.isFinite ||
        weight < minimumWeight ||
        weight > maximumWeight ||
        json['enabled'] is! bool) {
      throw const FormatException('Invalid relay block');
    }
    return QuickTagCloudRelayBlock(
      id: _id(json['id']),
      title: _text(json['title']),
      positive: _text(json['positive']),
      negative: _text(json['negative']),
      weight: weight,
      enabled: json['enabled'] as bool,
      rating: _text(json['rating']),
      sourceKey: json['sourceKey'] == null ? null : _text(json['sourceKey']),
      characters: _objects(
        json['characters'],
        100,
      ).map(QuickTagCloudRelayCharacter.fromJson).toList(),
    );
  }
}

class QuickTagCloudRelayPlan {
  QuickTagCloudRelayPlan({
    required this.id,
    required this.name,
    List<QuickTagCloudRelayBlock> blocks = const [],
  }) : blocks = List.unmodifiable(blocks);

  final String id;
  final String name;
  final List<QuickTagCloudRelayBlock> blocks;

  QuickTagCloudRelayPlan copyWith({
    String? name,
    List<QuickTagCloudRelayBlock>? blocks,
  }) => QuickTagCloudRelayPlan(
    id: id,
    name: name ?? this.name,
    blocks: blocks ?? this.blocks,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'blocks': blocks.map((value) => value.toJson()).toList(),
  };

  factory QuickTagCloudRelayPlan.fromJson(Map<String, dynamic> json) {
    final blocks = _objects(
      json['blocks'],
      500,
    ).map(QuickTagCloudRelayBlock.fromJson).toList();
    if (blocks.map((block) => block.id).toSet().length != blocks.length) {
      throw const FormatException('Duplicate relay block IDs');
    }
    return QuickTagCloudRelayPlan(
      id: _id(json['id']),
      name: _text(json['name']),
      blocks: blocks,
    );
  }
}

class QuickTagCloudRelayDocument {
  QuickTagCloudRelayDocument({
    required List<QuickTagCloudRelayPlan> plans,
    required this.activePlanId,
    this.format = QuickTagCloudRelayFormat.nai,
    this.join = QuickTagCloudRelayJoin.comma,
  }) : plans = List.unmodifiable(plans);

  factory QuickTagCloudRelayDocument.empty() => QuickTagCloudRelayDocument(
    plans: [QuickTagCloudRelayPlan(id: 'default', name: '')],
    activePlanId: 'default',
  );

  final List<QuickTagCloudRelayPlan> plans;
  final String activePlanId;
  final QuickTagCloudRelayFormat format;
  final QuickTagCloudRelayJoin join;
  QuickTagCloudRelayPlan get activePlan =>
      plans.firstWhere((plan) => plan.id == activePlanId);

  QuickTagCloudRelayDocument copyWith({
    List<QuickTagCloudRelayPlan>? plans,
    String? activePlanId,
    QuickTagCloudRelayFormat? format,
    QuickTagCloudRelayJoin? join,
  }) => QuickTagCloudRelayDocument(
    plans: plans ?? this.plans,
    activePlanId: activePlanId ?? this.activePlanId,
    format: format ?? this.format,
    join: join ?? this.join,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'activePlanId': activePlanId,
    'format': format.name,
    'join': join.name,
    'plans': plans.map((value) => value.toJson()).toList(),
  };

  factory QuickTagCloudRelayDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported relay version');
    }
    final plans = _objects(
      json['plans'],
      100,
    ).map(QuickTagCloudRelayPlan.fromJson).toList();
    final active = _id(json['activePlanId']);
    if (plans.isEmpty ||
        !plans.any((plan) => plan.id == active) ||
        plans.map((plan) => plan.id).toSet().length != plans.length) {
      throw const FormatException('Invalid relay plans');
    }
    return QuickTagCloudRelayDocument(
      plans: plans,
      activePlanId: active,
      format: QuickTagCloudRelayFormat.values.byName(_text(json['format'])),
      join: QuickTagCloudRelayJoin.values.byName(_text(json['join'])),
    );
  }
}

String _text(Object? value) {
  if (value is! String || value.length > 100000) {
    throw const FormatException('Invalid relay text');
  }
  return value;
}

String _id(Object? value) {
  final result = _text(value);
  if (result.isEmpty) throw const FormatException('Missing relay ID');
  return result;
}

Iterable<Map<String, dynamic>> _objects(Object? value, int limit) {
  if (value is! List || value.length > limit) {
    throw const FormatException('Invalid relay list');
  }
  return value.map((item) => Map<String, dynamic>.from(item as Map));
}

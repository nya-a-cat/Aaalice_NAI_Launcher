import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/local_storage_service.dart';
import '../../data/models/online_gallery/gallery_item.dart';
import '../../data/models/online_gallery/gallery_source.dart';
import '../../data/models/online_gallery/quick_tag_cloud_relay.dart';
import '../../data/services/online_gallery/quick_tag_cloud_relay_service.dart';
import 'online_gallery_provider.dart';
import 'quick_tag_cloud_gallery_provider.dart';

class QuickTagCloudRelayState {
  const QuickTagCloudRelayState({
    required this.document,
    this.isSaving = false,
    this.isCorrupt = false,
    this.saveFailed = false,
  });
  final QuickTagCloudRelayDocument document;
  final bool isSaving;
  final bool isCorrupt;
  final bool saveFailed;
}

final quickTagCloudRelayProvider =
    NotifierProvider<QuickTagCloudRelayController, QuickTagCloudRelayState>(
      QuickTagCloudRelayController.new,
    );

final quickTagCloudRelayAllowedRatingsProvider = Provider<Set<String>>((ref) {
  final ratings = ref.watch(
    onlineGalleryNotifierProvider.select((state) => state.selectedRatings),
  );
  final access = ref.watch(quickTagCloudFilterProvider);
  return QuickTagCloudRelayService.effectiveRatings(
    ratings,
    allowNsfw: access.allowNsfw,
    allowR18g: access.allowR18g,
  );
});

class QuickTagCloudRelayController extends Notifier<QuickTagCloudRelayState> {
  static const storageKey = 'quick_tag_cloud_relay_v1';
  static const maximumStorageCharacters = 4 * 1024 * 1024;
  late LocalStorageService _storage;
  Future<void> _tail = Future.value();
  var _disposed = false;

  @override
  QuickTagCloudRelayState build() {
    _storage = ref.read(localStorageServiceProvider);
    ref.onDispose(() => _disposed = true);
    try {
      final stored = _storage.getSetting<Object>(storageKey);
      if (stored == null) {
        return QuickTagCloudRelayState(
          document: QuickTagCloudRelayDocument.empty(),
        );
      }
      if (stored is! String || stored.length > maximumStorageCharacters) {
        throw const FormatException('Invalid relay storage');
      }
      final document = QuickTagCloudRelayDocument.fromJson(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
      return QuickTagCloudRelayState(document: document);
    } catch (_) {
      return QuickTagCloudRelayState(
        document: QuickTagCloudRelayDocument.empty(),
        isCorrupt: true,
      );
    }
  }

  Future<void> _commit(
    QuickTagCloudRelayDocument Function(QuickTagCloudRelayDocument) change, {
    bool recover = false,
  }) {
    final operation = _tail.then((_) async {
      if (_disposed) throw StateError('Relay controller disposed');
      if (state.isCorrupt && !recover) {
        throw StateError('Relay storage requires explicit recovery');
      }
      if (recover && !state.isCorrupt) {
        throw StateError('Relay storage does not require recovery');
      }
      final previous = state;
      state = QuickTagCloudRelayState(
        document: previous.document,
        isSaving: true,
        isCorrupt: previous.isCorrupt,
      );
      try {
        final next = change(previous.document);
        final encoded = jsonEncode(next.toJson());
        if (encoded.length > maximumStorageCharacters) {
          throw const FormatException('Relay storage size limit exceeded');
        }
        // Validate constructed values before committing; corruption never falls
        // through to an automatic default-state write.
        QuickTagCloudRelayDocument.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
        if (recover) {
          final key = '$storageKey.recovery.${const Uuid().v4()}';
          final original = _storage.getSetting<Object>(storageKey);
          await _storage.setSetting<Object?>(key, original);
        }
        await _storage.setSetting<String>(storageKey, encoded);
        if (!_disposed) state = QuickTagCloudRelayState(document: next);
      } catch (_) {
        if (!_disposed) {
          state = QuickTagCloudRelayState(
            document: previous.document,
            isCorrupt: previous.isCorrupt,
            saveFailed: true,
          );
        }
        rethrow;
      }
    });
    // A failed write must not poison later retries; callers still receive it.
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> recoverWithBackup() =>
      _commit((_) => QuickTagCloudRelayDocument.empty(), recover: true);

  Future<void> selectPlan(String id) => _commit((document) {
    if (!document.plans.any((plan) => plan.id == id)) {
      throw StateError('Unknown plan');
    }
    return document.copyWith(activePlanId: id);
  });

  Future<void> createPlan(String name) => _commit((document) {
    final plan = QuickTagCloudRelayPlan(
      id: const Uuid().v4(),
      name: name.trim(),
    );
    return document.copyWith(
      plans: [...document.plans, plan],
      activePlanId: plan.id,
    );
  });

  Future<void> renamePlan(String id, String name) => _commit(
    (document) => document.copyWith(
      plans: [
        for (final plan in document.plans)
          plan.id == id ? plan.copyWith(name: name.trim()) : plan,
      ],
    ),
  );

  Future<void> deletePlan(String id) => _commit((document) {
    if (document.plans.length <= 1) throw StateError('Keep one relay plan');
    final plans = document.plans.where((plan) => plan.id != id).toList();
    return document.copyWith(
      plans: plans,
      activePlanId: document.activePlanId == id ? plans.first.id : null,
    );
  });

  Future<void> setFormat(QuickTagCloudRelayFormat format) =>
      _commit((document) => document.copyWith(format: format));

  Future<void> setJoin(QuickTagCloudRelayJoin join) =>
      _commit((document) => document.copyWith(join: join));

  Future<void> _changeBlocks(
    String planId,
    List<QuickTagCloudRelayBlock> Function(List<QuickTagCloudRelayBlock>)
    change,
  ) => _commit((document) {
    if (!document.plans.any((plan) => plan.id == planId)) {
      throw StateError('Unknown plan');
    }
    return document.copyWith(
      plans: [
        for (final plan in document.plans)
          plan.id == planId ? plan.copyWith(blocks: change(plan.blocks)) : plan,
      ],
    );
  });

  Future<void> addBlock(String planId, QuickTagCloudRelayBlock block) =>
      _changeBlocks(planId, (blocks) => [...blocks, block]);

  Future<void> updateBlock(String planId, QuickTagCloudRelayBlock block) =>
      _changeBlocks(planId, (blocks) {
        final index = blocks.indexWhere((current) => current.id == block.id);
        if (index < 0) throw StateError('Relay block no longer exists');
        final current = blocks[index];
        if (!current.allowedBy(
          ref.read(quickTagCloudRelayAllowedRatingsProvider),
        )) {
          throw StateError('Source is locked by current rating settings');
        }
        final next = blocks.toList();
        next[index] = current.copyWith(
          title: block.title,
          positive: block.positive,
          negative: block.negative,
          weight: block.weight,
          enabled: block.enabled,
        );
        return next;
      });

  Future<void> toggleBlock(String planId, String blockId) => _changeBlocks(
    planId,
    (blocks) => [
      for (final block in blocks)
        block.id == blockId ? block.copyWith(enabled: !block.enabled) : block,
    ],
  );

  Future<void> removeBlock(String planId, String blockId) => _changeBlocks(
    planId,
    (blocks) => blocks.where((block) => block.id != blockId).toList(),
  );

  Future<void> moveBlock(String planId, String blockId, int delta) =>
      _changeBlocks(planId, (blocks) {
        final index = blocks.indexWhere((block) => block.id == blockId);
        if (index < 0 || index + delta < 0 || index + delta >= blocks.length) {
          return blocks;
        }
        final next = blocks.toList();
        final block = next.removeAt(index);
        next.insert(index + delta, block);
        return next;
      });

  /// Called by gallery detail actions; duplicate source slots are not appended.
  Future<void> addFromDetail(GalleryDetail detail) {
    final planId = state.document.activePlanId;
    if (detail.item.sourceId != GallerySourceId.quickTagCloud) {
      return Future.error(ArgumentError('Expected QuickTagCloud detail'));
    }
    final block = QuickTagCloudRelayBlock(
      id: const Uuid().v4(),
      title: detail.item.title ?? '',
      positive: detail.prompt ?? '',
      negative: detail.negativePrompt ?? '',
      sourceKey: detail.item.stableKey,
      rating: detail.item.rating ?? 'unknown',
      characters: [
        for (final character in detail.characterPrompts)
          QuickTagCloudRelayCharacter(
            label: character.label,
            positive: character.prompt,
            negative: character.negativePrompt,
          ),
      ],
    );
    return _changeBlocks(planId, (blocks) {
      if (!block.allowedBy(
        ref.read(quickTagCloudRelayAllowedRatingsProvider),
      )) {
        throw StateError('Source is locked by current rating settings');
      }
      if (blocks.any((item) => item.sourceKey == block.sourceKey)) {
        return blocks;
      }
      return [...blocks, block];
    });
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/datasources/gallery_data_source.dart';
import '../../core/database/datasources/gallery_vibe_family_repository.dart';
import '../../data/models/vibe/vibe_family.dart';
import '../../data/services/vibe_style/vibe_style_analysis_service.dart';
import '../../data/services/vibe_style/vibe_style_worker.dart';
import 'local_gallery_vibe_provider.dart';

final vibeFamilyProvider =
    ChangeNotifierProvider.autoDispose<VibeFamilyController>((ref) {
      final gallery = GalleryDataSource();
      return VibeFamilyController(
        gallery.vibeFamilies,
        initializeGallery: () =>
            ref.read(localGalleryVibeProvider.notifier).initialize(),
      );
    });

class VibeFamilyController extends ChangeNotifier {
  VibeFamilyController(this.repository, {this.initializeGallery})
    : _analysis = VibeStyleAnalysisService(repository);
  final GalleryVibeFamilyRepository repository;
  final Future<void> Function()? initializeGallery;
  final VibeStyleAnalysisService _analysis;
  List<VibeFamilySummary> summaries = [];
  VibeFamilyState decisions = const VibeFamilyState();
  VibeStyleAnalysis? result;
  VibeStyleProgress? progress;
  bool loading = true, analyzing = false, saving = false, cancelled = false;
  String? error;
  bool _alive = true;
  Future<void>? _initialization;

  List<VibeStyleMatch> get suggestions =>
      result?.matches
          .where((m) => !decisions.excludes(m.left, m.right))
          .toList() ??
      [];

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      error = null;
      await initializeGallery?.call();
      await repository.initialize();
      await _reload();
    } catch (_) {
      error = 'load';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _reload() async {
    final next = await repository.load();
    final codes = await repository.summaries();
    if (!_alive) return;
    decisions = next;
    summaries = codes;
  }

  Future<void> retry() {
    _initialization = null;
    loading = true;
    _notify();
    return initialize();
  }

  Future<void> analyze() async {
    if (analyzing || saving || loading) return;
    analyzing = true;
    cancelled = false;
    error = null;
    progress = null;
    _notify();
    try {
      final next = await _analysis.analyze(
        onProgress: (value) {
          progress = value;
          _notify();
        },
      );
      if (_alive) result = next;
    } on VibeStyleCancelled {
      cancelled = true;
    } catch (_) {
      error = 'analysis';
    } finally {
      analyzing = false;
      progress = null;
      _notify();
    }
  }

  void cancel() => _analysis.cancel();
  Future<void> merge(Set<String> hashes, String name) =>
      _save(() => repository.merge(hashes, name));
  Future<void> separate(String a, String b) =>
      _save(() => repository.separate(a, b));
  Future<void> split(String hash) => _save(() => repository.split(hash));
  Future<void> rename(String id, String name) =>
      _save(() => repository.rename(id, name));
  Future<void> restore(String pair) =>
      _save(() => repository.restorePair(pair));
  Future<void> _save(Future<void> Function() operation) async {
    if (saving) return;
    saving = true;
    error = null;
    _notify();
    try {
      await operation();
      await _reload();
    } catch (e) {
      error = e.toString().contains('separation_conflict')
          ? 'conflict'
          : 'save';
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (_alive) notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    _analysis.cancel();
    super.dispose();
  }
}

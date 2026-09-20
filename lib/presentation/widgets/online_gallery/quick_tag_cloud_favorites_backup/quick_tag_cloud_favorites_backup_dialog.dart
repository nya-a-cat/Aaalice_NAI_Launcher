import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/file_export_service.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_community_service.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_codec.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_plan.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_resolver.dart';
import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_store.dart';
import '../../../providers/online_gallery_local_favorites_provider.dart';
import '../../../providers/online_gallery_provider.dart';
import '../../../providers/quick_tag_cloud_gallery_provider.dart';
import '../../common/themed_confirm_dialog.dart';
import 'quick_tag_cloud_favorites_backup_files.dart';
import 'quick_tag_cloud_favorites_backup_input.dart';
import 'quick_tag_cloud_favorites_backup_preview.dart';

Future<void> showQuickTagCloudFavoritesBackup(BuildContext context) =>
    showDialog<void>(context: context,
      builder: (_) => const QuickTagCloudFavoritesBackupDialog());

class QuickTagCloudFavoritesBackupDialog extends ConsumerStatefulWidget {
  const QuickTagCloudFavoritesBackupDialog({super.key});
  @override
  ConsumerState<QuickTagCloudFavoritesBackupDialog> createState() =>
      _QuickTagCloudFavoritesBackupDialogState();
}

class _QuickTagCloudFavoritesBackupDialogState
    extends ConsumerState<QuickTagCloudFavoritesBackupDialog> {
  final _text = TextEditingController();
  late final QuickTagCloudFavoritesBackupStore _store;
  QuickTagCloudBackupPreview? _preview;
  QuickTagCloudBackupPlan? _mergePlan, _replacePlan;
  CancelToken? _cancel;
  String? _error;
  bool _busy = false, _saving = false, _replace = false, _restored = false;

  @override
  void initState() {
    super.initState();
    _store = QuickTagCloudFavoritesBackupStore(
      ref.read(localStorageServiceProvider),
      ref.read(onlineGalleryLocalFavoritesRepositoryProvider),
    );
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _restored = false; });
    try {
      await action();
    } on QuickTagCloudBackupException catch (error) {
      if (mounted) setState(() => _error = error.code);
    } on DioException catch (error) {
      if (mounted && !CancelToken.isCancel(error)) {
        setState(() => _error = 'failed');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    } finally {
      if (mounted) setState(() { _busy = false; _saving = false; _cancel = null; });
    }
  }

  Future<void> _importFile() => _run(() async {
    final source = await pickQuickTagCloudBackupFile();
    if (source != null && mounted) {
      _text.text = source;
      setState(() => _preview = null);
    }
  });

  Future<void> _prepare() => _run(() async {
    setState(() => _preview = null);
    final filter = ref.read(quickTagCloudFilterProvider);
    final community = QuickTagCloudCommunityService();
    final resolver = QuickTagCloudBackupResolver(
      ref.read(quickTagCloudGallerySourceAdapterProvider),
      allowNsfw: filter.allowNsfw, allowR18g: filter.allowR18g,
      communityService: community,
    );
    final token = CancelToken();
    _cancel = token;
    late final QuickTagCloudBackupPreview preview;
    try {
      preview = await _store.prepare(_text.text,
        resolve: resolver.resolve, resolveCommunity: resolver.resolveCommunity,
        cancelToken: token);
    } finally {
      community.dispose();
    }
    QuickTagCloudBackupPlan? merge, replace;
    try { merge = preview.plan(replace: false); }
    on QuickTagCloudBackupException catch (e) {
      if (e.code != 'tooLarge') rethrow;
    }
    try { replace = preview.plan(replace: true); }
    on QuickTagCloudBackupException catch (e) {
      if (e.code != 'tooLarge') rethrow;
    }
    if (merge == null && replace == null) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    if (mounted) setState(() {
      _preview = preview; _mergePlan = merge; _replacePlan = replace;
      _replace = merge == null;
    });
  });

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null || _busy) return;
    if (_replace) {
      final confirmed = await ThemedConfirmDialog.show(
        context: context, title: context.l10n.quickTagBackupReplace,
        content: context.l10n.quickTagBackupReplaceWarning,
        confirmText: context.l10n.quickTagBackupReplace,
        type: ThemedConfirmDialogType.danger,
      );
      if (!mounted || !confirmed) return;
    }
    await _run(() async {
      setState(() => _saving = true);
      try {
        await _store.commit(preview, replace: _replace);
      } finally {
        ref.invalidate(onlineGalleryLocalFavoritesProvider);
      }
      if (mounted) setState(() { _restored = true; _preview = null; });
    });
  }

  Future<void> _export({required bool transfer}) => _run(() async {
    final snapshot = await _store.snapshot();
    if (!mounted) return;
    if (transfer) {
      await Clipboard.setData(ClipboardData(
        text: QuickTagCloudFavoritesBackupCodec.transfer(snapshot.current)));
    } else {
      await FileExportService.saveText(
        text: QuickTagCloudFavoritesBackupCodec.encode(snapshot.current),
        fileName: 'novelai-tag-favorites.json',
        dialogTitle: context.l10n.quickTagBackupExportJson,
        mimeType: 'application/json', allowedExtensions: ['json'],
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(l.quickTagBackupTitle),
        content: _buildContent(context),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l.common_close),
          ),
          if (_preview != null)
            FilledButton(
              onPressed: _busy ? null : _commit,
              child: Text(
                _replace ? l.quickTagBackupReplace : l.quickTagBackupMerge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l = context.l10n;
    final preview = _preview;
    final plan = preview == null ? null : (_replace ? _replacePlan : _mergePlan);
    final error = switch (_error) {
      'tooLarge' => l.quickTagBackupTooLarge,
      'invalid' => l.quickTagBackupInvalid,
      'stale' => l.quickTagBackupStale,
      null => null,
      _ => l.quickTagBackupFailed,
    };
    return SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QuickTagCloudFavoritesBackupInput(
              controller: _text,
              busy: _busy,
              onChanged: () => setState(() => _preview = null),
              onImportFile: _importFile,
              onPrepare: _prepare,
              onCancel: !_saving && _cancel != null
                  ? () => _cancel?.cancel()
                  : null,
            ),
            if (plan != null && preview != null) ...[
              const SizedBox(height: 16),
              QuickTagCloudFavoritesBackupPreview(
                preview: preview,
                plan: plan,
                replace: _replace,
                mergeAvailable: _mergePlan != null,
                replaceAvailable: _replacePlan != null,
                busy: _busy,
                onReplaceChanged: (value) => setState(() => _replace = value),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_restored)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(l.quickTagBackupRestored),
              ),
            const SizedBox(height: 16),
            _buildExportActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildExportActions(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(
          onPressed: _busy ? null : () => _export(transfer: false),
          child: Text(l.quickTagBackupExportJson),
        ),
        TextButton(
          onPressed: _busy ? null : () => _export(transfer: true),
          child: Text(l.quickTagBackupCopyTransfer),
        ),
      ],
    );
  }
}

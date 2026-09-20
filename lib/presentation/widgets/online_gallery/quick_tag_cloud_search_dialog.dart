import 'package:flutter/material.dart';

import '../../../data/datasources/remote/online_gallery/quick_tag_cloud_search_parser.dart';
import '../../../l10n/app_localizations.dart';

Future<String?> showQuickTagCloudSearch(
  BuildContext context, {
  String initialQuery = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _QuickTagCloudSearchDialog(initialQuery: initialQuery),
);

class _QuickTagCloudSearchDialog extends StatefulWidget {
  const _QuickTagCloudSearchDialog({required this.initialQuery});

  final String initialQuery;

  @override
  State<_QuickTagCloudSearchDialog> createState() =>
      _QuickTagCloudSearchDialogState();
}

class _QuickTagCloudSearchDialogState extends State<_QuickTagCloudSearchDialog> {
  late final _query = TextEditingController(text: widget.initialQuery);
  final _value = TextEditingController();
  String _field = 'prompt';
  bool _excluded = false;
  String? _error;

  bool get _canExclude => quickTagCloudTextFields.contains(_field);

  @override
  void dispose() {
    _query.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.onlineGallery_codexAdvancedSearch),
      scrollable: true,
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.onlineGallery_codexSearchHelp),
            const SizedBox(height: 16),
            _buildFieldSelector(l10n),
            const SizedBox(height: 12),
            _buildValueInput(l10n),
            CheckboxListTile(
              value: _excluded,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.onlineGallery_codexSearchExclude),
              onChanged: _canExclude
                  ? (value) => setState(() => _excluded = value ?? false)
                  : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('quick-tag-cloud-search-add-condition'),
                onPressed: _addCondition,
                icon: const Icon(Icons.add),
                label: Text(l10n.onlineGallery_codexSearchAddCondition),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('quick-tag-cloud-search-expression'),
              controller: _query,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.onlineGallery_codexSearchQuery,
                errorText: _error,
                errorMaxLines: 5,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('quick-tag-cloud-search-submit'),
          onPressed: _submit,
          icon: const Icon(Icons.search),
          label: Text(l10n.common_search),
        ),
      ],
    );
  }

  Widget _buildFieldSelector(AppLocalizations l10n) {
    final fields = <String, String>{
      'default': l10n.onlineGallery_all,
      'title': l10n.onlineGallery_codexSearchTitle,
      'prompt': l10n.onlineGallery_codexPrompt,
      'negative': l10n.onlineGallery_codexNegativePrompt,
      'note': l10n.onlineGallery_codexNote,
      'raw': l10n.onlineGallery_tags,
      'author': l10n.onlineGallery_codexAuthor,
      'codex': l10n.onlineGallery_codexLabel,
      'type': l10n.onlineGallery_codexSearchType,
      'path': l10n.onlineGallery_codexCategory,
      'has': l10n.onlineGallery_codexMediaFilter,
      'fav': l10n.onlineGallery_favorites,
      'directory': l10n.onlineGallery_codexSearchDirectory,
    };
    return DropdownButtonFormField<String>(
      key: const ValueKey('quick-tag-cloud-search-field'),
      initialValue: _field,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.onlineGallery_codexSearchField),
      items: [
        for (final entry in fields.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (field) => setState(() {
        _field = field ?? 'prompt';
        _value.clear();
        if (!_canExclude) _excluded = false;
      }),
    );
  }

  Widget _buildValueInput(AppLocalizations l10n) {
    final options = switch (_field) {
      'has' => {'image': l10n.onlineGallery_codexWithImages,
                'noimage': l10n.onlineGallery_codexWithoutImages},
      'fav' => {'true': l10n.onlineGallery_favorited,
                'false': l10n.onlineGallery_unfavorited},
      'type' => {'codex': 'codex', 'string': 'string',
                'composition': 'composition', 'pack': 'pack'},
      _ => <String, String>{},
    };
    if (options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        key: ValueKey('quick-tag-cloud-search-value-$_field'),
        initialValue: options.containsKey(_value.text) ? _value.text : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: l10n.onlineGallery_codexSearchValue),
        items: [for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) => setState(() => _value.text = value ?? ''),
      );
    }
    return TextField(
      key: const ValueKey('quick-tag-cloud-search-value'),
      controller: _value,
      decoration: InputDecoration(
        labelText: l10n.onlineGallery_codexSearchValue,
        hintText: _field == 'directory' ? 'codex:directory' : null,
      ),
      onSubmitted: (_) => _addCondition(),
    );
  }

  void _addCondition() {
    final value = _value.text.trim();
    final separator = value.indexOf(':');
    final filter = QuickTagCloudSearchFilter(
      field: _field,
      value: _field == 'directory' && separator >= 0
          ? value.substring(separator + 1) : value,
      codexId: _field == 'directory' && separator >= 0
          ? value.substring(0, separator) : '',
      excluded: _excluded,
    );
    final candidate = [_query.text.trim(), filter.serialize()]
        .where((part) => part.isNotEmpty).join(' ');
    if (!_validate(candidate)) return;
    _query.text = candidate;
    _value.clear();
    setState(() {});
  }

  bool _validate(String query) {
    final plan = QuickTagCloudSearchParser.parse(query);
    if (!plan.hasErrors) {
      setState(() => _error = null);
      return true;
    }
    final values = plan.issues.map((issue) => issue.value)
        .where((value) => value.isNotEmpty).toSet().join(', ');
    setState(() => _error = [
      AppLocalizations.of(context)!.onlineGallery_codexSearchInvalid,
      if (values.isNotEmpty) values,
    ].join('\n'));
    return false;
  }

  void _submit() {
    final query = _query.text.trim();
    if (_validate(query)) Navigator.pop(context, query);
  }
}

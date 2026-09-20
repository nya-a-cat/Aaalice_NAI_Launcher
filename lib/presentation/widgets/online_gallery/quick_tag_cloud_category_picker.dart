import 'package:flutter/material.dart';

import '../../../data/models/online_gallery/quick_tag_cloud_codex.dart';
import '../../../l10n/app_localizations.dart';

Future<List<String>?> showQuickTagCloudCategoryPicker(
  BuildContext context,
  QuickTagCloudCodex codex,
  List<String> selectedPath,
) async {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.onlineGallery_codexCategory),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 600),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                selected: selectedPath.isEmpty,
                leading: const Icon(Icons.apps),
                title: Text(l10n.onlineGallery_codexAllCategories),
                onTap: () => Navigator.pop(dialogContext, <String>[]),
              ),
              ..._categoryTiles(
                dialogContext,
                codex.tree,
                const [],
                selectedPath,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

List<Widget> _categoryTiles(
  BuildContext context,
  List<dynamic> nodes,
  List<String> parent,
  List<String> selected,
) {
  return [
    for (final rawNode in nodes.whereType<Map>())
      _categoryTile(
        context,
        Map<String, dynamic>.from(rawNode),
        parent,
        selected,
      ),
  ];
}

Widget _categoryTile(
  BuildContext context,
  Map<String, dynamic> node,
  List<String> parent,
  List<String> selected,
) {
  final name = node['name']?.toString() ?? '';
  final path = [...parent, name];
  final children = node['children'] is List
      ? List<dynamic>.from(node['children'] as List)
      : const <dynamic>[];
  final title = Row(
    children: [
      Expanded(child: Text(name)),
      if (node['count'] != null)
        SizedBox(
          width: 56,
          child: Text(
            node['count'].toString(),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
  if (children.isEmpty) {
    return ListTile(
      selected: _samePath(path, selected),
      contentPadding: EdgeInsets.only(
        left: 16.0 + parent.length * 14,
        right: 16,
      ),
      title: title,
      trailing: const SizedBox.square(dimension: 24),
      onTap: () => Navigator.pop(context, path),
    );
  }
  return ExpansionTile(
    initiallyExpanded:
        selected.length >= path.length &&
        _samePath(path, selected.take(path.length).toList()),
    tilePadding: EdgeInsets.only(left: 16.0 + parent.length * 14, right: 16),
    title: InkWell(
      onTap: () => Navigator.pop(context, path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: title,
      ),
    ),
    children: _categoryTiles(context, children, path, selected),
  );
}

bool quickTagCloudContainsCategoryPath(List<dynamic> nodes, List<String> path) {
  var level = nodes;
  for (final part in path) {
    Map<String, dynamic>? match;
    for (final raw in level.whereType<Map>()) {
      final candidate = Map<String, dynamic>.from(raw);
      if (candidate['name']?.toString() == part) {
        match = candidate;
        break;
      }
    }
    if (match == null) return false;
    level = match['children'] is List
        ? List<dynamic>.from(match['children'] as List)
        : const [];
  }
  return true;
}

bool _samePath(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

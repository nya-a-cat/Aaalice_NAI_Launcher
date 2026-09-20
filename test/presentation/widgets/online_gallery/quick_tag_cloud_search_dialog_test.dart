import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/online_gallery/quick_tag_cloud_search_dialog.dart';

void main() {
  for (final width in [360.0, 700.0, 1180.0]) {
    testWidgets('builds a quoted field search at width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.reset);
      String? submitted;
      await tester.pumpWidget(_host(onSearch: (value) => submitted = value));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-tag-cloud-search-value')),
        'red hair',
      );
      await tester.tap(
        find.byKey(const ValueKey('quick-tag-cloud-search-add-condition')),
      );
      await tester.pumpAndSettle();
      final query = tester.widget<TextField>(
        find.byKey(const ValueKey('quick-tag-cloud-search-expression')),
      );
      expect(query.controller!.text, 'prompt:"red hair"');
      await tester.tap(
        find.byKey(const ValueKey('quick-tag-cloud-search-submit')),
      );
      await tester.pumpAndSettle();
      expect(submitted, 'prompt:"red hair"');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid expression remains visible until repaired', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(_host(onSearch: (value) => submitted = value));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final expression = find.byKey(
      const ValueKey('quick-tag-cloud-search-expression'),
    );
    await tester.enterText(expression, 'prompt:"unfinished');
    await tester.tap(
      find.byKey(const ValueKey('quick-tag-cloud-search-submit')),
    );
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(
      tester.widget<TextField>(expression).decoration!.errorText,
      isNotNull,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(expression, 'has:image -note:watermark');
    await tester.tap(
      find.byKey(const ValueKey('quick-tag-cloud-search-submit')),
    );
    await tester.pumpAndSettle();
    expect(submitted, 'has:image -note:watermark');
    expect(tester.takeException(), isNull);
  });
}

Widget _host({required ValueChanged<String> onSearch}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await showQuickTagCloudSearch(context);
          if (result != null) onSearch(result);
        },
        child: const Text('Open'),
      ),
    ),
  ),
);

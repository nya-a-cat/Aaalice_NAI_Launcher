import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nai_launcher/data/models/online_gallery/quick_tag_cloud_relay.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/quick_tag_cloud_relay_provider.dart';
import 'package:nai_launcher/presentation/widgets/online_gallery/quick_tag_cloud_relay/quick_tag_cloud_relay_dialog.dart';
import 'package:nai_launcher/presentation/widgets/online_gallery/quick_tag_cloud_relay/relay_output_panel.dart';

class _RelayController extends QuickTagCloudRelayController {
  _RelayController(this.document);
  final QuickTagCloudRelayDocument document;

  @override
  QuickTagCloudRelayState build() => QuickTagCloudRelayState(document: document);

  @override
  Future<void> setFormat(QuickTagCloudRelayFormat format) async {
    state = QuickTagCloudRelayState(document: state.document.copyWith(format: format));
  }
}

Widget _scope(QuickTagCloudRelayDocument document, Widget child) => ProviderScope(
  overrides: [
    quickTagCloudRelayProvider.overrideWith(() => _RelayController(document)),
    quickTagCloudRelayAllowedRatingsProvider.overrideWithValue({'g', 's'}),
  ],
  child: child,
);

void main() {
  testWidgets('relay send closes enclosing compact popup before changing branch',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 850);
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/gallery', routes: [
      ShellRoute(builder: (context, state, child) => child, routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('generation'))),
        GoRoute(path: '/gallery', builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context, useRootNavigator: true,
              builder: (context) => TextButton(
                onPressed: () => showQuickTagCloudRelay(context),
                child: const Text('open relay'),
              ),
            ),
            child: const Text('source filter'),
          ),
        )),
      ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(_scope(QuickTagCloudRelayDocument.empty(),
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    ));
    await tester.tap(find.text('source filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open relay'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.widget<QuickTagCloudRelayPanel>(find.byType(QuickTagCloudRelayPanel)).onSent();
    await tester.pumpAndSettle();
    expect(find.text('generation'), findsOneWidget);
    expect(find.text('open relay'), findsNothing);
    expect(find.byType(QuickTagCloudRelayPanel), findsNothing);
    expect(find.byType(ModalBarrier), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid SD preview remains editable and can switch to NAI',
      (tester) async {
    final nested = '${'{[' * 65}cat${']}' * 65}';
    final document = QuickTagCloudRelayDocument(
      plans: [QuickTagCloudRelayPlan(id: 'plan', name: '', blocks: [
        QuickTagCloudRelayBlock(id: 'block', title: '', positive: nested),
      ])],
      activePlanId: 'plan', format: QuickTagCloudRelayFormat.sd,
    );
    await tester.pumpWidget(_scope(document, MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: RelayOutputPanel(onSent: () {}))),
    )));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Fill generation page');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(DropdownButton<QuickTagCloudRelayFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NAI').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

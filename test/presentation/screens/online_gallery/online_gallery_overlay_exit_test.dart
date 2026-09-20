import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/screens/online_gallery/online_gallery_overlay_exit.dart';

void main() {
  testWidgets('closes only the two captured gallery overlays', (tester) async {
    VoidCallback? leaveDetail;
    var leaves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (unrelatedContext) => AlertDialog(
                  title: const Text('Unrelated dialog'),
                  actions: [
                    TextButton(
                      child: const Text('Community'),
                      onPressed: () => showDialog<void>(
                        context: unrelatedContext,
                        builder: (communityContext) {
                          final leaveCommunity = galleryOwnedOverlayExit(
                            communityContext,
                          );
                          return AlertDialog(
                            title: const Text('Community dialog'),
                            actions: [
                              TextButton(
                                child: const Text('Detail'),
                                onPressed: () => showDialog<void>(
                                  context: communityContext,
                                  builder: (detailContext) {
                                    leaveDetail = galleryOwnedOverlayExit(
                                      detailContext,
                                      onExit: () {
                                        leaves++;
                                        leaveCommunity();
                                      },
                                    );
                                    return AlertDialog(
                                      title: const Text('Detail dialog'),
                                      actions: [
                                        TextButton(
                                          onPressed: leaveDetail,
                                          child: const Text('Navigate'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    for (final label in ['Open', 'Community', 'Detail', 'Navigate']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(find.text('Unrelated dialog'), findsOneWidget);
    expect(find.text('Community dialog'), findsNothing);
    expect(find.text('Detail dialog'), findsNothing);
    expect(leaves, 1);
    leaveDetail!();
    await tester.pumpAndSettle();
    expect(leaves, 1);
    expect(find.text('Unrelated dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page context cannot remove a page route', (tester) async {
    var leaves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: galleryOwnedOverlayExit(
                context,
                onExit: () => leaves++,
              ),
              child: const Text('Stay on page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Stay on page'));
    await tester.pumpAndSettle();
    expect(leaves, 0);
    expect(find.text('Stay on page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

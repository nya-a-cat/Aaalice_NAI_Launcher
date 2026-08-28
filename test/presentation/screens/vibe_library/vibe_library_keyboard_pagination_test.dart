import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/providers/vibe_library_category_provider.dart';
import 'package:nai_launcher/presentation/providers/vibe_library_provider.dart';
import 'package:nai_launcher/presentation/providers/vibe_library_selection_provider.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/vibe_library_commands.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/vibe_library_screen_controller.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/vibe_library_workspace.dart';

void main() {
  testWidgets('saved Vibe pages respond to left and right arrow keys', (
    tester,
  ) async {
    final entries = List.generate(
      3,
      (index) => VibeLibraryEntry(
        id: 'vibe-$index',
        name: 'Vibe $index',
        vibeDisplayName: 'Vibe $index',
        vibeEncoding: 'encoded-$index',
        createdAt: DateTime(2025, 1, index + 1),
      ),
    );
    final state = VibeLibraryState(
      entries: entries,
      currentPage: 1,
      pageSize: 1,
    );
    final controller = VibeLibraryScreenController(onSearch: (_) async {});
    addTearDown(controller.dispose);
    final commands = <VibeLibraryCommand>[];

    await tester.binding.setSurfaceSize(const Size(1180, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vibeLibraryNotifierProvider.overrideWith(
            () => _TestVibeLibraryNotifier(state),
          ),
          vibeLibrarySelectionNotifierProvider.overrideWith(
            _TestVibeLibrarySelectionNotifier.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: VibeLibraryWorkspace(
              libraryState: state,
              categoryState: const VibeLibraryCategoryState(),
              selectionState: const SelectionModeState(),
              currentModel: ImageModels.animeDiffusionV45Full,
              controller: controller,
              onCommand: commands.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(commands.whereType<PreviousPageCommand>(), hasLength(1));
    expect(commands.whereType<NextPageCommand>(), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

class _TestVibeLibraryNotifier extends VibeLibraryNotifier {
  _TestVibeLibraryNotifier(this.initialState);

  final VibeLibraryState initialState;

  @override
  VibeLibraryState build() => initialState;
}

class _TestVibeLibrarySelectionNotifier
    extends VibeLibrarySelectionNotifier {
  @override
  SelectionModeState build() => const SelectionModeState();
}

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/design_system_config.dart';
import 'package:cb_file_manager/ui/components/common/screen_scaffold.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop file surface uses a flat Fluent command surface',
      (tester) async {
    await tester.pumpWidget(
      fluent.FluentApp(
        home: ScreenScaffold(
          selectionState: const SelectionState(),
          body: const SizedBox(
            key: ValueKey<String>('desktop-file-surface-body'),
          ),
          isNetworkPath: false,
          onClearSelection: () {},
          showRemoveTagsDialog: (_) {},
          showManageAllTagsDialog: (_) {},
          showDeleteConfirmationDialog: (_) {},
          isDesktop: true,
          showAppBar: true,
          showSearchBar: false,
          searchBar: const Text('Search'),
          pathNavigationBar: const Text('Path'),
          actions: const [Text('Action')],
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('desktop-file-surface-body')),
        findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    if (DesignSystemConfig.enableLegacyMaterialDesktopShell) {
      expect(find.byType(Scaffold), findsOneWidget);
    } else {
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(Scaffold), findsNothing);
    }
  });
}

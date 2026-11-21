import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/design_system/primitives/cb_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'CB modal uses the same desktop shell as Dialog in $brightness',
      (tester) async {
        final theme = createDesktopAcrylicMaterialBridgeTheme(
          baseTheme: brightness == Brightness.dark
              ? ThemeConfig.getDarkTheme()
              : ThemeConfig.getLightTheme(),
          brightness: brightness,
          strength: 1.25,
          preferTransparentBackdrop: true,
        );
        Future<Material> render(Widget dialog) async {
          await tester.pumpWidget(MaterialApp(theme: theme, home: dialog));
          await tester.pumpAndSettle();
          return tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Material),
                )
                .first,
          );
        }

        final reference = await render(
          const Dialog(child: Text('Existing modal')),
        );
        final actual = await render(
          const CbDialog(title: 'SSH', content: Text('Connection')),
        );
        expect(actual.color, reference.color);
        expect(actual.shape, reference.shape);
        expect(actual.elevation, reference.elevation);
        expect(actual.shadowColor, reference.shadowColor);
        expect(actual.surfaceTintColor, reference.surfaceTintColor);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

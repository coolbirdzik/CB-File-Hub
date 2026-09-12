import 'package:cb_file_manager/design_system/cb_theme_builder.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Breadcrumb Overflow', () {
    testWidgets(
      'breadcrumb does not overflow a deep sandbox path at CI-observed widths',
      (tester) async {
        // Mirrors a real CI-only failure: a GitHub Actions Windows runner's
        // longer username ("RUNNER~1") plus a descriptive temp-dir name pushed
        // this 7-segment path past the width _estimatedNaturalWidth predicted,
        // throwing a RenderFlex overflow that never reproduced locally because
        // the estimate measured labels with the default font instead of the
        // theme's actual font family. Real font metrics only apply on a real
        // device, so this must run as an integration test, not a widget test.
        const parts = [
          'C:',
          'Users',
          'RUNNER~1',
          'AppData',
          'Local',
          'Temp',
          'cb_e2e_newfolder_3e850208',
        ];
        final segments = [
          for (var i = 0; i < parts.length; i++)
            BreadcrumbSegment(
              label: parts[i],
              icon: i == 0 ? PhosphorIconsLight.hardDrive : null,
            ),
        ];

        for (final width in [636.0, 500.0, 400.0, 300.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: CbThemeBuilder.build(
                brightness: Brightness.light,
                accent: Colors.blue,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    height: 32,
                    child: BreadcrumbAddressBar(segments: segments),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'width $width');
        }
      },
    );
  });
}

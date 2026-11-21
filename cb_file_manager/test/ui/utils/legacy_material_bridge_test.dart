// The legacy `package:flutter/material.dart` import is deliberate: it is what
// flutter_markdown_plus, media_kit_video, flutter_colorpicker and
// window_manager still use, and the bridge exists for them.
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cb_file_manager/ui/utils/legacy_material_bridge.dart';

class _Seen {
  Brightness? brightness;
  String? copyLabel;
}

Widget _app(_Seen seen, {required bool bridged}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    builder: (context, child) => bridged
        ? LegacyMaterialBridge(child: child ?? const SizedBox.shrink())
        : child ?? const SizedBox.shrink(),
    home: Builder(
      builder: (context) {
        seen.brightness = legacy.Theme.of(context).brightness;
        seen.copyLabel = legacy.Localizations.of<legacy.MaterialLocalizations>(
          context,
          legacy.MaterialLocalizations,
        )?.copyButtonLabel;
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets(
    'legacy widgets see the app theme and localizations when bridged',
    (tester) async {
      final seen = _Seen();
      await tester.pumpWidget(_app(seen, bridged: true));

      expect(seen.brightness, Brightness.dark);
      expect(seen.copyLabel, 'Copy');
    },
  );

  testWidgets(
    'without the bridge legacy widgets get a light theme and no localizations',
    (tester) async {
      final seen = _Seen();
      await tester.pumpWidget(_app(seen, bridged: false));

      expect(seen.brightness, Brightness.light);
      expect(seen.copyLabel, isNull);
    },
  );
}

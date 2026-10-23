import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/components/common/column_chooser_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<({List<ColumnVisibility> applied, List<Set<String>> extras})> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    ColumnVisibility initial = const ColumnVisibility(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final applied = <ColumnVisibility>[];
    final extras = <Set<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: ColumnChooserDialog(
            initial: initial,
            onApply: applied.add,
            additionalColumns: const {'seeds': 'Seeds'},
            onApplyAdditionalColumns: extras.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return (applied: applied, extras: extras);
  }

  testWidgets('ticking columns shows them in order and applies', (
    tester,
  ) async {
    final result = await pump(tester);

    await tester.tap(find.byKey(const ValueKey('column-dialog-path')));
    await tester.tap(find.byKey(const ValueKey('column-dialog-extra-seeds')));
    await tester.pump();
    expect(find.byKey(const ValueKey('column-shown-path')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('column-shown-extra-seeds')),
      findsOneWidget,
    );

    // Hiding from the shown list unticks it.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('column-shown-size')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('column-shown-size')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('column-dialog-apply')));
    await tester.pump();
    final applied = result.applied.single;
    expect(applied.path, isTrue);
    expect(applied.size, isFalse);
    expect(applied.visibleColumns.last, DetailsColumn.path);
    expect(result.extras.single, {'seeds'});
  });

  testWidgets('search filters the available columns', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('column-dialog-search')),
        matching: find.byType(EditableText),
      ),
      'folder',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('column-dialog-parentFolder')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('column-dialog-size')), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('column-dialog-search')),
        matching: find.byType(EditableText),
      ),
      'zzzz-no-such-column',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('column-dialog-parentFolder')),
      findsNothing,
    );
    // Windows may still be listing its properties.
    if (!Platform.isWindows) {
      expect(find.text('No matching columns'), findsOneWidget);
    }
  });

  testWidgets('narrow screens split the lists into tabs', (tester) async {
    await pump(tester, size: const Size(400, 800));
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Shown (4)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

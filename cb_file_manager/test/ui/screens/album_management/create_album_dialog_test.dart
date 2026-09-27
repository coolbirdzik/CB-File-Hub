import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/screens/album_management/create_album_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('image source dialog lays out a populated directory list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const sourcePath = r'C:\Pictures\Source';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: CbThemeBuilder.build(
          brightness: Brightness.light,
          accent: Colors.teal,
        ),
        home: CreateAlbumDialog(
          sourceMode: true,
          directoryPicker: () async => sourcePath,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CreateAlbumDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-image-source-directory')));
    await tester.pump();

    expect(find.text(sourcePath), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

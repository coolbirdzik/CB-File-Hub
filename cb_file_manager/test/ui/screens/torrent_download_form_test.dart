import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_download_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_options_window_app.dart';

void main() {
  final destination = p.join(Directory.systemTemp.path, 'payload');
  testWidgets(
    'standalone form submits using Enter without popping the host route',
    (tester) async {
      TorrentDownloadOptions? result;
      var ready = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: CbThemeBuilder.build(
            brightness: Brightness.light,
            accent: Colors.teal,
          ),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TorrentDownloadDialog(
            name: 'Standalone torrent',
            initialDestination: destination,
            startImmediately: false,
            onComplete: (value) => result = value,
            onReady: () => ready++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('torrent-download-destination')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result!.destination, destination);
      expect(result!.startImmediately, isFalse);
      expect(
        find.byKey(const ValueKey('torrent-download-window-form')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(ready, 1);
    },
  );

  testWidgets('reused window retains appearance and paints each fresh form', (
    tester,
  ) async {
    var ready = 0;
    Future<void> render(TorrentDownloadRequest? request, int id) async {
      await tester.pumpWidget(
        TorrentOptionsWindowContent(
          request: request,
          requestId: id,
          onComplete: (_) {},
          onReady: () => ready++,
        ),
      );
      await tester.pumpAndSettle();
    }

    final request = TorrentDownloadRequest(
      name: 'First',
      initialDestination: destination,
      language: 'vi',
      dark: true,
      accent: Colors.teal.toARGB32(),
    );
    await render(request, 1);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('vi'));
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.themeAnimationDuration, Duration.zero);
    expect(ready, 1);

    await tester.enterText(
      find.byKey(const ValueKey('torrent-download-destination')),
      '$destination-edited',
    );
    await render(null, 1);
    final hidden = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(identical(hidden.theme, app.theme), isTrue);
    expect(hidden.locale, app.locale);
    expect(ready, 1);

    await render(request, 2);
    final reopened = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(identical(reopened.theme, app.theme), isTrue);
    expect(ready, 2);
    final field = tester.widget<CbTextField>(
      find.byKey(const ValueKey('torrent-download-destination')),
    );
    expect(field.controller!.text, destination);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom chrome moves, minimizes and cancels at minimum size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(540, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var drags = 0;
    var minimizes = 0;
    var closes = 0;
    TorrentDownloadOptions? result;
    await tester.pumpWidget(
      TorrentOptionsWindowContent(
        request: TorrentDownloadRequest(
          name: List.filled(12, 'Torrent with a long name').join(' '),
          initialDestination: destination,
          language: 'vi',
        ),
        requestId: 1,
        onReady: () {},
        onWindowDrag: () => drags++,
        onWindowMinimize: () => minimizes++,
        onComplete: (value) {
          closes++;
          result = value;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('torrent-window-drag')),
      const Offset(40, 0),
    );
    expect(drags, 1);
    await tester.tap(find.byKey(const ValueKey('torrent-window-minimize')));
    await tester.pumpAndSettle();
    expect(minimizes, 1);
    expect(closes, 0);
    final close = find.byKey(const ValueKey('torrent-window-close'));
    final button = tester.widget<CbButton>(close);
    expect(button.tooltip, 'Đóng');
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}

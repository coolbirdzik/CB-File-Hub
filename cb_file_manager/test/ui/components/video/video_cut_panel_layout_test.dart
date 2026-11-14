import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/media/lossless_cut_service.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_cut_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
    await (FontLoader('JetBrains Mono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')))
        .load();
    await (FontLoader('packages/phosphor_flutter/PhosphorLight')..addFont(
          rootBundle.load(
            'packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
          ),
        ))
        .load();
  });

  for (final size in [
    const Size(960, 600),
    const Size(720, 600),
    const Size(390, 600),
    const Size(320, 360),
  ]) {
    testWidgets('bounded editor keeps actions visible at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final panel = GlobalKey<VideoCutPanelState>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: CbThemeBuilder.build(
            brightness: Brightness.dark,
            accent: Colors.blue,
          ),
          home: Scaffold(
            backgroundColor: const Color(0xff101012),
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width - 24,
                    maxHeight: math.max(
                      0,
                      math.min(
                        math.max(280, size.height * .58),
                        size.height - 96,
                      ),
                    ),
                  ),
                  child: VideoCutPanel(
                    key: panel,
                    source: 'D:/Videos/Chuyến đi Đà Lạt 2026.mkv',
                    duration: const Duration(minutes: 12, seconds: 40),
                    position: () => const Duration(minutes: 2, seconds: 18),
                    onSeek: (_) {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final detected = await tester.runAsync(LosslessCutService.findExecutable);
      if (detected != null) {
        // Discovery checks filesystem candidates asynchronously between frames.
        for (
          var attempt = 0;
          attempt < 100 && find.text('Chọn FFmpeg').evaluate().isNotEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
        }
        expect(find.text('Chọn FFmpeg'), findsNothing);
      }
      panel.currentState!.markIn();
      await tester.pumpAndSettle();
      for (final editable in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        final painter = TextPainter(
          text: TextSpan(text: editable.controller.text, style: editable.style),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          painter.width,
          lessThanOrEqualTo(tester.getSize(find.byWidget(editable)).width + .5),
          reason: 'A complete timecode must fit without horizontal scrolling',
        );
        painter.dispose();
      }
      final export = find.text('Xuất lossless');
      expect(export, findsOneWidget);
      expect(tester.getRect(export).bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
      if (size.width >= 720) {
        expect(
          tester.getSize(find.byType(VideoCutPanel)).height,
          lessThan(300),
        );
      }

      Future<void> capture(String suffix) async {
        final folder = Platform.environment['CB_CUT_PREVIEW_DIR'];
        if (folder == null) return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(folder).create(recursive: true);
          await File(
            '$folder/cut-${size.width.toInt()}-$suffix.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('compact');
      await tester.tap(find.text('Tùy chọn xuất'));
      await tester.pumpAndSettle();
      expect(find.text('Thời gian file'), findsOneWidget);
      expect(tester.getRect(export).bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
      await capture('options');
      await tester.tap(find.text('Tùy chọn xuất'));
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        await tester.ensureVisible(find.text('Thêm đoạn'));
        await tester.tap(find.text('Thêm đoạn'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Các đoạn sẽ xuất (3)'), findsOneWidget);
      final last = find.byKey(const ValueKey('cut-segment-2'));
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('batch');
    });
  }
}

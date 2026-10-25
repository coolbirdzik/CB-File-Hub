import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/config/app_ui_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() {
    // Alias bundled font bytes to exercise every theme mapping without HTTP.
    // The visual identity of the downloaded font is outside this test's scope.
    final bytes = File('assets/fonts/Inter-Regular.ttf').readAsBytesSync();
    final fontData = ByteData.sublistView(bytes);
    final manifest = <String, Object?>{
      for (final family in [
        'Roboto',
        'OpenSans',
        'NotoSans',
        'NunitoSans',
        'SourceSans3',
        'IBMPlexSans',
      ])
        for (final variant in [
          'Thin',
          'ExtraLight',
          'Light',
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
          'Black',
          'Italic',
          'MediumItalic',
        ])
          'test_fonts/$family-$variant.ttf': [
            {'asset': 'test_fonts/$family-$variant.ttf'},
          ],
    };
    GoogleFonts.config.allowRuntimeFetching = false;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      return key.startsWith('test_fonts/') ? fontData : null;
    });
  });

  tearDownAll(() {
    messenger.setMockMessageHandler('flutter/assets', null);
    GoogleFonts.config.allowRuntimeFetching = originalFetching;
  });

  for (final font in AppUiFont.values.where(
    (font) => font != AppUiFont.inter,
  )) {
    test(
      '${font.name} maps Flutter text themes and preserves typography',
      () async {
        final original = ThemeData.light().copyWith(
          appBarTheme: const AppBarThemeData(
            titleTextStyle: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          inputDecorationTheme: const InputDecorationThemeData(
            errorStyle: TextStyle(fontSize: 15, color: Colors.red),
          ),
        );
        final result = AppUiFontConfig.applyToTheme(original, font);
        await GoogleFonts.pendingFonts();

        expect(result.textTheme.bodyMedium!.fontFamily, isNotNull);
        expect(
          result.textTheme.bodyMedium!.fontFamily,
          isNot(original.textTheme.bodyMedium!.fontFamily),
        );
        for (final pair in [
          (original.textTheme.displayLarge!, result.textTheme.displayLarge!),
          (original.textTheme.bodyMedium!, result.textTheme.bodyMedium!),
          (original.textTheme.labelSmall!, result.textTheme.labelSmall!),
          (
            original.primaryTextTheme.titleMedium!,
            result.primaryTextTheme.titleMedium!,
          ),
          (
            original.appBarTheme.titleTextStyle!,
            result.appBarTheme.titleTextStyle!,
          ),
          (
            original.inputDecorationTheme.errorStyle!,
            result.inputDecorationTheme.errorStyle!,
          ),
        ]) {
          expect(pair.$2.fontSize, pair.$1.fontSize);
          expect(pair.$2.fontWeight, pair.$1.fontWeight);
          expect(pair.$2.color, pair.$1.color);
          expect(pair.$2.fontFamily, isNotNull);
        }
      },
    );
  }

  test('the bundled Inter theme is retained', () {
    final original = ThemeData.light();
    expect(
      AppUiFontConfig.applyToTheme(original, AppUiFont.inter),
      same(original),
    );
  });
}

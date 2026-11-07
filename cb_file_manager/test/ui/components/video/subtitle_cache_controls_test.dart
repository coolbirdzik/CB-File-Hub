import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_cache_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cache extends SubtitleCache {
  int entries = 2;
  bool fail = false;
  @override
  Future<SubtitleCacheStats> stats() async =>
      SubtitleCacheStats(entries, entries * 100);
  @override
  Future<void> clear({String? key}) async {
    if (fail) throw StateError('disk unavailable');
    entries = 0;
  }
}

void main() {
  Future<void> show(WidgetTester tester, _Cache cache) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SubtitleCacheControls(cache: cache)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('explains database reuse and clearing refreshes saved counts', (
    tester,
  ) async {
    final cache = _Cache();
    await show(tester, cache);
    expect(find.textContaining('saved in the app database'), findsOneWidget);
    expect(find.textContaining('Model downloads are kept'), findsOneWidget);
    expect(find.textContaining('2 saved versions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-clear-cache')));
    await tester.pumpAndSettle();
    expect(cache.entries, 0);
    expect(find.textContaining('0 saved versions'), findsOneWidget);
  });
  testWidgets('failed clearing stays visible and preserves counts', (
    tester,
  ) async {
    final cache = _Cache()..fail = true;
    await show(tester, cache);
    await tester.tap(find.byKey(const ValueKey('ai-subtitle-clear-cache')));
    await tester.pumpAndSettle();
    expect(cache.entries, 2);
    expect(find.textContaining('disk unavailable'), findsOneWidget);
  });
}

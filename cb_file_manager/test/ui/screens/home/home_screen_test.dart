import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/home_content_service.dart';
import 'package:cb_file_manager/services/media_library_updates.dart';
import 'package:cb_file_manager/ui/screens/home/home_media_card.dart';
import 'package:cb_file_manager/ui/screens/home/home_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Content extends HomeContentService {
  Future<List<String>> Function() recent = () async => [
    r'C:\Photos',
    r'D:\Projects',
  ];
  late final Completer<HomeMediaPreviews> previews = Completer();
  Future<HomeMediaPreviews> Function()? mediaLoader;

  @override
  Future<List<String>> loadRecentPaths() => recent();

  @override
  Future<HomeMediaPreviews> loadMediaPreviews(List<String> recentPaths) =>
      mediaLoader?.call() ?? previews.future;
}

void main() {
  late TabManagerBloc tabs;
  late DrawerCubit drawer;
  late _Content content;

  setUp(() {
    tabs = TabManagerBloc();
    drawer = DrawerCubit();
    content = _Content();
  });

  tearDown(() async {
    await tabs.close();
    await drawer.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 1100,
    bool reduced = false,
    bool vietnamese = false,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tabs.add(AddTab(path: '#home'));
    await tester.pump();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: tabs),
          BlocProvider.value(value: drawer),
        ],
        child: MaterialApp(
          theme: CbThemeBuilder.build(
            brightness: Brightness.light,
            accent: Colors.teal,
          ),
          locale: Locale(vietnamese ? 'vi' : 'en'),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: HomeScreen(
            tabId: tabs.state.activeTabId!,
            contentService: content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recent folders work while media previews are still loading', (
    tester,
  ) async {
    await mount(tester);
    expect(content.previews.isCompleted, isFalse);
    expect(find.byType(HomeMediaCard), findsNWidgets(2));
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, r'D:\Projects');
    expect(tabs.state.activeTab!.name, 'Projects');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library cards navigate in the Home tab and support keyboard activation',
    (tester) async {
      await mount(tester);
      final homeId = tabs.state.activeTabId;
      tabs.add(AddTab(path: r'C:\Other'));
      await tester.pumpAndSettle();
      final photo = find.byKey(const ValueKey('home-photos'));
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(
        tabs.state.tabs.firstWhere((tab) => tab.id == homeId).path,
        '#gallery',
      );
      expect(tabs.state.activeTab!.path, r'C:\Other');

      final video = find.byKey(const ValueKey('home-videos'));
      final node = Focus.of(
        tester.element(
          find
              .descendant(of: video, matching: find.byType(AnimatedScale))
              .first,
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tabs.state.tabs.firstWhere((tab) => tab.id == homeId).path,
        '#video',
      );
    },
  );

  testWidgets(
    'narrow Vietnamese layout supports large text and reduced motion',
    (tester) async {
      await mount(
        tester,
        width: 360,
        reduced: true,
        vietnamese: true,
        textScale: 1.5,
      );
      expect(find.text('Tiếp tục từ lần trước'), findsOneWidget);
      expect(find.byType(FadeTransition), findsNothing);
      final photos = tester.getRect(find.byKey(const ValueKey('home-photos')));
      final videos = tester.getRect(find.byKey(const ValueKey('home-videos')));
      expect(videos.top, greaterThan(photos.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed history can be retried and empty history has guidance', (
    tester,
  ) async {
    content.recent = () async => throw StateError('unavailable');
    await mount(tester);
    expect(find.text('Recent folders could not be loaded.'), findsOneWidget);
    content.recent = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Folders you visit will appear here.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late preview completion is safe after leaving Home', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    content.previews.complete(const HomeMediaPreviews());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'privacy change clears displayed previews before reload finishes',
    (tester) async {
      content.previews.complete(
        const HomeMediaPreviews(images: ['private.jpg']),
      );
      await mount(tester);
      final photos = find.byKey(const ValueKey('home-photos'));
      expect(tester.widget<HomeMediaCard>(photos).previews, ['private.jpg']);
      final reloaded = Completer<HomeMediaPreviews>();
      content.mediaLoader = () => reloaded.future;
      MediaLibraryUpdates.notifyChanged();
      await tester.pump();
      expect(tester.widget<HomeMediaCard>(photos).previews, isEmpty);
      reloaded.complete(const HomeMediaPreviews());
      await tester.pumpAndSettle();
      expect(tester.widget<HomeMediaCard>(photos).previews, isEmpty);
    },
  );

  testWidgets(
    'privacy change prevents an older preview request from restoring NSFW images',
    (tester) async {
      await mount(tester);
      content.mediaLoader = () async => const HomeMediaPreviews();
      MediaLibraryUpdates.notifyChanged();
      await tester.pumpAndSettle();
      content.previews.complete(
        const HomeMediaPreviews(images: ['stale-private.jpg']),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HomeMediaCard>(find.byKey(const ValueKey('home-photos')))
            .previews,
        isEmpty,
      );
    },
  );
}

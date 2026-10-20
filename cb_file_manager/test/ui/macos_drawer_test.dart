import 'package:cb_file_manager/config/fluent_theme_config.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/ui/drawer.dart';
import 'package:cb_file_manager/services/filesystem/macos_user_folders_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _DrawerStateFixture extends DrawerCubit {
  void showFavorites(List<MacosUserFolder> folders) => emit(
    state.copyWith(
      macosUserFolders: folders,
      pinnedPaths: [
        ...folders.map((folder) => folder.path),
        '/work/My Project',
      ],
      isPinnedExpanded: true,
    ),
  );

  @override
  Future<void> togglePinnedPath(String path) async => emit(
    state.copyWith(
      pinnedPaths: state.pinnedPaths.where((value) => value != path).toList(),
    ),
  );

  @override
  Future<void> setActiveTab(String? tabId) async {}

  @override
  Future<void> setStorageExpanded(bool isExpanded) async {
    emit(state.copyWith(isStorageExpanded: isExpanded));
  }
}

Widget _drawerHost(
  TabManagerBloc tabs,
  DrawerCubit drawer,
  ValueChanged<bool> onPinChanged,
) => fluent.FluentApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizationsDelegate()],
  theme: FluentThemeConfig.getTheme(AppThemeType.light),
  home: Theme(
    data: ThemeConfig.getLightTheme(),
    child: MultiBlocProvider(
      providers: [
        BlocProvider<TabManagerBloc>.value(value: tabs),
        BlocProvider<DrawerCubit>.value(value: drawer),
      ],
      child: Builder(
        builder: (context) => Align(
          alignment: Alignment.centerLeft,
          child: CBDrawer(
            context,
            isPinned: true,
            onPinStateChanged: onPinChanged,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'Finder favorites navigate in the current tab and allow removal',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'CB File Hub',
        packageName: 'cb.file.hub',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final tabs = TabManagerBloc()..add(AddTab(path: '#home', name: 'Home'));
      final drawer = _DrawerStateFixture()
        ..showFavorites(const [
          MacosUserFolder(
            kind: MacosUserFolderKind.applications,
            path: '/Applications',
          ),
          MacosUserFolder(
            kind: MacosUserFolderKind.downloads,
            path: '/Users/demo/Downloads',
          ),
          MacosUserFolder(
            kind: MacosUserFolderKind.documents,
            path: '/Volumes/Work/My Documents',
          ),
        ]);
      addTearDown(tabs.close);
      await tester.pumpWidget(_drawerHost(tabs, drawer, (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('My Project'), findsOneWidget);
      final tabId = tabs.state.activeTab!.id;
      for (final (label, path) in [
        ('Downloads', '/Users/demo/Downloads'),
        ('Applications', '/Applications'),
        ('Documents', '/Volumes/Work/My Documents'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tabs.state.activeTab!.path, path);
        expect(tabs.state.activeTab!.name, label);
        expect(tabs.state.activeTab!.id, tabId);
        expect(tabs.state.tabs.length, 1);
      }
      final row = find
          .ancestor(
            of: find.text('Applications'),
            matching: find.byType(fluent.HoverButton),
          )
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(fluent.IconButton)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Applications'), findsNothing);
      expect(find.text('Downloads'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await drawer.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('macOS sidebar navigates and pins through rounded glass', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'CB File Hub',
      packageName: 'cb.file.hub',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final tabs = TabManagerBloc();
    final drawer = _DrawerStateFixture();
    addTearDown(tabs.close);
    final pinChanges = <bool>[];
    await tester.pumpWidget(_drawerHost(tabs, drawer, pinChanges.add));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('fluent-drawer-acrylic'));
    expect(tester.getSize(find.byType(CBDrawer)).width, 260);
    expect(tester.getTopLeft(surface).dx, 8);
    expect(
      tester.widget<FluentChromeSurface>(surface).borderRadius,
      BorderRadius.circular(16),
    );
    expect(FluentSurfaceTokens.drawerItemHeight, 36);
    expect(find.byType(AppKitView), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab?.path, '#home');
    final pin = find.byType(fluent.IconButton).first;
    await tester.tap(pin);
    expect(pinChanges, [false]);
    await tester.tap(find.text('Drives'));
    await tester.pumpAndSettle();
    expect(drawer.state.isStorageExpanded, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await drawer.close();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

import 'dart:async';

import 'package:cb_file_manager/config/fluent_theme_config.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/ui/drawer.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/ui/widgets/drawer/storage_section_widget.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

const _disk = DriveInfo(
  path: 'W:\\',
  displayName: 'Work disk',
  kind: DriveKind.fixed,
  requiresAdmin: true,
);
const _wsl = DriveInfo(
  path: '\\\\wsl.localhost\\Drawer-test-distro\\',
  displayName: 'Test Debian',
  label: 'Drawer-test-distro',
  kind: DriveKind.wsl,
);

class _StorageFixture extends DrawerCubit {
  _StorageFixture() : super(loadDrives: () async => [_disk, _wsl]) {
    emit(
      state.copyWith(
        storageLocations: [
          _disk.toStorageDirectory(),
          _wsl.toStorageDirectory(),
        ],
        isStorageExpanded: true,
        activeTabId: 'fixture',
      ),
    );
  }
  @override
  Future<void> setActiveTab(String? tabId) async {}
  @override
  Future<void> setStorageExpanded(bool isExpanded) async =>
      emit(state.copyWith(isStorageExpanded: isExpanded));
}

void main() {
  test(
    'drawer volume reload shares typed inventory, WSL roots and expansion state',
    () async {
      final changes = StreamController<void>();
      var drives = [_disk, _wsl];
      final drawer = DrawerCubit(
        volumeChanges: changes.stream,
        loadDrives: () async => drives,
      );
      addTearDown(changes.close);
      addTearDown(drawer.close);
      final loaded = drawer.stream.firstWhere(
        (s) => s.storageLocations.length == 2,
      );
      changes.add(null);
      final state = await loaded;
      expect(state.storageLocations.first.driveInfo, _disk);
      expect(state.storageLocations.first.requiresAdmin, isTrue);
      expect(state.storageLocations.last.path, _wsl.path);
      expect(state.storageLocations.last.volumeLabel, 'Test Debian');
      expect(
        storageLocationIcon(state.storageLocations.last),
        PhosphorIconsLight.linuxLogo,
      );
      drives = [_disk];
      final refreshed = drawer.stream.firstWhere(
        (s) => s.storageLocations.length == 1,
      );
      changes.add(null);
      final next = await refreshed;
      expect(next.isStorageExpanded, state.isStorageExpanded);
      expect(next.activeTabId, state.activeTabId);
    },
  );

  testWidgets(
    'Material drawer shows the shared WSL name/icon and opens its UNC path',
    (tester) async {
      final drawer = _StorageFixture();
      addTearDown(() async {
        if (!drawer.isClosed) await drawer.close();
      });
      String? navigated;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: BlocProvider<DrawerCubit>.value(
              value: drawer,
              child: ListView(
                children: [
                  StorageSectionWidget(
                    initialExpanded: true,
                    onNavigate: (path, _) => navigated = path,
                    onTrashTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Debian'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsLight.linuxLogo), findsOneWidget);
      await tester.tap(find.text('Test Debian'));
      expect(navigated, _wsl.path);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final closed = drawer.close();
      await tester.pump();
      await closed;
    },
  );

  testWidgets(
    'Fluent drawer opens WSL in the current tab without probing the root',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'CB File Hub',
        packageName: 'cb.file.hub',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final tabs = TabManagerBloc()..add(AddTab(path: '#home', name: 'Home'));
      final drawer = _StorageFixture();
      addTearDown(tabs.close);
      addTearDown(() async {
        if (!drawer.isClosed) await drawer.close();
      });
      await tester.pumpWidget(
        fluent.FluentApp(
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
                    onPinStateChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabId = tabs.state.activeTabId;
      expect(find.byIcon(PhosphorIconsLight.linuxLogo), findsOneWidget);
      await tester.tap(find.text('Test Debian'));
      await tester.pumpAndSettle();
      expect(tabs.state.activeTab!.path, _wsl.path);
      expect(tabs.state.activeTab!.name, 'Test Debian');
      expect(tabs.state.activeTabId, tabId);
      expect(tabs.state.tabs, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      final closed = drawer.close();
      await tester.pump();
      await closed;
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

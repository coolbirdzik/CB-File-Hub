import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/services/filesystem/macos_user_folders_service.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/ui/widgets/drawer/pinned_section_widget.dart';
import 'package:cb_file_manager/ui/widgets/drawer/sidebar_pinned_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

final _folders = [
  for (final kind in MacosUserFolderKind.values)
    MacosUserFolder(kind: kind, path: '/native/${kind.name}'),
];

class _Favorites extends DrawerCubit {
  _Favorites() {
    emit(
      state.copyWith(
        macosUserFolders: _folders,
        pinnedPaths: _folders.map((folder) => folder.path).toList(),
        isPinnedExpanded: true,
      ),
    );
  }

  @override
  Future<void> togglePinnedPath(String path) async => emit(
    state.copyWith(
      pinnedPaths: state.pinnedPaths.where((value) => value != path).toList(),
    ),
  );
}

void main() {
  test(
    'both renderers share localized system labels, icons and arbitrary user pins',
    () {
      final english = EnglishLocalizations();
      final vietnamese = VietnameseLocalizations();
      final entries = [
        for (final folder in _folders)
          SidebarPinnedEntry.fromPath(
            folder.path,
            l10n: english,
            userFolders: _folders,
          ),
      ];
      expect(entries.map((entry) => entry.title).toList(), [
        'Applications',
        'Desktop',
        'Documents',
        'Downloads',
        'home',
        'Pictures',
        'Music',
        'Movies',
      ]);
      expect(
        entries.map((entry) => entry.icon).toSet().length,
        _folders.length,
      );
      final downloads = SidebarPinnedEntry.fromPath(
        '/native/downloads/',
        l10n: vietnamese,
        userFolders: _folders,
      );
      expect(downloads.title, vietnamese.downloads);
      expect(downloads.icon, PhosphorIconsLight.downloadSimple);
      final custom = SidebarPinnedEntry.fromPath(
        '/custom/Applications',
        l10n: english,
        userFolders: _folders,
      );
      expect(custom.title, 'Applications');
      expect(custom.icon, PhosphorIconsLight.folder);
    },
  );

  testWidgets('Material Favorites uses native paths for navigation and unpin', (
    tester,
  ) async {
    final drawer = _Favorites();
    final navigated = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
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
                PinnedSectionWidget(
                  initialExpanded: true,
                  onNavigate: (path, _) => navigated.add(path),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsOneWidget);
    await tester.tap(find.text('Downloads'));
    expect(navigated, ['/native/downloads']);
    await tester.tap(
      find.byTooltip(EnglishLocalizations().unpinFromSidebar).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Applications'), findsNothing);
    expect(find.text('Downloads'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await drawer.close();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

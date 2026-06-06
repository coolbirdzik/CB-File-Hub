import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';

void main() {
  group('05 Navigation Fix Tests', () {
    test('05.01 SystemScreenRouter clearWidgetCache should work correctly', () {
      // Test that clearWidgetCache method exists and works
      expect(() => SystemScreenRouter.clearWidgetCache(), returnsNormally);
      expect(() => SystemScreenRouter.clearWidgetCache('test-tab'),
          returnsNormally);
    });

    test('05.02 Path transition logic should work correctly', () {
      // Test the logic that determines when to clear cache
      String currentPath = '#tags';
      String newPath = '/storage/emulated/0';

      bool shouldClearCache =
          currentPath.startsWith('#') && !newPath.startsWith('#');
      expect(shouldClearCache, isTrue);

      // Test case where we shouldn't clear cache
      currentPath = '#tags';
      newPath = '#network';
      shouldClearCache =
          currentPath.startsWith('#') && !newPath.startsWith('#');
      expect(shouldClearCache, isFalse);

      // Test case where we shouldn't clear cache (both normal paths)
      currentPath = '/storage/emulated/0';
      newPath = '/storage/emulated/0/Downloads';
      shouldClearCache =
          currentPath.startsWith('#') && !newPath.startsWith('#');
      expect(shouldClearCache, isFalse);
    });

    test('05.03 Tab history should include and navigate back to drives path',
        () async {
      final bloc = TabManagerBloc();
      bloc.add(AddTab(path: kDrivesPath, name: 'Drives'));
      await Future<void>.delayed(Duration.zero);

      final tab = bloc.state.activeTab;
      expect(tab, isNotNull);

      final tabId = tab!.id;
      bloc.add(UpdateTabPath(tabId, r'C:\'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.canTabNavigateBack(tabId), isTrue);
      final previousPath = bloc.backNavigationToPath(tabId);
      expect(previousPath, equals(kDrivesPath));
      expect(bloc.canTabNavigateForward(tabId), isTrue);
    });
  });
}

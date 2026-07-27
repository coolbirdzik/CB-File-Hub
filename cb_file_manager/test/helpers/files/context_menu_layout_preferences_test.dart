import 'package:cb_file_manager/helpers/files/context_menu_layout_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextMenuLayoutPreference', () {
    test('uses defaults when stored JSON is invalid', () {
      final preference = ContextMenuLayoutPreference.fromJson(
        ContextMenuLayoutTarget.file,
        'invalid',
      );

      expect(preference.order, defaultFileContextMenuLayout);
      expect(preference.hiddenIds, isEmpty);
    });

    test('preserves stored order and appends newly introduced commands', () {
      final preference = ContextMenuLayoutPreference.fromJson(
        ContextMenuLayoutTarget.multiSelection,
        '{"order":["delete","copy"],"hidden":["copy"]}',
      );

      expect(preference.order.take(2), <String>['delete', 'copy']);
      expect(
        preference.order,
        containsAll(defaultMultiSelectionContextMenuLayout),
      );
      expect(preference.hiddenIds, <String>{'copy'});
    });

    test('round-trips order and visibility', () {
      const original = ContextMenuLayoutPreference(
        order: <String>['tags', 'copy', contextMenuThirdPartyAppsId],
        hiddenIds: <String>{contextMenuThirdPartyAppsId},
      );

      final decoded = ContextMenuLayoutPreference.fromJson(
        ContextMenuLayoutTarget.multiSelection,
        original.toJson(),
      );

      expect(decoded.order.take(3), original.order);
      expect(decoded.hiddenIds, original.hiddenIds);
    });
  });
}

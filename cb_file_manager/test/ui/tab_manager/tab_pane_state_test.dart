import 'package:cb_file_manager/ui/tab_manager/core/tab_pane_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(TabPaneState.clearAll);
  tearDown(TabPaneState.clearAll);

  test('a tab with no toggle yet falls back to the defaults', () {
    expect(TabPaneState.previewVisible('tab-a'), isNull);
    expect(TabPaneState.propertiesVisible('tab-a'), isNull);
  });

  test('toggles are kept per tab', () {
    TabPaneState.setPreviewVisible('tab-a', false);
    TabPaneState.setPropertiesVisible('tab-a', true);

    expect(TabPaneState.previewVisible('tab-a'), isFalse);
    expect(TabPaneState.propertiesVisible('tab-a'), isTrue);
    expect(TabPaneState.previewVisible('tab-b'), isNull);
    expect(TabPaneState.propertiesVisible('tab-b'), isNull);
  });

  test('closing a tab drops its state and its split pane state', () {
    TabPaneState.setPropertiesVisible('tab-a', true);
    TabPaneState.setPropertiesVisible('tab-a_split', true);
    TabPaneState.setPreviewVisible('tab-b', false);
    TabPaneState.setPreviewVisible('tab-b_split', false);

    TabPaneState.retainTabs({'tab-b'});

    expect(TabPaneState.propertiesVisible('tab-a'), isNull);
    expect(TabPaneState.propertiesVisible('tab-a_split'), isNull);
    expect(TabPaneState.previewVisible('tab-b'), isFalse);
    expect(TabPaneState.previewVisible('tab-b_split'), isFalse);
  });
}

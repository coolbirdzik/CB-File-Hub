import 'package:cb_file_manager/bloc/selection/selection_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'different selection operations remain distinct with identical props',
    () {
      const file = ToggleFileSelection('/same/path');
      const folder = ToggleFolderSelection('/same/path');
      const add = AddTagToItem('/same/path', 'tag');
      const remove = RemoveTagFromItem('/same/path', 'tag');

      expect(file, isNot(folder));
      expect(folder, isNot(file));
      expect(add, isNot(remove));
      expect(remove, isNot(add));
      expect(<SelectionEvent>{file, folder, add, remove}, hasLength(4));
    },
  );

  test('navigation commands with empty props remain distinct', () {
    final commands = <FileNavigationEvent>{
      const FileNavigationInit(),
      const FileNavigationReloadCurrentFolder(),
      const FileNavigationLoadDrives(),
    };

    expect(commands, hasLength(3));
  });

  test('the same operation retains value equality and consistent hashing', () {
    const first = ToggleFileSelection('/same/path', ctrlSelect: true);
    const second = ToggleFileSelection('/same/path', ctrlSelect: true);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    final operations = <SelectionEvent>{first}..add(second);
    expect(operations, hasLength(1));
    expect(first, isNot(const ToggleFileSelection('/same/path')));
  });
}

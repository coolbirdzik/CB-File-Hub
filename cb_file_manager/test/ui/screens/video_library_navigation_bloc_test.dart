import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_library_navigation_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved sort applied before the first load keeps it loading', () async {
    final bloc = VideoLibraryNavigationBloc(libraryId: 1);
    addTearDown(bloc.close);

    bloc.add(
      const FileNavigationSetSortOption(SortOption.sizeDesc, persist: false),
    );
    final state = await bloc.stream.first;

    expect(state.sortOption, SortOption.sizeDesc);
    // Not "loaded with no videos": the library load has not run yet.
    expect(state.isLoading, isTrue);
    expect(state.files, isEmpty);
  });
}

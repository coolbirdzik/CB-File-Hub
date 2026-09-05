import 'package:flutter/material.dart';
import '../screens/folder_list/folder_list_bloc.dart';
import '../screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';

/// Initializes tag search functionality for tabbed folder screens
///
/// Handles:
/// - Tag search parameter initialization
/// - Global vs local tag search setup
/// - #search?tag= path handling
/// - Tag controller text setup
class TagSearchInitializer {
  /// Initializes tag search based on widget parameters
  ///
  /// Returns the initialized search tag and global search flag
  static TagSearchConfig initialize({
    required String? searchTag,
    required bool globalTagSearch,
    required String path,
    required FolderListBloc folderListBloc,
    required TextEditingController tagController,
    required bool isMounted,
  }) {
    // Clear cache to ensure fresh results
    TagManager.clearCache();

    String? currentSearchTag = searchTag;
    bool isGlobalSearch = globalTagSearch;

    // Handle tag search initialization
    if (searchTag != null) {
      debugPrint(
        'TabbedFolderListScreen: Initializing with tag search for "$searchTag"',
      );
      debugPrint('Global search mode: $globalTagSearch');

      // Initialize with tag search
      if (globalTagSearch) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (isMounted && !folderListBloc.isClosed) {
            folderListBloc.add(SearchByTagGlobally(searchTag));
            tagController.text = searchTag;
          }
        });
      } else {
        // Local tag search within current directory
        Future.delayed(const Duration(milliseconds: 500), () {
          if (isMounted && !folderListBloc.isClosed) {
            folderListBloc.add(
              FolderListLoad(path),
            ); // First load the directory
            folderListBloc.add(SearchByTag(searchTag)); // Then search within it
          }
        });

        // Set tag controller text for search bar
        tagController.text = searchTag;
      }
    } else if (path.startsWith('#search?tag=')) {
      // Handle search path with tag parameter
      final tag =
          UriUtils.extractTagFromSearchPath(path) ??
          path.substring('#search?tag='.length);
      debugPrint('TabbedFolderListScreen: Handling search path with tag: $tag');

      // Set tag controller text for search bar
      tagController.text = tag;

      // Set search mode to global tag search
      isGlobalSearch = true;
      currentSearchTag = tag;

      // Perform global tag search
      Future.delayed(const Duration(milliseconds: 50), () {
        if (isMounted && !folderListBloc.isClosed) {
          folderListBloc.add(SearchByTagGlobally(tag));
        }
      });
    } else {
      // Normal directory loading - clear any existing filters first
      folderListBloc.add(const ClearSearchAndFilters());
      folderListBloc.add(FolderListLoad(path));
    }

    return TagSearchConfig(
      currentSearchTag: currentSearchTag,
      isGlobalSearch: isGlobalSearch,
    );
  }
}

/// Configuration result from tag search initialization
class TagSearchConfig {
  final String? currentSearchTag;
  final bool isGlobalSearch;

  const TagSearchConfig({
    required this.currentSearchTag,
    required this.isGlobalSearch,
  });
}

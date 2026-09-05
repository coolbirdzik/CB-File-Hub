import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/screens/system_screen.dart';
import 'package:cb_file_manager/ui/screens/tag_management/tag_management_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';

/// A tab component for the tag management screen
/// This component wraps the TagManagementScreen inside our SystemScreen base class
class TagManagementTab extends StatelessWidget {
  /// The ID for the tab
  final String tabId;

  /// Constructor
  const TagManagementTab({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    return SystemScreen(
      title: 'Tags',
      systemId: '#tags',
      icon: PhosphorIconsLight.tag,
      child: TagManagementScreen(
        tabId: tabId,
        startingDirectory: '',
        onTagSelected: (tag) => _openTagSearchTab(context, tag),
      ),
    );
  }

  /// Opens the search results for the selected tag in the CURRENT tab,
  /// navigating in place like browsing into a folder. This tab (which hosts the
  /// tag screen) has its path swapped to the tag-search path, so its content
  /// changes to the results and the back button returns to the tag list.
  void _openTagSearchTab(BuildContext context, String tag) {
    final searchSystemId = UriUtils.buildTagSearchPath(tag);
    final tabName = 'Tag: $tag';

    final tabBloc = BlocProvider.of<TabManagerBloc>(context);

    // Navigate this tab in place instead of spawning a new one.
    tabBloc.add(UpdateTabPath(tabId, searchSystemId));
    tabBloc.add(UpdateTabName(tabId, tabName));
  }

  /// Static method to open the tag management tab
  static void openTagManagementTab(BuildContext context) {
    SystemScreen.openInTab(
      context,
      systemId: '#tags',
      title: 'Tags',
      icon: PhosphorIconsLight.tag,
    );
  }
}

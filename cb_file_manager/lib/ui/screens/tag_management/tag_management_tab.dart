import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/screens/system_screen.dart';
import 'package:cb_file_manager/ui/screens/tag_management/tag_management_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';

/// A tab component for the tag management screen
/// This component wraps the TagManagementScreen inside our SystemScreen base class
class TagManagementTab extends StatelessWidget {
  /// The ID for the tab
  final String tabId;

  /// Constructor
  const TagManagementTab({
    Key? key,
    required this.tabId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SystemScreen(
      title: 'Tags',
      systemId: '#tags',
      icon: PhosphorIconsLight.tag,
      child: TagManagementScreen(
        startingDirectory: '',
        onTagSelected: (tag) => _openTagSearchTab(context, tag),
      ),
    );
  }

  /// Opens a new tab with search results for the selected tag
  void _openTagSearchTab(BuildContext context, String tag) {
    final searchSystemId = UriUtils.buildTagSearchPath(tag);

    // Create a tab name that's user-friendly
    final tabName = 'Tag: $tag';

    // Check if this tab already exists
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final existingTab = tabBloc.state.tabs.firstWhere(
      (tab) => tab.path == searchSystemId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    if (existingTab.id.isNotEmpty) {
      // If tab exists, switch to it
      tabBloc.add(SwitchToTab(existingTab.id));
    } else {
      // Otherwise, create a new tab for this tag search
      tabBloc.add(
        AddTab(
          path: searchSystemId,
          name: tabName,
          switchToTab: true,
        ),
      );
    }
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

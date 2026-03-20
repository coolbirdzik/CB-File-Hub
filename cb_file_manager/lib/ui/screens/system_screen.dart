import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';

/// A base class for all system screens in the application
/// System screens are screens that are not tied to a file system path
/// but represent system functionality like tags, trash, settings, etc.
class SystemScreen extends StatelessWidget {
  /// The title of the system screen
  final String title;

  /// The system ID (used for routing, e.g. #tags, #trash)
  final String systemId;

  /// The icon to display in the tab
  final IconData icon;

  /// The actual content of the system screen
  final Widget child;

  /// Whether to show the app bar (default: true)
  final bool showAppBar;

  /// Additional actions to display in the app bar
  final List<Widget>? actions;

  /// Constructor
  const SystemScreen({
    Key? key,
    required this.title,
    required this.systemId,
    required this.icon,
    required this.child,
    this.showAppBar = false,
    this.actions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(title),
              actions: actions,
              // Replace the close button with a back button
              // This will automatically handle whether to show a back arrow
              // or a close button depending on the navigation stack.
              leading: Navigator.canPop(context) ? const BackButton() : null,
            )
          : null,
      body: Container(
        color: Colors.transparent,
        child: child,
      ),
    );
  }

  /// Factory method to create a system screen tab
  /// This can be used to programmatically add a system screen tab to the tab manager
  static void openInTab(
    BuildContext context, {
    required String systemId,
    required String title,
    required IconData icon,
  }) {
    // Check if a tab with this systemId already exists
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final existingTab = tabBloc.state.tabs.firstWhere(
      (tab) => tab.path == systemId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    if (existingTab.id.isNotEmpty) {
      // If tab exists, switch to it
      tabBloc.add(SwitchToTab(existingTab.id));
    } else {
      // Otherwise, create a new tab
      tabBloc.add(
        AddTab(
          path: systemId,
          name: title,
          switchToTab: true,
        ),
      );
    }
  }
}

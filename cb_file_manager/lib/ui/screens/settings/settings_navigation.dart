import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config/languages/app_localizations.dart';
import '../../tab_manager/core/tab_data.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_paths.dart';

/// Sections of the Settings screen that other screens can link to.
enum SettingsAnchor {
  /// Cloud/remote AI providers used by CB Agent.
  aiProviders,

  /// On-device models (Local AI Advisor).
  localAi,
}

/// Section the Settings screen should scroll to next. [SettingsScreen] clears
/// it once it has scrolled there.
final ValueNotifier<SettingsAnchor?> pendingSettingsAnchor =
    ValueNotifier<SettingsAnchor?>(null);

/// Set when Settings should open the local model installer on arrival. The
/// Local AI section clears it once the installer is shown.
final ValueNotifier<bool> pendingLocalModelInstaller = ValueNotifier<bool>(
  false,
);

/// Opens Settings in a tab (reusing an open one) and scrolls to [anchor].
/// [openLocalModelInstaller] also opens the list of models to install.
void openSettings(
  BuildContext context, {
  SettingsAnchor? anchor,
  bool openLocalModelInstaller = false,
}) {
  final tabBloc = BlocProvider.of<TabManagerBloc>(context);
  final existingTab = tabBloc.state.tabs.firstWhere(
    (tab) => tab.path == kSettingsPath,
    orElse: () => TabData(id: '', name: '', path: ''),
  );
  if (existingTab.id.isNotEmpty) {
    tabBloc.add(SwitchToTab(existingTab.id));
  } else {
    tabBloc.add(
      AddTab(
        path: kSettingsPath,
        name: AppLocalizations.of(context)!.settings,
        switchToTab: true,
      ),
    );
  }
  pendingSettingsAnchor.value = anchor;
  if (openLocalModelInstaller) pendingLocalModelInstaller.value = true;
}

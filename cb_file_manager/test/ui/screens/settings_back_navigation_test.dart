import 'dart:async';

import 'package:cb_file_manager/ui/screens/settings/settings_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_browsing/network_recovery_test.dart' show host;

void main() {
  testWidgets('Settings Back returns to queue but closes a standalone tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Keep settings data loading while exercising its always-visible header.
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final pendingPath = Completer<String>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, (_) => pendingPath.future);
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));

    final tabs = TabManagerBloc()..add(AddTab(path: kSubtitleQueuePath));
    addTearDown(tabs.close);
    await tester.pump();
    final queueId = tabs.state.activeTab!.id;

    await tester.pumpWidget(
      host(
        BlocProvider.value(
          value: tabs,
          child: BlocBuilder<TabManagerBloc, TabManagerState>(
            builder: (context, state) {
              if (state.activeTab?.path == kSettingsPath) {
                return const SettingsScreen();
              }
              return Text(state.activeTab?.path ?? '');
            },
          ),
        ),
      ),
    );

    tabs.add(UpdateTabPath(queueId, kSettingsPath));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsLight.arrowLeft));
    await tester.pump();
    expect(tabs.state.tabs, hasLength(1));
    expect(tabs.state.activeTab?.id, queueId);
    expect(tabs.state.activeTab?.path, kSubtitleQueuePath);
    expect(tabs.canTabNavigateForward(queueId), isTrue);
    expect(find.text(kSubtitleQueuePath), findsOneWidget);

    tabs.add(AddTab(path: kSettingsPath));
    await tester.pump();
    await tester.pump();
    expect(tabs.state.tabs, hasLength(2));
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsLight.arrowLeft));
    await tester.pump();
    expect(tabs.state.tabs, hasLength(1));
    expect(tabs.state.activeTab?.id, queueId);
    expect(tabs.state.activeTab?.path, kSubtitleQueuePath);
    // Closing a tab schedules a throttled thumbnail-cache save.
    await tester.pump(const Duration(seconds: 10));
  });
}

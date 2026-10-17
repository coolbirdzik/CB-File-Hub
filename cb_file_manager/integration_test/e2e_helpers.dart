// Shared E2E test infrastructure.
// Imported by all E2E test files.
import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_sandbox_paths.dart';

/// Install before any app singleton opens its database or preference files.
/// Real filesystem operations still run, but app data belongs to this suite.
void registerE2EAppSandbox() {
  setUpAll(() async {
    await E2ESandboxPaths.install();
    SharedPreferences.setMockInitialValues({
      'torrent.autoImport': false,
      'torrent.scanRoots': <String>[],
      'torrent.qbittorrentSources': <String>[],
    });
  });
  tearDownAll(E2ESandboxPaths.uninstall);
}

/// Runs E2E teardown for a test: clears config, stops services, wipes sandbox dir.
Future<void> e2eTearDown(WidgetTester tester, Directory dir) async {
  // Unmount first: listeners/focus/theme dependencies must be detached before
  // disposing the services they use. Never leave the previous app tree alive
  // while resetting GetIt or starting the next app instance.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  CbE2EConfig.clear();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 50));

  // Sequential order is critical:
  // 1. clearClipboard() — prevents FileOperations singleton state leaking between tests.
  // 2. stopWatching() — prevents SocketException when sandbox dir is deleted.
  // 3. locator.reset() — disposes BLoCs/services.
  // 4. clearSharedPreferences — resets view_mode so next test starts clean.
  // 5. _deleteDirectorySafe() — removes the sandbox.
  FileOperations().clearClipboard();
  await tearDownCbFileAppForNextE2ETest();
  await clearSharedPreferencesForE2E();
  await deleteDirectorySafe(dir);
}

/// Clears SharedPreferences keys written by the app during E2E tests.
Future<void> clearSharedPreferencesForE2E() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme_onboarding_completed_v1');
    await prefs.remove('view_mode');
    for (final key in prefs.getKeys()) {
      if (key.startsWith('e2e_')) await prefs.remove(key);
    }
  } catch (_) {}
}

/// Deletes a directory safely, ignoring errors.
Future<void> deleteDirectorySafe(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {}
}

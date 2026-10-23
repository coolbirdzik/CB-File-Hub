import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// Legacy Windows preferences cache the JSON inside the platform store too.
/// Refresh that store before reload, so a different app process's saved choices
/// reach both legacy getters and subsequent setters in this process.
Future<void> reloadTorrentPreferences(
  SharedPreferences preferences, {
  SharedPreferencesWindows Function()? createWindowsStore,
}) async {
  if (SharedPreferencesStorePlatform.instance is SharedPreferencesWindows) {
    SharedPreferencesStorePlatform.instance =
        createWindowsStore?.call() ?? SharedPreferencesWindows();
  }
  await preferences.reload();
}

import 'dart:async';

import 'package:cb_file_manager/providers/theme_provider.dart';
import 'package:flutter/foundation.dart';

Future<ThemeProvider> loadThemeProvider(TargetPlatform platform) async {
  final provider = ThemeProvider(platform: platform);
  final loaded = Completer<void>();
  void onLoaded() {
    if (!loaded.isCompleted) loaded.complete();
  }

  provider.addListener(onLoaded);
  await loaded.future;
  provider.removeListener(onLoaded);
  return provider;
}

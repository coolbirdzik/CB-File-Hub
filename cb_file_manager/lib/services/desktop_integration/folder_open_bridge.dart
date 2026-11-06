import 'dart:io';

import 'package:flutter/services.dart';

import '../../ui/tab_manager/core/tab_manager.dart';
import 'folder_launch_request.dart';

/// macOS open events can arrive before Flutter or after the first window loads.
class FolderOpenBridge {
  static const _channel = MethodChannel('cb_file_manager/folder_open');
  static final pendingRejections = <String>[];
  static TabManagerBloc? _tabs;
  static void Function(List<String>)? _onRejected;

  static Future<void> attach(
    TabManagerBloc tabs,
    void Function(List<String>) onRejected,
  ) async {
    _tabs = tabs;
    _onRejected = onRejected;
    if (pendingRejections.isNotEmpty) {
      final rejected = List<String>.of(pendingRejections);
      pendingRejections.clear();
      onRejected(rejected);
    }
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFolders' && call.arguments is List) {
        await _open((call.arguments as List).whereType<String>().toList());
      }
    });
    final pending = await _channel.invokeListMethod<String>('ready');
    if (pending != null && pending.isNotEmpty) await _open(pending);
  }

  static Future<void> _open(List<String> paths) async {
    final tabs = _tabs;
    if (tabs == null) return;
    final request = await FolderLaunchRequest.takeArguments([
      '--open-folder',
      ...paths,
    ]);
    if (_tabs != tabs || tabs.isClosed) return;
    for (final tab in request.tabs) {
      tabs.add(AddTab(path: tab.path, name: tab.name));
    }
    if (request.rejected.isNotEmpty) _onRejected?.call(request.rejected);
  }

  static void detach(TabManagerBloc tabs) {
    if (_tabs != tabs) return;
    _tabs = null;
    _onRejected = null;
    if (Platform.isMacOS) _channel.setMethodCallHandler(null);
  }
}

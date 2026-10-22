// Standalone launcher for measuring the production Cleaner UI on one folder.
// No E2E mode, simulated results, saved scan tree, or incremental scan is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

class _FolderScanService extends DiskCleanerService {
  final String root;
  final File output;
  int generation = 0;

  _FolderScanService(this.root, this.output)
    // Keep benchmark configuration separate from the shared application service.
    // ignore: invalid_use_of_visible_for_testing_member
    : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);

  @override
  Future<List<DriveSpace>> getDriveSpace() async => [
    DriveSpace(
      path: root,
      label: 'Benchmark corpus',
      totalBytes: 1024 * 1024 * 1024,
      freeBytes: 512 * 1024 * 1024,
    ),
  ];

  @override
  FullDiskScanResult? cachedFullScanResult(String drivePath) => null;

  @override
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
    int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  }) async {
    final current = ++generation;
    final handle = await spawnFullDiskScan(
      drivePath: root,
      maxDepth: maxDepth,
      minDisplayEntryBytes: minDisplayEntryBytes,
      maxChildrenPerDirectory: maxChildrenPerDirectory,
      useNativeScanner: true,
    );
    unawaited(
      handle.future.then((result) async {
        // The production screen awaits the same future and sets its final tree
        // in this event-loop turn. Wait until that frame has finished building.
        await WidgetsBinding.instance.endOfFrame;
        await output.writeAsString(
          jsonEncode({
            'generation': current,
            'files': result.root.fileCount,
            'bytes': result.root.sizeBytes,
            'display_nodes': result.nodeCount,
            'partial': result.isPartial,
            'mode': result.scanMode.name,
            'coverage_issues': result.coverageIssues.length,
          }),
        );
      }),
    );
    return handle;
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || !Directory(args.first).existsSync()) {
    stderr.writeln(
      'Usage: cb_file_hub.exe <existing folder> <completion.json>',
    );
    exit(64);
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (!CbNative.isAvailable) throw StateError('Rust library is required.');
  // Keep accessibility available for the external ready-state observer.
  final semantics = WidgetsBinding.instance.ensureSemantics();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('CB Cleaner benchmark');
  await windowManager.setSize(const Size(1280, 900));
  runApp(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: CbAgentCleanerScreen(
          tabId: 'benchmark',
          cleanerService: _FolderScanService(
            Directory(args.first).absolute.path,
            File(args[1]).absolute,
          ),
        ),
      ),
    ),
  );
  await windowManager.show();
  // The semantics handle must live as long as the app.
  windowManager.addListener(_SemanticsLifetime(semantics.dispose));
}

class _SemanticsLifetime with WindowListener {
  final VoidCallback disposeSemantics;
  _SemanticsLifetime(this.disposeSemantics);

  @override
  void onWindowClose() => disposeSemantics();
}

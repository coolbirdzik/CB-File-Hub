// E2E data isolation: redirects path_provider so the app's database, tags,
// preferences-backed files, thumbnail caches, trash, etc. all land inside a
// throwaway sandbox directory instead of the real
// `Documents/CBFileHub_v2/...` of your debug/release install.
//
// Without this, running the screenshot/E2E flow writes showcase tags
// (`vacation`, `favorite`, parent/child demo tags, ...) straight into the
// real SQLite DB and pollutes the app data you actually use.
//
// Usage (call once, before any test body runs `runCbFileApp()`):
//
//   setUpAll(() async {
//     await E2ESandboxPaths.install();
//   });
//   tearDownAll(() async {
//     await E2ESandboxPaths.uninstall();
//   });
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// A [PathProviderPlatform] that serves every directory request from a single
/// sandbox root under the system temp dir. Installed only during E2E runs.
class E2ESandboxPaths extends PathProviderPlatform {
  E2ESandboxPaths._(this._root);

  final Directory _root;

  static E2ESandboxPaths? _active;
  static PathProviderPlatform? _previous;

  /// True while a sandbox override is installed.
  static bool get isInstalled => _active != null;

  /// The provider that was active before the sandbox was installed.
  ///
  /// E2E infrastructure that has to reach the device's real directories — the
  /// screenshot report needs a location `adb pull` can read — goes through this
  /// instead of [PathProviderPlatform.instance], which the sandbox owns.
  static PathProviderPlatform get platformProvider =>
      _previous ?? PathProviderPlatform.instance;

  /// Absolute path of the current sandbox root, or null when not installed.
  static String? get rootPath => _active?._root.path;

  /// Installs the sandbox override. Idempotent — calling twice keeps the first
  /// sandbox. Returns the sandbox root path.
  static Future<String> install() async {
    if (_active != null) return _active!._root.path;
    final root = await Directory.systemTemp.createTemp('cb_e2e_appdata_');
    // Pre-create the well-known sub-paths so first-time writers don't race.
    for (final name in const [
      'documents',
      'support',
      'temp',
      'library',
      'downloads',
    ]) {
      Directory(p.join(root.path, name)).createSync(recursive: true);
    }
    _previous = PathProviderPlatform.instance;
    final provider = E2ESandboxPaths._(root);
    PathProviderPlatform.instance = provider;
    _active = provider;
    return root.path;
  }

  /// Restores the previous provider and deletes the sandbox directory.
  static Future<void> uninstall() async {
    final active = _active;
    if (active == null) return;
    if (_previous != null) {
      PathProviderPlatform.instance = _previous!;
    }
    _active = null;
    _previous = null;
    try {
      if (await active._root.exists()) {
        await active._root.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup; the OS clears systemTemp eventually.
    }
  }

  Future<String> _sub(String name) async {
    final dir = Directory(p.join(_root.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() => _sub('temp');

  @override
  Future<String?> getApplicationSupportPath() => _sub('support');

  @override
  Future<String?> getLibraryPath() => _sub('library');

  @override
  Future<String?> getApplicationDocumentsPath() => _sub('documents');

  @override
  Future<String?> getDownloadsPath() => _sub('downloads');

  @override
  Future<String?> getExternalStoragePath() => _sub('documents');

  @override
  Future<List<String>?> getExternalCachePaths() async => [await _sub('temp')];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => [await _sub('documents')];
}

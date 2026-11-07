// Opt-in widget rendering of the Cleaner's App storage page with sample
// data, once per desktop platform and language. No app folder, native
// application or Trash is touched; extension icons are drawn here.
// Run from cb_file_manager:
// flutter test --no-pub tool/capture_app_storage_screenshots_test.dart \
//   --dart-define=CB_CAPTURE_SCREENSHOTS=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/bloc/cleaner_app_storage/cleaner_app_storage.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/docker/docker_storage.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_storage_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_app_storage_view.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_utilities_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

class _ShowcaseLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const _ShowcaseLocalizations();
  @override
  bool isSupported(Locale locale) => ['en', 'vi'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      locale.languageCode == 'vi'
      ? VietnameseLocalizations()
      : EnglishLocalizations();
  @override
  bool shouldReload(_ShowcaseLocalizations old) => false;
}

/// Where each platform keeps editor data, and how its window looks.
class _Platform {
  final String name;
  final TargetPlatform target;
  final String home;
  final String Function(String folder) dataRoot;
  final String separator;
  final List<EditorProduct> editors;

  const _Platform({
    required this.name,
    required this.target,
    required this.home,
    required this.dataRoot,
    required this.separator,
    required this.editors,
  });

  bool get usesTrash => target != TargetPlatform.windows;

  /// Where an app is installed.
  String install(String name) => switch (target) {
    TargetPlatform.macOS => '/Applications/$name.app',
    TargetPlatform.windows => 'C:\\Program Files\\$name',
    _ => '/opt/${name.toLowerCase().replaceAll(' ', '-')}',
  };

  /// Per-user data of an app named [name].
  String data(String name) => dataRoot(name);

  /// The per-user cache folder.
  String cache(String name) => switch (target) {
    TargetPlatform.macOS => '/Users/you/Library/Caches/$name',
    TargetPlatform.windows => 'C:\\Users\\You\\AppData\\Local\\$name\\Cache',
    _ => '/home/you/.cache/${name.toLowerCase()}',
  };

  String join(List<String> parts) => parts.join(separator);
}

final _platforms = [
  _Platform(
    name: 'macos',
    target: TargetPlatform.macOS,
    home: '/Users/you',
    dataRoot: (folder) => '/Users/you/Library/Application Support/$folder',
    separator: '/',
    editors: [EditorProduct.all[0], EditorProduct.all[3]],
  ),
  _Platform(
    name: 'windows',
    target: TargetPlatform.windows,
    home: r'C:\Users\You',
    dataRoot: (folder) => 'C:\\Users\\You\\AppData\\Roaming\\$folder',
    separator: r'\',
    editors: [EditorProduct.all[0], EditorProduct.all[1]],
  ),
  _Platform(
    name: 'linux',
    target: TargetPlatform.linux,
    home: '/home/you',
    dataRoot: (folder) => '/home/you/.config/$folder',
    separator: '/',
    editors: [EditorProduct.all[0], EditorProduct.all[2]],
  ),
];

/// (id, display name, version, install, data, colour)
const _extensions = <(String, String, String, int, int, int)>[
  ('ms-python.python', 'Python', '2026.18.0', 92 * _mb, 310 * _mb, 0xFF3776AB),
  ('ms-dotnettools.csharp', 'C#', '2.160.4', 503 * _mb, 0, 0xFF68217A),
  (
    'rust-lang.rust-analyzer',
    'rust-analyzer',
    '0.4.2650',
    148 * _mb,
    96 * _mb,
    0xFFB7410E,
  ),
  ('ms-vscode.cpptools', 'C/C++', '1.29.3', 121 * _mb, 74 * _mb, 0xFF00599C),
  ('golang.go', 'Go', '0.50.0', 18 * _mb, 142 * _mb, 0xFF00ADD8),
  ('ms-toolsai.jupyter', 'Jupyter', '2026.9.0', 64 * _mb, 58 * _mb, 0xFFF37626),
  ('esbenp.prettier-vscode', 'Prettier', '11.0.0', 52 * _mb, 0, 0xFF56B3B4),
  ('dbaeumer.vscode-eslint', 'ESLint', '3.0.16', 9 * _mb, 21 * _mb, 0xFF4B32C3),
  ('redhat.vscode-yaml', 'YAML', '1.18.0', 23 * _mb, 2 * _mb, 0xFFCB171E),
  ('dart-code.dart-code', 'Dart', '3.146.0', 84 * _mb, 12 * _mb, 0xFF0175C2),
];

Future<String> _drawIcon(Directory dir, String name, int color) async {
  const size = 128.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, size, size),
    const Radius.circular(26),
  );
  canvas.drawRRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(size, size), [
        Color(color),
        Color.lerp(Color(color), Colors.black, 0.35)!,
      ]),
  );
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 58),
        )
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 58,
            // Tests have no system fonts; use the app's bundled one.
            fontFamily: CbTypography.label.fontFamily,
          ),
        )
        ..addText(name.characters.first.toUpperCase());
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: size));
  canvas.drawParagraph(paragraph, Offset(0, (size - paragraph.height) / 2));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/${name.replaceAll(RegExp(r'\W'), '_')}.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

EditorStorageReport _report(
  _Platform platform,
  EditorProduct editor,
  Map<String, String> icons, {
  required bool primary,
}) {
  final data = platform.dataRoot(editor.dataFolder);
  final extensionsRoot = platform.join([
    platform.home,
    editor.homeFolder,
    'extensions',
  ]);
  final scale = primary ? 1.0 : 0.22;
  int bytes(int value) => (value * scale).round();
  String extensionPath(String id, String version) =>
      platform.join([extensionsRoot, '$id-$version']);
  String inData(List<String> parts) => platform.join([data, ...parts]);
  // VS Code is running in the macOS shot, so its caches are kept.
  final running = primary && platform.target == TargetPlatform.macOS;

  return EditorStorageReport(
    editor: editor,
    dataRoot: data,
    extensionsRoot: extensionsRoot,
    isRunning: running,
    extensions: [
      for (final (id, name, version, install, storage, _)
          in primary ? _extensions : _extensions.take(4))
        EditorExtensionUsage(
          id: id,
          version: version,
          displayName: name,
          path: extensionPath(id, version),
          iconPath: icons[id],
          status: EditorExtensionStatus.installed,
          installBytes: bytes(install),
          globalStorageBytes: bytes(storage * 2 ~/ 3),
          workspaceStorageBytes: bytes(storage ~/ 3),
        ),
      if (primary) ...[
        EditorExtensionUsage(
          id: 'ms-python.python',
          version: '2026.16.0',
          displayName: 'Python',
          path: extensionPath('ms-python.python', '2026.16.0'),
          iconPath: icons['ms-python.python'],
          status: EditorExtensionStatus.obsolete,
          installBytes: 91 * _mb,
        ),
        EditorExtensionUsage(
          id: 'rust-lang.rust-analyzer',
          version: '0.4.2610',
          displayName: 'rust-analyzer',
          path: extensionPath('rust-lang.rust-analyzer', '0.4.2610'),
          iconPath: icons['rust-lang.rust-analyzer'],
          status: EditorExtensionStatus.obsolete,
          installBytes: 146 * _mb,
        ),
      ],
    ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes)),
    orphanedExtensionData: [
      EditorExtensionData(
        id: 'vscode.git',
        paths: [
          inData(['User', 'globalStorage', 'vscode.git']),
        ],
        bytes: bytes(36 * _mb),
      ),
    ],
    workspaces: [
      for (var i = 0; i < (primary ? 46 : 9); i++)
        EditorWorkspaceUsage(
          path: inData(['User', 'workspaceStorage', 'w$i']),
          target: platform.join([platform.home, 'Projects', 'app-$i']),
          status: i % 4 == 0
              ? EditorWorkspaceStatus.missing
              : EditorWorkspaceStatus.present,
          bytes: bytes((9 + i % 7 * 6) * _mb),
        ),
    ],
    data: [
      EditorDataUsage(
        kind: EditorDataKind.cache,
        paths: [
          inData(['Cache']),
          inData(['CachedData']),
        ],
        bytes: bytes(612 * _mb),
        cleanable: running
            ? const []
            : [
                EditorCleanTarget(inData(['Cache']), bytes(402 * _mb)),
                EditorCleanTarget(inData(['CachedData']), bytes(210 * _mb)),
              ],
      ),
      EditorDataUsage(
        kind: EditorDataKind.extensionDownloads,
        paths: [
          inData(['CachedExtensionVSIXs']),
        ],
        bytes: bytes(843 * _mb),
        cleanable: [
          EditorCleanTarget(
            inData(['CachedExtensionVSIXs', 'ms-python.python-2026.16.0']),
            bytes(843 * _mb),
          ),
        ],
      ),
      EditorDataUsage(
        kind: EditorDataKind.logs,
        paths: [
          inData(['logs']),
        ],
        bytes: bytes(478 * _mb),
        cleanable: [
          for (var day = 1; day <= 9; day++)
            EditorCleanTarget(
              inData(['logs', '202611${day.toString().padLeft(2, '0')}T0900']),
              bytes(52 * _mb),
            ),
        ],
      ),
      EditorDataUsage(
        kind: EditorDataKind.crashReports,
        paths: [
          inData(['Crashpad']),
        ],
        bytes: bytes(128 * _mb),
        cleanable: [
          EditorCleanTarget(
            inData(['Crashpad', 'completed', 'a.dmp']),
            bytes(124 * _mb),
          ),
        ],
      ),
      EditorDataUsage(
        kind: EditorDataKind.webStorage,
        paths: [
          inData(['WebStorage']),
        ],
        bytes: bytes(2 * _gb + 310 * _mb),
      ),
      EditorDataUsage(
        kind: EditorDataKind.localHistory,
        paths: [
          inData(['User', 'History']),
        ],
        bytes: bytes(420 * _mb),
      ),
      EditorDataUsage(
        kind: EditorDataKind.settings,
        paths: [
          inData(['User']),
        ],
        bytes: bytes(82 * _mb),
      ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes)),
  );
}

List<CleanerUtilityDestination> _destinations(
  AppLocalizations l,
  TargetPlatform platform,
) => [
  CleanerUtilityDestination(
    id: 'smartClean',
    title: l.cleanerSmartCleanTitle,
    description: l.cleanerSmartCleanUtilityDescription,
    group: l.cleanerUtilitiesStorageGroup,
    icon: PhosphorIconsLight.sparkle,
  ),
  if (platform != TargetPlatform.linux)
    CleanerUtilityDestination(
      id: 'diskCleaner',
      title: l.cleanerDiskUsageTitle,
      description: l.cleanerDiskUtilityDescription,
      group: l.cleanerUtilitiesStorageGroup,
      icon: PhosphorIconsLight.hardDrive,
    ),
  if (platform == TargetPlatform.windows)
    CleanerUtilityDestination(
      id: 'appInsights',
      title: l.cleanerAppsTitle,
      description: l.cleanerAppsUtilityDescription,
      group: l.cleanerUtilitiesStorageGroup,
      icon: PhosphorIconsLight.appWindow,
    ),
  CleanerUtilityDestination(
    id: 'appLeftovers',
    title: l.cleanerLeftoversTitle,
    description: l.cleanerLeftoversUtilityDescription,
    group: l.cleanerUtilitiesStorageGroup,
    icon: PhosphorIconsLight.folderDashed,
  ),
  CleanerUtilityDestination(
    id: 'appStorage',
    title: l.cleanerAppStorageTitle,
    description: l.cleanerAppStorageUtilityDescription,
    group: l.cleanerUtilitiesStorageGroup,
    icon: PhosphorIconsLight.chartPieSlice,
  ),
];

/// A plain window frame so each shot reads as its platform.
class _WindowFrame extends StatelessWidget {
  final TargetPlatform platform;
  final String title;
  final Widget child;

  const _WindowFrame({
    required this.platform,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    Widget dot(Color color) => Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    Widget caption(IconData icon) => SizedBox(
      width: 46,
      child: Icon(icon, size: 14, color: c.textSecondary),
    );
    final titleText = Text(
      title,
      style: CbTypography.label.copyWith(color: c.textSecondary),
    );
    final bar = switch (platform) {
      TargetPlatform.macOS => Row(
        children: [
          const SizedBox(width: 14),
          dot(const Color(0xFFFF5F57)),
          dot(const Color(0xFFFEBC2E)),
          dot(const Color(0xFF28C840)),
          Expanded(child: Center(child: titleText)),
          const SizedBox(width: 74),
        ],
      ),
      TargetPlatform.windows => Row(
        children: [
          const SizedBox(width: 14),
          Icon(PhosphorIconsLight.folder, size: CbSizes.iconMd, color: c.icon),
          const SizedBox(width: 10),
          Expanded(child: titleText),
          caption(PhosphorIconsLight.minus),
          caption(PhosphorIconsLight.square),
          caption(PhosphorIconsLight.x),
        ],
      ),
      _ => Row(
        children: [
          const SizedBox(width: 40),
          Expanded(child: Center(child: titleText)),
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: c.fillSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsLight.x, size: 12, color: c.textPrimary),
          ),
        ],
      ),
    };
    return ColoredBox(
      color: c.canvas,
      child: Column(
        children: [
          SizedBox(height: 38, child: bar),
          Divider(height: 1, color: c.strokeSubtle),
          Expanded(child: child),
        ],
      ),
    );
  }
}

DockerImage _image(String name, int mb, {int containers = 0}) {
  final [repository, tag] = name.split(':');
  return DockerImage(
    id: 'sha256:${name.hashCode.toRadixString(16).padLeft(12, '0')}',
    repository: repository,
    tag: tag,
    size: mb * _mb,
    uniqueSize: mb * _mb,
    containers: containers,
  );
}

final _docker = DockerReport(
  status: DockerStatus.ready,
  images: [
    _image('postgres:16', 450, containers: 1),
    _image('redis:7', 140, containers: 1),
    _image('node:20', 1100),
    _image('python:3.12', 1020),
    _image('app/web:old', 640),
    _image('app/api:old', 520),
    _image('<none>:<none>', 380),
    _image('<none>:<none>', 210),
  ],
  containers: const [
    DockerContainer(
      id: '1',
      name: 'db',
      image: 'postgres:16',
      state: 'running',
      size: 2,
    ),
    DockerContainer(
      id: '2',
      name: 'migrate',
      image: 'app/api:old',
      state: 'exited',
      size: 12 * _mb,
    ),
  ],
  volumes: const [
    DockerVolume(name: 'db-data', links: 1, size: 1800 * _mb),
    DockerVolume(name: 'old-project_cache', links: 0, size: 420 * _mb),
  ],
  buildCache: const [
    DockerBuildCacheEntry(
      id: 'x',
      description: 'npm ci',
      size: 8900 * _mb,
      inUse: false,
    ),
  ],
);

class _ShowcaseScanner implements AppStorageScanner {
  final AppSpaceReport report;

  _ShowcaseScanner(this.report);

  @override
  Future<AppSpaceReport?> scan({
    required void Function(int done, int total) onProgress,
    required void Function(AppSpaceReport partial) onPartial,
  }) async => report;

  @override
  void cancel() {}
}

AppSpaceEntry _app(
  _Platform platform,
  String id,
  String name, {
  bool running = false,
  EditorStorageReport? editor,
  required List<(AppSpaceKind, AppSpaceTier, String, int)> items,
}) => AppSpaceEntry(
  app: InstalledAppInfo(
    id: id,
    displayName: name,
    source: switch (platform.target) {
      TargetPlatform.macOS => InstalledAppSource.macApp,
      TargetPlatform.windows => InstalledAppSource.win32,
      _ => InstalledAppSource.linuxDesktop,
    },
  ),
  isRunning: running,
  editor: editor,
  items: [
    for (final (kind, tier, path, bytes) in items)
      AppSpaceItem(path: path, kind: kind, tier: tier, bytes: bytes),
  ],
);

AppSpaceReport _appReport(_Platform platform, Map<String, String> icons) {
  const review = AppSpaceTier.review;
  const safe = AppSpaceTier.safe;
  const optional = AppSpaceTier.optional;
  String join(String root, String child) => platform.join([root, child]);
  final code = EditorProduct.all.first;
  final entries = [
    _app(
      platform,
      'docker',
      'Docker Desktop',
      items: [
        (AppSpaceKind.userData, review, platform.data('Docker'), 38 * _gb),
        (AppSpaceKind.install, review, platform.install('Docker'), 2 * _gb),
      ],
    ),
    _app(
      platform,
      'vscode',
      code.name,
      running: platform.target == TargetPlatform.macOS,
      editor: _report(platform, code, icons, primary: true),
      items: [
        (
          AppSpaceKind.install,
          review,
          platform.install('Visual Studio Code'),
          920 * _mb,
        ),
      ],
    ),
    _app(
      platform,
      'chrome',
      'Google Chrome',
      running: true,
      items: [
        (AppSpaceKind.cache, review, platform.cache('Google'), 5 * _gb),
        (
          AppSpaceKind.install,
          review,
          platform.install('Google Chrome'),
          1430 * _mb,
        ),
        (AppSpaceKind.userData, review, platform.data('Google'), 1120 * _mb),
      ],
    ),
    _app(
      platform,
      'spotify',
      'Spotify',
      items: [
        (AppSpaceKind.cache, optional, platform.cache('Spotify'), 3200 * _mb),
        (AppSpaceKind.install, review, platform.install('Spotify'), 310 * _mb),
        (AppSpaceKind.userData, review, platform.data('Spotify'), 190 * _mb),
      ],
    ),
    _app(
      platform,
      'slack',
      'Slack',
      items: [
        (
          AppSpaceKind.cache,
          safe,
          join(platform.data('Slack'), 'Cache'),
          640 * _mb,
        ),
        (
          AppSpaceKind.logs,
          safe,
          join(platform.data('Slack'), 'logs'),
          82 * _mb,
        ),
        (
          AppSpaceKind.crashReports,
          safe,
          join(platform.data('Slack'), 'Crashpad'),
          41 * _mb,
        ),
        (
          AppSpaceKind.webStorage,
          review,
          join(platform.data('Slack'), 'IndexedDB'),
          310 * _mb,
        ),
        (AppSpaceKind.install, review, platform.install('Slack'), 520 * _mb),
      ],
    ),
    _app(
      platform,
      'teams',
      'Microsoft Teams',
      items: [
        (
          AppSpaceKind.cache,
          safe,
          join(platform.data('Microsoft Teams'), 'Cache'),
          910 * _mb,
        ),
        (
          AppSpaceKind.install,
          review,
          platform.install('Microsoft Teams'),
          640 * _mb,
        ),
      ],
    ),
    _app(
      platform,
      'figma',
      'Figma',
      items: [
        (
          AppSpaceKind.cache,
          safe,
          join(platform.data('Figma'), 'GPUCache'),
          310 * _mb,
        ),
        (AppSpaceKind.install, review, platform.install('Figma'), 420 * _mb),
      ],
    ),
    _app(
      platform,
      'zoom',
      'Zoom',
      items: [
        (
          AppSpaceKind.logs,
          optional,
          join(platform.data('Zoom'), 'logs'),
          150 * _mb,
        ),
        (AppSpaceKind.install, review, platform.install('Zoom'), 360 * _mb),
      ],
    ),
  ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
  return AppSpaceReport(
    entries: entries,
    generatedAt: DateTime(2026, 11, 7),
    docker: _docker,
  );
}

void main() {
  testWidgets('Capture the App storage page on every desktop platform', (
    tester,
  ) async {
    final originalShadows = debugDisableShadows;
    debugDisableShadows = false;
    final iconDir = Directory.systemTemp.createTempSync('cb_app_icons_');
    try {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final icons = <String, String>{};
      await tester.runAsync(() async {
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in manifest) {
          final loader = FontLoader(entry['family'] as String);
          for (final font in entry['fonts'] as List) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
        for (final (id, name, _, _, _, color) in _extensions) {
          icons[id] = await _drawIcon(iconDir, name, color);
        }
      });

      // Decode the icons into the image cache under the exact key the
      // 32 px extension icon asks for (Image.file with cacheWidth at 1x), so
      // the page paints them on its first frame.
      await tester.pumpWidget(const SizedBox.shrink());
      final context = tester.element(find.byType(SizedBox));
      await tester.runAsync(() async {
        for (final path in icons.values) {
          await precacheImage(
            ResizeImage(FileImage(File(path)), width: 32),
            context,
          );
        }
      });

      for (final platform in _platforms) {
        debugDefaultTargetPlatformOverride = platform.target;
        for (final locale in ['en', 'vi']) {
          final cubit = CleanerAppStorageCubit(
            scanner: _ShowcaseScanner(_appReport(platform, icons)),
          );
          await cubit.scan();
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: CbThemeBuilder.build(
                  brightness: Brightness.light,
                  accent: ThemeConfig
                      .accentSeedColors[ThemeConfig.defaultAccentColor]!,
                ),
                locale: Locale(locale),
                supportedLocales: const [Locale('en'), Locale('vi')],
                localizationsDelegates: const [
                  _ShowcaseLocalizations(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) {
                    final l = AppLocalizations.of(context)!;
                    return Scaffold(
                      body: _WindowFrame(
                        platform: platform.target,
                        title: 'CB File Hub',
                        child: CleanerUtilitiesShell(
                          title: l.cleanerUtilitiesTitle,
                          subtitle: l.cleanerUtilitiesSubtitle,
                          selectedId: 'appStorage',
                          destinations: _destinations(l, platform.target),
                          onSelected: (_) {},
                          child: CleanerAppStorageView(
                            cubit: cubit,
                            usesTrash: platform.usesTrash,
                            onOpenFolder: (_) {},
                            onOpenLeftovers: () {},
                            onClean: (_, _) async => throw StateError(
                              'Screenshot scenes cannot clean',
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> capture(String name) async {
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(
                '../screenshots/features/app_storage/$locale',
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/$name.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          // Docker opens first; one shot of it per language.
          if (platform.target == TargetPlatform.macOS) await capture('docker');
          // Then the apps: close Docker, open the editor.
          await tester.tap(
            find.byKey(const ValueKey('cleaner-app-storage-docker-toggle')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('cleaner-app-storage-toggle-vscode')),
          );
          await tester.pumpAndSettle();
          await capture(platform.name);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await cubit.close();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = originalShadows;
      iconDir.deleteSync(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('CB_CAPTURE_SCREENSHOTS'));
}

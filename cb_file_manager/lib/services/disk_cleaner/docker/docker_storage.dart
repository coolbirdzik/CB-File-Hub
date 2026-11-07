import 'dart:convert';
import 'dart:io';

/// Runs the Docker CLI. Injected in tests.
typedef DockerRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

enum DockerStatus {
  /// The daemon answered.
  ready,

  /// The CLI exists but the daemon (Docker Desktop, dockerd) is not running.
  notRunning,

  /// No `docker` executable was found.
  notInstalled,

  /// The CLI answered with something that could not be read.
  failed,
}

class DockerImage {
  final String id;
  final String repository;
  final String tag;
  final int size;

  /// Layers only this image uses: what removing it frees.
  final int uniqueSize;

  /// Containers (running or stopped) created from it.
  final int containers;

  const DockerImage({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    required this.uniqueSize,
    required this.containers,
  });

  /// Untagged leftovers of rebuilt images.
  bool get isDangling => repository == '<none>' && tag == '<none>';

  bool get isUnused => containers == 0;

  String get name => isDangling
      ? id.replaceFirst('sha256:', '').substring(0, 12)
      : '$repository:$tag';
}

class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String state;

  /// The container's writable layer.
  final int size;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.size,
  });

  bool get isRunning =>
      state == 'running' || state == 'paused' || state == 'restarting';
}

class DockerVolume {
  final String name;

  /// Containers using it, stopped ones included.
  final int links;
  final int size;

  const DockerVolume({
    required this.name,
    required this.links,
    required this.size,
  });

  bool get isUnused => links == 0;
}

class DockerBuildCacheEntry {
  final String id;
  final String description;
  final int size;
  final bool inUse;
  final DateTime? lastUsed;

  const DockerBuildCacheEntry({
    required this.id,
    required this.description,
    required this.size,
    required this.inUse,
    this.lastUsed,
  });
}

/// What one prune removes. Applied in this order: containers first, so the
/// images and volumes they held become unused.
enum DockerCleanKind {
  /// `docker container prune`: stopped containers and their writable layer.
  stoppedContainers,

  /// `docker image prune`: untagged leftovers of rebuilt images.
  danglingImages,

  /// `docker image prune -a`: every image no container uses. They are
  /// downloaded or built again when needed.
  unusedImages,

  /// `docker builder prune -a`: build cache not in use. Builds get slower
  /// once.
  buildCache,

  /// `docker volume prune -a`: volumes no container uses. Their data is
  /// gone for good.
  unusedVolumes;

  List<String> get pruneArgs => switch (this) {
    stoppedContainers => const ['container', 'prune', '--force'],
    danglingImages => const ['image', 'prune', '--force'],
    unusedImages => const ['image', 'prune', '--all', '--force'],
    buildCache => const ['builder', 'prune', '--all', '--force'],
    unusedVolumes => const ['volume', 'prune', '--all', '--force'],
  };

  /// Regenerable: checked when results arrive. The rest is opt-in.
  bool get selectedByDefault => this == danglingImages || this == buildCache;
}

/// Docker's own view of its disk: images, containers, volumes and build
/// cache inside its VM disk or `/var/lib/docker`.
class DockerReport {
  final DockerStatus status;
  final List<DockerImage> images;
  final List<DockerContainer> containers;
  final List<DockerVolume> volumes;
  final List<DockerBuildCacheEntry> buildCache;

  /// Docker's own estimate per [DockerCleanKind] where it gives one
  /// (`docker system df`), else summed from the lists.
  final Map<String, int> reclaimableByType;

  /// Docker's total per type (`docker system df`): image layers shared
  /// between images are counted once.
  final Map<String, int> sizeByType;
  final String? message;

  const DockerReport({
    required this.status,
    this.images = const [],
    this.containers = const [],
    this.volumes = const [],
    this.buildCache = const [],
    this.reclaimableByType = const {},
    this.sizeByType = const {},
    this.message,
  });

  bool get isReady => status == DockerStatus.ready;

  int get imageBytes => sizeByType['Images'] ?? _sumImages(images);
  int get containerBytes =>
      sizeByType['Containers'] ?? containers.fold(0, (s, c) => s + c.size);
  int get volumeBytes =>
      sizeByType['Local Volumes'] ?? volumes.fold(0, (s, v) => s + v.size);
  int get buildCacheBytes =>
      sizeByType['Build Cache'] ?? buildCache.fold(0, (s, b) => s + b.size);
  int get totalBytes =>
      imageBytes + containerBytes + volumeBytes + buildCacheBytes;

  /// Images share layers, so their total is the shared part once plus each
  /// image's own layers.
  static int _sumImages(List<DockerImage> images) {
    if (images.isEmpty) return 0;
    final shared = images.fold<int>(
      0,
      (m, i) => (i.size - i.uniqueSize) > m ? i.size - i.uniqueSize : m,
    );
    return shared + images.fold<int>(0, (s, i) => s + i.uniqueSize);
  }

  /// What a prune of [kind] would free, as far as Docker tells.
  int bytesOf(DockerCleanKind kind) => switch (kind) {
    DockerCleanKind.stoppedContainers =>
      containers.where((c) => !c.isRunning).fold(0, (s, c) => s + c.size),
    DockerCleanKind.danglingImages =>
      images
          .where((i) => i.isDangling && i.isUnused)
          .fold(0, (s, i) => s + i.uniqueSize),
    DockerCleanKind.unusedImages =>
      reclaimableByType['Images'] ??
          images.where((i) => i.isUnused).fold(0, (s, i) => s + i.uniqueSize),
    DockerCleanKind.buildCache =>
      reclaimableByType['Build Cache'] ??
          buildCache.where((b) => !b.inUse).fold(0, (s, b) => s + b.size),
    DockerCleanKind.unusedVolumes =>
      reclaimableByType['Local Volumes'] ??
          volumes.where((v) => v.isUnused).fold(0, (s, v) => s + v.size),
  };

  int countOf(DockerCleanKind kind) => switch (kind) {
    DockerCleanKind.stoppedContainers =>
      containers.where((c) => !c.isRunning).length,
    DockerCleanKind.danglingImages =>
      images.where((i) => i.isDangling && i.isUnused).length,
    DockerCleanKind.unusedImages => images.where((i) => i.isUnused).length,
    DockerCleanKind.buildCache => buildCache.where((b) => !b.inUse).length,
    DockerCleanKind.unusedVolumes => volumes.where((v) => v.isUnused).length,
  };

  /// Prunes with something to remove.
  List<DockerCleanKind> get cleanable => [
    for (final kind in DockerCleanKind.values)
      if (countOf(kind) > 0) kind,
  ];
}

/// Reads and prunes Docker through its CLI. Nothing here touches Docker's
/// files directly: its disk is a VM image (Docker Desktop) or root-owned.
class DockerTool {
  final DockerRunner run;
  final String? Function() locate;

  DockerTool({DockerRunner? run, String? Function()? locate})
    : run = run ?? _defaultRun,
      locate = locate ?? defaultExecutable;

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> args,
  ) => Process.run(executable, args).timeout(const Duration(minutes: 10));

  /// GUI apps on macOS do not get the shell's PATH, so the usual install
  /// places are checked as well.
  static String? defaultExecutable() {
    final env = Platform.environment;
    final windows = Platform.isWindows;
    final name = windows ? 'docker.exe' : 'docker';
    final home = windows ? env['USERPROFILE'] : env['HOME'];
    final candidates = <String>[
      for (final dir in (env['PATH'] ?? '').split(windows ? ';' : ':'))
        if (dir.isNotEmpty) '$dir${Platform.pathSeparator}$name',
      if (Platform.isMacOS) ...[
        '/usr/local/bin/docker',
        '/opt/homebrew/bin/docker',
        '/Applications/Docker.app/Contents/Resources/bin/docker',
        if (home != null) '$home/.docker/bin/docker',
      ],
      if (Platform.isLinux) ...[
        '/usr/bin/docker',
        '/usr/local/bin/docker',
        if (home != null) '$home/.docker/bin/docker',
      ],
      if (windows) r'C:\Program Files\Docker\Docker\resources\bin\docker.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<DockerReport> load() async {
    final docker = locate();
    if (docker == null) {
      return const DockerReport(status: DockerStatus.notInstalled);
    }
    final ProcessResult verbose;
    final ProcessResult summary;
    try {
      verbose = await run(docker, const [
        'system',
        'df',
        '--verbose',
        '--format',
        'json',
      ]);
      if (verbose.exitCode != 0) {
        final error = '${verbose.stderr}'.trim();
        return DockerReport(
          status: _isDaemonDown(error)
              ? DockerStatus.notRunning
              : DockerStatus.failed,
          message: error,
        );
      }
      summary = await run(docker, const ['system', 'df', '--format', 'json']);
    } on Object catch (error) {
      return DockerReport(status: DockerStatus.failed, message: '$error');
    }
    return parse(
      '${verbose.stdout}',
      summary: summary.exitCode == 0 ? '${summary.stdout}' : '',
    );
  }

  static bool _isDaemonDown(String error) {
    final lower = error.toLowerCase();
    return lower.contains('cannot connect') ||
        lower.contains('is the docker daemon running') ||
        lower.contains('error during connect') ||
        lower.contains('docker desktop is not running');
  }

  /// Runs the prunes for [kinds] in [DockerCleanKind] order and returns the
  /// space Docker says each freed (0 when it does not say). An unused-images
  /// prune covers the dangling ones, so that prune is skipped.
  Future<Map<DockerCleanKind, int>> prune(
    Set<DockerCleanKind> kinds, {
    void Function(DockerCleanKind kind)? onStep,
  }) async {
    final docker = locate();
    if (docker == null) throw StateError('Docker is not installed');
    final freed = <DockerCleanKind, int>{};
    for (final kind in DockerCleanKind.values) {
      if (!kinds.contains(kind)) continue;
      if (kind == DockerCleanKind.danglingImages &&
          kinds.contains(DockerCleanKind.unusedImages)) {
        continue;
      }
      onStep?.call(kind);
      final result = await run(docker, kind.pruneArgs);
      if (result.exitCode != 0) {
        throw StateError(
          '${kind.pruneArgs.take(2).join(' ')}: ${'${result.stderr}'.trim()}',
        );
      }
      freed[kind] = reclaimedBytes('${result.stdout}');
    }
    return freed;
  }

  /// `Total reclaimed space: 1.2GB` (prunes) or `Total: 3GB` (builder).
  static int reclaimedBytes(String output) {
    final match = RegExp(
      r'Total(?: reclaimed space)?:\s*([\d.]+\s*[kMGTP]?i?B)',
      caseSensitive: false,
    ).firstMatch(output);
    return match == null ? 0 : parseSize(match.group(1)!);
  }

  static DockerReport parse(String verbose, {String summary = ''}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(verbose.trim());
    } on FormatException catch (error) {
      return DockerReport(status: DockerStatus.failed, message: '$error');
    }
    if (decoded is! Map) {
      return const DockerReport(status: DockerStatus.failed);
    }
    final json = decoded;
    List<Map> list(String key) => [
      for (final item in (json[key] as List?) ?? const [])
        if (item is Map) item,
    ];
    String text(Map item, String key) => '${item[key] ?? ''}';
    int number(Map item, String key) => int.tryParse(text(item, key)) ?? 0;
    bool flag(Map item, String key) =>
        item[key] == true || text(item, key) == 'true';

    final reclaimable = <String, int>{};
    final sizes = <String, int>{};
    for (final line in const LineSplitter().convert(summary)) {
      try {
        final row = jsonDecode(line);
        if (row is Map && row['Type'] is String) {
          reclaimable['${row['Type']}'] = parseSize(
            '${row['Reclaimable'] ?? ''}'.split(' ').first,
          );
          sizes['${row['Type']}'] = parseSize('${row['Size'] ?? ''}');
        }
      } on FormatException {
        continue;
      }
    }

    return DockerReport(
      status: DockerStatus.ready,
      reclaimableByType: reclaimable,
      sizeByType: sizes,
      images: [
        for (final item in list('Images'))
          DockerImage(
            id: text(item, 'ID'),
            repository: text(item, 'Repository'),
            tag: text(item, 'Tag'),
            size: parseSize(text(item, 'Size')),
            uniqueSize: parseSize(text(item, 'UniqueSize')),
            containers: number(item, 'Containers'),
          ),
      ],
      containers: [
        for (final item in list('Containers'))
          DockerContainer(
            id: text(item, 'ID'),
            name: text(item, 'Names'),
            image: text(item, 'Image'),
            state: text(item, 'State'),
            // "2B (virtual 300MB)": the writable layer only.
            size: parseSize(text(item, 'Size').split(' ').first),
          ),
      ],
      volumes: [
        for (final item in list('Volumes'))
          DockerVolume(
            name: text(item, 'Name'),
            links: number(item, 'Links'),
            size: parseSize(text(item, 'Size')),
          ),
      ],
      buildCache: [
        for (final item in list('BuildCache'))
          DockerBuildCacheEntry(
            id: text(item, 'ID'),
            description: text(item, 'Description'),
            size: parseSize(text(item, 'Size')),
            inUse: flag(item, 'InUse'),
            lastUsed: DateTime.tryParse(
              text(item, 'LastUsedAt').split(' ').take(2).join('T'),
            ),
          ),
      ],
    );
  }

  /// Docker prints decimal sizes (`13.86GB`, `380.9kB`, `89B`); `N/A` and
  /// unknown text are 0.
  static int parseSize(String value) {
    final match = RegExp(
      r'^([\d.]+)\s*([kKMGTP]?)(i?)B$',
    ).firstMatch(value.trim());
    if (match == null) return 0;
    final amount = double.tryParse(match.group(1)!) ?? 0;
    final base = match.group(3)!.isEmpty ? 1000 : 1024;
    final power = switch (match.group(2)!.toUpperCase()) {
      'K' => 1,
      'M' => 2,
      'G' => 3,
      'T' => 4,
      'P' => 5,
      _ => 0,
    };
    var factor = 1;
    for (var i = 0; i < power; i++) {
      factor *= base;
    }
    return (amount * factor).round();
  }
}

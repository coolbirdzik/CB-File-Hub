import 'disk_tree_node.dart';

/// A well-known reason a Windows drive fills up.
///
/// These are explanations for CB Agent, not cleanup rules: a matched path is
/// never selected or deleted because of this table. Deletion safety still
/// comes from [CleanerCategories] and the user's review.
class CleanerSpaceCause {
  final String id;
  final String label;

  /// Why this path is typically large.
  final String explanation;

  /// The safe way to reclaim space, which is often not deleting the path.
  final String action;

  /// CLEAN, REVIEW or KEEP as a starting point for the agent's assessment.
  final String verdict;

  final bool filesOnly;
  final RegExp _pattern;

  CleanerSpaceCause({
    required this.id,
    required this.label,
    required this.explanation,
    required this.action,
    required this.verdict,
    required String pattern,
    this.filesOnly = false,
  }) : _pattern = RegExp(pattern);

  bool matches(String normalizedPath, bool isFile) =>
      (!filesOnly || isFile) && _pattern.hasMatch(normalizedPath);
}

class CleanerSpaceCauseMatch {
  final CleanerSpaceCause cause;
  final List<DiskTreeNode> nodes;

  CleanerSpaceCauseMatch(this.cause) : nodes = <DiskTreeNode>[];

  int get totalBytes => nodes.fold(0, (sum, node) => sum + node.sizeBytes);
}

/// A node where space concentrates: at least the threshold in size, but no
/// single child reaches it, so this is the most specific place to look.
class CleanerSpaceHotspot {
  final DiskTreeNode node;

  /// Bytes held directly by this node rather than by a child above threshold.
  final int spreadBytes;

  /// True when the node has large children, but its remaining contents are
  /// themselves large enough to report.
  final bool isResidual;

  const CleanerSpaceHotspot({
    required this.node,
    required this.spreadBytes,
    this.isResidual = false,
  });
}

class CleanerFileTypeTotal {
  final String group;
  int bytes = 0;
  int files = 0;
  final List<DiskTreeNode> largest = <DiskTreeNode>[];

  CleanerFileTypeTotal(this.group);
}

/// Read-only diagnosis of a full-disk scan tree for CB Agent.
class CleanerSpaceInsights {
  CleanerSpaceInsights._();

  static String normalize(String path) => path
      .trim()
      .replaceAll('/', r'\')
      .toUpperCase()
      .replaceFirst(RegExp(r'\\+$'), '');

  static const _user = r'^[A-Z]:\\USERS\\[^\\]+';
  static const _local =
      '$_user'
      r'\\APPDATA\\LOCAL';
  static const _roaming =
      '$_user'
      r'\\APPDATA\\ROAMING';

  /// Ordered from specific to generic. The first match wins and its subtree
  /// is not searched again, so a cause is never counted twice.
  static final List<CleanerSpaceCause> causes = [
    CleanerSpaceCause(
      id: 'hibernation_file',
      label: 'Hibernation file (hiberfil.sys)',
      explanation:
          'Holds RAM contents for hibernate and Fast Startup; usually 40-75% of installed RAM.',
      action:
          'Do not delete the file. Run "powercfg /h off" as admin to disable hibernation and Fast Startup, or "powercfg /h /type reduced" to shrink it.',
      verdict: 'KEEP',
      pattern: r'^[A-Z]:\\HIBERFIL\.SYS$',
      filesOnly: true,
    ),
    CleanerSpaceCause(
      id: 'page_file',
      label: 'Virtual memory (pagefile.sys / swapfile.sys)',
      explanation:
          'Windows paging file; Windows sizes it automatically from RAM and memory pressure.',
      action:
          'Do not delete the file. Adjust it only under System > Advanced system settings > Performance > Virtual memory.',
      verdict: 'KEEP',
      pattern: r'^[A-Z]:\\(PAGEFILE|SWAPFILE)\.SYS$',
      filesOnly: true,
    ),
    CleanerSpaceCause(
      id: 'restore_points',
      label: 'System Restore / shadow copies',
      explanation:
          'Restore points and Volume Shadow Copies. Usually not readable by the scan, so it often appears as unaccounted space.',
      action:
          'Check with "vssadmin list shadowstorage". Reduce Max Usage or delete old restore points in System Protection > Configure.',
      verdict: 'REVIEW',
      pattern: r'^[A-Z]:\\SYSTEM VOLUME INFORMATION$',
    ),
    CleanerSpaceCause(
      id: 'previous_windows',
      label: 'Previous Windows installation (Windows.old)',
      explanation:
          'Left after a Windows feature upgrade so you can roll back; Windows removes it after about 10 days.',
      action:
          'Remove from Settings > System > Storage > Temporary files > Previous Windows installation(s) once the upgrade is stable. Rollback is lost.',
      verdict: 'REVIEW',
      pattern: r'^[A-Z]:\\(WINDOWS\.OLD|\$WINDOWS\.~BT|\$WINDOWS\.~WS)$',
    ),
    CleanerSpaceCause(
      id: 'recycle_bin',
      label: 'Recycle Bin',
      explanation: 'Deleted files still occupy space until the bin is emptied.',
      action: 'Empty the Recycle Bin after checking nothing needs restoring.',
      verdict: 'REVIEW',
      pattern: r'^[A-Z]:\\\$RECYCLE\.BIN$',
    ),
    CleanerSpaceCause(
      id: 'component_store',
      label: 'Windows component store (WinSxS)',
      explanation:
          'Windows components and update backups. Much of its apparent size is hard links shared with C:\\Windows, so the real cost is smaller.',
      action:
          'Never delete manually. Run "Dism /Online /Cleanup-Image /StartComponentCleanup" or Disk Cleanup > Windows Update Cleanup.',
      verdict: 'KEEP',
      pattern: r'^[A-Z]:\\WINDOWS\\WINSXS$',
    ),
    CleanerSpaceCause(
      id: 'installer_cache',
      label: 'Windows Installer cache',
      explanation:
          'MSI/MSP packages Windows needs to repair, patch and uninstall installed programs.',
      action:
          'Never delete manually; uninstall unused programs instead. Removing it breaks repair and uninstall.',
      verdict: 'KEEP',
      pattern: r'^[A-Z]:\\(WINDOWS\\INSTALLER|PROGRAMDATA\\PACKAGE CACHE)$',
    ),
    CleanerSpaceCause(
      id: 'windows_update_download',
      label: 'Windows Update downloads',
      explanation:
          'Downloaded update packages and Delivery Optimization cache.',
      action:
          'Use the windows_update_cache cleaner category or Disk Cleanup > Windows Update Cleanup / Delivery Optimization Files.',
      verdict: 'CLEAN',
      pattern:
          r'^[A-Z]:\\WINDOWS\\(SOFTWAREDISTRIBUTION\\DOWNLOAD|SERVICEPROFILES\\NETWORKSERVICE\\APPDATA\\LOCAL\\MICROSOFT\\WINDOWS\\DELIVERYOPTIMIZATION)$',
    ),
    CleanerSpaceCause(
      id: 'crash_dumps',
      label: 'Crash dumps and error reports',
      explanation:
          'Memory dumps and Windows Error Reporting archives created after crashes.',
      action:
          'Safe to remove unless someone is troubleshooting a crash; Disk Cleanup lists them as system error memory dump files.',
      verdict: 'CLEAN',
      pattern:
          r'(^[A-Z]:\\WINDOWS\\(MEMORY\.DMP|MINIDUMP|LIVEKERNELREPORTS)$|^[A-Z]:\\PROGRAMDATA\\MICROSOFT\\WINDOWS\\WER$|'
          '$_local'
          r'\\CRASHDUMPS$)',
    ),
    CleanerSpaceCause(
      id: 'temp_files',
      label: 'Temporary files',
      explanation: 'Leftovers from installers, updates and running apps.',
      action: 'Use the windows_temp/user_temp cleaner categories.',
      verdict: 'CLEAN',
      pattern:
          r'(^[A-Z]:\\WINDOWS\\TEMP$|'
          '$_local'
          r'\\TEMP$)',
    ),
    CleanerSpaceCause(
      id: 'wsl_disk',
      label: 'WSL Linux distribution disk',
      explanation:
          'A WSL distro virtual disk (ext4.vhdx). It grows as Linux writes files and does not shrink by itself after deletions.',
      action:
          'Clean files inside Linux, run "wsl --shutdown", then compact the VHDX (Optimize-VHD or diskpart "compact vdisk"). Never delete it unless the distro is unwanted; it holds all Linux data.',
      verdict: 'REVIEW',
      pattern: r'\\EXT4\.VHDX$',
      filesOnly: true,
    ),
    CleanerSpaceCause(
      id: 'docker_data',
      label: 'Docker Desktop data',
      explanation:
          'Images, containers, build cache and volumes stored in a growing virtual disk.',
      action:
          'Run "docker system df" then "docker system prune" (volumes only after review), and compact the disk from Docker Desktop.',
      verdict: 'REVIEW',
      pattern:
          r'('
          '$_local'
          r'\\DOCKER$|^[A-Z]:\\PROGRAMDATA\\DOCKER(DESKTOP)?$|\\DOCKER_DATA\.VHDX$)',
    ),
    CleanerSpaceCause(
      id: 'virtual_machine_disk',
      label: 'Virtual machine / disk image',
      explanation:
          'A virtual machine disk or mounted disk image; contains a full operating system or data volume.',
      action:
          'Delete only VMs the user no longer needs, from the VM manager; otherwise compact or move it to another drive.',
      verdict: 'REVIEW',
      pattern: r'\.(VHDX?|VMDK|VDI|QCOW2|AVHDX)$',
      filesOnly: true,
    ),
    CleanerSpaceCause(
      id: 'android_dev',
      label: 'Android SDK / emulators',
      explanation:
          'Android SDK platforms, system images and emulator (AVD) disks.',
      action:
          'Remove unused system images and AVDs from Android Studio Device Manager / SDK Manager.',
      verdict: 'REVIEW',
      pattern:
          r'('
          '$_local'
          r'\\ANDROID\\SDK$|'
          '$_user'
          r'\\\.ANDROID\\AVD$)',
    ),
    CleanerSpaceCause(
      id: 'ai_models',
      label: 'Downloaded AI models',
      explanation:
          'Local LLM / diffusion model weights from Hugging Face, Ollama, LM Studio and similar tools; often several GB each.',
      action:
          'Remove models the user no longer uses from the owning tool; they can be downloaded again.',
      verdict: 'REVIEW',
      pattern:
          r'('
          '$_user'
          r'\\\.CACHE\\HUGGINGFACE$|'
          '$_user'
          r'\\\.OLLAMA\\MODELS$|'
          '$_user'
          r'\\\.LMSTUDIO\\MODELS$|\.(GGUF|SAFETENSORS|CKPT)$)',
    ),
    CleanerSpaceCause(
      id: 'dev_package_cache',
      label: 'Developer package caches',
      explanation:
          'Downloaded build dependencies (Gradle, Maven, NuGet, npm, Yarn, pip, Cargo, Pub, Go, Conda).',
      action:
          'Re-downloadable. Clear with the tool itself (e.g. "npm cache clean --force", "dart pub cache clean", "gradle --stop" then delete caches) or the dev_cache category.',
      verdict: 'CLEAN',
      pattern:
          r'('
          '$_user'
          r'\\(\.GRADLE\\CACHES|\.M2\\REPOSITORY|\.NUGET\\PACKAGES|\.CARGO\\REGISTRY|GO\\PKG\\MOD|\.CONDA\\PKGS|(ANACONDA|MINICONDA)3\\PKGS)$|'
          '$_local'
          r'\\(NPM-CACHE|YARN\\CACHE|PIP\\CACHE|PUB\\CACHE)$|'
          '$_roaming'
          r'\\(NPM-CACHE|PUB\\CACHE)$)',
    ),
    CleanerSpaceCause(
      id: 'node_modules',
      label: 'node_modules folders',
      explanation:
          'JavaScript project dependencies; recreated by "npm install" from package.json.',
      action:
          'Remove from inactive projects only; reinstall when the project is used again.',
      verdict: 'REVIEW',
      pattern: r'\\NODE_MODULES$',
    ),
    CleanerSpaceCause(
      id: 'game_library',
      label: 'Installed games',
      explanation: 'Game installs from Steam, Epic, Xbox, Riot or EA.',
      action:
          'Uninstall unplayed games from their launcher (not by deleting folders); they can be redownloaded.',
      verdict: 'REVIEW',
      pattern:
          r'(\\STEAMAPPS\\COMMON$|\\EPIC GAMES$|^[A-Z]:\\XBOXGAMES$|\\RIOT GAMES$|\\EA GAMES$)',
    ),
    CleanerSpaceCause(
      id: 'cloud_sync',
      label: 'Cloud-synced folder',
      explanation:
          'Files kept locally by OneDrive, Google Drive, Dropbox or iCloud. Deleting here usually deletes them from the cloud too.',
      action:
          'Use the sync client\'s "Free up space" / online-only mode instead of deleting.',
      verdict: 'KEEP',
      pattern:
          r'('
          '$_user'
          r'\\(ONEDRIVE[^\\]*|DROPBOX|GOOGLE DRIVE|ICLOUDDRIVE)$)',
    ),
    CleanerSpaceCause(
      id: 'phone_backup',
      label: 'iPhone / iPad backups',
      explanation:
          'Full device backups made by iTunes or Apple Devices; each can be tens of GB.',
      action:
          'Delete old device backups from Apple Devices / iTunes > Manage Backups.',
      verdict: 'REVIEW',
      pattern: r'\\APPLE( COMPUTER)?\\MOBILESYNC\\BACKUP$',
    ),
    CleanerSpaceCause(
      id: 'mail_data',
      label: 'Outlook mail data',
      explanation:
          '.ost is a rebuildable offline cache of a mailbox; .pst is a personal archive that may be the only copy of mail.',
      action:
          'For .ost reduce "Mail to keep offline" in Outlook. Never delete .pst without a backup.',
      verdict: 'KEEP',
      pattern: r'\.(OST|PST)$',
      filesOnly: true,
    ),
    CleanerSpaceCause(
      id: 'downloads',
      label: 'Downloads folder',
      explanation:
          'Accumulates installers, archives and media that were only needed once.',
      action:
          'Let the user sort by size/date and remove what they recognise; installers and archives are typical candidates.',
      verdict: 'REVIEW',
      pattern:
          '$_user'
          r'\\DOWNLOADS$',
    ),
    CleanerSpaceCause(
      id: 'personal_files',
      label: 'Personal files',
      explanation:
          'Documents, photos, videos and music the user created or collected.',
      action:
          'Never delete automatically. Suggest moving to another drive, external storage or cloud.',
      verdict: 'KEEP',
      pattern:
          '$_user'
          r'\\(DOCUMENTS|PICTURES|VIDEOS|MUSIC|DESKTOP)$',
    ),
  ];

  static CleanerSpaceCause? causeFor(DiskTreeNode node) {
    return causeForPath(node.fullPath, isFile: node.isFile);
  }

  /// Match metadata without constructing or transferring a scan-tree node.
  static CleanerSpaceCause? causeForPath(String path, {required bool isFile}) {
    if (path.isEmpty) return null;
    return _causeForPath(normalize(path), isFile);
  }

  /// The cause of [path] itself or of the nearest ancestor folder that has
  /// one, e.g. a file deep inside a Steam library resolves to "Installed
  /// games".
  static CleanerSpaceCause? causeWithin(String path, {bool isFile = false}) {
    var current = normalize(path);
    var currentIsFile = isFile;
    while (current.isNotEmpty) {
      final cause = _causeForPath(current, currentIsFile);
      if (cause != null) return cause;
      final slash = current.lastIndexOf(r'\');
      if (slash <= 2) return null;
      current = current.substring(0, slash);
      currentIsFile = false;
    }
    return null;
  }

  static CleanerSpaceCause? _causeForPath(String normalizedPath, bool isFile) {
    for (final cause in causes) {
      if (cause.matches(normalizedPath, isFile)) return cause;
    }
    return null;
  }

  /// Every known cause in [root], largest first. Each subtree is attributed to
  /// the outermost matching path only.
  static List<CleanerSpaceCauseMatch> findCauses(DiskTreeNode root) {
    final byId = <String, CleanerSpaceCauseMatch>{};
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final cause = identical(node, root) ? null : causeFor(node);
      if (cause != null) {
        (byId[cause.id] ??= CleanerSpaceCauseMatch(cause)).nodes.add(node);
        continue;
      }
      stack.addAll(node.children);
    }
    final matches = byId.values.where((match) => match.totalBytes > 0).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    for (final match in matches) {
      match.nodes.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
    return matches;
  }

  /// The minimum size worth reporting as a hotspot on a drive of [rootBytes].
  static int hotspotThreshold(int rootBytes) {
    const floor = 256 * 1024 * 1024;
    final relative = rootBytes ~/ 200; // 0.5%
    return relative > floor ? relative : floor;
  }

  /// The most specific nodes holding at least [threshold] bytes, largest
  /// first. Ancestors are omitted unless their remaining contents are large.
  static List<CleanerSpaceHotspot> findHotspots(
    DiskTreeNode root, {
    int? threshold,
    int limit = 15,
  }) {
    final minBytes = threshold ?? hotspotThreshold(root.sizeBytes);
    final hotspots = <CleanerSpaceHotspot>[];
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node.sizeBytes < minBytes) continue;
      final largeChildren = node.children
          .where(
            (child) => child.fullPath.isNotEmpty && child.sizeBytes >= minBytes,
          )
          .toList();
      final isTarget = node.fullPath.isNotEmpty && !identical(node, root);
      if (largeChildren.isEmpty) {
        if (isTarget) {
          hotspots.add(
            CleanerSpaceHotspot(node: node, spreadBytes: node.sizeBytes),
          );
        }
        continue;
      }
      final residual =
          node.sizeBytes -
          largeChildren.fold<int>(0, (sum, child) => sum + child.sizeBytes);
      if (isTarget && residual >= minBytes) {
        hotspots.add(
          CleanerSpaceHotspot(
            node: node,
            spreadBytes: residual,
            isResidual: true,
          ),
        );
      }
      stack.addAll(largeChildren);
    }
    hotspots.sort((a, b) => b.spreadBytes.compareTo(a.spreadBytes));
    return hotspots.length > limit ? hotspots.sublist(0, limit) : hotspots;
  }

  static const Map<String, Set<String>> fileTypeGroups = {
    'video': {
      'MP4',
      'MKV',
      'AVI',
      'MOV',
      'WMV',
      'M4V',
      'WEBM',
      'TS',
      'MTS',
      'M2TS',
      'FLV',
      'MPG',
      'MPEG',
    },
    'disk_image': {
      'ISO',
      'IMG',
      'VHD',
      'VHDX',
      'VMDK',
      'VDI',
      'QCOW2',
      'WIM',
      'ESD',
    },
    'archive': {'ZIP', 'RAR', '7Z', 'TAR', 'GZ', 'TGZ', 'XZ', 'BZ2', 'ZST'},
    'installer': {
      'EXE',
      'MSI',
      'MSIX',
      'MSIXBUNDLE',
      'APPX',
      'APPXBUNDLE',
      'APK',
      'CAB',
      'MSP',
    },
    'ai_model': {'GGUF', 'SAFETENSORS', 'CKPT', 'PT', 'PTH', 'ONNX'},
    'database_mail': {'OST', 'PST', 'DB', 'SQLITE', 'MDF', 'LDF', 'EDB'},
    'audio': {'MP3', 'FLAC', 'WAV', 'M4A', 'AAC', 'OGG', 'WMA', 'AIFF'},
    'image_raw': {
      'JPG',
      'JPEG',
      'PNG',
      'HEIC',
      'PSD',
      'TIF',
      'TIFF',
      'RAW',
      'CR2',
      'CR3',
      'NEF',
      'ARW',
      'DNG',
    },
    'dump_log': {'DMP', 'HDMP', 'MDMP', 'LOG', 'ETL', 'TMP'},
    'game_data': {'PAK', 'UCAS', 'UTOC', 'BUNDLE', 'VPK', 'ASSETS'},
  };

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toUpperCase();
  }

  static String? groupOfExtension(String extension) {
    for (final entry in fileTypeGroups.entries) {
      if (entry.value.contains(extension)) return entry.key;
    }
    return null;
  }

  /// Totals of real file rows under [root] by type group, largest first.
  ///
  /// Only files kept as rows by the scan are counted; small files rolled up
  /// into aggregate rows have no name and are reported as "other".
  static List<CleanerFileTypeTotal> fileTypeTotals(
    DiskTreeNode root, {
    int largestPerGroup = 3,
  }) {
    final totals = <String, CleanerFileTypeTotal>{};
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (!node.isFile) {
        stack.addAll(node.children);
        continue;
      }
      final group = node.isAggregate
          ? 'other'
          : groupOfExtension(extensionOf(node.name)) ?? 'other';
      final total = totals[group] ??= CleanerFileTypeTotal(group);
      total.bytes += node.sizeBytes;
      total.files += node.isAggregate ? node.aggregatedItemCount : 1;
      if (!node.isAggregate && node.fullPath.isNotEmpty) {
        total.largest.add(node);
        total.largest.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        if (total.largest.length > largestPerGroup) total.largest.removeLast();
      }
    }
    return totals.values.where((total) => total.bytes > 0).toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
  }

  static DiskTreeNode? find(DiskTreeNode root, String path) {
    final target = normalize(path);
    if (target.isEmpty || target == normalize(root.fullPath)) return root;
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final candidate = normalize(node.fullPath);
      if (candidate == target) return node;
      if (node.fullPath.isEmpty || target.startsWith('$candidate\\')) {
        stack.addAll(node.children);
      }
    }
    return null;
  }

  /// Nodes under [scope] that pass every supplied filter, largest first.
  ///
  /// A matching folder is not searched further, so nested matches are never
  /// counted twice in [totalBytes].
  static ({List<DiskTreeNode> matches, int count, int totalBytes}) search(
    DiskTreeNode scope, {
    String? query,
    Set<String> extensions = const {},
    String? typeGroup,
    int minBytes = 0,
    String kind = 'any',
    int limit = 20,
  }) {
    final needle = query?.trim().toUpperCase() ?? '';
    final groupExtensions = typeGroup == null
        ? null
        : fileTypeGroups[typeGroup];
    final matches = <DiskTreeNode>[];
    var count = 0;
    var totalBytes = 0;
    bool passes(DiskTreeNode node) {
      if (node.fullPath.isEmpty || node.isAggregate) return false;
      if (kind == 'file' && !node.isFile) return false;
      if (kind == 'folder' && node.isFile) return false;
      if (needle.isNotEmpty && !node.name.toUpperCase().contains(needle)) {
        return false;
      }
      if (extensions.isEmpty && groupExtensions == null) return true;
      if (!node.isFile) return false;
      final extension = extensionOf(node.name);
      return (extensions.isEmpty || extensions.contains(extension)) &&
          (groupExtensions == null || groupExtensions.contains(extension));
    }

    final stack = <DiskTreeNode>[...scope.children];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      // Children are never larger than their parent.
      if (node.sizeBytes < minBytes) continue;
      if (!passes(node)) {
        stack.addAll(node.children);
        continue;
      }
      count++;
      totalBytes += node.sizeBytes;
      matches.add(node);
      if (matches.length > limit * 4) {
        matches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        matches.removeRange(limit, matches.length);
      }
    }
    matches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return (
      matches: matches.length > limit ? matches.sublist(0, limit) : matches,
      count: count,
      totalBytes: totalBytes,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';

/// A small indicator for an external SRT beside a video or in its Subs folder.
class SubtitleThumbnailBadge extends StatefulWidget {
  final String videoPath;

  const SubtitleThumbnailBadge({super.key, required this.videoPath});

  @override
  State<SubtitleThumbnailBadge> createState() => _SubtitleThumbnailBadgeState();
}

class _SubtitleThumbnailBadgeState extends State<SubtitleThumbnailBadge> {
  _SubtitleFolderIndex? _index;
  bool _hasSubtitle = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(SubtitleThumbnailBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (p.dirname(oldWidget.videoPath) != p.dirname(widget.videoPath)) {
      _detach();
      _attach();
    }
    _hasSubtitle = _index?.hasSubtitle(widget.videoPath) ?? false;
  }

  void _attach() {
    final path = widget.videoPath;
    // Virtual network paths are not local filesystem directories.
    if (!p.isAbsolute(path) || path.contains('://')) return;
    _index = _SubtitleFolderIndex.acquire(p.normalize(p.dirname(path)));
    _index!.addListener(_changed);
    _hasSubtitle = _index!.hasSubtitle(path);
  }

  void _detach() {
    _index?.removeListener(_changed);
    _index?.release();
    _index = null;
  }

  void _changed() {
    final hasSubtitle = _index?.hasSubtitle(widget.videoPath) ?? false;
    if (_hasSubtitle != hasSubtitle) setState(() => _hasSubtitle = hasSubtitle);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSubtitle) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Semantics(
        label: 'SRT',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(
              PhosphorIconsBold.subtitles,
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// One asynchronous directory index per mounted grid folder. Check directory
/// metadata periodically so new queue exports appear without reopening the grid.
class _SubtitleFolderIndex extends ChangeNotifier {
  static final _active = <String, _SubtitleFolderIndex>{};
  final String folder;
  final Set<String> _stems = {};
  late final Timer _timer;
  int _users = 0;
  bool _loading = false, _disposed = false;
  (DateTime?, DateTime?)? _stamp;

  _SubtitleFolderIndex(this.folder) {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  static _SubtitleFolderIndex acquire(String folder) {
    final key = Platform.isWindows ? folder.toLowerCase() : folder;
    final index = _active.putIfAbsent(key, () => _SubtitleFolderIndex(folder));
    index._users++;
    return index;
  }

  void release() {
    if (--_users != 0) return;
    _active.remove(Platform.isWindows ? folder.toLowerCase() : folder);
    _disposed = true;
    _timer.cancel();
    dispose();
  }

  bool hasSubtitle(String video) =>
      _stems.contains(_key(p.basenameWithoutExtension(video))) ||
      _stems.contains(_key(p.basename(video)));

  static String _key(String name) => name.toLowerCase();

  static final _variant = RegExp(
    r'\.(?:[a-z]{2,3}(?:[-_][a-z0-9]{2,8})*|forced|sdh|cc|ai)$',
  );

  static Future<DateTime?> _modified(String directory) async {
    final stat = await Directory(directory).stat();
    return stat.type == FileSystemEntityType.directory ? stat.modified : null;
  }

  Future<void> _refresh() async {
    if (_loading || _disposed) return;
    _loading = true;
    try {
      final subs = p.join(folder, 'Subs');
      final stamp = (await _modified(folder), await _modified(subs));
      if (_disposed || _stamp == stamp) return;
      final srtStems = <String>{};
      final videoNames = <String>{};
      for (final directory in [folder, if (stamp.$2 != null) subs]) {
        try {
          await for (final entry in Directory(
            directory,
          ).list(followLinks: false)) {
            if (_disposed) return;
            if (entry is! File) continue;
            final extension = p.extension(entry.path).toLowerCase();
            final stem = _key(p.basenameWithoutExtension(entry.path));
            if (extension == '.srt') {
              srtStems.add(stem);
            } else if (directory == folder &&
                FileTypeRegistry.getCategory(extension) == FileCategory.video) {
              videoNames.addAll([stem, _key(p.basename(entry.path))]);
            }
          }
        } on FileSystemException {
          // Missing/inaccessible directories may be retried on the next tick.
          return;
        }
      }
      if (_disposed) return;
      final stems = <String>{};
      for (var stem in srtStems) {
        // Prefer the exact/longest video name: movie.en.mkv must not cause
        // movie.mkv to show a badge when only movie.en.srt exists.
        while (!videoNames.contains(stem) && _variant.hasMatch(stem)) {
          stem = stem.replaceFirst(_variant, '');
        }
        if (videoNames.contains(stem)) stems.add(stem);
      }
      _stamp = stamp;
      if (_stems.length == stems.length && _stems.containsAll(stems)) return;
      _stems
        ..clear()
        ..addAll(stems);
      notifyListeners();
    } on FileSystemException {
      // A drive can disappear while its grid remains open.
    } finally {
      _loading = false;
    }
  }
}

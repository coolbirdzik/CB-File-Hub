import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';

/// Shows all tags on hover, independently of the visible tag-chip limit.
/// Reads metadata only for the hovered file, including views with hidden tags.
class FileTagsTooltip extends StatefulWidget {
  const FileTagsTooltip({
    super.key,
    required this.path,
    required this.child,
    this.loadTags = TagManager.getTags,
  });

  final String path;
  final Widget child;
  final Future<List<String>> Function(String path) loadTags;

  @override
  State<FileTagsTooltip> createState() => _FileTagsTooltipState();
}

class _FileTagsTooltipState extends State<FileTagsTooltip> {
  List<String> _tags = const [];
  StreamSubscription<String>? _subscription;
  bool _hovering = false;
  int _request = 0;

  @override
  void didUpdateWidget(FileTagsTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.loadTags != widget.loadTags) {
      _request++;
      _tags = const [];
      if (_hovering) _refreshTags();
    }
  }

  Future<void> _refreshTags() async {
    final request = ++_request;
    try {
      final tags = await widget.loadTags(widget.path);
      if (!mounted || request != _request) return;
      setState(() => _tags = List.of(tags));
    } catch (error) {
      // Metadata failures must not interfere with opening or selecting files.
      debugPrint('Could not load hover tags for ${widget.path}: $error');
    }
  }

  void _onEnter() {
    _hovering = true;
    _subscription ??= TagManager.onTagChanged.listen((changedPath) {
      final path = changedPath.replaceFirst(
        RegExp(r'^(preserve_scroll:|tag_only:)'),
        '',
      );
      if (path == widget.path || path.startsWith('global:')) _refreshTags();
    });
    _refreshTags();
  }

  void _onExit() {
    _hovering = false;
    _request++;
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: CbTooltip(
        message: [
          p.basename(widget.path),
          ..._tags.map((tag) => '#$tag'),
        ].join('\n'),
        waitDuration: const Duration(milliseconds: 500),
        triggerMode: TooltipTriggerMode.manual,
        child: widget.child,
      ),
    );
  }
}

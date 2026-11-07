import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../utils/format_utils.dart';
import '../../../../services/media/subtitle_cache.dart';

/// Shared in subtitle settings and the CB Agent/model manager.
class SubtitleCacheControls extends StatefulWidget {
  final SubtitleCache? cache;
  const SubtitleCacheControls({super.key, this.cache});
  @override
  State<SubtitleCacheControls> createState() => _SubtitleCacheControlsState();
}

class _SubtitleCacheControlsState extends State<SubtitleCacheControls> {
  SubtitleCacheStats? _stats;
  bool _busy = false;
  String? _error;
  SubtitleCache get cache => widget.cache ?? SubtitleCache.instance;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final stats = await cache.stats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await cache.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final stats = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(l.aiSubtitleCache, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(l.aiSubtitleCacheHint),
        if (stats != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.aiSubtitleCacheStats(
                stats.entries,
                FormatUtils.formatFileSize(stats.bytes),
              ),
            ),
          ),
        if (_error != null)
          Text(
            '${l.aiSubtitleCacheFailed}\n$_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton.icon(
          key: const ValueKey('ai-subtitle-clear-cache'),
          onPressed: _busy ? null : _clear,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_sweep_outlined),
          label: Text(l.aiSubtitleCacheClear),
        ),
      ],
    );
  }
}

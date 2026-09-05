import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';
import 'package:cb_file_manager/helpers/media/fc_native_video_thumbnail.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:image/image.dart' as img;

/// A dialog that lets the user seek through a video and pick a specific frame
/// as a thumbnail image.
///
/// Returns the path to the extracted JPEG file, or `null` if cancelled.
class VideoFramePickerDialog extends StatefulWidget {
  /// Path to the video file.
  final String videoPath;

  const VideoFramePickerDialog({super.key, required this.videoPath});

  /// Show the dialog and return the path to the extracted thumbnail, or null.
  static Future<String?> show(BuildContext context, String videoPath) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VideoFramePickerDialog(videoPath: videoPath),
    );
  }

  @override
  State<VideoFramePickerDialog> createState() => _VideoFramePickerDialogState();
}

class _VideoFramePickerDialogState extends State<VideoFramePickerDialog> {
  late final Player _player;
  late final VideoController _videoController;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _selectedSecond = 0;
  bool _isLoading = true;
  bool _isExtracting = false;
  String? _error;

  // Preview frame (captured bytes)
  Uint8List? _previewBytes;
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      // Listen for duration
      _player.stream.duration.listen((d) {
        if (mounted && d.inMilliseconds > 0) {
          setState(() {
            _duration = d;
            _selectedSecond = _selectedSecond.clamp(0, d.inSeconds);
          });
        }
      });

      // Listen for position
      _player.stream.position.listen((p) {
        if (mounted) {
          setState(() => _position = p);
        }
      });

      // Listen for errors
      _player.stream.error.listen((e) {
        if (mounted) {
          setState(() {
            _error = e;
            _isLoading = false;
          });
        }
      });

      // Open the video paused
      await _player.open(Media(widget.videoPath), play: false);

      // Wait a bit for the first frame to render
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      AppLogger.error('[VideoFramePicker] Failed to init player', error: e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _seekTo(Duration position) async {
    final second = position.inSeconds.clamp(0, _duration.inSeconds);
    if (mounted) {
      setState(() {
        _selectedSecond = second;
        _position = Duration(seconds: second);
      });
    }
    await _player.seek(Duration(seconds: second));
    // Clear preview when seeking
    if (mounted) {
      setState(() => _previewBytes = null);
    }
  }

  /// Capture a preview of the current frame.
  Future<void> _capturePreview() async {
    if (_isPreviewing) return;
    setState(() => _isPreviewing = true);

    try {
      final bytes = await _player.screenshot();
      if (bytes != null && mounted) {
        setState(() => _previewBytes = bytes);
      }
    } catch (e) {
      AppLogger.warning('[VideoFramePicker] Preview capture failed: $e');
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  /// Extract the current frame and save to disk.
  Future<void> _extractAndSave() async {
    if (_isExtracting) return;
    setState(() => _isExtracting = true);

    try {
      final cacheDir = await AppPathHelper.getTagThumbnailDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(cacheDir.path, 'tag_video_$timestamp.jpg');

      String? savedPath;

      // Strategy 1 (WYSIWYG): capture exactly the frame media_kit is currently
      // showing. The player and the native extractor seek independently, so
      // re-seeking natively can land on a different (earlier) keyframe than the
      // one on screen. Screenshotting the displayed frame guarantees the saved
      // image matches what the user picked.
      final bytes = await _player.screenshot();
      if (bytes != null && bytes.isNotEmpty) {
        // Decode and re-encode as JPEG for consistent file format
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final jpeg = img.encodeJpg(decoded, quality: 95);
          final file = File(outputPath);
          await file.writeAsBytes(jpeg);
          if (await file.exists() && await file.length() > 0) {
            savedPath = outputPath;
          }
        } else {
          // Raw bytes might already be usable — write directly
          final file = File(outputPath);
          await file.writeAsBytes(bytes);
          if (await file.exists() && await file.length() > 0) {
            savedPath = outputPath;
          }
        }
      }

      // Strategy 2 (fallback): if the screenshot failed, extract natively using
      // the player's actual current position (not just the slider value) so we
      // stay as close as possible to the displayed frame.
      if (savedPath == null && Platform.isWindows) {
        final posSeconds = _position.inSeconds;
        savedPath = await FcNativeVideoThumbnail.generateThumbnail(
          videoPath: widget.videoPath,
          outputPath: outputPath,
          width: 1024,
          format: 'jpg',
          timeSeconds: posSeconds,
          quality: 95,
        );
      }

      if (savedPath != null && mounted) {
        Navigator.of(context).pop(savedPath);
      } else if (mounted) {
        setState(() {
          _error = 'Failed to extract frame. Try a different position.';
          _isExtracting = false;
        });
      }
    } catch (e) {
      AppLogger.error('[VideoFramePicker] Extract failed', error: e);
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isExtracting = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.6).clamp(400.0, 800.0);
    final videoHeight = (dialogWidth * 9 / 16).clamp(200.0, 450.0);

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: screenSize.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.filmSlate,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pick frame from video',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsLight.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(null),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Video player area
            SizedBox(
              width: dialogWidth,
              height: videoHeight,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _duration == Duration.zero
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsLight.warningCircle,
                              size: 48,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                      ),
                    ),
            ),

            // Seek controls
            if (_duration.inMilliseconds > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(Duration(seconds: _selectedSecond)),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        container: true,
                        child: Slider(
                          // Use one discrete tick per second so the selected
                          // frame always maps to an exact second position.
                          value: _selectedSecond.toDouble().clamp(
                            0,
                            _duration.inSeconds.toDouble(),
                          ),
                          max: _duration.inSeconds.toDouble(),
                          divisions: _duration.inSeconds > 0
                              ? _duration.inSeconds
                              : 1,
                          onChanged: (value) {
                            _seekTo(Duration(seconds: value.round()));
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Quick seek buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _seekButton(PhosphorIconsLight.skipBack, '-10s', -10),
                    const SizedBox(width: 4),
                    _seekButton(PhosphorIconsLight.caretLeft, '-1s', -1),
                    const SizedBox(width: 8),
                    // Play/pause
                    StreamBuilder<bool>(
                      stream: _player.stream.playing,
                      initialData: false,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return IconButton(
                          icon: Icon(
                            isPlaying
                                ? PhosphorIconsFill.pause
                                : PhosphorIconsFill.play,
                            size: 28,
                          ),
                          onPressed: () => _player.playOrPause(),
                          tooltip: isPlaying ? 'Pause' : 'Play',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _seekButton(PhosphorIconsLight.caretRight, '+1s', 1),
                    const SizedBox(width: 4),
                    _seekButton(PhosphorIconsLight.skipForward, '+10s', 10),
                  ],
                ),
              ),
            ],

            // Error message
            if (_error != null && _duration.inMilliseconds > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),

            // Preview
            if (_previewBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _previewBytes!,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Preview at ${_formatDuration(_position)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isExtracting
                        ? null
                        : () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isExtracting || _duration == Duration.zero
                        ? null
                        : _capturePreview,
                    icon: _isPreviewing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(PhosphorIconsLight.eye, size: 18),
                    label: const Text('Preview'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isExtracting || _duration == Duration.zero
                        ? null
                        : _extractAndSave,
                    icon: _isExtracting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(PhosphorIconsLight.check, size: 18),
                    label: const Text('Use this frame'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seekButton(IconData icon, String tooltip, int seconds) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: () {
        final newSecond = (_selectedSecond + seconds).clamp(
          0,
          _duration.inSeconds,
        );
        final newPos = Duration(seconds: newSecond);
        _seekTo(newPos);
      },
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

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

  const VideoFramePickerDialog({Key? key, required this.videoPath})
      : super(key: key);

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
          setState(() => _duration = d);
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
    await _player.seek(position);
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
      final cacheDir = await AppPathHelper.getSubDir('tag_thumbnails');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(cacheDir.path, 'tag_video_$timestamp.jpg');

      String? savedPath;

      // Strategy 1: Try native plugin (Windows) — extract at specific time
      if (Platform.isWindows) {
        final posSeconds = _position.inSeconds;
        savedPath = await FcNativeVideoThumbnail.generateThumbnail(
          videoPath: widget.videoPath,
          outputPath: outputPath,
          width: 1024,
          format: 'jpg',
          timeSeconds: posSeconds > 0 ? posSeconds : null,
          quality: 95,
        );
      }

      // Strategy 2: Fallback — use media_kit screenshot
      if (savedPath == null) {
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
                  Icon(PhosphorIconsLight.filmSlate,
                      size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pick frame from video',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
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
                                Icon(PhosphorIconsLight.warningCircle,
                                    size: 48, color: theme.colorScheme.error),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
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
                      _formatDuration(_position),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _position.inMilliseconds
                            .toDouble()
                            .clamp(0, _duration.inMilliseconds.toDouble()),
                        max: _duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          _seekTo(Duration(milliseconds: value.round()));
                        },
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
                    _seekButton(
                        PhosphorIconsLight.skipBack, '-10s', -10),
                    const SizedBox(width: 4),
                    _seekButton(
                        PhosphorIconsLight.caretLeft, '-1s', -1),
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
                    _seekButton(
                        PhosphorIconsLight.caretRight, '+1s', 1),
                    const SizedBox(width: 4),
                    _seekButton(
                        PhosphorIconsLight.skipForward, '+10s', 10),
                  ],
                ),
              ),
            ],

            // Error message
            if (_error != null && _duration.inMilliseconds > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _error!,
                  style: TextStyle(
                      color: theme.colorScheme.error, fontSize: 12),
                ),
              ),

            // Preview
            if (_previewBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    onPressed:
                        _isExtracting ? null : () => Navigator.of(context).pop(null),
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
        final newPos = Duration(
          milliseconds:
              (_position.inMilliseconds + seconds * 1000)
                  .clamp(0, _duration.inMilliseconds),
        );
        _seekTo(newPos);
      },
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

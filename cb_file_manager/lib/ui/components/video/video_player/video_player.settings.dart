part of 'video_player.dart';

// ── Abstract host ────────────────────────────────────────────────────────────
// Declares all state members that the settings mixin reads/writes, so that the
// mixin does not need a direct reference to _VideoPlayerState.

abstract class _VideoPlayerSettingsHost extends _VideoPlayerVolumeHost {
  // Video controller (needed to recreate when hw-accel changes)
  set _videoController(VideoController? v);

  // Subtitle
  List<SubtitleTrack> get _subtitleTracks;
  int? get _selectedSubtitleTrack;
  set _selectedSubtitleTrack(int? v);

  // Playback speed
  double get _playbackSpeed;
  set _playbackSpeed(double v);

  // Video filters
  double get _brightness;
  set _brightness(double v);
  double get _contrast;
  set _contrast(double v);
  double get _saturation;
  set _saturation(double v);

  // Sleep timer
  Duration? get _sleepDuration;

  // Technical settings
  String get _selectedCodec;
  set _selectedCodec(String v);
  String get _videoScaleMode;
  set _videoScaleMode(String v);
  bool get _hardwareAcceleration;
  set _hardwareAcceleration(bool v);
  String get _videoDecoder;
  set _videoDecoder(String v);
  String get _audioDecoder;
  set _audioDecoder(String v);
  int get _bufferSize;
  set _bufferSize(int v);
  int get _networkTimeout;
  set _networkTimeout(int v);
  String get _subtitleEncoding;
  set _subtitleEncoding(String v);
  String get _videoOutputFormat;
  set _videoOutputFormat(String v);
  int get _videoSeekSpeed;
  set _videoSeekSpeed(int v);

  // Methods from main state that the mixin delegates to
  void _cancelSleepTimer();
  void _setSleepTimer(Duration duration);
  VideoControllerConfiguration _buildVideoControllerConfig();
}

// ── Settings mixin ───────────────────────────────────────────────────────────

mixin _VideoPlayerSettingsMixin on _VideoPlayerSettingsHost {
  // ── Quick-access dialogs ──────────────────────────────────────────────────

  void _showSubtitleDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subtitles'),
        content: SubtitleDialogContent(
          tracks: _subtitleTracks,
          selected: _selectedSubtitleTrack,
          onSelect: (v) => setState(() => _selectedSubtitleTrack = v),
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPlaybackSpeedDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback Speed'),
        content: PlaybackSpeedDialogContent(
          current: _playbackSpeed,
          onSelect: (v) {
            setState(() => _playbackSpeed = v);
            _setPlaybackSpeed(v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showVideoFiltersDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Video Filters'),
          content: VideoFiltersDialogContent(
            brightness: _brightness,
            contrast: _contrast,
            saturation: _saturation,
            onBrightnessChanged: (v) {
              setState(() => _brightness = v);
              setDialogState(() {});
            },
            onContrastChanged: (v) {
              setState(() => _contrast = v);
              setDialogState(() {});
            },
            onSaturationChanged: (v) {
              setState(() => _saturation = v);
              setDialogState(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _brightness = 1.0;
                  _contrast = 1.0;
                  _saturation = 1.0;
                });
                setDialogState(() {});
              },
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sleep Timer'),
        content: SleepTimerDialogContent(
          selected: _sleepDuration,
          onSelect: (v) {
            if (v == null) {
              _cancelSleepTimer();
            } else {
              _setSleepTimer(v);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ── Main settings dialog ──────────────────────────────────────────────────

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final acrylicBg = (Theme.of(context).dialogTheme.backgroundColor ??
                    Theme.of(context).colorScheme.surface)
                .withValues(alpha: 0.82);
            return AlertDialog(
              backgroundColor: acrylicBg,
              title: const Text('Video Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Codec Selection
                    const Text('Codec:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _selectedCodec,
                      expand: true,
                      items: const [
                        CbSelectItem(value: 'auto', label: 'Auto'),
                        CbSelectItem(value: 'h264', label: 'H.264'),
                        CbSelectItem(value: 'h265', label: 'H.265/HEVC'),
                        CbSelectItem(value: 'vp9', label: 'VP9'),
                        CbSelectItem(value: 'av1', label: 'AV1'),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _selectedCodec = value);
                        setState(() => _selectedCodec = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Video Scale Mode
                    const Text('Video Scale Mode:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _videoScaleMode,
                      expand: true,
                      items: const [
                        CbSelectItem(
                            value: 'cover', label: 'Cover (Fill & Crop)'),
                        CbSelectItem(
                            value: 'contain', label: 'Contain (Fit All)'),
                        CbSelectItem(value: 'fill', label: 'Fill (Stretch)'),
                        CbSelectItem(value: 'fitWidth', label: 'Fit Width'),
                        CbSelectItem(value: 'fitHeight', label: 'Fit Height'),
                        CbSelectItem(
                            value: 'none', label: 'None (Original Size)'),
                        CbSelectItem(value: 'scaleDown', label: 'Scale Down'),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _videoScaleMode = value);
                        setState(() => _videoScaleMode = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Hardware Acceleration
                    SwitchListTile(
                      title: const Text('Hardware Acceleration'),
                      subtitle: const Text('Use GPU for video decoding'),
                      value: _hardwareAcceleration,
                      onChanged: (value) {
                        setDialogState(() {
                          _hardwareAcceleration = value;
                          _videoDecoder = value ? 'hardware' : 'software';
                        });
                        setState(() {
                          _hardwareAcceleration = value;
                          _videoDecoder = value ? 'hardware' : 'software';
                          if (_player != null) {
                            _videoController = VideoController(
                              _player!,
                              configuration: _buildVideoControllerConfig(),
                            );
                          }
                        });
                        _saveSettings();
                      },
                    ),

                    // Video Decoder
                    const Text('Video Decoder:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _videoDecoder,
                      expand: true,
                      items: const [
                        CbSelectItem(value: 'auto', label: 'Auto'),
                        CbSelectItem(value: 'software', label: 'Software'),
                        CbSelectItem(value: 'hardware', label: 'Hardware'),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _videoDecoder = value;
                          if (value == 'software') {
                            _hardwareAcceleration = false;
                          }
                          if (value == 'hardware') {
                            _hardwareAcceleration = true;
                          }
                        });
                        setState(() {
                          _videoDecoder = value;
                          if (value == 'software') {
                            _hardwareAcceleration = false;
                          }
                          if (value == 'hardware') {
                            _hardwareAcceleration = true;
                          }
                          if (_player != null) {
                            _videoController = VideoController(
                              _player!,
                              configuration: _buildVideoControllerConfig(),
                            );
                          }
                        });
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Audio Decoder
                    const Text('Audio Decoder:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _audioDecoder,
                      expand: true,
                      items: const [
                        CbSelectItem(value: 'auto', label: 'Auto'),
                        CbSelectItem(value: 'software', label: 'Software'),
                        CbSelectItem(value: 'hardware', label: 'Hardware'),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _audioDecoder = value);
                        setState(() => _audioDecoder = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Buffer Size
                    VideoPlayerLabeledSlider(
                      label: 'Buffer Size: ${_bufferSize}MB',
                      value: _bufferSize.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: (value) {
                        setDialogState(() => _bufferSize = value.round());
                        setState(() => _bufferSize = value.round());
                        _saveSettings();
                      },
                    ),

                    // Network Timeout
                    VideoPlayerLabeledSlider(
                      label: 'Network Timeout: ${_networkTimeout}s',
                      value: _networkTimeout.toDouble(),
                      min: 5,
                      max: 120,
                      divisions: 23,
                      onChanged: (value) {
                        setDialogState(() => _networkTimeout = value.round());
                        setState(() => _networkTimeout = value.round());
                        _saveSettings();
                      },
                    ),

                    // Subtitle Encoding
                    const Text('Subtitle Encoding:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _subtitleEncoding,
                      expand: true,
                      items: const [
                        CbSelectItem(value: 'utf-8', label: 'UTF-8'),
                        CbSelectItem(value: 'utf-16', label: 'UTF-16'),
                        CbSelectItem(value: 'iso-8859-1', label: 'ISO-8859-1'),
                        CbSelectItem(
                            value: 'windows-1252', label: 'Windows-1252'),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _subtitleEncoding = value);
                        setState(() => _subtitleEncoding = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Video Output Format
                    const Text('Video Output Format:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    CbSelect<String>(
                      value: _videoOutputFormat,
                      expand: true,
                      items: const [
                        CbSelectItem(value: 'auto', label: 'Auto'),
                        CbSelectItem(value: 'yuv420p', label: 'YUV420P'),
                        CbSelectItem(value: 'rgb24', label: 'RGB24'),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _videoOutputFormat = value);
                        setState(() => _videoOutputFormat = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Seek Speed
                    Text(
                      AppLocalizations.of(context)!.seekSpeed,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildSeekSpeedChip(
                          context: context,
                          label: AppLocalizations.of(context)!.seekSpeedSlow,
                          value: 0,
                          setDialogState: setDialogState,
                        ),
                        const SizedBox(width: 8),
                        _buildSeekSpeedChip(
                          context: context,
                          label: AppLocalizations.of(context)!.seekSpeedMedium,
                          value: 1,
                          setDialogState: setDialogState,
                        ),
                        const SizedBox(width: 8),
                        _buildSeekSpeedChip(
                          context: context,
                          label: AppLocalizations.of(context)!.seekSpeedFast,
                          value: 2,
                          setDialogState: setDialogState,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _resetSettings();
                    setDialogState(() {});
                  },
                  child: const Text('Reset to Default'),
                ),
                TextButton(
                  onPressed: () => RouteUtils.safePopDialog(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Playback speed ────────────────────────────────────────────────────────

  void _setPlaybackSpeed(double speed) {
    if (_player != null) {
      _player!.setRate(speed);
    } else if (_vlcController != null) {
      _vlcController!.setPlaybackSpeed(speed);
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _saveSettings() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setVideoPlayerString('video_codec', _selectedCodec);
      await prefs.setVideoPlayerBool(
          'hardware_acceleration', _hardwareAcceleration);
      await prefs.setVideoPlayerString('video_decoder', _videoDecoder);
      await prefs.setVideoPlayerString('audio_decoder', _audioDecoder);
      await prefs.setVideoPlayerInt('buffer_size', _bufferSize);
      await prefs.setVideoPlayerInt('network_timeout', _networkTimeout);
      await prefs.setVideoPlayerString('subtitle_encoding', _subtitleEncoding);
      await prefs.setVideoPlayerString(
          'video_output_format', _videoOutputFormat);
      await prefs.setVideoPlayerString('video_scale_mode', _videoScaleMode);
      await prefs.setVideoSeekSpeed(_videoSeekSpeed);
      debugPrint('Video player settings saved successfully');
    } catch (e) {
      debugPrint('Error saving video player settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();

      // One-time Windows migration: previous versions defaulted hardware
      // acceleration ON, which crashes media_kit's D3D11 decoder path on some
      // Windows GPUs/drivers ("Failed to create D3D11 Device" -> "Lost
      // connection to device"). Force it OFF once on Windows so existing
      // users get the safe default. The user can still re-enable it manually.
      if (!kIsWeb && Platform.isWindows) {
        final migrated = await prefs.getVideoPlayerBool(
                'hw_accel_windows_migrated',
                defaultValue: false) ??
            false;
        if (!migrated) {
          await prefs.setVideoPlayerBool('hardware_acceleration', false);
          await prefs.setVideoPlayerString('video_decoder', 'software');
          await prefs.setVideoPlayerBool('hw_accel_windows_migrated', true);
          debugPrint(
              'VideoPlayer: applied one-time Windows HW-accel safety migration');
        }
      }

      _selectedCodec = await prefs.getVideoPlayerString('video_codec',
              defaultValue: 'auto') ??
          'auto';
      // Default hardware acceleration OFF on Windows: media_kit's D3D11/ANGLE
      // rendering path can fail to create a device (E_OUTOFMEMORY) on some
      // GPUs/drivers and crash the engine ("Lost connection to device").
      // Software decoding avoids that. Mirrors the desktop PiP windows.
      final hwAccelDefault = kIsWeb ? true : !Platform.isWindows;
      _hardwareAcceleration = await prefs.getVideoPlayerBool(
              'hardware_acceleration',
              defaultValue: hwAccelDefault) ??
          hwAccelDefault;
      _videoDecoder = await prefs.getVideoPlayerString('video_decoder',
              defaultValue: 'auto') ??
          'auto';
      _audioDecoder = await prefs.getVideoPlayerString('audio_decoder',
              defaultValue: 'auto') ??
          'auto';
      _bufferSize =
          await prefs.getVideoPlayerInt('buffer_size', defaultValue: 10) ?? 10;
      _networkTimeout =
          await prefs.getVideoPlayerInt('network_timeout', defaultValue: 30) ??
              30;
      _subtitleEncoding = await prefs.getVideoPlayerString('subtitle_encoding',
              defaultValue: 'utf-8') ??
          'utf-8';
      _videoOutputFormat = await prefs.getVideoPlayerString(
              'video_output_format',
              defaultValue: 'auto') ??
          'auto';
      _videoScaleMode = await prefs.getVideoPlayerString('video_scale_mode',
              defaultValue: 'contain') ??
          'contain';
      _videoSeekSpeed = await prefs.getVideoSeekSpeed();

      // Keep hardware acceleration in sync with explicit decoder choice
      if (_videoDecoder == 'software') _hardwareAcceleration = false;
      if (_videoDecoder == 'hardware') _hardwareAcceleration = true;

      debugPrint('Video player settings loaded successfully');
    } catch (e) {
      debugPrint('Error loading video player settings: $e');
    }
  }

  void _resetSettings() {
    setState(() {
      _selectedCodec = 'auto';
      _hardwareAcceleration = kIsWeb ? true : !Platform.isWindows;
      _videoDecoder = 'auto';
      _audioDecoder = 'auto';
      _bufferSize = 10;
      _networkTimeout = 30;
      _subtitleEncoding = 'utf-8';
      _videoOutputFormat = 'auto';
      _videoScaleMode = 'contain';
      _videoSeekSpeed = 1;
    });
    _saveSettings();
  }

  // ── Seek speed chip ───────────────────────────────────────────────────────

  Widget _buildSeekSpeedChip({
    required BuildContext context,
    required String label,
    required int value,
    required void Function(void Function()) setDialogState,
  }) {
    final isSelected = _videoSeekSpeed == value;
    return Expanded(
      child: InkWell(
        onTap: () async {
          await UserPreferences.instance.setVideoSeekSpeed(value);
          setDialogState(() => _videoSeekSpeed = value);
          setState(() => _videoSeekSpeed = value);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

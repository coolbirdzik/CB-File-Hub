part of 'video_player.dart';

// ── Abstract host ────────────────────────────────────────────────────────────
// Declares all state members that the settings mixin reads/writes, so that the
// mixin does not need a direct reference to _VideoPlayerState.

abstract class _VideoPlayerSettingsHost extends _VideoPlayerVolumeHost {
  // Video controller (needed to recreate when hw-accel changes)
  set _videoController(PlaybackVideoController? v);

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
  VideoWheelAction get _videoWheelAction;
  set _videoWheelAction(VideoWheelAction v);

  // Methods from main state that the mixin delegates to
  void _cancelSleepTimer();
  void _setSleepTimer(Duration duration);
  PlaybackVideoConfiguration _buildVideoControllerConfig();
}

// ── Settings mixin ───────────────────────────────────────────────────────────

mixin _VideoPlayerSettingsMixin on _VideoPlayerSettingsHost {
  // ── Quick-access dialogs ──────────────────────────────────────────────────

  void _showSubtitleDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr.vpSubtitles),
        content: SubtitleDialogContent(
          tracks: _subtitleTracks,
          selected: _selectedSubtitleTrack,
          onSelect: (v) => setState(() => _selectedSubtitleTrack = v),
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: Text(context.tr.cancel),
          ),
        ],
      ),
    );
  }

  void _showPlaybackSpeedDialog() {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr.vpPlaybackSpeed),
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
            child: Text(context.tr.cancel),
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
          title: Text(context.tr.vpVideoFilters),
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
              child: Text(context.tr.vpReset),
            ),
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(context),
              child: Text(context.tr.close),
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
        title: Text(context.tr.vpSleepTimer),
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
            child: Text(context.tr.cancel),
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
            final acrylicBg =
                (Theme.of(context).dialogTheme.backgroundColor ??
                        Theme.of(context).colorScheme.surface)
                    .withValues(alpha: 0.82);
            return AlertDialog(
              backgroundColor: acrylicBg,
              title: Text(context.tr.vpVideoSettings),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Codec Selection
                    Text(
                      context.tr.vpCodec,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<String>(
                      value: _selectedCodec,
                      expand: true,
                      items: [
                        CbSelectItem(value: 'auto', label: context.tr.vpAuto),
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
                    Text(
                      context.tr.vpScaleMode,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<String>(
                      value: _videoScaleMode,
                      expand: true,
                      items: [
                        CbSelectItem(
                          value: 'contain',
                          label: context.tr.vpScaleContain,
                        ),
                        CbSelectItem(
                          value: 'cover',
                          label: context.tr.vpScaleCover,
                        ),
                        CbSelectItem(
                          value: 'fill',
                          label: context.tr.vpScaleFill,
                        ),
                        CbSelectItem(
                          value: 'fitWidth',
                          label: context.tr.vpScaleFitWidth,
                        ),
                        CbSelectItem(
                          value: 'fitHeight',
                          label: context.tr.vpScaleFitHeight,
                        ),
                        CbSelectItem(
                          value: 'none',
                          label: context.tr.vpScaleNone,
                        ),
                        CbSelectItem(
                          value: 'scaleDown',
                          label: context.tr.vpScaleDown,
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _videoScaleMode = value);
                        setState(() => _videoScaleMode = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildVideoDecodingSection(context, setDialogState),
                    const SizedBox(height: 16),

                    // Audio Decoder
                    Text(
                      context.tr.vpAudioDecoder,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<String>(
                      value: _audioDecoder,
                      expand: true,
                      items: [
                        CbSelectItem(value: 'auto', label: context.tr.vpAuto),
                        CbSelectItem(
                          value: 'software',
                          label: context.tr.vpSoftware,
                        ),
                        CbSelectItem(
                          value: 'hardware',
                          label: context.tr.vpHardware,
                        ),
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
                      label: context.tr.vpBufferSize(_bufferSize),
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
                      label: context.tr.vpNetworkTimeout(_networkTimeout),
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
                    Text(
                      context.tr.vpSubtitleEncoding,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<String>(
                      value: _subtitleEncoding,
                      expand: true,
                      items: [
                        CbSelectItem(value: 'utf-8', label: 'UTF-8'),
                        CbSelectItem(value: 'utf-16', label: 'UTF-16'),
                        CbSelectItem(value: 'iso-8859-1', label: 'ISO-8859-1'),
                        CbSelectItem(
                          value: 'windows-1252',
                          label: 'Windows-1252',
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _subtitleEncoding = value);
                        setState(() => _subtitleEncoding = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Video Output Format
                    Text(
                      context.tr.vpOutputFormat,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<String>(
                      value: _videoOutputFormat,
                      expand: true,
                      items: [
                        CbSelectItem(value: 'auto', label: context.tr.vpAuto),
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
                    const SizedBox(height: 16),

                    // Mouse wheel action
                    Text(
                      AppLocalizations.of(context)!.videoWheelAction,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CbSelect<VideoWheelAction>(
                      value: _videoWheelAction,
                      expand: true,
                      items: [
                        CbSelectItem(
                          value: VideoWheelAction.volume,
                          label: AppLocalizations.of(context)!.videoWheelVolume,
                        ),
                        CbSelectItem(
                          value: VideoWheelAction.seek,
                          label: AppLocalizations.of(context)!.videoWheelSeek,
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _videoWheelAction = value);
                        setState(() => _videoWheelAction = value);
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppLocalizations.of(context)!.videoWheelActionDescription,
                      style: Theme.of(context).textTheme.bodySmall,
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
                  child: Text(context.tr.vpResetToDefault),
                ),
                TextButton(
                  onPressed: () => RouteUtils.safePopDialog(context),
                  child: Text(context.tr.close),
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
      setState(() => _playbackSpeed = speed);
    }
  }

  /// One user-facing decoder choice; see [PlaybackVideoConfiguration.forDecoder].
  Widget _buildVideoDecodingSection(
    BuildContext context,
    StateSetter setDialogState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mode = switch (_videoDecoder) {
      'hardware' || 'software' => _videoDecoder,
      _ => 'auto',
    };
    final description = switch (mode) {
      'hardware' => l10n.videoDecodingGpuDescription,
      'software' => l10n.videoDecodingCpuDescription,
      _ when !kIsWeb && Platform.isWindows =>
        l10n.videoDecodingAutoDescriptionWindows,
      _ => l10n.videoDecodingAutoDescription,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.videoDecoding,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        CbSelect<String>(
          value: mode,
          expand: true,
          items: [
            CbSelectItem(value: 'auto', label: l10n.videoDecodingAuto),
            CbSelectItem(value: 'hardware', label: l10n.videoDecodingGpu),
            CbSelectItem(value: 'software', label: l10n.videoDecodingCpu),
          ],
          onChanged: (value) {
            setState(() {
              _videoDecoder = value;
              if (_player != null) {
                _videoController = PlaybackVideoController(
                  _player!,
                  configuration: _buildVideoControllerConfig(),
                );
              }
            });
            setDialogState(() {});
            _saveSettings();
          },
        ),
        const SizedBox(height: 6),
        Text(description, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          l10n.videoDecodingReopenHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _saveSettings() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setVideoPlayerString('video_codec', _selectedCodec);
      await prefs.setVideoPlayerBool(
        'hardware_acceleration',
        _hardwareAcceleration,
      );
      await prefs.setVideoPlayerString('video_decoder', _videoDecoder);
      await prefs.setVideoPlayerString('audio_decoder', _audioDecoder);
      await prefs.setVideoPlayerInt('buffer_size', _bufferSize);
      await prefs.setVideoPlayerInt('network_timeout', _networkTimeout);
      await prefs.setVideoPlayerString('subtitle_encoding', _subtitleEncoding);
      await prefs.setVideoPlayerString(
        'video_output_format',
        _videoOutputFormat,
      );
      await prefs.setVideoPlayerString('video_scale_mode', _videoScaleMode);
      await prefs.setVideoSeekSpeed(_videoSeekSpeed);
      await prefs.setVideoWheelAction(_videoWheelAction);
      debugPrint('Video player settings saved successfully');
    } catch (e) {
      debugPrint('Error saving video player settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();

      // An earlier one-time migration forced 'software' on every Windows
      // install, indistinguishable from a real choice. 'auto' now keeps the
      // CPU for normal videos there too, adding only GPU decoding for 4K with
      // a live CPU fallback, so move those installs to it once.
      if (!kIsWeb && Platform.isWindows) {
        final migrated =
            await prefs.getVideoPlayerBool(
              'video_decoder_auto_migrated',
              defaultValue: false,
            ) ??
            false;
        if (!migrated) {
          final current = await prefs.getVideoPlayerString('video_decoder');
          if (current != 'hardware') {
            await prefs.setVideoPlayerString('video_decoder', 'auto');
          }
          await prefs.setVideoPlayerBool('video_decoder_auto_migrated', true);
        }
      }

      // The reads are independent; issue them together so the player (which
      // waits for these settings) is created sooner.
      final (
        (codec, videoDecoder, audioDecoder, videoOutputFormat, videoScaleMode),
        (
          bufferSize,
          networkTimeout,
          subtitleEncoding,
          videoSeekSpeed,
          videoWheelAction,
        ),
      ) = await (
        (
          prefs.getVideoPlayerString('video_codec', defaultValue: 'auto'),
          prefs.getVideoPlayerString('video_decoder', defaultValue: 'auto'),
          prefs.getVideoPlayerString('audio_decoder', defaultValue: 'auto'),
          prefs.getVideoPlayerString(
            'video_output_format',
            defaultValue: 'auto',
          ),
          prefs.getVideoPlayerString(
            'video_scale_mode',
            defaultValue: 'contain',
          ),
        ).wait,
        (
          prefs.getVideoPlayerInt('buffer_size', defaultValue: 10),
          prefs.getVideoPlayerInt('network_timeout', defaultValue: 30),
          prefs.getVideoPlayerString(
            'subtitle_encoding',
            defaultValue: 'utf-8',
          ),
          prefs.getVideoSeekSpeed(),
          prefs.getVideoWheelAction(),
        ).wait,
      ).wait;
      _selectedCodec = codec ?? 'auto';
      _videoDecoder = videoDecoder ?? 'auto';
      _audioDecoder = audioDecoder ?? 'auto';
      _bufferSize = bufferSize ?? 10;
      _networkTimeout = networkTimeout ?? 30;
      _subtitleEncoding = subtitleEncoding ?? 'utf-8';
      _videoOutputFormat = videoOutputFormat ?? 'auto';
      _videoScaleMode = videoScaleMode ?? 'contain';
      _videoSeekSpeed = videoSeekSpeed;
      _videoWheelAction = videoWheelAction;

      debugPrint('Video player settings loaded successfully');
    } catch (e) {
      debugPrint('Error loading video player settings: $e');
    }
  }

  void _resetSettings() {
    setState(() {
      _selectedCodec = 'auto';
      _videoDecoder = 'auto';
      _audioDecoder = 'auto';
      _bufferSize = 10;
      _networkTimeout = 30;
      _subtitleEncoding = 'utf-8';
      _videoOutputFormat = 'auto';
      _videoScaleMode = 'contain';
      _videoSeekSpeed = 1;
      _videoWheelAction = VideoWheelAction.volume;
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

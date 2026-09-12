part of 'video_player.dart';

abstract class _VideoPlayerVolumeHost extends State<VideoPlayer> {
  bool get _isMuted;
  set _isMuted(bool v);

  double get _savedVolume;
  set _savedVolume(double v);

  double get _lastVolume;
  set _lastVolume(double v);

  bool get _isRestoringVolume;
  set _isRestoringVolume(bool v);

  PlaybackPlayer? get _player;
}

mixin _VideoPlayerVolumeMixin on _VideoPlayerVolumeHost {
  Future<void> _applyVolumeSettings() async {
    // The shared media_kit backend also queues volume before native attachment.
    await _applyVolumeToActiveController();
  }

  Future<void> _persistVolumePreference(double volume0to100) async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setVideoPlayerVolume(volume0to100.clamp(0.0, 100.0));
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _persistMutePreference(bool muted) async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setVideoPlayerMute(muted);
    } catch (_) {
      // Best-effort.
    }
  }

  double _currentEffectiveVolume0to100() {
    if (_isMuted) return 0.0;
    final v = _savedVolume > 0
        ? _savedVolume
        : (_lastVolume > 0 ? _lastVolume : 70.0);
    return v.clamp(0.0, 100.0);
  }

  Future<void> _applyVolumeToActiveController({bool updateUi = true}) async {
    if (!mounted) return;
    final vol0to100 = _currentEffectiveVolume0to100();
    try {
      if (_player != null) {
        final restoringBefore = _isRestoringVolume;
        _isRestoringVolume = true;
        await _player!.setVolume(vol0to100);
        _isRestoringVolume = restoringBefore;
      }
    } catch (_) {
      // Best-effort: if setting volume fails, allow volume updates again.
      _isRestoringVolume = false;
    }

    if (updateUi && mounted) {
      setState(() {});
    }
  }

  Future<void> _setVolumeFromUser(double volume0to100) async {
    final v = volume0to100.clamp(0.0, 100.0);
    final wasMuted = _isMuted;
    setState(() {
      _savedVolume = v;
      if (v > 0.1) _lastVolume = v;
      if (v <= 0.1) _isMuted = true;
    });

    if (v > 0.1 && _isMuted) {
      setState(() => _isMuted = false);
      await _persistMutePreference(false);
    }
    if (v <= 0.1 && !wasMuted) {
      await _persistMutePreference(true);
    }

    await _applyVolumeToActiveController(updateUi: false);
    await _persistVolumePreference(v);
  }

  Future<void> _toggleMuteFromUser() async {
    final nextMuted = !_isMuted;
    setState(() => _isMuted = nextMuted);
    await _persistMutePreference(nextMuted);
    await _applyVolumeToActiveController();
  }
}

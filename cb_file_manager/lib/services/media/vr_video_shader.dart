import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'media_kit_playback.dart';

/// Projection & stereo layout modes for 4K/8K VR video playback.
enum VrProjectionMode {
  off,
  sbsMono,
  ouMono,
  vr180Sbs,
  vr180Ou,
  vr360Mono,
  vr360Sbs,
  vr360Ou,
}

/// Immutable camera and projection state for VR video viewing.
class VrViewState {
  const VrViewState({
    this.mode = VrProjectionMode.off,
    this.yawDeg = 0.0,
    this.pitchDeg = 0.0,
    this.fovDeg = 95.0,
  });

  final VrProjectionMode mode;
  final double yawDeg;
  final double pitchDeg;
  final double fovDeg;

  static const double minFovDeg = 45.0;
  static const double maxFovDeg = 120.0;
  static const double maxPitchDeg = 85.0;

  bool get isActive => mode != VrProjectionMode.off;

  bool get isSpherical => switch (mode) {
    VrProjectionMode.vr180Sbs ||
    VrProjectionMode.vr180Ou ||
    VrProjectionMode.vr360Mono ||
    VrProjectionMode.vr360Sbs ||
    VrProjectionMode.vr360Ou => true,
    VrProjectionMode.off ||
    VrProjectionMode.sbsMono ||
    VrProjectionMode.ouMono => false,
  };

  bool get is180 =>
      mode == VrProjectionMode.vr180Sbs || mode == VrProjectionMode.vr180Ou;

  bool get isSbs =>
      mode == VrProjectionMode.sbsMono ||
      mode == VrProjectionMode.vr180Sbs ||
      mode == VrProjectionMode.vr360Sbs;

  bool get isOu =>
      mode == VrProjectionMode.ouMono ||
      mode == VrProjectionMode.vr180Ou ||
      mode == VrProjectionMode.vr360Ou;

  VrViewState copyWith({
    VrProjectionMode? mode,
    double? yawDeg,
    double? pitchDeg,
    double? fovDeg,
  }) {
    final nextMode = mode ?? this.mode;
    final nextPitch = (pitchDeg ?? this.pitchDeg).clamp(
      -maxPitchDeg,
      maxPitchDeg,
    );
    final nextFov = (fovDeg ?? this.fovDeg).clamp(minFovDeg, maxFovDeg);
    var nextYaw = yawDeg ?? this.yawDeg;
    if (nextMode == VrProjectionMode.vr180Sbs ||
        nextMode == VrProjectionMode.vr180Ou) {
      nextYaw = nextYaw.clamp(-90.0, 90.0);
    } else {
      nextYaw = ((nextYaw + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;
    }
    return VrViewState(
      mode: nextMode,
      yawDeg: nextYaw,
      pitchDeg: nextPitch,
      fovDeg: nextFov,
    );
  }

  VrViewState resetView() => VrViewState(mode: mode);

  @override
  bool operator ==(Object other) =>
      other is VrViewState &&
      other.mode == mode &&
      (other.yawDeg - yawDeg).abs() < 0.05 &&
      (other.pitchDeg - pitchDeg).abs() < 0.05 &&
      (other.fovDeg - fovDeg).abs() < 0.05;

  @override
  int get hashCode => Object.hash(
    mode,
    (yawDeg * 10).round(),
    (pitchDeg * 10).round(),
    (fovDeg * 10).round(),
  );
}

/// Builds zero-copy libmpv GLSL user shaders for GPU VR projection.
///
/// Running the equirectangular projection inside mpv's `//!HOOK MAIN` pass
/// samples the full GPU-decoded 8K texture directly and renders straight to the
/// viewport resolution (`//!WIDTH OUTPUT.w`, `//!HEIGHT OUTPUT.h`) without any
/// CPU readback.
class VrVideoShader {
  const VrVideoShader._();

  /// Suggests a VR preset from common filename tags (e.g. `180x180_3dh`,
  /// `VR180`, `360_TB`, `SBS`). Returns [VrProjectionMode.off] when no tag
  /// matches.
  static VrProjectionMode detectHintFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    final is180 = RegExp(
      r'(?:^|[\s._\-\[\(])(vr180|180x180|180_180|180)(?:$|[\s._\-\]\)])',
    ).hasMatch(lower);
    final is360 = RegExp(
      r'(?:^|[\s._\-\[\(])(vr360|360x360|360x180|360)(?:$|[\s._\-\]\)])',
    ).hasMatch(lower);
    final isSbs = RegExp(
      r'(?:^|[\s._\-\[\(])(sbs|lr|3dh|hsbs|fsbs)(?:$|[\s._\-\]\)])',
    ).hasMatch(lower);
    final isOu = RegExp(
      r'(?:^|[\s._\-\[\(])(ou|tb|bt|3dv|hou|htb)(?:$|[\s._\-\]\)])',
    ).hasMatch(lower);

    if (is180) {
      return isOu ? VrProjectionMode.vr180Ou : VrProjectionMode.vr180Sbs;
    }
    if (is360) {
      if (isSbs) return VrProjectionMode.vr360Sbs;
      if (isOu) return VrProjectionMode.vr360Ou;
      return VrProjectionMode.vr360Mono;
    }
    if (isSbs) return VrProjectionMode.sbsMono;
    if (isOu) return VrProjectionMode.ouMono;
    return VrProjectionMode.off;
  }

  /// Generates a libmpv GLSL hook shader for [state], or null when
  /// [VrProjectionMode.off].
  static String? buildGlsl(VrViewState state) {
    if (!state.isActive) return null;

    if (state.mode == VrProjectionMode.sbsMono) {
      return '''
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC CB File Hub VR SBS Single Eye
vec4 hook() {
  vec2 uv = vec2(HOOKED_pos.x * 0.5, HOOKED_pos.y);
  return HOOKED_tex(uv);
}
''';
    }

    if (state.mode == VrProjectionMode.ouMono) {
      return '''
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC CB File Hub VR Over-Under Single Eye
vec4 hook() {
  vec2 uv = vec2(HOOKED_pos.x, HOOKED_pos.y * 0.5);
  return HOOKED_tex(uv);
}
''';
    }

    final yawRad = state.yawDeg * math.pi / 180.0;
    final pitchRad = state.pitchDeg * math.pi / 180.0;
    final tanHalfFov = math.tan((state.fovDeg * math.pi / 180.0) * 0.5);
    final is180Flag = state.is180 ? 1 : 0;
    final uScale = state.isSbs ? 0.5 : 1.0;
    final vScale = state.isOu ? 0.5 : 1.0;

    return '''
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC CB File Hub VR Equirectangular Projection
const float PI = 3.14159265358979323846;
const float YAW = ${yawRad.toStringAsFixed(6)};
const float PITCH = ${pitchRad.toStringAsFixed(6)};
const float TAN_HALF_FOV = ${tanHalfFov.toStringAsFixed(6)};
const float U_SCALE = ${uScale.toStringAsFixed(2)};
const float V_SCALE = ${vScale.toStringAsFixed(2)};

vec4 hook() {
  vec2 ndc = HOOKED_pos * 2.0 - 1.0;
  float aspect = target_size.x / max(target_size.y, 1.0);
  // Camera space ray: +X right, +Y down (screen space), +Z forward.
  vec3 dir = normalize(vec3(
    ndc.x * aspect * TAN_HALF_FOV,
    -ndc.y * TAN_HALF_FOV,
    1.0
  ));

  // Pitch around X axis.
  float cp = cos(PITCH);
  float sp = sin(PITCH);
  dir = vec3(
    dir.x,
    dir.y * cp - dir.z * sp,
    dir.y * sp + dir.z * cp
  );

  // Yaw around Y axis.
  float cy = cos(YAW);
  float sy = sin(YAW);
  dir = vec3(
    dir.x * cy + dir.z * sy,
    dir.y,
    -dir.x * sy + dir.z * cy
  );

  float lon = atan(dir.x, dir.z);
  float lat = asin(clamp(dir.y, -1.0, 1.0));

  float u;
  float v = 0.5 - lat / PI;
  if ($is180Flag == 1) {
    u = lon / PI + 0.5;
    if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
      return vec4(0.0, 0.0, 0.0, 1.0);
    }
  } else {
    u = fract(lon / (2.0 * PI) + 0.5);
  }

  vec2 uv = vec2(clamp(u, 0.0, 1.0) * U_SCALE, clamp(v, 0.0, 1.0) * V_SCALE);
  return HOOKED_tex(uv);
}
''';
  }
}

/// Manages writing and applying the active VR GLSL shader to a [PlaybackPlayer]
/// with throttling so interactive pan/zoom stays smooth.
class VrShaderController {
  VrShaderController({this.tempDirectory});

  final Directory? tempDirectory;
  File? _shaderFile;
  VrViewState _applied = const VrViewState();
  VrViewState? _pending;
  PlaybackPlayer? _pendingPlayer;
  Timer? _throttle;
  bool _disposed = false;

  Future<void> apply(PlaybackPlayer player, VrViewState state) async {
    if (_disposed) return;
    _pending = state;
    _pendingPlayer = player;
    if (_throttle == null) {
      await _flush();
    }
  }

  Future<void> _flush() async {
    final target = _pending;
    final player = _pendingPlayer;
    _pending = null;
    if (_disposed || target == null || player == null) return;
    if (target == _applied) return;
    _applied = target;

    final glsl = VrVideoShader.buildGlsl(target);
    if (glsl == null) {
      await player.setNativeProperty('glsl-shaders', '');
    } else {
      try {
        final file = await _ensureShaderFile();
        await file.writeAsString(glsl, flush: true);
        if (_disposed) return;
        // mpv accepts forward slashes on all platforms including Windows.
        final mpvPath = file.path.replaceAll(r'\', '/');
        await player.setNativeProperty('glsl-shaders', mpvPath);
      } catch (e) {
        debugPrint('VrShaderController: failed to apply shader: $e');
      }
    }

    if (_disposed) return;
    _throttle = Timer(const Duration(milliseconds: 33), () {
      _throttle = null;
      if (!_disposed && _pending != null) {
        unawaited(_flush());
      }
    });
  }

  Future<File> _ensureShaderFile() async {
    if (_shaderFile != null) return _shaderFile!;
    final dir = tempDirectory ?? Directory.systemTemp;
    final id = identityHashCode(this);
    final ts = DateTime.now().microsecondsSinceEpoch;
    _shaderFile = File(p.join(dir.path, 'cb_vr_${id}_$ts.glsl'));
    return _shaderFile!;
  }

  Future<void> clear(PlaybackPlayer? player) async {
    _throttle?.cancel();
    _throttle = null;
    _pending = null;
    _applied = const VrViewState();
    if (player != null) {
      await player.setNativeProperty('glsl-shaders', '');
    }
  }

  void dispose() {
    _disposed = true;
    _throttle?.cancel();
    _throttle = null;
    _pending = null;
    _pendingPlayer = null;
    final file = _shaderFile;
    _shaderFile = null;
    if (file != null) {
      unawaited(file.delete().catchError((Object _) => file));
    }
  }
}

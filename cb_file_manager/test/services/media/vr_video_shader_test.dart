import 'package:cb_file_manager/services/media/vr_video_shader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VrViewState', () {
    test('clamps pitch, fov, and 180-degree yaw', () {
      const base = VrViewState(mode: VrProjectionMode.vr180Sbs);
      final clamped = base.copyWith(yawDeg: 140, pitchDeg: -120, fovDeg: 200);
      expect(clamped.yawDeg, 90.0);
      expect(clamped.pitchDeg, -VrViewState.maxPitchDeg);
      expect(clamped.fovDeg, VrViewState.maxFovDeg);
      expect(clamped.isActive, isTrue);
      expect(clamped.isSpherical, isTrue);
      expect(clamped.is180, isTrue);
      expect(clamped.isSbs, isTrue);
    });

    test('wraps 360-degree yaw cleanly across +-180', () {
      const base = VrViewState(mode: VrProjectionMode.vr360Mono);
      final wrapped = base.copyWith(yawDeg: 195);
      expect(wrapped.yawDeg, closeTo(-165.0, 0.001));
    });

    test('resetView preserves active mode and restores default angles', () {
      const moved = VrViewState(
        mode: VrProjectionMode.vr180Ou,
        yawDeg: 45,
        pitchDeg: -20,
        fovDeg: 70,
      );
      final reset = moved.resetView();
      expect(reset.mode, VrProjectionMode.vr180Ou);
      expect(reset.yawDeg, 0.0);
      expect(reset.pitchDeg, 0.0);
      expect(reset.fovDeg, 95.0);
    });
  });

  group('VrVideoShader.detectHintFromFileName', () {
    test('detects common VR180, VR360, SBS, and OU tags', () {
      expect(
        VrVideoShader.detectHintFromFileName('Sample_8K_180x180_3dh.mp4'),
        VrProjectionMode.vr180Sbs,
      );
      expect(
        VrVideoShader.detectHintFromFileName('concert_VR180_TB.mkv'),
        VrProjectionMode.vr180Ou,
      );
      expect(
        VrVideoShader.detectHintFromFileName('spacewalk_360_8k.mp4'),
        VrProjectionMode.vr360Mono,
      );
      expect(
        VrVideoShader.detectHintFromFileName('coaster_360_SBS.mp4'),
        VrProjectionMode.vr360Sbs,
      );
      expect(
        VrVideoShader.detectHintFromFileName('nature_360_OU.mp4'),
        VrProjectionMode.vr360Ou,
      );
      expect(
        VrVideoShader.detectHintFromFileName('movie_HSBS_4K.mkv'),
        VrProjectionMode.sbsMono,
      );
      expect(
        VrVideoShader.detectHintFromFileName('holiday_4k_60fps.mp4'),
        VrProjectionMode.off,
      );
    });
  });

  group('VrVideoShader.buildGlsl', () {
    test('returns null when off', () {
      expect(VrVideoShader.buildGlsl(const VrViewState()), isNull);
    });

    test('generates single-eye crop shader for SBS and OU', () {
      final sbs = VrVideoShader.buildGlsl(
        const VrViewState(mode: VrProjectionMode.sbsMono),
      );
      expect(sbs, isNotNull);
      expect(sbs, contains('//!HOOK MAIN'));
      expect(sbs, contains('//!WIDTH OUTPUT.w'));
      expect(sbs, contains('HOOKED_pos.x * 0.5'));

      final ou = VrVideoShader.buildGlsl(
        const VrViewState(mode: VrProjectionMode.ouMono),
      );
      expect(ou, isNotNull);
      expect(ou, contains('HOOKED_pos.y * 0.5'));
    });

    test('generates equirectangular projection shader with camera params', () {
      final vr180 = VrVideoShader.buildGlsl(
        const VrViewState(
          mode: VrProjectionMode.vr180Sbs,
          yawDeg: 30,
          pitchDeg: -10,
          fovDeg: 90,
        ),
      );
      expect(vr180, isNotNull);
      expect(vr180, contains('//!HOOK MAIN'));
      expect(vr180, contains('const float U_SCALE = 0.50;'));
      expect(vr180, contains('const float V_SCALE = 1.00;'));
      expect(vr180, contains('if (1 == 1)'));
    });
  });
}

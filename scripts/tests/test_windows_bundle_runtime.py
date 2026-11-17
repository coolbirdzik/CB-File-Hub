"""Native component checks against a built bundle; no Flutter app/E2E runner."""
import ctypes
import json
import math
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import time
import unittest
import wave


@unittest.skipUnless(os.name == 'nt' and os.environ.get('CB_BUNDLE_DIR'),
                     'Set CB_BUNDLE_DIR to a built Windows Release bundle')
class WindowsBundleRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.bundle = Path(os.environ['CB_BUNDLE_DIR']).resolve()

    @unittest.skipUnless(os.environ.get('CB_MEDIA_FIXTURES'), 'Set CB_MEDIA_FIXTURES to synthetic codec clips')
    def test_bundled_media_kit_backend_plays_codec_matrix(self):
        class Event(ctypes.Structure):
            _fields_ = [('event_id', ctypes.c_int), ('error', ctypes.c_int),
                        ('reply_userdata', ctypes.c_uint64), ('data', ctypes.c_void_p)]

        class EndFile(ctypes.Structure):
            _fields_ = [('reason', ctypes.c_int), ('error', ctypes.c_int)]

        with os.add_dll_directory(str(self.bundle)):
            mpv = ctypes.CDLL(str(self.bundle / 'libmpv-2.dll'))
            mpv.mpv_create.restype = ctypes.c_void_p
            mpv.mpv_initialize.argtypes = [ctypes.c_void_p]
            mpv.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
            mpv.mpv_command.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
            mpv.mpv_wait_event.argtypes = [ctypes.c_void_p, ctypes.c_double]
            mpv.mpv_wait_event.restype = ctypes.POINTER(Event)
            mpv.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
            player = mpv.mpv_create()
            self.assertTrue(player)
            try:
                # Decode actual video/audio without creating a window or making sound.
                for key, value in [(b'vo', b'null'), (b'ao', b'null'),
                                   (b'hwdec', b'no'), (b'terminal', b'no')]:
                    self.assertEqual(mpv.mpv_set_option_string(player, key, value), 0)
                self.assertEqual(mpv.mpv_initialize(player), 0)
                fixtures = Path(os.environ['CB_MEDIA_FIXTURES']).resolve()
                for name in ['h264-aac.mkv', 'hevc-aac.mkv', 'vp9-opus.webm', 'av1-opus.mkv',
                             'audio.mp3', 'audio.flac', 'audio.ogg']:
                    with self.subTest(codec=name):
                        command = (ctypes.c_char_p * 3)(b'loadfile', str(fixtures / name).encode('utf-8'), None)
                        self.assertEqual(mpv.mpv_command(player, command), 0)
                        deadline = time.monotonic() + 30
                        while time.monotonic() < deadline:
                            event = mpv.mpv_wait_event(player, 0.1).contents
                            if event.event_id == 7:  # MPV_EVENT_END_FILE
                                end = ctypes.cast(event.data, ctypes.POINTER(EndFile)).contents
                                self.assertEqual(end.reason, 0, f'{name}: reason={end.reason}, error={end.error}')
                                self.assertEqual(end.error, 0)
                                break
                        else:
                            self.fail(f'Timeout playing {name}')
            finally:
                mpv.mpv_terminate_destroy(player)

    @unittest.skipUnless(os.environ.get('CB_MEDIA_FIXTURES'), 'Set CB_MEDIA_FIXTURES to synthetic codec clips')
    def test_codec_matrix_stream_copy_decode_subtitles_and_native_thumbnails(self):
        fixtures = Path(os.environ['CB_MEDIA_FIXTURES']).resolve()
        expected = ['h264-aac.mkv', 'hevc-aac.mkv', 'vp9-opus.webm', 'av1-opus.mkv',
                    'audio.mp3', 'audio.flac', 'audio.ogg']
        env = dict(os.environ, PATH=str(self.bundle) + os.pathsep + os.environ.get('PATH', ''))
        with tempfile.TemporaryDirectory(prefix='cb-codecs-') as temporary:
            for name in expected:
                with self.subTest(codec=name):
                    source = fixtures / name
                    self.assertTrue(source.is_file(), str(source))
                    exported = Path(temporary) / name
                    for arguments in [
                        ['-i', str(source), '-map', '0', '-c', 'copy', str(exported)],
                        ['-i', str(exported), '-map', '0:v?', '-map', '0:a?', '-f', 'null', '-'],
                    ]:
                        result = subprocess.run([str(self.bundle / 'ffmpeg.exe'), '-v', 'error', *arguments],
                                                capture_output=True, text=True, env=env, timeout=30)
                        self.assertEqual(result.returncode, 0, result.stderr)
                    request = dict(id=1, command='decode', source=str(exported), duration_ms=500)
                    result = subprocess.run([str(self.bundle / 'subtitles/cb-subtitle-worker.exe')],
                                            input=json.dumps(request) + '\n', env=env,
                                            capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    response = json.loads(result.stdout.strip())
                    self.assertNotIn('error', response)
                    self.assertGreater(response['rms'], 0.01)
                    if name.startswith('audio.'):
                        continue
                    thumbnail = os.environ.get('CB_THUMBNAIL_TEST_EXE')
                    self.assertTrue(thumbnail, 'CB_THUMBNAIL_TEST_EXE is required for video fixtures')
                    result = subprocess.run([thumbnail, str(exported), str(Path(temporary) / name)],
                                            capture_output=True, text=True, env=env, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_canonical_litert_dlls_load_without_alias_copies(self):
        names = ['webgpu_dawn.dll', 'libLiteRt.dll', 'libGemmaModelConstraintProvider.dll',
                 'libLiteRtTopKWebGpuSampler.dll', 'libLiteRtWebGpuAccelerator.dll',
                 'LiteRtLm.dll']
        for name in names:
            self.assertTrue((self.bundle / name).is_file(),
                            f'Missing bundled native asset: {name}. '
                            'Check the native-assets CMake install rule and Flutter hook output.')
        for alias in ['libwebgpu_dawn.dll', 'LiteRt.dll', 'GemmaModelConstraintProvider.dll',
                      'LiteRtTopKWebGpuSampler.dll', 'LiteRtWebGpuAccelerator.dll']:
            self.assertFalse((self.bundle / alias).exists())
        # Isolate CRT initialization and native-library lifetime from unittest.
        code = """
import ctypes, os, sys
from pathlib import Path
root = Path(sys.argv[1])
with os.add_dll_directory(str(root)):
    loaded = [ctypes.WinDLL(str(root / name)) for name in sys.argv[2:]]
print('Loaded all canonical LiteRT DLLs')
"""
        result = subprocess.run([sys.executable, '-c', code, str(self.bundle), *names],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shared_ffmpeg_cli_and_isolated_subtitle_decoder(self):
        self.assertTrue((self.bundle / 'subtitles/vulkan-1.dll').is_file())
        self.assertFalse(list((self.bundle / 'subtitles').glob('av*-*.dll')))
        self.assertFalse(list((self.bundle / 'ffmpeg').glob('*.dll')))
        env = dict(os.environ, PATH=str(self.bundle) + os.pathsep + os.environ.get('PATH', ''))
        with tempfile.TemporaryDirectory(prefix='cb-bundle-decode-') as temporary:
            audio = Path(temporary) / 'tone.wav'
            cut = Path(temporary) / 'cut.wav'
            cli = str(self.bundle / 'ffmpeg.exe')
            with wave.open(str(audio), 'wb') as output:
                output.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                output.writeframes(b''.join(struct.pack('<h', int(5000 * math.sin(i * math.tau * 440 / 16000)))
                                            for i in range(16000)))
            export = subprocess.run([cli, '-v', 'error', '-ss', '0.1', '-i', str(audio),
                                     '-t', '0.5', '-c', 'copy', str(cut)], env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(export.returncode, 0, export.stderr)
            request = dict(id=1, command='decode', source=str(cut), duration_ms=1000)
            result = subprocess.run([str(self.bundle / 'subtitles/cb-subtitle-worker.exe')],
                                    cwd=self.bundle / 'subtitles', env=env,
                                    input=json.dumps(request) + '\n',
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            response = json.loads(result.stdout.strip())
            self.assertNotIn('error', response)
            self.assertGreater(response['samples'], 0)
            self.assertGreater(response['rms'], 0)


if __name__ == '__main__':
    unittest.main()

"""Component tests for the native worker; does not launch the Flutter app.

python native/subtitles/test_worker.py --worker <exe> [--model <ggml-base.bin>]
    [--speech-sample <jfk.wav>] [--japanese-sample <ja.mp3>] [--ffmpeg <ffmpeg executable>]
"""
import argparse
import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import unittest
import wave

parser = argparse.ArgumentParser()
parser.add_argument('--worker', required=True, type=Path)
parser.add_argument('--model', type=Path)
parser.add_argument('--speech-sample', type=Path)
parser.add_argument('--japanese-sample', type=Path)
parser.add_argument('--ffmpeg', type=Path)
parser.add_argument('--gpu', action='store_true')
parser.add_argument('--test-gpu-startup', action='store_true')
args, remaining = parser.parse_known_args()


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='subtitle-component-', dir=args.worker.parent)
        self.root = Path(self.temp.name)
        self.wav = self.root / 'phụ đề 測試.wav'
        with wave.open(str(self.wav), 'wb') as output:
            output.setparams((2, 2, 44100, 0, 'NONE', 'not compressed'))
            frames = bytearray()
            for i in range(44100 * 4):
                sample = 0 if i < 44100 * 2 else int(5000 * math.sin(i * math.tau * 440 / 44100))
                frames.extend(struct.pack('<hh', sample, sample))
            output.writeframes(frames)

    def tearDown(self):
        self.temp.cleanup()

    def run_worker(self, *requests):
        requests = [{'id': i + 1, **request} for i, request in enumerate(requests)]
        result = subprocess.run([str(args.worker.resolve())], input=''.join(json.dumps(r) + '\n' for r in requests),
                                capture_output=True, text=True, encoding='utf-8', timeout=180)
        self.assertEqual(result.returncode, 0, result.stderr[-2000:])
        events = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(events), len(requests))
        self.assertEqual([e['id'] for e in events], list(range(1, len(events) + 1)))
        return events

    def test_resample_seek_and_unicode_source(self):
        first, second = self.run_worker(
            {'command': 'decode', 'source': str(self.wav), 'start_ms': 0, 'duration_ms': 1000},
            {'command': 'decode', 'source': str(self.wav), 'start_ms': 2500, 'duration_ms': 1000})
        self.assertEqual(first['samples'], 16000)
        self.assertEqual(first['rms'], 0)
        self.assertEqual(second['samples'], 16000)
        self.assertGreater(second['rms'], 0.1)

    def test_errors_are_protocol_messages(self):
        bad, missing, unknown = self.run_worker(
            {'command': 'transcribe', 'source': str(self.wav)},
            {'command': 'decode', 'source': str(self.root / 'missing.wav')},
            {'command': 'unsupported'})
        for event in (bad, missing, unknown):
            self.assertIn('error', event)

    @unittest.skipUnless(args.ffmpeg, 'Pass --ffmpeg to verify multi-track decoding')
    def test_selected_audio_track(self):
        media = self.root / 'tracks.mkv'
        subprocess.run([str(args.ffmpeg), '-v', 'error', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
                        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '4',
                        '-map', '0:a', '-map', '1:a', '-c:a', 'pcm_s16le', str(media)], check=True, timeout=30)
        silence, tone = self.run_worker(
            {'command': 'decode', 'source': str(media), 'audio_track': 0, 'start_ms': 1000, 'duration_ms': 1000},
            {'command': 'decode', 'source': str(media), 'audio_track': 1, 'start_ms': 1000, 'duration_ms': 1000})
        self.assertEqual(silence['rms'], 0)
        self.assertGreater(tone['rms'], 0.05)

    @unittest.skipUnless(args.model and args.speech_sample, 'Pass --model and --speech-sample for inference')
    def test_real_model_unicode_path_and_timestamps(self):
        model = self.root / 'mô hình 測試.bin'
        model.hardlink_to(args.model.resolve())
        ready, recognized = self.run_worker(
            {'command': 'init', 'model': str(model), 'gpu': args.gpu},
            {'command': 'transcribe', 'source': str(args.speech_sample.resolve()),
             'start_ms': 0, 'duration_ms': 10000, 'language': 'en'})
        self.assertTrue(ready['ready'])
        self.assertIn('country', ' '.join(s['text'] for s in recognized['segments']).lower())
        for segment in recognized['segments']:
            self.assertTrue(0 <= segment['start_ms'] < segment['end_ms'] <= 10000)

    @unittest.skipUnless(args.model and args.japanese_sample, 'Pass --model and --japanese-sample for Japanese inference')
    def test_japanese_explicit_and_auto_keep_requested_timeline(self):
        ready, explicit, auto = self.run_worker(
            {'command': 'init', 'model': str(args.model.resolve()), 'gpu': args.gpu},
            {'command': 'transcribe', 'source': str(args.japanese_sample.resolve()),
             'start_ms': 0, 'duration_ms': 8000, 'language': 'ja'},
            {'command': 'transcribe', 'source': str(args.japanese_sample.resolve()),
             'start_ms': 0, 'duration_ms': 1000, 'language': 'auto'})
        self.assertTrue(ready['ready'])
        self.assertEqual(explicit['language'], 'ja')
        text = ''.join(s['text'] for s in explicit['segments'])
        self.assertTrue(any('\u3040' <= c <= '\u30ff' for c in text))
        self.assertEqual(auto['language'], 'ja')
        self.assertEqual(auto['audio_ms'], 1000)
        for event, limit in ((explicit, 8000), (auto, 1000)):
            for segment in event['segments']:
                self.assertTrue(0 <= segment['start_ms'] < segment['end_ms'] <= limit)

    @unittest.skipUnless(args.model, 'Pass --model for recognition silence gate')
    def test_auto_context_does_not_turn_later_audio_into_silent_chunk_subtitles(self):
        _, silent = self.run_worker(
            {'command': 'init', 'model': str(args.model.resolve()), 'gpu': args.gpu},
            {'command': 'transcribe', 'source': str(self.wav),
             'start_ms': 0, 'duration_ms': 1000, 'language': 'auto'})
        self.assertEqual(silent['segments'], [])
        self.assertEqual(silent['audio_ms'], 1000)

    @unittest.skipUnless(args.model and args.japanese_sample and args.test_gpu_startup,
                         'Requires GPU and a helper built with CB_SUBTITLE_TEST_HOOKS=ON')
    def test_cpu_delivers_cues_during_gpu_warmup_then_hands_off(self):
        with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as log:
            worker = subprocess.Popen([str(args.worker.resolve())], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=log, text=True, encoding='utf-8')
            def request(payload):
                worker.stdin.write(json.dumps(payload) + '\n'); worker.stdin.flush()
                return json.loads(worker.stdout.readline())
            try:
                initialized = request({'id': 1, 'command': 'init', 'model': str(args.model.resolve()),
                    'gpu': True, 'test_warmup_delay_ms': 6000})
                self.assertTrue(initialized['accelerated'])
                command = {'command': 'transcribe', 'source': str(args.japanese_sample.resolve()),
                    'start_ms': 0, 'duration_ms': 8000, 'language': 'ja'}
                started = time.monotonic()
                first = request({'id': 2, **command})
                self.assertLess(time.monotonic() - started, 5)
                self.assertEqual(first['backend'], 'cpu-startup')
                self.assertTrue(first['segments'])
                time.sleep(6)
                second = request({'id': 3, **command})
                self.assertEqual(second['backend'], 'gpu')
                self.assertEqual(second['language'], 'ja')
                self.assertTrue(second['segments'])
            finally:
                worker.terminate()
                try: worker.wait(timeout=5)
                except subprocess.TimeoutExpired: worker.kill(); worker.wait()
                worker.stdin.close()
                worker.stdout.close()

    @unittest.skipUnless(args.model and args.japanese_sample, 'Requires a Japanese speech fixture')
    def test_metadata_hint_avoids_redundant_language_detection(self):
        _, recognized = self.run_worker(
            {'command': 'init', 'model': str(args.model.resolve()), 'gpu': args.gpu},
            {'command': 'transcribe', 'source': str(args.japanese_sample.resolve()),
             'start_ms': 0, 'duration_ms': 8000, 'language': 'auto', 'language_hint': 'ja'})
        self.assertEqual(recognized['language'], 'ja')
        self.assertEqual(recognized['timings']['detect_ms'], 0)

    @unittest.skipUnless(args.model and args.japanese_sample, 'Requires a Japanese speech fixture')
    def test_confident_language_is_reused_only_for_contiguous_audio(self):
        commands = [{'command': 'init', 'model': str(args.model.resolve()), 'gpu': args.gpu}]
        for position in (0, 2000, 4000, 0):
            commands.append({'command': 'transcribe', 'source': str(args.japanese_sample.resolve()),
                'start_ms': position, 'duration_ms': 2000, 'language': 'auto'})
        _, first, second, reused, rewind = self.run_worker(*commands)
        self.assertEqual([e['language'] for e in (first, second, reused, rewind)], ['ja'] * 4)
        self.assertGreaterEqual(first['language_confidence'], 0.75)
        self.assertGreaterEqual(second['language_confidence'], 0.75)
        self.assertTrue(reused['language_reused'])
        self.assertEqual(reused['timings']['detect_ms'], 0)
        self.assertFalse(rewind['language_reused'])
        self.assertGreater(rewind['timings']['detect_ms'], 0)


if __name__ == '__main__':
    unittest.main(argv=['test_worker.py', *remaining])

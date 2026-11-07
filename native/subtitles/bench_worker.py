"""Bounded component benchmark; never starts or controls the Flutter app.

Only timing/count metadata is printed. Audio and transcripts stay on-device.
"""
import argparse
import json
from pathlib import Path
import queue
import statistics
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--worker', required=True, type=Path)
parser.add_argument('--model', required=True, type=Path)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--start-ms', type=int, default=120000)
parser.add_argument('--chunks', type=int, default=8)
parser.add_argument('--chunk-ms', type=int, default=8000)
parser.add_argument('--language', default='auto')
parser.add_argument('--gpu', action='store_true')
parser.add_argument('--init-warmup-delay-ms', type=int, default=0,
    help='Controlled startup test; requires a helper built with test hooks')
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
args.output.parent.mkdir(parents=True, exist_ok=True)

with args.output.with_suffix('.stderr.log').open('w', encoding='utf-8') as log:
    process = subprocess.Popen([str(args.worker.resolve())], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=log, text=True, encoding='utf-8', bufsize=1)
    responses = queue.Queue()
    def reader():
        for line in process.stdout:
            responses.put(json.loads(line))
        responses.put({'error': 'Worker exited'})
    threading.Thread(target=reader, daemon=True).start()
    def request(command):
        started = time.perf_counter()
        process.stdin.write(json.dumps(command) + '\n')
        process.stdin.flush()
        response = responses.get(timeout=180)
        if 'error' in response:
            raise RuntimeError(response['error'])
        return response, (time.perf_counter() - started) * 1000
    try:
        ready, load_ms = request({'id': 1, 'command': 'init',
            'model': str(args.model.resolve()), 'gpu': args.gpu,
            'test_warmup_delay_ms': args.init_warmup_delay_ms})
        if args.init_warmup_delay_ms and not (ready.get('test_hooks') and ready.get('accelerated')):
            raise RuntimeError('Startup delay requires GPU and CB_SUBTITLE_TEST_HOOKS=ON')
        chunks = []
        for index in range(args.chunks):
            start = args.start_ms + index * args.chunk_ms
            response, total_ms = request({'id': index + 2, 'command': 'transcribe',
                'source': str(args.source.resolve()), 'start_ms': max(0, start - 800),
                'duration_ms': args.chunk_ms + (800 if start else 0),
                'language': args.language, 'audio_track': 0})
            chunks.append({'index': index, 'total_ms': round(total_ms, 2),
                'rtf': round(total_ms / args.chunk_ms, 4),
                'language': response.get('language'), 'segments': len(response.get('segments', [])),
                'language_confidence': response.get('language_confidence'),
                'language_reused': response.get('language_reused', False),
                'backend': response.get('backend'),
                **response.get('timings', {})})
        times = [c['total_ms'] for c in chunks]
        report = {'model': args.model.name, 'language': args.language, 'gpu': args.gpu,
            'load_ms': round(load_ms, 2), 'chunk_ms': args.chunk_ms,
            'median_ms': round(statistics.median(times), 2),
            'max_ms': round(max(times), 2),
            'rtf': round(sum(times) / (args.chunks * args.chunk_ms), 4), 'chunks': chunks}
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps({k: v for k, v in report.items() if k != 'chunks'}))
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

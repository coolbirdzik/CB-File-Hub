"""Component stress test: hardware video decoding while ASR runs continuously.

No app/E2E runner, rendered frames, audio output or transcripts are produced.
"""
import argparse
import itertools
import json
from pathlib import Path
import re
import statistics
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
for name in ('ffmpeg', 'worker', 'model', 'source', 'output'):
    parser.add_argument('--' + name, type=Path, required=True)
parser.add_argument('--start-ms', type=int, default=600000)
parser.add_argument('--seconds', type=int, default=30)
args = parser.parse_args()
args.output.parent.mkdir(parents=True, exist_ok=True)
ffmpeg = [str(args.ffmpeg.resolve()), '-hide_banner', '-benchmark',
    '-init_hw_device', 'd3d11va=video:,vendor_id=0x10de',
    '-hwaccel', 'd3d11va', '-hwaccel_device', 'video', '-hwaccel_output_format', 'd3d11',
    '-ss', str(args.start_ms / 1000), '-i', str(args.source.resolve()),
    '-t', str(args.seconds), '-an', '-sn', '-dn', '-fps_mode', 'passthrough', '-f', 'null', '-']


def decode(label):
    started = time.monotonic()
    result = subprocess.run(ffmpeg, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
    args.output.with_suffix('.' + label + '.log').write_text(result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(result.stderr[-2000:])
    frames = int(re.findall(r'frame=\s*(\d+)', result.stderr)[-1])
    elapsed = time.monotonic() - started
    return {'frames': frames, 'elapsed_seconds': round(elapsed, 3), 'fps': round(frames / elapsed, 2)}


baseline = decode('baseline')
with args.output.with_suffix('.worker.log').open('w', encoding='utf-8') as log:
    worker = subprocess.Popen([str(args.worker.resolve())], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=log, text=True, encoding='utf-8')
    ids = itertools.count(1)
    samples, failures = [], []
    stop, ready = threading.Event(), threading.Event()
    def request(command):
        worker.stdin.write(json.dumps({'id': next(ids), **command}) + '\n'); worker.stdin.flush()
        response = json.loads(worker.stdout.readline())
        if 'error' in response:
            raise RuntimeError(response['error'])
        return response
    def recognize(index):
        started = time.monotonic()
        request({'command': 'transcribe', 'source': str(args.source.resolve()),
            'start_ms': args.start_ms + index * 8000, 'duration_ms': 8000, 'language': 'ja'})
        return (time.monotonic() - started) * 1000
    def stress():
        try:
            for index in range(200):
                if stop.is_set(): break
                samples.append(recognize(index + 3)); ready.set()
        except Exception as error:
            failures.append(str(error)); ready.set()
    thread = None
    try:
        request({'command': 'init', 'model': str(args.model.resolve()), 'gpu': True})
        for i in range(3): recognize(i)
        thread = threading.Thread(target=stress, daemon=True); thread.start()
        if not ready.wait(30): raise TimeoutError('ASR did not start')
        stressed = decode('continuous-asr')
    finally:
        stop.set()
        if thread: thread.join(timeout=90)
        worker.terminate()
        try: worker.wait(timeout=5)
        except subprocess.TimeoutExpired: worker.kill(); worker.wait()
        if thread: thread.join(timeout=5)
        worker.stdin.close(); worker.stdout.close()
    if failures: raise RuntimeError(failures)
    report = {'video_seconds': args.seconds, 'baseline': baseline, 'continuous_asr': stressed,
        'asr_requests': len(samples), 'asr_median_ms': round(statistics.median(samples), 2),
        'asr_max_ms': round(max(samples), 2)}
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))

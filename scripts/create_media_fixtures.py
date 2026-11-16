"""Generate short synthetic clips using a full FFmpeg, outside the app bundle."""
import argparse
from pathlib import Path
import subprocess


def generate(ffmpeg, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    videos = [
        ('h264-aac.mkv', 'libx264', 'aac', ['-preset', 'ultrafast']),
        ('hevc-aac.mkv', 'libx265', 'aac', ['-preset', 'ultrafast', '-x265-params', 'pools=none:frame-threads=1']),
        ('vp9-opus.webm', 'libvpx-vp9', 'libopus', ['-deadline', 'realtime', '-cpu-used', '8']),
        ('av1-opus.mkv', 'libaom-av1', 'libopus', ['-cpu-used', '8']),
    ]
    for name, video, audio, options in videos:
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-f', 'lavfi', '-i',
                        'testsrc2=size=96x64:rate=10:duration=1', '-f', 'lavfi', '-i',
                        'sine=frequency=440:duration=1', '-c:v', video, '-threads', '1',
                        *options, '-c:a', audio, '-shortest', str(destination / name)],
                       check=True, timeout=90)
    for name, codec in [('audio.mp3', 'libmp3lame'), ('audio.flac', 'flac'),
                        ('audio.ogg', 'libvorbis')]:
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-f', 'lavfi', '-i',
                        'sine=frequency=440:duration=1', '-c:a', codec, str(destination / name)],
                       check=True, timeout=30)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    generate(args.ffmpeg, args.output)

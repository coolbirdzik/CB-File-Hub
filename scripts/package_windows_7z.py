"""Create a fresh solid portable archive; never retain files from an older build."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def find_7z():
    installed = shutil.which('7z') or shutil.which('7zz')
    if installed:
        return installed
    candidate = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / '7-Zip/7z.exe'
    if candidate.is_file():
        return str(candidate)
    raise RuntimeError('7-Zip is required to package Windows portable releases.')


def package(source, destination):
    source = Path(source).resolve(strict=True)
    destination = Path(destination).resolve()
    if source == destination or source in destination.parents:
        raise ValueError('Archive destination must be outside the bundle.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cb-7z-', dir=destination.parent) as temporary:
        archive = Path(temporary) / 'portable.7z'
        subprocess.run([find_7z(), 'a', '-t7z', '-m0=LZMA2', '-mx=9', '-ms=on',
                        '-mmt=4', str(archive), '.'], cwd=source, check=True)
        subprocess.run([find_7z(), 't', str(archive)], check=True)
        os.replace(archive, destination)
    print(f'Portable 7z: {destination} ({destination.stat().st_size} bytes)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('destination')
    args = parser.parse_args()
    package(args.source, args.destination)

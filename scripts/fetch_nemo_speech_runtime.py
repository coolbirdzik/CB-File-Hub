"""Fetch the pinned Windows x64 NeMo-Speech ASR SDK into a build-only cache."""

import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

VERSION = '0.3.0'
HASHES = {
    'vulkan': '72b3b8b41bfe2be0320eff4e9d310594e4f99deefcde4a157799a039656963ce',
    'cpu': '4ed9740e361e4653f56c3dce7d1e81883a1c8b831c1bd7d01567fff1130b5b05',
}


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest()


def fetch(destination, backend):
    name = f'nemo-speech-{VERSION}-windows-x86_64-{backend}'
    sha256 = HASHES[backend]
    url = f'https://github.com/NVIDIA/NeMo-Speech.cpp/releases/download/v{VERSION}/{name}.zip'
    destination.mkdir(parents=True, exist_ok=True)
    marker = destination / 'manifest.json'
    try:
        manifest = json.loads(marker.read_text(encoding='utf-8'))
        if manifest['archive'] == sha256 and all(
            (destination / name).is_file() and digest(destination / name) == sha
            for name, sha in manifest['files'].items()
        ) and (destination / 'include/nemo_speech/asr.h').is_file():
            return
    except (OSError, ValueError, KeyError, TypeError):
        pass
    archive = destination / f'{name}.zip'
    if not archive.is_file() or digest(archive) != sha256:
        partial = archive.with_suffix('.zip.part')
        urllib.request.urlretrieve(url, partial)
        if digest(partial) != sha256:
            raise RuntimeError('NeMo-Speech SDK checksum mismatch')
        partial.replace(archive)
    files = {}
    with zipfile.ZipFile(archive) as release:
        for item in release.infolist():
            if item.is_dir():
                continue
            member = Path(item.filename)
            if member.parts[0] != name or '..' in member.parts:
                raise RuntimeError(f'Unexpected NeMo archive entry: {member}')
            relative = Path(*member.parts[1:])
            target = destination / relative
            if not target.resolve().is_relative_to(destination.resolve()):
                raise RuntimeError('NeMo archive escaped destination')
            target.parent.mkdir(parents=True, exist_ok=True)
            data = release.read(item)
            target.write_bytes(data)
            files[relative.as_posix()] = hashlib.sha256(data).hexdigest()
    marker.write_text(json.dumps({'archive': sha256, 'files': files}), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--backend', choices=HASHES, default='vulkan')
    args = parser.parse_args()
    fetch(args.destination.resolve(), args.backend)

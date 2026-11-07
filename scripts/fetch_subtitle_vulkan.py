"""Extract pinned Vulkan build tools and loader into the ignored build cache.

The SDK installer is treated only as a verified archive. It is never executed;
no SDK installation, environment changes, registry writes or driver changes.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
import zlib

VERSION = '1.4.350.0'
SDK_SHA = '855b27ba05d2d8119c5114c5d4ff870ca38f2c632b11e1bb9923b9b7e6ecfe7b'
RT_SHA = '23ce69f32cef3e2799617e2b1776cd0c71030d23a91f8375821cc40d76b185b9'
URL = f'https://sdk.lunarg.com/sdk/download/{VERSION}/windows/'
REQUIRED = ['Bin/glslc.exe', 'Bin/shaderc_shared.dll', 'Include/vulkan/vulkan.h',
    'Include/vulkan/vulkan.hpp', 'Lib/vulkan-1.lib', 'Bin/vulkan-1.dll', 'LICENSE-VulkanRT.txt',
    'Lib/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake', 'Include/spirv/unified1/spirv.hpp']


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def download(url, target, digest):
    def valid():
        return target.is_file() and sha256(target) == digest
    if valid():
        return
    request = urllib.request.Request(url, headers={'User-Agent': 'CB-File-Hub-build-tools/1.0'})
    for attempt in range(3):
        partial = None
        try:
            # Independent CMake configurations must not share a partial file.
            with tempfile.NamedTemporaryFile(dir=target.parent, prefix=target.name + '.',
                    suffix='.part', delete=False) as output:
                partial = Path(output.name)
                with urllib.request.urlopen(request, timeout=120) as response:
                    shutil.copyfileobj(response, output, 1024 * 1024)
            if sha256(partial) != digest:
                raise RuntimeError('Vulkan build-tool download checksum mismatch')
            os.replace(partial, target)
            return
        except urllib.error.HTTPError as error:
            if error.code not in (403, 408, 429, 500, 502, 503, 504) or attempt == 2:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise
        finally:
            if partial is not None:
                partial.unlink(missing_ok=True)
        time.sleep(2 ** attempt)


def fetch(root, cmake):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    marker = root / '.ready'
    if marker.is_file() and marker.read_text() == SDK_SHA + RT_SHA and all((root / f).is_file() for f in REQUIRED):
        return
    sdk = root / 'sdk.exe'
    runtime = root / 'runtime.zip'
    # LunarG documents Human=true for shared IPs hitting its download limit:
    # https://vulkan.lunarg.com/content/view/latest-sdk-version-api
    download(URL + f'vulkansdk-windows-X64-{VERSION}.exe?Human=true', sdk, SDK_SHA)
    download(URL + 'vulkan-runtime-components.zip?Human=true', runtime, RT_SHA)
    data = sdk.read_bytes()
    signature, offset = b'7z\xbc\xaf\x27\x1c', 0
    # The Qt installer contains several independent 7z payloads. Only extract
    # the headers, import library and shader compiler, never its installer code.
    with tempfile.TemporaryDirectory(prefix='payload-', dir=root) as temporary:
        while True:
            offset = data.find(signature, offset)
            if offset < 0:
                break
            begin = offset
            offset += len(signature)
            if begin + 32 > len(data) or zlib.crc32(data[begin + 12:begin + 32]) != struct.unpack_from('<I', data, begin + 8)[0]:
                continue
            after, size = struct.unpack_from('<QQ', data, begin + 12)
            end = begin + 32 + after + size
            if end > len(data):
                continue
            archive = Path(temporary) / f'{begin}.7z'
            archive.write_bytes(data[begin:end])
            listing = subprocess.check_output([cmake, '-E', 'tar', 'tf', str(archive)], encoding='utf-8', errors='replace')
            selected = []
            for line in listing.splitlines():
                path = line.strip().replace('\\', '/')
                if path.startswith(('Include/vulkan/', 'Include/vk_video/', 'Include/spirv/', 'Lib/cmake/SPIRV-Headers/')) or path in REQUIRED[:2] + ['Lib/vulkan-1.lib']:
                    # Verify every extraction target remains in the build cache.
                    resolved = (root / path).resolve()
                    if not resolved.is_relative_to(root):
                        raise RuntimeError('Unsafe Vulkan archive member')
                    selected.append(path)
            if selected:
                subprocess.run([cmake, '-E', 'tar', 'xf', str(archive), '--', *selected],
                    check=True, cwd=root, stdout=subprocess.DEVNULL)
    with zipfile.ZipFile(runtime) as archive:
        loader = next(name for name in archive.namelist() if name.replace('\\', '/').endswith('/x64/vulkan-1.dll'))
        license = next(name for name in archive.namelist() if name.endswith('/VulkanRT-License.txt'))
        (root / 'Bin/vulkan-1.dll').write_bytes(archive.read(loader))
        (root / 'LICENSE-VulkanRT.txt').write_bytes(archive.read(license))
    if not all((root / f).is_file() for f in REQUIRED):
        raise RuntimeError('Incomplete Vulkan build-tool extraction')
    marker.write_text(SDK_SHA + RT_SHA)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--cmake', default=shutil.which('cmake') or 'cmake')
    args = parser.parse_args()
    fetch(args.destination, args.cmake)
    print(args.destination.resolve())

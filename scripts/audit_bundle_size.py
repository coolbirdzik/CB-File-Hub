#!/usr/bin/env python3
"""Inventory an unpacked desktop bundle or an APK/AAB without extra packages."""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
import zipfile


def inventory(source):
    source = Path(source)
    duplicates = []
    if source.is_dir():
        rows = [dict(path=p.relative_to(source).as_posix(), bytes=p.stat().st_size)
                for p in sorted(source.rglob('*')) if p.is_file()]
        by_size = defaultdict(list)
        for row in rows:
            by_size[row['bytes']].append(row)
        by_hash = defaultdict(list)
        for candidates in by_size.values():
            if len(candidates) < 2:
                continue
            for row in candidates:
                with (source / row['path']).open('rb') as stream:
                    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
                by_hash[digest].append(row)
        duplicates = [dict(sha256=digest, paths=[r['path'] for r in group],
                           extra_bytes=group[0]['bytes'] * (len(group) - 1))
                      for digest, group in by_hash.items() if len(group) > 1]
        compressed = None
    else:
        with zipfile.ZipFile(source) as archive:
            rows = [dict(path=i.filename, bytes=i.file_size,
                         compressed_bytes=i.compress_size)
                    for i in archive.infolist() if not i.is_dir()]
        compressed = source.stat().st_size
    groups = defaultdict(int)
    abis = defaultdict(int)
    for row in rows:
        parts = row['path'].split('/')
        groups[parts[0] if len(parts) > 1 else '[root]'] += row['bytes']
        if parts[0] == 'lib' and len(parts) >= 3:
            abis[parts[1]] += row['bytes']
        elif len(parts) >= 4 and parts[1] == 'lib':
            abis[parts[2]] += row['bytes']  # AAB base/feature module
    return dict(source=str(source.resolve()), total_bytes=sum(r['bytes'] for r in rows),
                archive_bytes=compressed, groups=dict(sorted(groups.items())),
                abi_bytes=dict(sorted(abis.items())),
                duplicate_extra_bytes=sum(d['extra_bytes'] for d in duplicates),
                duplicates=duplicates,
                files=sorted(rows, key=lambda r: (-r['bytes'], r['path'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--json', type=Path, required=True)
    parser.add_argument('--expect-abis', help='Exact comma-separated APK/AAB ABI set')
    args = parser.parse_args()
    result = inventory(args.source)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    if args.expect_abis and set(args.expect_abis.split(',')) != set(result['abi_bytes']):
        parser.error(f"Unexpected native ABIs: {sorted(result['abi_bytes'])}")
    print(f"Unpacked: {result['total_bytes'] / 1048576:.2f} MiB; "
          f"duplicates: {result['duplicate_extra_bytes'] / 1048576:.2f} MiB")
    if result['archive_bytes'] is not None:
        print(f"Archive: {result['archive_bytes'] / 1048576:.2f} MiB")
    for row in result['files'][:15]:
        print(f"{row['bytes'] / 1048576:8.2f} MiB  {row['path']}")


if __name__ == '__main__':
    main()

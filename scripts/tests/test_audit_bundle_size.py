import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'audit_bundle_size', Path(__file__).resolve().parents[1] / 'audit_bundle_size.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class BundleInventoryTest(unittest.TestCase):
    def test_duplicate_bytes_require_equal_contents_not_equal_sizes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'one.dll').write_bytes(b'same')
            (root / 'alias.dll').write_bytes(b'same')
            (root / 'other.dll').write_bytes(b'diff')
            result = audit.inventory(root)
            self.assertEqual(result['total_bytes'], 12)
            self.assertEqual(result['duplicate_extra_bytes'], 4)
            self.assertEqual(set(result['duplicates'][0]['paths']), {'one.dll', 'alias.dll'})

    def test_apk_reports_per_abi_and_separates_archive_from_unpacked_size(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / 'app.apk'
            with zipfile.ZipFile(apk, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('lib/arm64-v8a/libapp.so', b'A' * 4096)
                archive.writestr('lib/x86_64/libapp.so', b'B' * 8192)
                archive.writestr('assets/font.ttf', b'C' * 1024)
            result = audit.inventory(apk)
            self.assertEqual(result['abi_bytes'], {'arm64-v8a': 4096, 'x86_64': 8192})
            self.assertEqual(result['total_bytes'], 13312)
            self.assertEqual(result['archive_bytes'], apk.stat().st_size)
            self.assertLess(result['archive_bytes'], result['total_bytes'])
            check = subprocess.run([sys.executable, spec.origin, str(apk),
                                    '--json', str(Path(temporary) / 'report.json'),
                                    '--expect-abis', 'arm64-v8a'],
                                   capture_output=True, text=True)
            self.assertNotEqual(check.returncode, 0)
            self.assertIn('Unexpected native ABIs', check.stderr)

    def test_aab_abis_are_read_from_module_library_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / 'app.aab'
            with zipfile.ZipFile(bundle, 'w') as archive:
                archive.writestr('base/lib/arm64-v8a/libapp.so', b'base')
                archive.writestr('feature/lib/arm64-v8a/libfeature.so', b'feature')
            self.assertEqual(audit.inventory(bundle)['abi_bytes'], {'arm64-v8a': 11})


if __name__ == '__main__':
    unittest.main()

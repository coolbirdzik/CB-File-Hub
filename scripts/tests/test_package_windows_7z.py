import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('package_windows_7z', Path(__file__).parents[1] / 'package_windows_7z.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
try:
    tool = packager.find_7z()
except RuntimeError:
    tool = None


@unittest.skipUnless(tool, '7-Zip required')
class PortableArchiveTest(unittest.TestCase):
    def test_repacking_drops_stale_files_and_preserves_unicode(self):
        with tempfile.TemporaryDirectory(prefix='cb-portable-') as temporary:
            root = Path(temporary)
            bundle = root / 'bundle'
            bundle.mkdir()
            obsolete = bundle / 'obsolete.dll'
            obsolete.write_bytes(b'old runtime')
            archive = root / 'portable.7z'
            packager.package(bundle, archive)
            obsolete.unlink()
            expected = bundle / 'phụ đề 測試.dll'
            expected.write_bytes(bytes(range(256)))
            packager.package(bundle, archive)
            extracted = root / 'unpacked'
            subprocess.run([tool, 'x', str(archive), f'-o{extracted}'], check=True, capture_output=True)
            self.assertFalse((extracted / obsolete.name).exists())
            self.assertEqual((extracted / expected.name).read_bytes(), expected.read_bytes())
            self.assertEqual([p.name for p in extracted.iterdir()], [expected.name])

    def test_archive_inside_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                packager.package(temporary, Path(temporary) / 'recursive.7z')


if __name__ == '__main__':
    unittest.main()

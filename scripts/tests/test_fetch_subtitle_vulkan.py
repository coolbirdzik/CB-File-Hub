"""Downloader regression tests; no network or SDK installer is executed."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location(
    'fetch_subtitle_vulkan', Path(__file__).resolve().parents[1] / 'fetch_subtitle_vulkan.py')
vulkan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vulkan)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / 'sdk.exe'
        self.body = b'verified SDK archive'
        self.digest = hashlib.sha256(self.body).hexdigest()
        self.url = vulkan.URL + 'sdk.exe?Human=true'

    def assert_no_partials(self):
        self.assertEqual(list(self.root.glob('*.part')), [])

    def test_valid_cached_download_needs_no_network(self):
        self.target.write_bytes(self.body)
        with patch.object(vulkan.urllib.request, 'urlopen') as open_url:
            vulkan.download(self.url, self.target, self.digest)
        open_url.assert_not_called()

    def test_transient_http_errors_retry_and_replace_only_verified_file(self):
        self.target.write_bytes(b'old invalid archive')
        errors = [urllib.error.HTTPError(self.url, code, 'retry', {}, None)
                  for code in (403, 429)]
        with patch.object(vulkan.urllib.request, 'urlopen',
                          side_effect=[*errors, io.BytesIO(self.body)]) as open_url, \
                patch.object(vulkan.time, 'sleep') as sleep:
            vulkan.download(self.url, self.target, self.digest)
        self.assertEqual(open_url.call_count, 3)
        self.assertEqual(open_url.call_args.args[0].full_url, self.url)
        self.assertTrue(open_url.call_args.args[0].get_header('User-agent'))
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])
        self.assertEqual(self.target.read_bytes(), self.body)
        self.assert_no_partials()

    def test_permanent_http_error_fails_without_retry(self):
        error = urllib.error.HTTPError(self.url, 404, 'missing', {}, None)
        with patch.object(vulkan.urllib.request, 'urlopen', side_effect=error) as open_url, \
                patch.object(vulkan.time, 'sleep') as sleep:
            with self.assertRaises(urllib.error.HTTPError):
                vulkan.download(self.url, self.target, self.digest)
        self.assertEqual(open_url.call_count, 1)
        sleep.assert_not_called()
        self.assertFalse(self.target.exists())
        self.assert_no_partials()

    def test_checksum_failure_preserves_existing_file(self):
        self.target.write_bytes(b'previous archive')
        with patch.object(vulkan.urllib.request, 'urlopen',
                          return_value=io.BytesIO(b'corrupt')) as open_url:
            with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                vulkan.download(self.url, self.target, self.digest)
        self.assertEqual(open_url.call_count, 1)
        self.assertEqual(self.target.read_bytes(), b'previous archive')
        self.assert_no_partials()

    def test_network_failure_has_bounded_retries_and_cleans_partials(self):
        with patch.object(vulkan.urllib.request, 'urlopen',
                          side_effect=urllib.error.URLError('offline')) as open_url, \
                patch.object(vulkan.time, 'sleep'):
            with self.assertRaises(urllib.error.URLError):
                vulkan.download(self.url, self.target, self.digest)
        self.assertEqual(open_url.call_count, 3)
        self.assertFalse(self.target.exists())
        self.assert_no_partials()

    def test_fetch_uses_shared_ip_urls_and_does_not_mark_failed_fetch_ready(self):
        # Stop before archive extraction, after observing both download URLs.
        with patch.object(vulkan, 'download', side_effect=[None, RuntimeError('offline')]) as download:
            with self.assertRaisesRegex(RuntimeError, 'offline'):
                vulkan.fetch(self.root, 'cmake')
        self.assertEqual([call.args[0] for call in download.call_args_list], [
            vulkan.URL + f'vulkansdk-windows-X64-{vulkan.VERSION}.exe?Human=true',
            vulkan.URL + 'vulkan-runtime-components.zip?Human=true',
        ])
        self.assertFalse((self.root / '.ready').exists())

    def test_ready_cache_still_requires_all_tools(self):
        (self.root / '.ready').write_text(vulkan.SDK_SHA + vulkan.RT_SHA)
        for name in vulkan.REQUIRED:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'tool')
        with patch.object(vulkan, 'download') as download:
            vulkan.fetch(self.root, 'cmake')
        download.assert_not_called()
        (self.root / vulkan.REQUIRED[0]).unlink()
        with patch.object(vulkan, 'download', side_effect=RuntimeError('missing tool')) as download:
            with self.assertRaisesRegex(RuntimeError, 'missing tool'):
                vulkan.fetch(self.root, 'cmake')
        download.assert_called_once()


if __name__ == '__main__':
    unittest.main()

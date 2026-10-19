import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    import release_metadata
except ModuleNotFoundError:
    release_metadata = None


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(release_metadata, 'release metadata helper is missing')

    def test_tag_must_match_stable_pubspec_version(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'pubspec.yaml').write_text('version: 2.3.10+20310\n')
            self.assertEqual(release_metadata.validate_version(root, '2.3.10'), '2.3.10+20310')
            self.assertEqual(release_metadata.validate_version(root), '2.3.10+20310')
            for tag in ('2.3.9', 'v2.3.10', '2.3.10-beta', '2.3.10/anything'):
                with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, 'tag'):
                    release_metadata.validate_version(root, tag)

    def test_prerelease_pubspec_cannot_publish_as_stable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'pubspec.yaml').write_text('version: 2.3.10-beta+20310\n')
            with self.assertRaisesRegex(ValueError, 'tag'):
                release_metadata.validate_version(root, '2.3.10')

    def test_selects_exact_single_artifact_from_packager_subdirectory(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            run = directory / 'Kazumi_2.3.10+20310_timestamp'
            run.mkdir()
            expected = run / 'Kazumi_2.3.10+20310_android.apk'
            expected.write_bytes(b'current apk')
            (run / 'Kazumi_2.3.9+20309_android.apk').write_bytes(b'stale apk')
            self.assertEqual(release_metadata.select_artifact(directory, '2.3.10+20310', 'android'), expected)

    def test_missing_or_ambiguous_artifact_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            with self.assertRaisesRegex(ValueError, 'one artifact'):
                release_metadata.select_artifact(directory, '2.3.10+20310', 'android')
            for folder in ('one', 'two'):
                (directory / folder).mkdir()
                (directory / folder / 'Kazumi_2.3.10+20310_android.apk').write_bytes(b'apk')
            with self.assertRaisesRegex(ValueError, 'one artifact'):
                release_metadata.select_artifact(directory, '2.3.10+20310', 'android')

    def test_release_checksums_cover_the_four_published_packages(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            contents = {
                'Kazumi_2.3.10+20310_android.apk': b'apk',
                'Kazumi_2.3.10+20310_ipa_no_sign.ipa': b'ipa',
                'Kazumi_2.3.10+20310_macos.dmg': b'dmg',
                'Kazumi_2.3.10+20310_windows_x64.zip': b'zip',
            }
            for name, payload in contents.items():
                (directory / name).write_bytes(payload)
            checksum_file = release_metadata.write_checksums(directory, '2.3.10+20310')
            expected = ''.join(f'{hashlib.sha256(contents[name]).hexdigest()}  {name}\n'
                               for name in sorted(contents))
            self.assertEqual(checksum_file.read_text(), expected)

    def test_incomplete_release_does_not_write_checksums(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / 'Kazumi_2.3.10+20310_android.apk').write_bytes(b'apk')
            with self.assertRaisesRegex(ValueError, 'Missing release artifacts'):
                release_metadata.write_checksums(directory, '2.3.10+20310')
            self.assertFalse((directory / 'SHA256SUMS').exists())

    def test_unexpected_packages_cannot_sneak_into_release(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for name in ('android.apk', 'ipa_no_sign.ipa', 'macos.dmg', 'windows_x64.zip', 'windows.msix'):
                (directory / f'Kazumi_2.3.10+20310_{name}').write_bytes(b'package')
            with self.assertRaisesRegex(ValueError, 'Unexpected release artifacts'):
                release_metadata.write_checksums(directory, '2.3.10+20310')


if __name__ == '__main__':
    unittest.main()

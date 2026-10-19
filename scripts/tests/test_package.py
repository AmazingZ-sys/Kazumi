import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'package.py'


@unittest.skipUnless(SCRIPT.exists(), 'implementation not present yet')
class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('packager', SCRIPT)
        cls.pkg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.pkg)

    def test_host_defaults_and_alias(self):
        self.assertEqual(self.pkg.select_platforms('all', 'Darwin'), ['android', 'ipa', 'macos'])
        self.assertEqual(self.pkg.select_platforms('all', 'Windows'), ['android', 'windows'])
        self.assertEqual(self.pkg.select_platforms('ios,android,ipa', 'Darwin'), ['ipa', 'android'])
        with self.assertRaises(ValueError):
            self.pkg.select_platforms('windows', 'Darwin')
        with self.assertRaises(ValueError):
            self.pkg.select_platforms('ipa', 'Windows')
        with self.assertRaises(ValueError):
            self.pkg.select_platforms('all,android', 'Darwin')

    def test_default_downloads(self):
        with patch.object(self.pkg.Path, 'home', return_value=Path('/Users/test')):
            self.assertEqual(self.pkg.default_output('Darwin'), Path('/Users/test/Downloads'))

    def test_release_build_embeds_the_selected_fork_update_repository(self):
        options = self.pkg.parser().parse_args(['--platform', 'android'])
        builder = self.pkg.Builder(Path('/project'), Path('/output'), options, '2.3.10', 'flutter', None)
        with patch.dict(self.pkg.os.environ, {'UPDATE_REPOSITORY': 'AmazingZ-sys/Kazumi'}, clear=True):
            command = builder.build_command('android')
        self.assertIn('--dart-define=UPDATE_REPOSITORY=AmazingZ-sys/Kazumi', command)

    def test_redirected_windows_desktop(self):
        with patch.object(self.pkg, 'windows_desktop', return_value=Path('/OneDrive/Desktop')):
            self.assertEqual(self.pkg.default_output('Windows'), Path('/OneDrive/Desktop'))

    def test_zip_contains_exe_dll_and_data(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bundle = root / 'Release'
            (bundle / 'data').mkdir(parents=True)
            (bundle / 'kazumi.exe').write_bytes(b'exe')
            (bundle / 'flutter_windows.dll').write_bytes(b'dll')
            (bundle / 'data/app.so').write_bytes(b'data')
            self.pkg.zip_directory(bundle, root / 'app.zip')
            with zipfile.ZipFile(root / 'app.zip') as archive:
                self.assertEqual(set(archive.namelist()), {'kazumi.exe', 'flutter_windows.dll', 'data/app.so'})

    def test_build_failure_never_exports_old_apk(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stale = root / 'build/app/outputs/flutter-apk/app-release.apk'
            stale.parent.mkdir(parents=True)
            stale.write_bytes(b'old')
            options = self.pkg.parser().parse_args(['--platform', 'android'])
            builder = self.pkg.Builder(root, root / 'export', options, '1.2.3+4', 'flutter', None)
            with patch.object(builder, 'run', side_effect=subprocess.CalledProcessError(1, ['flutter'])):
                with self.assertRaises(subprocess.CalledProcessError):
                    builder.build('android')
            self.assertFalse((root / 'export').exists())

    def test_android_exports_only_requested_current_variant(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'build/app/outputs/flutter-apk'
            source.mkdir(parents=True)
            (source / 'app-release.apk').write_bytes(b'universal')
            (source / 'app-arm64-v8a-release.apk').write_bytes(b'stale split')
            output = root / 'export'
            output.mkdir()
            options = self.pkg.parser().parse_args(['--platform', 'android'])
            builder = self.pkg.Builder(root, output, options, '1.2.3+4', 'flutter', None)
            with patch.object(builder, 'run'):
                paths = builder.build('android')
            self.assertEqual(len(paths), 1)
            self.assertEqual(paths[0].read_bytes(), b'universal')

    def test_android_clears_stale_release_plugin_registrant(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'build/app/outputs/flutter-apk/app-release.apk'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'apk')
            generated = root / 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
            generated.parent.mkdir(parents=True)
            generated.write_text('stale debug registrant', encoding='utf-8')
            output = root / 'export'
            output.mkdir()
            options = self.pkg.parser().parse_args(['--platform', 'android'])
            builder = self.pkg.Builder(root, output, options, '1.2.3+4', 'flutter', None)
            with patch.object(builder, 'run'):
                builder.build('android')
            self.assertFalse(generated.exists())

    def test_unsigned_ipa_payload_and_symlinks(self):
        if self.pkg.platform.system() != 'Darwin':
            self.skipTest('ditto integration requires macOS')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / 'build/ios/iphoneos/Runner.app'
            app.mkdir(parents=True)
            (app / 'Runner').write_bytes(b'runner')
            (app / 'link').symlink_to('Runner')
            out = root / 'export'
            out.mkdir()
            builder = self.pkg.Builder(root, out, self.pkg.parser().parse_args([]), '1.0.0', 'flutter', None)
            real_run = builder.run
            with patch.object(builder, 'run', side_effect=lambda args: None if args[0] == 'flutter' else real_run(args)):
                paths = builder.build('ipa')
            with zipfile.ZipFile(paths[0]) as archive:
                self.assertIn('Payload/Runner.app/Runner', archive.namelist())
                self.assertEqual(archive.read('Payload/Runner.app/link'), b'Runner')
                self.assertEqual(archive.getinfo('Payload/Runner.app/link').external_attr >> 28, 0xA)

    def test_missing_artifact_is_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            builder = self.pkg.Builder(root, root / 'out', self.pkg.parser().parse_args([]), '1', 'flutter', None)
            with patch.object(builder, 'run'):
                with self.assertRaises(FileNotFoundError):
                    builder.build('android')

    def test_dry_run_does_not_write_or_run_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / 'not created'
            with patch.object(self.pkg.subprocess, 'run', side_effect=AssertionError('spawned process')):
                self.assertEqual(self.pkg.main(['--platform', 'android', '--output', str(out), '--dry-run']), 0)
            self.assertFalse(out.exists())


class ScriptExistsTests(unittest.TestCase):
    def test_script_exists(self):
        self.assertTrue(SCRIPT.is_file(), 'packaging script has not been implemented')


if __name__ == '__main__':
    unittest.main()

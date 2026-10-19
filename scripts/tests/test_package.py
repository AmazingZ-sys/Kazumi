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

    def windows_builder(self, root, format_name):
        source = root / 'build/windows/x64/runner/Release'
        (source / 'data').mkdir(parents=True)
        (source / 'kazumi.exe').write_bytes(b'unsigned app')
        (source / 'flutter_windows.dll').write_bytes(b'third party dll')
        (source / 'data/app.so').write_bytes(b'app data')
        output = root / 'export'
        output.mkdir()
        options = self.pkg.parser().parse_args(['--platform', 'windows'])
        options.windows_format = format_name
        return self.pkg.Builder(root, output, options, '1.2.3+4', 'flutter', 'ISCC.exe')

    def windows_signing_environment(self, root):
        pfx = root / 'private.pfx'
        pfx.write_bytes(b'test fixture')
        return {'KAZUMI_WINDOWS_PFX': str(pfx),
                'KAZUMI_WINDOWS_PFX_PASSWORD': 'private test password',
                'KAZUMI_WINDOWS_CERT_SHA256': 'AB' * 32}

    def windows_command(self, command):
        if command[0] == 'ISCC.exe':
            stage = Path(next(arg[2:] for arg in command if str(arg).startswith('/O')))
            package_name = next(arg.split('=', 1)[1] for arg in command if str(arg).startswith('/DPackageName='))
            (stage / f'{package_name}.exe').write_bytes(b'unsigned installer')

    def test_windows_cli_accepts_both_formats(self):
        try:
            options = self.pkg.parser().parse_args(['--windows-format', 'both'])
        except SystemExit:
            self.fail('--windows-format both should be accepted')
        self.assertEqual(options.windows_format, 'both')

    def test_windows_both_formats_build_flutter_once(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(self.pkg.os.environ, {}, clear=True):
            builder = self.windows_builder(Path(temp), 'both')
            with patch.object(builder, 'run', side_effect=self.windows_command) as run:
                artifacts = builder.build('windows')
            self.assertEqual([p.name for p in artifacts],
                             ['Kazumi_1.2.3+4_windows_x64.zip', 'Kazumi_1.2.3+4_windows_x64_setup.exe'])
            self.assertEqual(sum(call.args[0][0] == 'flutter' for call in run.call_args_list), 1)

    def test_windows_signs_app_before_both_packages_and_then_installer(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            builder = self.windows_builder(root, 'both')
            events = []
            real_zip = self.pkg.zip_directory

            def run(command):
                if command[0] == 'flutter':
                    events.append('build')
                elif command[0] == 'ISCC.exe':
                    events.append('installer')
                    source = Path(next(arg.split('=', 1)[1] for arg in command if str(arg).startswith('/DSourceDir=')))
                    self.assertEqual((source / 'kazumi.exe').read_bytes(), b'signed app')
                    self.windows_command(command)
                else:
                    self.assertIn('-Mode', command)
                    self.assertEqual(command[command.index('-Mode') + 1], 'sign')
                    path = Path(command[command.index('-FilePath') + 1])
                    events.append(f'sign:{path.name}')
                    path.write_bytes(b'signed app' if path.name == 'kazumi.exe' else b'signed installer')
                    self.assertNotIn('private test password', [str(arg) for arg in command])

            def archive(source, destination):
                events.append('zip')
                real_zip(source, destination)

            with patch.dict(self.pkg.os.environ, self.windows_signing_environment(root), clear=True), \
                    patch.object(builder, 'run', side_effect=run), \
                    patch.object(self.pkg, 'zip_directory', side_effect=archive):
                artifacts = builder.build('windows')
            self.assertEqual(events, ['build', 'sign:kazumi.exe', 'zip', 'installer',
                                      'sign:Kazumi_1.2.3+4_windows_x64_setup.exe'])
            with zipfile.ZipFile(artifacts[0]) as archive:
                self.assertEqual(archive.read('kazumi.exe'), b'signed app')
                self.assertEqual(archive.read('flutter_windows.dll'), b'third party dll')
            self.assertEqual(artifacts[1].read_bytes(), b'signed installer')

    def test_windows_signing_failure_exports_neither_format(self):
        for fail_on in ('kazumi.exe', 'Kazumi_1.2.3+4_windows_x64_setup.exe'):
            with self.subTest(fail_on=fail_on), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                builder = self.windows_builder(root, 'both')

                def run(command):
                    if '-FilePath' in command and Path(command[command.index('-FilePath') + 1]).name == fail_on:
                        raise subprocess.CalledProcessError(1, ['pwsh'])
                    self.windows_command(command)

                with patch.dict(self.pkg.os.environ, self.windows_signing_environment(root), clear=True), \
                        patch.object(builder, 'run', side_effect=run):
                    with self.assertRaises(subprocess.CalledProcessError):
                        builder.build('windows')
                self.assertEqual(list(builder.output.iterdir()), [])

    def test_windows_partial_signing_configuration_fails_before_build(self):
        for present in ('KAZUMI_WINDOWS_PFX', 'KAZUMI_WINDOWS_PFX_PASSWORD', 'KAZUMI_WINDOWS_CERT_SHA256'):
            with self.subTest(present=present), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                builder = self.windows_builder(root, 'zip')
                env = self.windows_signing_environment(root)
                with patch.dict(self.pkg.os.environ, {present: env[present]}, clear=True), \
                        patch.object(builder, 'run') as run:
                    with self.assertRaisesRegex(ValueError, 'KAZUMI_WINDOWS'):
                        builder.build('windows')
                run.assert_not_called()
                self.assertEqual(list(builder.output.iterdir()), [])

    def test_windows_invalid_signing_configuration_fails_before_build(self):
        for invalid in ('empty_password', 'invalid_fingerprint', 'missing_pfx'):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                builder = self.windows_builder(root, 'zip')
                env = self.windows_signing_environment(root)
                if invalid == 'empty_password':
                    env['KAZUMI_WINDOWS_PFX_PASSWORD'] = ''
                elif invalid == 'invalid_fingerprint':
                    env['KAZUMI_WINDOWS_CERT_SHA256'] = 'not-a-sha256-fingerprint'
                else:
                    Path(env['KAZUMI_WINDOWS_PFX']).unlink()
                with patch.dict(self.pkg.os.environ, env, clear=True), patch.object(builder, 'run') as run:
                    with self.assertRaises((ValueError, FileNotFoundError)):
                        builder.build('windows')
                run.assert_not_called()

    def test_windows_unsigned_single_formats_remain_supported(self):
        for format_name in ('exe', 'zip'):
            with self.subTest(format_name=format_name), tempfile.TemporaryDirectory() as temp, \
                    patch.dict(self.pkg.os.environ, {}, clear=True):
                builder = self.windows_builder(Path(temp), format_name)
                with patch.object(builder, 'run', side_effect=self.windows_command) as run:
                    artifacts = builder.build('windows')
                self.assertEqual(len(artifacts), 1)
                self.assertEqual(artifacts[0].suffix, '.' + format_name)
                self.assertTrue(all('-FilePath' not in call.args[0] for call in run.call_args_list))

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

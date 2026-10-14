#!/usr/bin/env python3
"""Build and export Kazumi packages using Python 3.9+ and the local Flutter SDK."""
import argparse
import ctypes
from datetime import datetime
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HOST_TARGETS = {
    'Darwin': ['android', 'ipa', 'macos'],
    'Windows': ['android', 'windows'],
    'Linux': ['android'],
}
DEFINE_KEYS = ('DANDANAPI_APPID', 'DANDANAPI_KEY', 'KAZUMI_APPID', 'KAZUMI_KEY')


def parser():
    result = argparse.ArgumentParser(description='Kazumi 多平台 Release 打包与导出')
    result.add_argument('--platform', '-p', default='all', help='android,ipa,macos,windows（逗号分隔）；all=当前系统支持的平台，ios 为 ipa 别名')
    result.add_argument('--output', '-o', type=Path, help='导出目录；macOS 默认 Downloads，Windows 默认系统桌面')
    result.add_argument('--split-per-abi', action='store_true', help='Android 按 ABI 输出三个 APK（默认通用 APK）')
    result.add_argument('--export-options-plist', type=Path, help='使用 Xcode 导出配置生成签名 IPA；默认生成需侧载签名的 no_sign.ipa')
    result.add_argument('--windows-format', choices=['exe', 'zip'], default='exe', help='Windows 安装程序 exe（需 Inno Setup 6）或便携 zip')
    result.add_argument('--iscc', type=Path, help='Inno Setup 6 的 ISCC.exe 路径')
    result.add_argument('--flutter', default=os.environ.get('FLUTTER_BIN', 'flutter'), help='Flutter 可执行文件路径')
    result.add_argument('--dart-define-from-file', type=Path, help='传给 Flutter 的 JSON/.env 配置文件')
    result.add_argument('--skip-pub-get', action='store_true', help='复用已下载的依赖')
    result.add_argument('--dry-run', action='store_true', help='仅显示计划，不构建、不创建文件，也不检查工具是否安装')
    return result


def select_platforms(value, host):
    if host not in HOST_TARGETS:
        raise ValueError(f'不支持的宿主系统：{host}')
    names = list(dict.fromkeys('ipa' if item.strip().lower() == 'ios' else item.strip().lower()
                               for item in value.split(',')))
    if names == ['all']:
        return HOST_TARGETS[host][:]
    unsupported = [name for name in names if name not in HOST_TARGETS[host]]
    if unsupported:
        raise ValueError(f'{host} 无法构建：{", ".join(unsupported)}。本机支持：{", ".join(HOST_TARGETS[host])}；IPA/macOS 需要 Mac，Windows 需要 Windows。')
    return names


def windows_desktop():
    # CSIDL_DESKTOPDIRECTORY resolves the real desktop, including OneDrive redirection.
    buffer = ctypes.create_unicode_buffer(32768)
    if ctypes.windll.shell32.SHGetFolderPathW(None, 0x10, None, 0, buffer) != 0:
        raise OSError('无法获取 Windows 桌面路径，请使用 --output 指定目录')
    return Path(buffer.value)


def default_output(host):
    return windows_desktop() if host == 'Windows' else Path.home() / 'Downloads'


def require_tool(name):
    found = shutil.which(str(name))
    if not found:
        raise FileNotFoundError(f'找不到工具：{name}；请先安装并加入 PATH，参见 docs/packaging.md')
    return found


def find_iscc(explicit):
    if explicit:
        return require_tool(explicit)
    found = shutil.which('ISCC.exe')
    if found:
        return found
    for key in ('ProgramFiles(x86)', 'ProgramFiles', 'LOCALAPPDATA'):
        base = os.environ.get(key)
        if base:
            for folder in ('Inno Setup 6', 'Programs/Inno Setup 6'):
                candidate = Path(base) / folder / 'ISCC.exe'
                if candidate.is_file():
                    return str(candidate)
    raise FileNotFoundError('找不到 Inno Setup 6；请安装或指定 --iscc，也可使用 --windows-format zip')


def read_version(root):
    match = re.search(r'^version:\s*[\'"]?([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?)',
                      (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if not match:
        raise ValueError('pubspec.yaml 缺少有效 version')
    return match.group(1)


def zip_directory(source, destination):
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(source))


def file_signature(path):
    """Return metadata that changes when Xcode replaces an IPA in place."""
    stat = path.stat()
    return stat.st_ino, stat.st_size, stat.st_mtime_ns


class Builder:
    def __init__(self, root, output, options, version, flutter, iscc):
        self.root, self.output, self.options = root, output, options
        self.version, self.flutter, self.iscc = version, flutter, iscc

    def run(self, args):
        args = [str(arg) for arg in args]
        # Flutter on Windows is commonly exposed as flutter.bat. Launch batch
        # files through cmd.exe so paths with spaces work with subprocess too.
        command = args
        if os.name == 'nt' and args and args[0].lower().endswith(('.bat', '.cmd')):
            command = ['cmd.exe', '/d', '/c', *args]
        # Environment defines may contain keys; do not echo their values.
        visible = [arg.split('=', 2)[0] + '=' + arg.split('=', 2)[1] + '=***'
                   if arg.startswith('--dart-define=') else arg for arg in args]
        print('> ' + subprocess.list2cmdline(visible), flush=True)
        subprocess.run(command, cwd=self.root, check=True)

    def build_command(self, target):
        command = [self.flutter, 'build', {'android': 'apk', 'ipa': 'ios'}.get(target, target), '--release', '--no-pub']
        if target == 'android' and self.options.split_per_abi:
            command.append('--split-per-abi')
        if target == 'ipa':
            if self.options.export_options_plist:
                command[2] = 'ipa'
                command.append(f'--export-options-plist={self.options.export_options_plist}')
            else:
                command.append('--no-codesign')
        if target == 'windows':
            command.append('--target-platform=windows-x64')
        if self.options.dart_define_from_file:
            command.append(f'--dart-define-from-file={self.options.dart_define_from_file}')
        command.extend(f'--dart-define={key}={os.environ[key]}' for key in DEFINE_KEYS if key in os.environ)
        return command

    def require(self, path):
        if not path.exists():
            raise FileNotFoundError(f'构建未生成预期产物：{path}')
        return path

    def prepare_release_build(self, target):
        if target != 'android':
            return
        # `flutter pub get` can leave a debug registrant that includes
        # dev-only plugins (for example flutter_native_splash). Release builds
        # must regenerate it after removing the stale file so those classes are
        # not referenced without an Android implementation on the classpath.
        registrant = self.root / 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
        if registrant.exists():
            registrant.unlink()

    def build(self, target):
        stem = f'Kazumi_{self.version}_{target}'
        ipa_dir = self.root / 'build/ios/ipa'
        before = {p: file_signature(p) for p in ipa_dir.glob('*.ipa')} if target == 'ipa' else {}
        self.prepare_release_build(target)
        self.run(self.build_command(target))
        # Package only after a successful build; staging is removed on every exit path.
        with tempfile.TemporaryDirectory(prefix='kazumi-package-') as temp:
            stage = Path(temp)
            if target == 'android':
                variants = ['armeabi-v7a', 'arm64-v8a', 'x86_64'] if self.options.split_per_abi else [None]
                for abi in variants:
                    suffix = f'-{abi}' if abi else ''
                    source = self.require(self.root / f'build/app/outputs/flutter-apk/app{suffix}-release.apk')
                    shutil.copy2(source, stage / f'{stem}{suffix}.apk')
            elif target == 'ipa':
                if self.options.export_options_plist:
                    candidates = [p for p in ipa_dir.glob('*.ipa') if before.get(p) != file_signature(p)]
                    if len(candidates) != 1:
                        raise RuntimeError('签名导出未生成唯一的新 IPA，请检查上方 Xcode 导出日志及签名配置')
                    shutil.copy2(candidates[0], stage / f'{stem}.ipa')
                else:
                    source = self.require(self.root / 'build/ios/iphoneos/Runner.app')
                    payload = stage / 'Payload'
                    shutil.copytree(source, payload / 'Runner.app', symlinks=True)
                    # Match this repository's CI: ad-hoc sign embedded frameworks for sideloading.
                    for framework in sorted((payload / 'Runner.app/Frameworks').glob('*.framework')):
                        self.run(['codesign', '--force', '--sign', '-', '--preserve-metadata=identifier,entitlements', framework])
                    self.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', payload, stage / f'{stem}_no_sign.ipa'])
            elif target == 'macos':
                source = self.require(self.root / 'build/macos/Build/Products/Release/Kazumi.app')
                image = stage / 'image'
                image.mkdir()
                self.run(['ditto', source, image / source.name])
                (image / 'Applications').symlink_to('/Applications')
                self.run(['hdiutil', 'create', '-volname', 'Kazumi', '-srcfolder', image,
                          '-format', 'UDZO', stage / f'{stem}.dmg'])
            elif target == 'windows':
                source = self.require(self.root / 'build/windows/x64/runner/Release')
                self.require(source / 'kazumi.exe')
                self.require(source / 'flutter_windows.dll')
                self.require(source / 'data')
                if self.options.windows_format == 'zip':
                    zip_directory(source, stage / f'{stem}_x64.zip')
                else:
                    self.run([self.iscc, f'/DSourceDir={source}', f'/DAppVersion={self.version}',
                              f'/DPackageName={stem}_x64_setup', f'/O{stage}', self.root / 'scripts/windows-installer.iss'])
                    self.require(stage / f'{stem}_x64_setup.exe')
            artifacts = sorted(p for p in stage.iterdir() if p.is_file())
            if not artifacts:
                raise RuntimeError(f'{target} 打包没有产生文件')
            exported = []
            for artifact in artifacts:
                destination = self.output / artifact.name
                shutil.copy2(artifact, destination)
                exported.append(destination)
            return exported


def main(argv=None):
    options = parser().parse_args(argv)
    try:
        host = platform.system()
        targets = select_platforms(options.platform, host)
        output = (options.output or default_output(host)).expanduser().resolve()
        version = read_version(ROOT)
        for field in ('export_options_plist', 'dart_define_from_file'):
            value = getattr(options, field)
            if value:
                value = value.expanduser().resolve()
                if not value.is_file():
                    raise FileNotFoundError(f'文件不存在：{value}')
                setattr(options, field, value)
        if options.export_options_plist and 'ipa' not in targets:
            raise ValueError('--export-options-plist 需要选择 ipa 平台')
        print(f'平台：{", ".join(targets)}\n版本：{version}\n导出目录：{output}（每次创建独立子目录）', flush=True)
        if options.dry_run:
            builder = Builder(ROOT, output, options, version, options.flutter, options.iscc)
            formats = {'android': 'APK', 'ipa': '签名 IPA' if options.export_options_plist else '未签名 IPA（需侧载签名）',
                       'macos': 'DMG', 'windows': options.windows_format.upper()}
            if not options.skip_pub_get:
                print(f'准备依赖：{options.flutter} pub get')
            for target in targets:
                command = builder.build_command(target)
                print(subprocess.list2cmdline([arg for arg in command if not arg.startswith('--dart-define=')]))
                print(f'  打包为 {formats[target]}')
            return 0
        flutter = require_tool(options.flutter)
        iscc = find_iscc(options.iscc) if 'windows' in targets and options.windows_format == 'exe' else None
        if 'ipa' in targets or 'macos' in targets:
            require_tool('xcodebuild')
            require_tool('ditto')
        if 'ipa' in targets and not options.export_options_plist:
            require_tool('codesign')
        if 'macos' in targets:
            require_tool('hdiutil')
        output.mkdir(parents=True, exist_ok=True)
        if 'android' in targets:
            gradle = (ROOT / 'android/app/build.gradle').read_text(encoding='utf-8')
            if 'signingConfig signingConfigs.debug' in gradle:
                print('警告：android/app/build.gradle 的 Release 当前使用 debug keystore；APK 仅适合测试，不能用于正式分发或覆盖更新。', file=sys.stderr)
        run_output = Path(tempfile.mkdtemp(prefix=f'Kazumi_{version}_{datetime.now():%Y%m%d_%H%M%S}_', dir=output))
        builder = Builder(ROOT, run_output, options, version, flutter, iscc)
        if not options.skip_pub_get:
            builder.run([flutter, 'pub', 'get'])
        failures = []
        for target in targets:
            print(f'\n开始构建 {target}', flush=True)
            try:
                for artifact in builder.build(target):
                    print(f'已导出：{artifact}', flush=True)
            except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
                # CalledProcessError contains arguments, potentially including private defines.
                detail = f'命令退出码 {error.returncode}' if isinstance(error, subprocess.CalledProcessError) else str(error)
                print(f'{target} 失败：{detail}', file=sys.stderr, flush=True)
                failures.append(target)
        print(f'\n导出位置：{run_output}')
        if failures:
            print(f'失败平台：{", ".join(failures)}；其余成功产物已保留。', file=sys.stderr)
            return 1
        print('全部所选平台打包完成。')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        detail = f'命令退出码 {error.returncode}' if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f'错误：{detail}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\n已取消打包，已导出的文件保留。', file=sys.stderr)
        sys.exit(130)

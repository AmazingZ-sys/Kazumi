#!/usr/bin/env python3
"""Validate and collect the four packages published by the fork workflow."""
import argparse
import hashlib
from pathlib import Path
import re
import sys

from package import read_version

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_SUFFIXES = {
    'android': 'android.apk',
    'ipa': 'ipa_no_sign.ipa',
    'macos': 'macos.dmg',
    'windows': 'windows_x64.zip',
}


def validate_version(root, tag=None):
    version = read_version(root)
    if tag and (not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', tag)
                or version.partition('+')[0] != tag):
        raise ValueError(f'Release tag {tag!r} must match the stable pubspec version {version!r}')
    return version


def artifact_name(version, platform):
    return f'Kazumi_{version}_{ARTIFACT_SUFFIXES[platform]}'


def select_artifact(directory, version, platform):
    name = artifact_name(version, platform)
    candidates = sorted(path for path in directory.rglob(name) if path.is_file())
    if len(candidates) != 1:
        raise ValueError(f'Expected one artifact named {name}; found {len(candidates)}')
    return candidates[0]


def write_checksums(directory, version):
    expected = {artifact_name(version, platform) for platform in ARTIFACT_SUFFIXES}
    actual = {path.name for path in directory.iterdir() if path.is_file() and path.name != 'SHA256SUMS'}
    if expected - actual:
        raise ValueError(f'Missing release artifacts: {", ".join(sorted(expected - actual))}')
    if actual - expected:
        raise ValueError(f'Unexpected release artifacts: {", ".join(sorted(actual - expected))}')
    lines = []
    for name in sorted(expected):
        digest = hashlib.sha256()
        with (directory / name).open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(block)
        lines.append(f'{digest.hexdigest()}  {name}\n')
    destination = directory / 'SHA256SUMS'
    destination.write_text(''.join(lines), encoding='utf-8')
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    version = commands.add_parser('version', help='Read pubspec version and validate a release tag')
    version.add_argument('--tag')
    artifact = commands.add_parser('artifact', help='Select one exact package from the packager output')
    artifact.add_argument('--directory', type=Path, required=True)
    artifact.add_argument('--platform', choices=ARTIFACT_SUFFIXES, required=True)
    checksums = commands.add_parser('checksums', help='Require all four packages and write SHA256SUMS')
    checksums.add_argument('--directory', type=Path, required=True)
    checksums.add_argument('--tag', required=True)
    options = parser.parse_args(argv)
    try:
        version = validate_version(ROOT, getattr(options, 'tag', None))
        if options.command == 'version':
            print(version)
        elif options.command == 'artifact':
            print(select_artifact(options.directory, version, options.platform).resolve())
        else:
            print(write_checksums(options.directory, version))
        return 0
    except (OSError, ValueError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

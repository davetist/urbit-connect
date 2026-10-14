"""Capture an explicitly selected prior Simulator app and its matching SDK runtime.

This is an upgrade-test prerequisite, not product installation. Refuses replacing
an existing baseline and excludes private test bundles, logs and credentials.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
from targets import ROOT, TARGETS


def tree(path):
    entries = {p.relative_to(path).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*') if p.is_file()}
    return hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()


def capture(app, frameworks):
    TARGETS.require_owned(); app = app.resolve(); frameworks = frameworks.resolve()
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'org.example.urbitconnect.todo': raise ValueError('Wrong prior app bundle')
    sdk = list(frameworks.glob('UrbitConnect_*_PackageProduct.framework'))
    if len(sdk) != 1: raise ValueError('Select the matching prior PackageFrameworks directory')
    destination = TARGETS.work / 'baseline-Todo.app'; runtime = TARGETS.work / 'baseline-runtime/PackageFrameworks'
    marker = TARGETS.work / 'baseline-Todo.json'
    if destination.exists() or runtime.exists() or marker.exists(): raise ValueError('Baseline already captured; it was not replaced')
    shutil.copytree(app, destination, symlinks=True); runtime.mkdir(parents=True, mode=0o700)
    shutil.copytree(sdk[0], runtime / sdk[0].name, symlinks=True)
    marker.write_text(json.dumps({'project': str(ROOT), 'fixtureId': TARGETS.fixture_id, 'sqliteSchemaVersion': 1, 'bundleVersion': info['CFBundleVersion'], 'bundleSHA256': tree(destination), 'runtimeFrameworkPath': str(runtime), 'runtimeFrameworksSHA256': tree(runtime)}, indent=2) + '\n'); marker.chmod(0o600)
    print('Captured prior app and matching runtime in the owned alpha fixture; upgrade test must verify actual schema 1.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--app', required=True, type=Path); parser.add_argument('--frameworks', required=True, type=Path)
    args = parser.parse_args(); capture(args.app, args.frameworks)

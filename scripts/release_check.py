"""Build and bind reproducible local alpha artifacts; never publish or imply qualification."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import stat
import subprocess
import tarfile
from source_safety import read_regular, source_manifest as checked_source_manifest

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / 'release/version.json').read_text())['version']
SOURCE_GROUPS = ['desk', 'web', 'sdk/swift', 'Package.swift', 'examples/ios-todo', 'protocol', 'tests', 'scripts', 'docs', 'toolchain.json', 'release/version.json', 'release/ownership.json', 'release/manifest.schema.json', 'release/README.md', 'release/source-files.json', 'README.md', 'LICENSE', '.gitignore', 'third_party', 'integrations/grant-probe']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_manifest(root=None):
    return checked_source_manifest(ROOT if root is None else root)


def regular_source(path):
    relative = path.relative_to(ROOT)
    current = ROOT
    if stat.S_ISLNK(current.lstat().st_mode):
        raise ValueError('symlink in release sources: ' + str(path))
    for part in relative.parts:
        current = current / part
        mode = current.lstat().st_mode
        if stat.S_ISLNK(mode):
            raise ValueError('symlink in release sources: ' + str(path))
        if current != path and not stat.S_ISDIR(mode):
            raise ValueError('non-directory in release source path: ' + str(path))
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('non-file in release sources: ' + str(path))
    return path


def source_files(group):
    if group == 'web/dist':
        path = ROOT / group
        candidates = sorted(path.rglob('*'))
        return [regular_source(p) for p in candidates if not p.is_dir() or p.is_symlink()]
    prefix = group.rstrip('/') + '/'
    return [regular_source(ROOT / name) for name in source_manifest() if name == group or name.startswith(prefix)]


def tree(group):
    entries = {p.relative_to(ROOT).as_posix(): hashlib.sha256(read_regular(ROOT, p.relative_to(ROOT))).hexdigest() for p in source_files(group)}
    if not entries:
        raise ValueError('empty release input: ' + group)
    return {'sha256': hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(',', ':')).encode()).hexdigest(), 'files': entries}


def archive(path, groups):
    entries = {p.relative_to(ROOT).as_posix(): p for group in groups for p in source_files(group)}
    entries['LICENSE'] = source_files('LICENSE')[0]
    with path.open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as zipped, tarfile.open(fileobj=zipped, mode='w') as bundle:
        for name, source in sorted(entries.items()):
            data = read_regular(ROOT, source.relative_to(ROOT))
            info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o644; info.mtime = 0
            bundle.addfile(info, io.BytesIO(data))
    path.with_suffix(path.suffix + '.sha256').write_text(digest(path) + '  ' + path.name + '\n')
    return digest(path)


def publication_blockers():
    ownership = json.loads((ROOT / 'release/ownership.json').read_text())
    missing = [name for name in ['sourceOwner', 'maintenanceContact', 'securityContact', 'landscapeNoticeResolved'] if not ownership.get(name)]
    if not ownership.get('publicationAuthorized'):
        missing.append('publication authorization')
    return missing


def build_twice():
    output = ROOT / 'dist'; output.mkdir(exist_ok=True)
    snapshots = []
    for _ in range(2):
        for command in [['npm', '--prefix', 'web', 'run', 'build'], ['python3', 'scripts/bundle_web.py'], ['python3', 'scripts/package_desk.py', '--package-only']]:
            subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        sdk = output / ('connect-sdk-' + VERSION + '.tgz')
        todo = output / ('connect-todo-source-' + VERSION + '.tgz')
        source = output / ('connect-source-' + VERSION + '.tgz')
        archive(sdk, ['Package.swift', 'sdk/swift', 'docs/sdk-integration.md', 'protocol/v1', 'release/version.json'])
        archive(todo, ['examples/ios-todo', 'sdk/swift', 'Package.swift', 'docs/development.md', 'docs/quickstart-owner.md', 'release/version.json'])
        archive(source, SOURCE_GROUPS)
        desk = output / ('connect-' + VERSION + '.tgz')
        snapshots.append({name: {'path': str(path.relative_to(ROOT)), 'sha256': digest(path), 'kind': 'file'} for name, path in [('desk', desk), ('sdk', sdk), ('todo', todo), ('source', source)]} | {'web': {'path': 'web/dist', 'sha256': tree('web/dist')['sha256'], 'kind': 'tree'}})
    if snapshots[0] != snapshots[1]:
        raise ValueError('unsigned artifacts differ between independent builds')
    return snapshots[-1]


def manifest(artifacts=None):
    evidence = {}
    for p in sorted((ROOT / 'artifacts/alpha').glob('*.json')):
        # Hash reviewed aggregate files only; logs, auth fixtures and raw recordings stay private.
        if p.name not in {'qualification.json'}: evidence[p.relative_to(ROOT).as_posix()] = digest(p)
    return {'manifestVersion': 2, 'version': VERSION, 'protocolVersion': 1, 'sourceCommit': None, 'source': {group: tree(group) for group in SOURCE_GROUPS}, 'toolchain': json.loads((ROOT / 'toolchain.json').read_text()), 'artifacts': artifacts or {}, 'evidence': evidence, 'publicationBlockers': publication_blockers(), 'readinessPolicy': 'informational'}


def verify_manifest(value):
    if value.get('manifestVersion') not in {1, 2} or value.get('version') != VERSION:
        raise ValueError('unsupported release manifest')
    for record in value.get('artifacts', {}).values():
        path = ROOT / record['path']
        if record.get('kind') == 'tree':
            if record['path'] != 'web/dist' or tree('web/dist')['sha256'] != record['sha256']:
                raise ValueError('release artifact changed')
        elif not path.resolve().is_relative_to((ROOT / 'dist').resolve()) or not path.is_file() or digest(path) != record['sha256']:
            raise ValueError('release artifact changed')
    if set(value['source']) != set(SOURCE_GROUPS):
        raise ValueError('release manifest is missing source inputs')
    for group, expected in value['source'].items():
        if tree(group) != expected:
            raise ValueError('release source changed: ' + group)
    for name, expected in value.get('evidence', {}).items():
        path = ROOT / name
        if not path.resolve().is_relative_to((ROOT / 'artifacts/alpha').resolve()) or not path.is_file() or digest(path) != expected:
            raise ValueError('release evidence changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        verify_manifest(json.loads(args.verify.read_text())); print('PASS: release source/evidence hashes match'); return
    artifacts = build_twice() if args.build else None
    target = ROOT / 'release/manifest.json'; target.write_text(json.dumps(manifest(artifacts), indent=2) + '\n')
    print('Local manifest:', target)
    print('Publication pending:', ', '.join(publication_blockers()))
    if artifacts:
        print('PASS: two unsigned desk/web/SDK/Todo builds have identical hashes')


if __name__ == '__main__':
    main()

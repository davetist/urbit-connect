"""Install a verified archive only in the already authorized connect-dev experiment.

Run on reference-host via the pinned SSH helper with stdin, after creating target.json,
a verified Harbor backup, private Eyre binding and the empty mounted desk.
This script contains no owner credentials and refuses an unowned experiment.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile
import time
import urllib.request

ROOT = Path.home() / '.local/share/urbit-connect-alpha'
HARBOR = 'http://127.0.0.1:18789'


def private_write(path, value):
    descriptor, temporary = tempfile.mkstemp(prefix='.private-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(value)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def inspect_bundle(archive, kernel):
    if kernel != 408: raise ValueError('Unsupported runtime Kelvin; no desk files changed')
    entries = {}; total = 0
    with tarfile.open(archive) as bundle:
        for member in bundle:
            path = Path(member.name)
            total += member.size
            if (not member.isfile() or path.is_absolute() or '..' in path.parts
                    or str(path) != member.name or '\\' in member.name
                    or member.size > 4 * 1024 * 1024 or total > 16 * 1024 * 1024
                    or len(entries) >= 512 or member.name in entries):
                raise ValueError('Unsafe or oversized desk archive')
            entries[member.name] = bundle.extractfile(member).read()
    allowed = {'MANIFEST.sha256', 'LICENSE', 'THIRD_PARTY/urbit-LICENSE.txt', 'THIRD_PARTY/landscape-NOTICE.md'}
    if any(not name.startswith('connect/') and name not in allowed for name in entries):
        raise ValueError('Unexpected archive payload')
    names = set()
    try:
        for line in entries['MANIFEST.sha256'].decode().splitlines():
            digest, name = line.split('  ', 1)
            if not re.fullmatch('[a-f0-9]{64}', digest) or not name or name in names or hashlib.sha256(entries['connect/' + name]).hexdigest() != digest:
                raise ValueError('Desk manifest mismatch')
            names.add(name)
        if names != {name[8:] for name in entries if name.startswith('connect/')}:
            raise ValueError('Unmanifested desk file')
        if not re.fullmatch(rb'\s*\[%zuse\s+408\]\s*', entries['connect/sys.kelvin']):
            raise ValueError('Unsupported desk Kelvin')
    except (KeyError, UnicodeDecodeError) as error:
        raise ValueError('Incomplete desk manifest or Kelvin') from error
    return entries, names


def require_space(mounted, staging_bytes):
    # Keep room for the running pier and a second staging copy. This is a
    # conservative refusal threshold, not a measured minimum host size.
    if shutil.disk_usage(mounted).free < 1024 ** 3 + staging_bytes * 2:
        raise ValueError('Insufficient free space; no desk files changed')


def runtime_kernel(vats):
    match = re.search(r'(?:^|\n)(?:[^\n]*:dojo>\s*)?%base\s*\n\s*/sys/kelvin:\s*\[%zuse (\d+)\]', vats)
    if not match: raise ValueError('Live base Kelvin could not be established; no desk files changed')
    return int(match[1])


def request(path, data=None):
    headers = {'Content-Type': 'application/json'} if data is not None else {}
    raw = json.dumps(data).encode() if data is not None else None
    with urllib.request.urlopen(urllib.request.Request(HARBOR + path, data=raw, headers=headers), timeout=15) as response:
        body = response.read()
        return json.loads(body) if body else None


def command(target, text, name):
    job = json.loads((ROOT / 'start-job.json').read_text())['jobId']
    path = '/api/v1/jobs/' + job + '/logs'
    start = len(request(path)['output'])
    request('/api/v1/ships/' + target['harborShipId'] + '/terminal/input', {'input': '\x01\x0b' + text + '\r'})
    deadline = time.monotonic() + 180
    last = ''; changed = time.monotonic()
    while time.monotonic() < deadline:
        time.sleep(.3)
        value = request(path)['output'][start:]
        if value != last: last = value; changed = time.monotonic()
        clean = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b[su]', '', value).replace('\r', '')
        if re.search(r'~[a-z_-]+:dojo>\s*$', clean) and time.monotonic() - changed > 2:
            output = ROOT / ('dojo-' + name + '.txt'); private_write(output, clean)
            if any(marker in clean for marker in ['event failed', 'nest-fail', 'syntax error', 'find-fork', '-find.', 'ford: build failed']):
                raise RuntimeError('Desk command failed; private diagnostic retained')
            return clean
    raise TimeoutError('Test ship command did not settle; inspect private Harbor log')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['baseline', 'update'])
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--origin', required=True)
    args = parser.parse_args()
    assert re.fullmatch('[a-f0-9]{64}', args.sha256)
    assert ROOT.is_dir() and not ROOT.is_symlink()
    target = json.loads((ROOT / 'target.json').read_text())
    assert target['project'] == '/absolute/project'
    assert target['pier'] == '/mnt/harbor/piers/connect-dev'
    ship = request('/api/v1/ships/' + target['harborShipId'])
    assert ship['pierPath'] == target['pier'] and ship['identity'] == target['ship'] and ship['state'] == 'running'
    assert ship['httpBindAddress'] == '127.0.0.1' and ship['webPort'] == 8080 and not ship['recoveryBlocked']
    assert urllib.request.urlopen('http://127.0.0.1:8080/~/host', timeout=10).read().decode().strip() == target['ship']
    backup = json.loads((ROOT / 'backup-job.json').read_text())['jobId']
    job = request('/api/v1/jobs/' + backup)
    assert job['phase'] == 'completed' and not job['error'] and job['finishedAt'], 'Completed backup is required'
    backups = request('/api/v1/ships/' + target['harborShipId'] + '/backups')
    assert any(item.get('verified') is True for item in backups), 'A verified backup archive is required'
    archive = ROOT / ('connect-baseline.tgz' if args.stage == 'baseline' else 'connect-update.tgz')
    assert archive.is_file() and not archive.is_symlink() and hashlib.sha256(archive.read_bytes()).hexdigest() == args.sha256
    mounted = Path(target['pier']) / 'connect'
    assert mounted.is_dir() and not mounted.is_symlink(), 'Only the newly created, owned desk may be staged'
    tracking = ROOT / 'staged-files.json'
    if args.stage == 'baseline': assert not tracking.exists(), 'Baseline installation already attempted; inspect state before retrying'
    else: assert tracking.is_file(), 'Compatible update requires the recorded installed baseline'
    vats = command(target, '+vats', 'compatibility-preflight')
    entries, names = inspect_bundle(archive, runtime_kernel(vats))
    require_space(mounted, sum(len(entries['connect/' + name]) for name in names))
    for name in sorted(names):
        destination = mounted / name
        assert not destination.is_symlink() and not any(p.is_symlink() for p in destination.parents)
        destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes(entries['connect/' + name])
    if tracking.exists():
        for name in set(json.loads(tracking.read_text())) - names:
            path = mounted / name
            assert path.is_relative_to(mounted) and not path.is_symlink()
            path.unlink(missing_ok=True)
    command(target, '|commit %connect', args.stage + '-commit')
    if args.stage == 'baseline': command(target, '|install our %connect', 'baseline-install')
    deadline = time.monotonic() + 90
    while True:
        with urllib.request.urlopen(args.origin + '/connect/v1/info', timeout=30) as response:
            raw = response.read()
        try: info = json.loads(raw)
        except json.JSONDecodeError:
            if time.monotonic() >= deadline: raise RuntimeError('Installed test desk did not serve protocol JSON')
            time.sleep(1); continue
        break
    assert info['protocolVersion'] == 1 and info['ship'] == target['ship'] and info['development'] is False
    if args.stage == 'baseline': assert info['configured'] is False
    with urllib.request.urlopen(args.origin + '/apps/connect/', timeout=30) as response:
        assert response.status == 200 and b'<div id="app"' in response.read()
    tracking.write_text(json.dumps(sorted(names))); tracking.chmod(0o600)
    report = {'passed': True, 'stage': args.stage, 'archiveSHA256': args.sha256, 'deskFiles': len(names), 'protocolVersion': 1, 'realShip': True, 'normalSystemTLS': True, 'bundledOwnerUI': True, 'recordedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    (ROOT / (args.stage + '-install.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__': main()

"""Owned alpha fixture configuration, deliberately separate from the preserved demo."""
import errno
import hashlib
import json
import os
from pathlib import Path
import socket

ROOT = Path(__file__).resolve().parents[1]
OFFSETS = {
    'http': 0, 'runtime_https': 1, 'ames': 2, 'https': 3,
    'untrusted': 4, 'wrong_host': 5, 'control': 6, 'peer_https': 7,
    'primary_https': 8, 'unreachable': 9, 'primary_http': 10,
    'primary_runtime_https': 11, 'peer_http': 12, 'peer_runtime_https': 13,
    'primary_ames': 14, 'peer_ames': 15, 'package_http': 16,
    'package_runtime_https': 17, 'package_ames': 18,
}


class Targets:
    def __init__(self, root=ROOT, *, manifest=None, base_port=None):
        self.root = Path(root).resolve()
        digest = hashlib.sha256(str(self.root).encode()).hexdigest()
        self.fixture_id = 'alpha-' + digest[:12]
        self.work = self.root / '.work/alpha'
        self.manifest = Path(manifest) if manifest else self.work / 'targets.json'
        self.base_port = base_port if base_port is not None else 20000 + int(digest[:8], 16) % 20000
        if not 1024 <= self.base_port <= 65516:
            raise ValueError('fixture requires an unprivileged port block')

    def port(self, name):
        # Pinned Vere's local fake-galaxy routing uses 31337 + galaxy ID.
        # These two UDP listeners require exclusive ownership, never silent reuse.
        if name == 'primary_ames':
            return 31337
        if name == 'peer_ames':
            return 31338
        return self.base_port + OFFSETS[name]

    def origin(self, name='https'):
        return 'https://localhost:' + str(self.port(name))

    def state(self, name):
        if '/' in name or name in ('', '.', '..'):
            raise ValueError('one fixture state name is required')
        return self.work / name

    def value(self):
        return {
            'schemaVersion': 1, 'project': str(self.root), 'fixtureId': self.fixture_id,
            'work': str(self.work), 'ports': {name: self.port(name) for name in OFFSETS},
        }

    def require_owned(self):
        if self.manifest.is_symlink() or self.work.is_symlink():
            raise ValueError('invalid fixture manifest path')
        value = json.loads(self.manifest.read_text())
        if value.get('project') != str(self.root):
            raise ValueError('fixture belongs to a different project')
        if value != self.value() or self.manifest.resolve() != (self.work / 'targets.json').resolve():
            raise ValueError('fixture manifest does not match the owned configuration')
        return self

    def initialize(self):
        if self.manifest.exists():
            return self.require_owned()
        if self.work.is_symlink() or any(p.is_symlink() for p in self.work.parents):
            raise ValueError('fixture path must not traverse a symlink')
        # Refuse collision before writing a marker or touching any existing process.
        reservations = []
        try:
            for port in sorted({self.port(name) for name in OFFSETS}):
                for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
                    listener = socket.socket(socket.AF_INET, kind)
                    reservations.append(listener)
                    try:
                        listener.bind(('127.0.0.1', port))
                    except OSError as error:
                        if error.errno != errno.EADDRINUSE:
                            raise
                        raise ValueError(f'fixture port {port} is occupied; no process was changed') from error
            self.work.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.work.chmod(0o700)
            fd = os.open(self.manifest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w') as stream:
                stream.write(json.dumps(self.value(), indent=2) + '\n')
        finally:
            for listener in reservations:
                listener.close()
        return self


TARGETS = Targets()

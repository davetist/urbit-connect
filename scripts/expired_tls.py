"""Short-lived expired-certificate listener confined to the owned alpha fixture."""
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import ssl
import subprocess
import threading
from targets import TARGETS


@contextmanager
def serving():
    TARGETS.require_owned()
    ca = TARGETS.work / 'tls'
    root = ca / 'expired'
    if root.is_symlink(): raise ValueError('Unowned certificate directory')
    root.mkdir(mode=0o700, exist_ok=True)
    root.chmod(0o700)
    marker = {'project': str(TARGETS.root), 'fixtureId': TARGETS.fixture_id,
              'caSHA256': hashlib.sha256((ca / 'ca.crt').read_bytes()).hexdigest()}
    metadata = root / 'owner.json'
    if metadata.exists() and json.loads(metadata.read_text()) != marker:
        raise ValueError('Expired certificate belongs to another fixture')
    if not metadata.exists() and any(root.iterdir()): raise ValueError('Unowned certificate files')
    metadata.write_text(json.dumps(marker)); metadata.chmod(0o600)
    key, certificate = root / 'server.key', root / 'server.crt'
    if not certificate.exists():
        (root / 'index.txt').write_text(''); (root / 'serial').write_text('01\n')
        config = root / 'ca.conf'
        config.write_text('\n'.join([
            '[ca]', 'default_ca=fixture', '[fixture]',
            'database=' + str(root / 'index.txt'), 'serial=' + str(root / 'serial'),
            'new_certs_dir=' + str(root), 'certificate=' + str(ca / 'ca.crt'),
            'private_key=' + str(ca / 'ca.key'), 'default_md=sha256',
            'policy=names', 'x509_extensions=server', '[names]', 'commonName=supplied',
            '[server]', 'basicConstraints=critical,CA:FALSE',
            'keyUsage=critical,digitalSignature,keyEncipherment', 'extendedKeyUsage=serverAuth',
            'subjectAltName=DNS:localhost', ''
        ]))
        now = datetime.now(timezone.utc)
        with (root / 'private-setup.log').open('w') as log:
            os.chmod(log.name, 0o600)
            subprocess.run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
                            '-keyout', str(key), '-out', str(root / 'server.csr'),
                            '-subj', '/CN=localhost'], check=True, stdout=log, stderr=log)
            key.chmod(0o600)
            subprocess.run(['openssl', 'ca', '-batch', '-config', str(config),
                            '-in', str(root / 'server.csr'), '-out', str(certificate),
                            '-startdate', (now - timedelta(days=7)).strftime('%y%m%d%H%M%SZ'),
                            '-enddate', (now - timedelta(days=6)).strftime('%y%m%d%H%M%SZ')],
                           check=True, stdout=log, stderr=log)
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
        def log_message(self, *_): pass
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
    try:
        yield 'https://localhost:' + str(server.server_port)
    finally:
        server.shutdown(); server.server_close(); worker.join(timeout=5)

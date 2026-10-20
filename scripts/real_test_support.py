"""Private test controls for the specifically authorized real connect-dev target.

Uses system TLS for the app endpoint and an owned SSH tunnel for owner controls.
Never falls back to another ship or relaxes TLS. Credentials stay in the
test presenter/control process; the SDK receives only its own consent grant.
"""
from contextlib import contextmanager
import json
import shlex
import socket
import ssl
import subprocess
import sys
import time
import uuid
import urllib.error
import urllib.request
from targets import ROOT, TARGETS
from real_target import require_target, remote_tool, ssh_arguments
sys.path.insert(0, str(ROOT / 'tests/integration'))
from support import API, NoRedirect

PRIVATE = TARGETS.work / 'real-host'


class RealAPI(API):
    def __init__(self, local_origin, target):
        TARGETS.require_owned()
        require_target(target, str(ROOT))
        self.origin = local_origin; self.owner_origin = target['origin']; self.target = target
        self.opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))
        self.cookie = json.loads((PRIVATE / 'auth.json').read_text())['cookie']; self.csrf = None; self.packet_fixture=False; self.packet_run=uuid.uuid4().hex
        host = urllib.request.urlopen(local_origin + '/~/host', timeout=10).read().decode().strip()
        if host != target['ship']: raise ValueError('Real owner tunnel resolved a different ship')
        status, info, _ = self.request('/connect/v1/info')
        if status != 200 or info.get('ship') != target['ship'] or info.get('development') is not False or info.get('protocolVersion') != 1:
            raise ValueError('Real target identity/protocol did not match')

    def remote(self, arguments):
        command = shlex.join(['env', 'CONNECT_TEST_PROJECT=' + self.target['project'], *arguments])
        result = subprocess.run([*ssh_arguments(self.target), self.target['sshUser'] + '@' + self.target['sshHost'], command], capture_output=True)
        if result.returncode:
            path = PRIVATE / 'remote-failure.log'; path.write_bytes(result.stdout + result.stderr); path.chmod(0o600)
            raise RuntimeError('Real test control failed; private diagnostic retained')
        return result.stdout

    def ingress(self, enabled):
        self.remote(['systemctl', '--user', 'start' if enabled else 'stop', 'connect-dev-ingress.service'])
        if enabled:
            deadline = time.monotonic() + 30
            while True:
                try:
                    with urllib.request.urlopen(self.owner_origin + '/connect/v1/info', timeout=10) as response: info = json.load(response)
                    if info['ship'] != self.target['ship']: raise ValueError('Wrong real ingress target')
                    return
                except (OSError, ValueError):
                    if time.monotonic() >= deadline: raise RuntimeError('Real test ingress did not recover')
                    time.sleep(.3)

    def update_desk(self):
        if not self.target.get('updateSHA256'): raise ValueError('No verified update archive is selected')
        result = self.remote(['python3', remote_tool(self.target, 'real_install.py'), 'update', '--sha256', self.target['updateSHA256'], '--origin', self.owner_origin])
        report = json.loads(result.decode().splitlines()[-1])
        if report.get('passed') is not True: raise ValueError('Desk update did not pass')
        return report

    def packet_profile(self,profile):
        if profile not in ['local','100ms-1percent','500ms-5percent']:raise ValueError('Unknown network profile')
        script=remote_tool(self.target, 'netem_host.py')
        if not self.packet_fixture:
            # Bind ownership before dispatch: a lost SSH reply cannot orphan a
            # successfully started controller. Teardown reconciles this run ID.
            self.packet_fixture=True
            self.remote(['python3',script,'start',self.packet_run])
        return json.loads(self.remote(['python3',script,'profile',profile]).decode().splitlines()[-1])

    def stop_packet_fixture(self):
        if self.packet_fixture:
            self.remote(['python3',remote_tool(self.target, 'netem_host.py'),'stop',self.packet_run]);self.packet_fixture=False;self.packet_run=uuid.uuid4().hex

    def packet_status(self):
        if not self.packet_fixture:raise ValueError('No owned packet fixture is active')
        return json.loads(self.remote(['python3',remote_tool(self.target, 'netem_host.py'),'status']).decode().splitlines()[-1])


@contextmanager
def connected():
    TARGETS.require_owned()
    path = PRIVATE / 'target.json'
    if path.is_symlink(): raise ValueError('Invalid real target marker')
    target = json.loads(path.read_text())
    require_target(target, str(ROOT))
    if target.get('project') != str(ROOT) or target.get('fixtureId') != TARGETS.fixture_id or target.get('pier') != '/mnt/harbor/piers/connect-dev' or target.get('approved') is not True:
        raise ValueError('No explicitly authorized real target is bound to this fixture')
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
    log = PRIVATE / 'tunnel.log'
    arguments = [*ssh_arguments(target), '-o', 'ExitOnForwardFailure=yes', '-N', '-L', '127.0.0.1:' + str(port) + ':127.0.0.1:8080', target['sshUser'] + '@' + target['sshHost']]
    with log.open('wb') as output:
        log.chmod(0o600); process = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=output, stderr=output)
    try:
        deadline = time.monotonic() + 15
        while True:
            if process.poll() is not None: raise RuntimeError('Owned real-target tunnel failed; private diagnostic retained')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2): break
            except OSError:
                if time.monotonic() >= deadline: raise TimeoutError('Owned real-target tunnel did not start')
                time.sleep(.1)
        yield RealAPI('http://127.0.0.1:' + str(port), target)
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)

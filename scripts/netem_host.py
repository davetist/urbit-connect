"""Owned unprivileged packet-loss fixture for connect-dev's private upstream.

Run on the reference ARM64 host. All tc rules live in a new user/network
namespace; the shared host interfaces and personal ship routes are untouched.
The real app endpoint retains the existing system-trusted TLS termination.
"""
import json
import os
from pathlib import Path
import secrets
import re
import signal
import socket
import socketserver
import select
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = Path.home() / '.local/share/urbit-connect-alpha'
SOCKET = ROOT / 'netem-control.sock'
METADATA = ROOT / 'netem.json'
STARTING = ROOT / 'netem-starting.json'

def run_identity(value=None):
    value=value or secrets.token_hex(16)
    if not re.fullmatch('[a-f0-9]{32}',value):raise ValueError('Invalid owned run identity')
    return value

def outcome_path(run_id):
    return ROOT/('netem-outcome-'+run_identity(run_id)+'.json')

def require_target():
    target=json.loads((ROOT/'target.json').read_text())
    if target.get('project')!='/absolute/project' or target.get('pier')!='/mnt/harbor/piers/connect-dev':raise ValueError('Unowned network target')
    with urllib.request.urlopen('http://127.0.0.1:8080/~/host',timeout=5)as response:
        if response.read().decode().strip()!=target.get('ship'):raise ValueError('Private upstream resolved another ship')


def relay():
    slots = threading.BoundedSemaphore(64)
    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            if not slots.acquire(blocking=False): return
            try:
                with socket.create_connection(('10.0.2.2', 8080), timeout=40) as upstream:
                    self.request.settimeout(40)
                    while True:
                        ready, _, _ = select.select([self.request, upstream], [], [], 40)
                        if not ready: return
                        for source in ready:
                            raw = source.recv(65536)
                            if not raw: return
                            (upstream if source is self.request else self.request).sendall(raw)
            except OSError: pass
            finally: slots.release()
    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True
    Server(('0.0.0.0', 8081), Handler).serve_forever()


def control(value):
    metadata = json.loads(METADATA.read_text())
    assert metadata['project'] == '/absolute/project'
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(30); connection.connect(str(SOCKET))
        connection.sendall((json.dumps(value | {'secret': metadata['secret']}) + '\n').encode())
        result = json.loads(connection.makefile('rb').readline(65536))
    if 'error' in result: raise RuntimeError('Owned network fixture control failed')
    return result


def start(run_id=None):
    run_id=run_identity(run_id)
    assert not SOCKET.exists() and not METADATA.exists() and not STARTING.exists(), 'An existing packet fixture must be inspected, not reused'
    assert not outcome_path(run_id).exists(), 'A completed run cannot be silently restarted'
    require_target()
    fd=os.open(STARTING,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as stream:stream.write(json.dumps({'runID':run_id}))
    path=ROOT/'netem-supervisor.log'
    child=None
    try:
        with path.open('ab') as log:
            path.chmod(0o600)
            child=subprocess.Popen([sys.executable,__file__,'serve',run_id],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
        deadline=time.monotonic()+20
        while not METADATA.exists() or not SOCKET.exists():
            if child.poll() is not None:raise RuntimeError('Owned packet fixture did not start; private log retained')
            if time.monotonic()>=deadline:raise TimeoutError('Owned packet fixture did not become ready')
            time.sleep(.1)
        assert json.loads(METADATA.read_text())['runID']==run_id
        return control({'action':'status'})
    except Exception:
        if child is not None and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
        if child is None:STARTING.unlink(missing_ok=True)
        raise


def stop(run_id=None):
    if run_id is None:run_id=json.loads(METADATA.read_text())['runID']
    run_id=run_identity(run_id);deadline=time.monotonic()+45;requested=False
    while True:
        path=outcome_path(run_id)
        if path.exists():
            result=json.loads(path.read_text())
            if result.get('cleanupError') or not result.get('ingressRestored') or not result.get('childrenStopped'):raise RuntimeError('Packet teardown failed; private outcome retained')
            if not METADATA.exists() and not STARTING.exists() and not SOCKET.exists():return result
            if time.monotonic()>=deadline:raise TimeoutError('Owned packet markers were not removed')
            time.sleep(.1);continue
        if METADATA.exists():
            if json.loads(METADATA.read_text()).get('runID')!=run_id:raise ValueError('Refusing a different packet fixture run')
            if not requested:control({'action':'stop'});requested=True
        if STARTING.exists() and json.loads(STARTING.read_text()).get('runID')!=run_id:raise ValueError('Refusing another startup')
        if not METADATA.exists() and not STARTING.exists() and not requested:return {'stopped':True,'runID':run_id,'notStarted':True}
        if time.monotonic()>=deadline:raise TimeoutError('Owned packet teardown did not finish')
        time.sleep(.1)


def serve(run_id=None):
    run_id=run_identity(run_id)
    require_target()
    assert not SOCKET.exists() and not METADATA.exists(), 'Refusing existing fixture; inspect ownership before retrying'
    tools = ROOT / 'network-tools/sysroot'
    env = dict(os.environ, LD_LIBRARY_PATH=str(tools / 'usr/lib/aarch64-linux-gnu'))
    logs = ROOT / 'netem-private.log'; log = logs.open('ab'); logs.chmod(0o600)
    namespace=None;slirp=None
    api_socket = ROOT / ('slirp-' + secrets.token_hex(6) + '.sock')
    original = None; applied = None; profile = 'local'; secret = secrets.token_hex(32)
    def interrupted(*_): raise RuntimeError('Owned packet fixture interrupted')
    signal.signal(signal.SIGTERM,interrupted)
    signal.signal(signal.SIGINT,interrupted)

    def tc(arguments, check=True):
        assert namespace.poll() is None, 'Owned namespace is no longer alive'
        result = subprocess.run(['nsenter', '-t', str(namespace.pid), '-U', '-n', '--preserve-credentials', '--', '/usr/sbin/tc', *arguments], capture_output=True, text=True)
        if check and result.returncode: raise RuntimeError('Isolated tc operation failed: ' + result.stderr.strip()[:200])
        return result

    def set_profile(name):
        nonlocal profile
        if name not in ['local', '100ms-1percent', '500ms-5percent']: raise ValueError('Unsupported bounded network profile')
        tc(['qdisc', 'del', 'dev', 'tap0', 'root'], check=False)
        if name != 'local':
            delay, loss = ('100ms', '1%') if name == '100ms-1percent' else ('500ms', '5%')
            tc(['qdisc', 'add', 'dev', 'tap0', 'root', 'handle', '1:', 'prio'])
            tc(['qdisc', 'add', 'dev', 'tap0', 'parent', '1:1', 'handle', '10:', 'netem', 'delay', delay, 'loss', loss])
            # Only relay→Eyre TCP packets traverse netem. Replies to Caddy use
            # another band, so the upstream connection gains the named RTT.
            tc(['filter', 'add', 'dev', 'tap0', 'parent', '1:', 'protocol', 'ip', 'prio', '1', 'u32', 'match', 'ip', 'dst', '10.0.2.2/32', 'match', 'ip', 'protocol', '6', '0xff', 'match', 'ip', 'dport', '8080', '0xffff', 'flowid', '1:1'])
        profile = name
        return {'profile': profile, 'qdisc': json.loads(tc(['-s', '-j', 'qdisc', 'show', 'dev', 'tap0']).stdout), 'isolatedNamespace': True}

    try:
        namespace = subprocess.Popen(['unshare', '-Urn', sys.executable, __file__, 'relay'], stdout=log, stderr=log)
        slirp = subprocess.Popen([str(tools / 'usr/bin/slirp4netns'), '--configure', '--mtu=1500', '--api-socket=' + str(api_socket), str(namespace.pid), 'tap0'], env=env, stdout=log, stderr=log)
        deadline = time.monotonic() + 15
        while not api_socket.exists():
            if namespace.poll() is not None or slirp.poll() is not None: raise RuntimeError('Owned network helper exited; private log retained')
            if time.monotonic() >= deadline: raise TimeoutError('Owned network helper did not initialize')
            time.sleep(.1)
        with socket.socket(socket.AF_UNIX) as api:
            api.settimeout(10); api.connect(str(api_socket))
            api.sendall(json.dumps({'execute': 'add_hostfwd', 'arguments': {'proto': 'tcp', 'host_addr': '127.0.0.1', 'host_port': 36583, 'guest_addr': '10.0.2.100', 'guest_port': 8081}}).encode())
            response = json.loads(api.recv(65536)); assert 'return' in response
        import urllib.request
        while True:
            try:
                with urllib.request.urlopen('http://127.0.0.1:36583/connect/v1/info', timeout=5) as response: assert json.load(response)['development'] is False
                break
            except OSError:
                if time.monotonic() >= deadline: raise
                time.sleep(.1)
        config = ROOT / 'Caddyfile'; original = config.read_text()
        assert original.count('reverse_proxy 127.0.0.1:8080') == 1
        applied = original.replace('reverse_proxy 127.0.0.1:8080', 'reverse_proxy 127.0.0.1:36583')
        config.write_text(applied)
        reload = subprocess.run([str(ROOT / 'caddy'), 'reload', '--address', '127.0.0.1:36581', '--config', str(config), '--adapter', 'caddyfile'], stdout=log, stderr=log,timeout=10)
        assert reload.returncode == 0
        METADATA.write_text(json.dumps({'project': '/absolute/project', 'secret': secret,'runID':run_id})); METADATA.chmod(0o600)
        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                try:
                    value = json.loads(self.rfile.readline(65536))
                    assert secrets.compare_digest(value.get('secret', ''), secret)
                    if value['action'] == 'profile': result = set_profile(value['profile'])
                    elif value['action'] == 'status': result = {'profile': profile, 'qdisc': json.loads(tc(['-s', '-j', 'qdisc', 'show', 'dev', 'tap0']).stdout), 'isolatedNamespace': True,'runID':run_id}
                    elif value['action'] == 'stop':
                        result = {'stopping': True}; threading.Thread(target=server.shutdown, daemon=True).start()
                    else: raise ValueError('Unsupported network action')
                except Exception as error:
                    log.write((type(error).__name__ + ': ' + str(error) + '\n').encode()); log.flush(); result = {'error': type(error).__name__}
                self.wfile.write((json.dumps(result) + '\n').encode())
        with socketserver.ThreadingUnixStreamServer(str(SOCKET), Handler) as server:
            SOCKET.chmod(0o600); server.serve_forever()
    finally:
        outcome={'runID':run_id,'stopped':True,'ingressRestored':False,'childrenStopped':False}
        try:
            if original is not None:
                config = ROOT / 'Caddyfile'
                if config.read_text() == applied:
                    config.write_text(original)
                    subprocess.run([str(ROOT / 'caddy'), 'reload', '--address', '127.0.0.1:36581', '--config', str(config), '--adapter', 'caddyfile'], check=True, stdout=log, stderr=log,timeout=10)
                elif config.read_text() != original:
                    raise RuntimeError('Ingress changed independently; refuse to overwrite it')
            outcome['ingressRestored']=True
        except Exception as error:
            outcome['cleanupError']=type(error).__name__
            raise
        finally:
            try:
                errors=[]
                for child in [slirp, namespace]:
                    try:
                        if child is not None and child.poll() is None:
                            child.terminate()
                            try: child.wait(timeout=5)
                            except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=5)
                    except Exception as error:errors.append(error)
                if errors:raise errors[0]
                outcome['childrenStopped']=True
            except Exception as error:
                outcome['cleanupError']=type(error).__name__
                raise
            finally:
                path=outcome_path(run_id);path.write_text(json.dumps(outcome));path.chmod(0o600)
                api_socket.unlink(missing_ok=True); SOCKET.unlink(missing_ok=True); METADATA.unlink(missing_ok=True); STARTING.unlink(missing_ok=True); log.close()


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'relay': relay()
    elif mode == 'start': print(json.dumps(start(sys.argv[2]if len(sys.argv)>2 else None)))
    elif mode == 'serve': serve(sys.argv[2]if len(sys.argv)>2 else None)
    elif mode == 'profile': print(json.dumps(control({'action': 'profile', 'profile': sys.argv[2]})))
    elif mode=='stop':print(json.dumps(stop(sys.argv[2]if len(sys.argv)>2 else None)))
    elif mode=='status':print(json.dumps(control({'action':mode})))
    else: raise ValueError('Unknown owned network action')

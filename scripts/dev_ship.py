"""Private isolated Urbit development supervisor (never a product service)."""
import argparse
import json
import os
from pathlib import Path
import pty
import re
import secrets
import socket
import socketserver
import subprocess
import sys
import threading
import time
from targets import TARGETS

ROOT = Path(__file__).resolve().parents[1]
MARKER = ".connect-owned-test-state"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[su]")


def prepare_state(path: Path) -> Path:
    path = path.absolute()
    if path.is_symlink() or any(p.is_symlink() for p in path.parents):
        # macOS /var is an OS-provided alias; callers should use resolved parents.
        if path.is_symlink() or any(p.is_symlink() and str(p) != "/var" for p in path.parents):
            raise ValueError("state path must not traverse a symlink")
    if path.exists() and not (path / MARKER).is_file() and any(path.iterdir()):
        raise ValueError("refusing nonempty unowned state directory")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    marker = path / MARKER
    if marker.is_symlink():
        raise ValueError("invalid ownership marker")
    if not marker.exists():
        marker.write_text(json.dumps({"project": str(ROOT), "fixtureId": TARGETS.fixture_id, "secret": secrets.token_hex(32)}))
        marker.chmod(0o600)
    data = json.loads(marker.read_text())
    if data.get("project") != str(ROOT):
        raise ValueError("state belongs to a different project")
    if data.get('fixtureId') != TARGETS.fixture_id:
        raise ValueError('state belongs to a different fixture; the preserved demo cannot be reused')
    return path


def runtime_command(binary: Path, pill: Path, state: Path, port: int, ship: str = "zod", ames_port: int | None = None) -> list[str]:
    if ship not in ("zod", "nec"):
        raise ValueError("Only the two explicitly supported fake galaxy identities are allowed")
    if not 1024 <= port <= 65532:
        raise ValueError("use an unprivileged port with room for adjacent ports")
    if not (state / MARKER).is_file() or (state / ship).is_symlink():
        raise ValueError("runtime requires a real owned state directory")
    ames_port = port + 2 if ames_port is None else ames_port
    if not 1024 <= ames_port <= 65535:raise ValueError("Use an unprivileged Ames port")
    cmd = [str(binary), "--lmdb-map-size", "68719476736", "-b", "127.0.0.1",
           "--http-port", str(port), "--https-port", str(port + 1),
           "--ames-port", str(ames_port), "--no-dock"]
    pier = state / ship
    if pier.exists():
        cmd += ["-L", str(pier)]
    else:
        cmd += ["-F", ship, "-B", str(pill), "-c", str(pier)]
    return cmd


def rpc(state: Path, action: str, **kwargs):
    marker = state / MARKER
    if state.is_symlink() or marker.is_symlink():
        raise ValueError('invalid fixture state')
    ownership = json.loads(marker.read_text())
    if ownership.get('project') != str(ROOT) or ownership.get('fixtureId') != TARGETS.fixture_id:
        raise ValueError('refusing control of an unowned fixture')
    meta = json.loads((state / "supervisor.json").read_text())
    secret = ownership['secret']
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(float(kwargs.get("timeout", 30)) + 10)
        sock.connect(meta["socket"])
        sock.sendall((json.dumps({"secret": secret, "action": action, **kwargs}) + "\n").encode())
        stream = sock.makefile("rb")
        line = stream.readline(8 * 1024 * 1024)
        if not line:
            raise ConnectionError("test supervisor closed its socket")
        reply = json.loads(line)
    if "error" in reply:
        raise RuntimeError(reply["error"])
    return reply


def serve(state: Path, port: int, ship: str = "zod", ames_port: int | None = None):
    config = json.loads((ROOT / "toolchain.json").read_text())
    binary = ROOT / config["vere"]["localPath"]
    pill = ROOT / config["pill"]["localPath"]
    master, slave = pty.openpty()
    proc = subprocess.Popen(runtime_command(binary, pill, state, port, ship, ames_port), cwd=state,
                            stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    secret = json.loads((state / MARKER).read_text())["secret"]
    path = f"/tmp/connect-{secrets.token_hex(10)}.sock"
    buffer = bytearray()
    lock = threading.Lock()
    command_lock = threading.Lock()
    changed = [time.monotonic()]
    log = open(state / "runtime.log", "ab", buffering=0)
    os.chmod(state / "runtime.log", 0o600)

    def pump():
        try:
            while chunk := os.read(master, 65536):
                log.write(chunk)
                with lock:
                    buffer.extend(chunk)
                    changed[0] = time.monotonic()
        except OSError:
            pass

    threading.Thread(target=pump, daemon=True).start()

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            try:
                req = json.loads(self.rfile.readline(1024 * 1024))
                if not secrets.compare_digest(req.get("secret", ""), secret):
                    raise ValueError("unauthorized supervisor request")
                action = req["action"]
                if action == "status":
                    with lock:
                        ready = b"web interface live" in buffer and ("~"+ship+":dojo>").encode() in buffer
                    out = {"ready": ready, "alive": proc.poll() is None, "pid": proc.pid,
                           "http": f"http://127.0.0.1:{port}"}
                elif action == "command":
                    with command_lock:
                        command = req["command"]
                        if "\n" in command or "\r" in command or len(command) > 16000:
                            raise ValueError("one bounded Dojo command is required")
                        with lock:
                            start = len(buffer)
                        # Dojo retains failed input in its editing buffer.
                        os.write(master, ("\x01\x0b" + command + "\r").encode())
                        deadline = time.monotonic() + min(float(req.get("timeout", 30)), 240)
                        until = req.get("until")
                        while time.monotonic() < deadline:
                            time.sleep(0.1)
                            with lock:
                                content = ANSI.sub("", bytes(buffer[start:]).decode(errors="replace")).replace("\r", "")
                                quiet = time.monotonic() - changed[0] > 1.2
                            done = until in content if until else "~"+ship+":dojo>" in content
                            if done and quiet:
                                break
                            if proc.poll() is not None:
                                break
                        else:
                            raise TimeoutError("Dojo command did not settle; inspect private runtime.log")
                        out = {"output": content}
                elif action in ("stop", "crash"):
                    # Only our own Popen child can be signaled. Never trust a persisted PID.
                    if proc.poll() is None:
                        proc.kill() if action == "crash" else proc.terminate()
                        proc.wait(timeout=90)
                    out = {"exitCode": proc.returncode}
                    threading.Thread(target=server.shutdown, daemon=True).start()
                else:
                    raise ValueError("unknown supervisor operation")
            except Exception as exc:
                out = {"error": str(exc)}
            self.wfile.write((json.dumps(out) + "\n").encode())

    with socketserver.ThreadingUnixStreamServer(path, Handler) as server:
        os.chmod(path, 0o600)
        (state / "supervisor.json").write_text(json.dumps({"socket": path, "port": port}))
        os.chmod(state / "supervisor.json", 0o600)
        try:
            server.serve_forever()
        finally:
            log.close()
            os.close(master)
            Path(path).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "serve", "status", "stop", "crash", "command"])
    parser.add_argument("--state-dir", type=Path, default=TARGETS.state('dev'))
    parser.add_argument("--port", type=int, default=TARGETS.port('http'))
    parser.add_argument("--ames-port",type=int)
    parser.add_argument("--ship", choices=["zod", "nec"], default="zod")
    parser.add_argument("--command")
    parser.add_argument("--until")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--output", type=Path, help="Write potentially sensitive output privately")
    args = parser.parse_args()
    TARGETS.require_owned()
    state = prepare_state(args.state_dir)
    if args.action == "serve":
        serve(state, args.port, args.ship, args.ames_port)
        return
    if args.action == "start":
        try:
            reply = rpc(state, "status")
            if reply["alive"]:
                print(json.dumps(reply))
                return
        except (OSError, RuntimeError):
            pass
        with open(state / "supervisor.log", "ab") as log:
            subprocess.Popen([sys.executable, __file__, "serve", "--state-dir", str(state), "--port", str(args.port), "--ship", args.ship, "--ames-port", str(args.ames_port if args.ames_port is not None else args.port + 2)],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        deadline = time.monotonic() + 240
        while time.monotonic() < deadline:
            time.sleep(0.5)
            try:
                reply = rpc(state, "status")
                if not reply["alive"]:
                    raise RuntimeError("runtime exited; inspect private logs")
                if reply["ready"]:
                    print(json.dumps(reply))
                    return
            except OSError:
                pass
        raise TimeoutError("ship bootstrap not ready after 240 seconds; inspect private logs")
    kwargs = {}
    if args.action == "command":
        kwargs = {"command": args.command, "timeout": args.timeout, "until": args.until}
    reply = rpc(state, args.action, **kwargs)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(args.output, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(reply, f)
        print("Private output saved")
    else:
        print(json.dumps(reply))


if __name__ == "__main__":
    main()

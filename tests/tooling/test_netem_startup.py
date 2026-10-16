import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import netem_host


class BoundaryObserved(Exception):
    pass


class NetemStartup(unittest.TestCase):
    def exercise(self, output, *, delay=0, helper_exit=False, timeout=2):
        actual_popen = subprocess.Popen
        children = []
        launches = []
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            ready = root / 'test-relay-bound'
            starting = root / 'starting.json'
            starting.write_text(json.dumps({'runID': 'e' * 32}))
            code = ('import pathlib,sys,time\n'
                    f'time.sleep({delay!r})\n'
                    + (f'pathlib.Path({str(ready)!r}).write_text("bound")\n'
                       f'sys.stdout.buffer.write({output!r});sys.stdout.buffer.flush()\n'
                       if output is not None else '')
                    + ('time.sleep(60)\n' if output != b'' else ''))

            def launch(arguments, **kwargs):
                if arguments[0] == 'unshare':
                    child = actual_popen([sys.executable, '-c', code], **kwargs)
                else:
                    launches.append(ready.exists())
                    if not helper_exit:
                        raise BoundaryObserved()
                    child = actual_popen([sys.executable, '-c', 'raise SystemExit(17)'], **kwargs)
                children.append(child)
                return child

            error = None
            started = time.monotonic()
            try:
                with patch.multiple(netem_host, ROOT=root, SOCKET=root / 'control.sock',
                                    METADATA=root / 'metadata.json', STARTING=starting), \
                        patch.object(netem_host, 'require_target'), \
                        patch.object(netem_host.signal, 'signal'), \
                        patch.object(netem_host, 'HELPER_STARTUP_TIMEOUT', timeout, create=True), \
                        patch.object(netem_host.subprocess, 'Popen', side_effect=launch):
                    try:
                        netem_host.serve('e' * 32)
                    except Exception as failure:
                        error = failure
                elapsed = time.monotonic() - started
                outcome = json.loads((root / ('netem-outcome-' + 'e' * 32 + '.json')).read_text())
                self.assertTrue(outcome['childrenStopped'])
                self.assertTrue(outcome['ingressRestored'])
                self.assertFalse(any((root / name).exists() for name in ['control.sock', 'metadata.json', 'starting.json']))
                self.assertTrue(all(child.poll() is not None for child in children))
                if children[0].stdout is not None:
                    self.assertTrue(children[0].stdout.closed)
                return launches, error, elapsed
            finally:
                for child in children:
                    if child.poll() is None:
                        child.terminate()
                        child.wait(timeout=5)
                    if child.stdout is not None:
                        child.stdout.close()

    def test_slirp_waits_for_delayed_namespace_relay_readiness(self):
        launches, error, _ = self.exercise(b'connect-netem-relay-ready\n', delay=.1)
        self.assertEqual(launches, [True])
        self.assertIsInstance(error, BoundaryObserved)

    def test_wrong_namespace_readiness_cannot_start_slirp(self):
        launches, error, _ = self.exercise(b'wrong-ready\n')
        self.assertEqual(launches, [])
        self.assertIsInstance(error, RuntimeError)

    def test_namespace_eof_cannot_start_slirp(self):
        launches, error, _ = self.exercise(b'')
        self.assertEqual(launches, [])
        self.assertIsInstance(error, RuntimeError)

    def test_namespace_readiness_timeout_is_bounded_and_cleans_up(self):
        launches, error, elapsed = self.exercise(None, timeout=.2)
        self.assertEqual(launches, [])
        self.assertIsInstance(error, TimeoutError)
        self.assertLess(elapsed, 2)

    def test_exited_slirp_still_stops_ready_namespace_and_cleans_up(self):
        launches, error, _ = self.exercise(b'connect-netem-relay-ready\n', helper_exit=True)
        self.assertEqual(launches, [True])
        self.assertIsInstance(error, RuntimeError)


if __name__ == '__main__':
    unittest.main()

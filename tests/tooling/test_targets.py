"""Regressions for refusing cross-checkout and active-demo fixture reuse."""
import importlib.util
import json
from pathlib import Path
import socket
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))

class TargetTests(unittest.TestCase):
    def targets(self):
        import targets
        return targets

    def test_distinct_source_directories_have_distinct_fixture_identity(self):
        mod = self.targets()
        a, b = mod.Targets(Path('/tmp/source-a')), mod.Targets(Path('/tmp/source-b'))
        self.assertNotEqual(a.fixture_id, b.fixture_id)
        self.assertNotEqual(a.port('https'), b.port('https'))
        self.assertEqual(a.work, a.root / '.work/alpha')

    def test_manifest_from_another_checkout_is_rejected_before_rewrite(self):
        mod = self.targets()
        with tempfile.TemporaryDirectory() as folder:
            first = mod.Targets(Path(folder) / 'first')
            first.initialize()
            raw = first.manifest.read_bytes()
            with self.assertRaisesRegex(ValueError, 'different project'):
                mod.Targets(Path(folder) / 'second', manifest=first.manifest).initialize()
            self.assertEqual(first.manifest.read_bytes(), raw)

    def test_occupied_port_refuses_initialization_without_creating_fixture(self):
        mod = self.targets()
        with tempfile.TemporaryDirectory() as folder, socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            target = mod.Targets(Path(folder), base_port=listener.getsockname()[1])
            with self.assertRaisesRegex(ValueError, 'occupied'):
                target.initialize()
            self.assertFalse(target.manifest.exists())

    def test_manifest_rejects_tampered_port_or_path(self):
        mod = self.targets()
        with tempfile.TemporaryDirectory() as folder:
            target = mod.Targets(Path(folder)); target.initialize()
            value = json.loads(target.manifest.read_text()); value['work'] = '/tmp/active-demo'
            target.manifest.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, 'manifest'):
                target.require_owned()

    def test_old_demo_marker_is_rejected_without_changing_it(self):
        import dev_ship
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder); marker = state / dev_ship.MARKER
            marker.write_text(json.dumps({'project': str(ROOT), 'secret': 'test-secret'}))
            before = marker.read_bytes()
            with self.assertRaisesRegex(ValueError, 'fixture'):
                dev_ship.prepare_state(state)
            self.assertEqual(marker.read_bytes(), before)

if __name__ == '__main__': unittest.main()

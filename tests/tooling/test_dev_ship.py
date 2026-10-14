import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location("dev_ship", ROOT / "scripts/dev_ship.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class IsolatedShipTests(unittest.TestCase):
    def test_refuses_nonempty_unowned_state_and_does_not_modify_it(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / "precious.txt").write_text("keep")
            with self.assertRaises(ValueError):
                dev.prepare_state(p)
            self.assertEqual((p / "precious.txt").read_text(), "keep")
            self.assertEqual(len(list(p.iterdir())), 1)

    def test_refuses_symlink_state(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            (base / "actual").mkdir()
            (base / "link").symlink_to(base / "actual")
            with self.assertRaises(ValueError):
                dev.prepare_state(base / "link")

    def test_owned_state_is_private_and_can_be_reopened(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "new"
            self.assertEqual(dev.prepare_state(p), p)
            self.assertEqual(p.stat().st_mode & 0o777, 0o700)
            self.assertEqual(dev.prepare_state(p), p)

    def test_boot_targets_existing_owned_parent_and_loopback_only(self):
        with tempfile.TemporaryDirectory() as d:
            p = dev.prepare_state(Path(d) / "trial")
            cmd = dev.runtime_command(Path("/vere"), Path("/pill"), p, 18432)
            self.assertIn("-F", cmd)
            self.assertEqual(cmd[cmd.index("-b") + 1], "127.0.0.1")
            self.assertEqual(cmd[cmd.index("-c") + 1], str(p / "zod"))
            self.assertEqual(cmd[cmd.index("-B") + 1], "/pill")
            (p / "zod").mkdir()
            resumed = dev.runtime_command(Path("/vere"), Path("/pill"), p, 18432)
            self.assertNotIn("-F", resumed)
            self.assertNotIn("-c", resumed)
            self.assertEqual(resumed[-1], str(p / "zod"))


if __name__ == "__main__":
    unittest.main()

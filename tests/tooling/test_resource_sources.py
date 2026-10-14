"""Offline checks for the reusable resource consumer's shipped contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ResourceSourceTests(unittest.TestCase):
    def test_probe_contract_copies_match_connect(self):
        for relative in ('sur/connect.hoon', 'mar/connect-exchange.hoon', 'mar/connect-revoke.hoon'):
            with self.subTest(contract=relative):
                self.assertEqual((ROOT / 'integrations/grant-probe/desk' / relative).read_bytes(),
                                 (ROOT / 'desk' / relative).read_bytes())


if __name__ == '__main__': unittest.main()

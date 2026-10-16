from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import check


class CheckRunner(unittest.TestCase):
    def execute(self, output, code=0):
        with tempfile.TemporaryDirectory() as folder:
            rows = []
            completed = subprocess.CompletedProcess(['fixture'], code, stdout=output)
            with patch.object(check, 'ROOT', Path(folder)), patch.object(check, 'REPORTS', rows), \
                    patch.object(check.subprocess, 'run', return_value=completed):
                try:
                    check.run('fixture', ['fixture'], r'Ran (\d+) tests?')
                except RuntimeError:
                    return rows, False
                return rows, True

    def test_skipped_suites_cannot_pass(self):
        for ending in ['OK (skipped=1)', 'OK (skipped=12)', '1 skipped', 'ℹ skipped 1']:
            with self.subTest(ending=ending):
                rows, passed = self.execute('Ran 2 tests\n' + ending + '\n')
                self.assertFalse(passed)
                self.assertFalse(rows[0]['passed'])

    def test_zero_or_missing_cases_cannot_pass(self):
        for output in ['Ran 0 tests\nOK\n', 'OK\n']:
            with self.subTest(output=output):
                rows, passed = self.execute(output)
                self.assertFalse(passed)
                self.assertFalse(rows[0]['passed'])

    def test_nonzero_exit_cannot_pass(self):
        rows, passed = self.execute('Ran 2 tests\nOK\n', code=1)
        self.assertFalse(passed)
        self.assertFalse(rows[0]['passed'])

    def test_complete_unskipped_suite_passes(self):
        rows, passed = self.execute('Ran 2 tests\nOK (skipped=0)\n')
        self.assertTrue(passed)
        self.assertTrue(rows[0]['passed'])
        self.assertEqual(rows[0]['cases'], 2)


if __name__ == '__main__':
    unittest.main()

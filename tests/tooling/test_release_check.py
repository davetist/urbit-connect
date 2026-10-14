import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import release_check

class ReleaseTests(unittest.TestCase):
    def test_generated_web_tree_can_be_bound_without_including_private_files(self):
        actual = release_check.tree('web/dist')
        self.assertIn('web/dist/index.html', actual['files'])
        self.assertFalse(any('.work/' in path for path in actual['files']))

    def test_artifact_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            previous = release_check.ROOT
            root = Path(folder)
            for name in ['release', 'docs', 'artifacts/alpha', 'dist']:
                (root / name).mkdir(parents=True, exist_ok=True)
            artifact = root / 'dist/sdk.tgz'; artifact.write_bytes(b'first')
            release_check.ROOT = root
            try:
                value = {'manifestVersion': 1, 'version': release_check.VERSION, 'source': {}, 'evidence': {}, 'artifacts': {'sdk': {'path': 'dist/sdk.tgz', 'sha256': release_check.digest(artifact)}}}
                artifact.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'artifact'):
                    release_check.verify_manifest(value)
            finally:
                release_check.ROOT = previous

    def test_source_archive_never_copies_an_owned_fixture(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'sources.tgz'
            release_check.archive(output, ['sdk/swift'])
            import tarfile
            with tarfile.open(output) as bundle:
                names = bundle.getnames()
            self.assertTrue(any(name.endswith('ConnectClient.swift') for name in names))
            self.assertFalse(any('/.build/' in name or '/.work/' in name for name in names))

    def test_source_archive_contains_generic_resource_consumer(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'sources.tgz'
            release_check.archive(output, release_check.SOURCE_GROUPS)
            import tarfile
            with tarfile.open(output) as bundle:
                names = set(bundle.getnames())
            required = {
                'integrations/grant-probe/desk/app/grant-probe.hoon',
                'integrations/grant-probe/desk/desk.bill',
                'integrations/grant-probe/desk/sys.kelvin',
                'integrations/grant-probe/desk/sur/connect.hoon',
                'integrations/grant-probe/desk/mar/connect-exchange.hoon',
                'integrations/grant-probe/desk/mar/connect-revoke.hoon',
            }
            self.assertTrue(required.issubset(names), sorted(required - names))

if __name__ == '__main__': unittest.main()

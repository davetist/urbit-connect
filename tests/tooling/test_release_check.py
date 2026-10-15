import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import release_check
import package_desk

class ReleaseTests(unittest.TestCase):
    def owner_fixture(self, root):
        for name in ['scripts', 'release', 'web/src', 'desk/lib', 'docs']:
            (root / name).mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'scripts/bundle_web.py', root / 'scripts/bundle_web.py')
        shutil.copy2(ROOT / 'scripts/source_safety.py', root / 'scripts/source_safety.py')
        shutil.copy2(ROOT / 'web/vite.config.ts', root / 'web/vite.config.ts')
        (root / 'web/node_modules').symlink_to(ROOT / 'web/node_modules', target_is_directory=True)
        (root / 'web/package.json').write_text(json.dumps({'type': 'module', 'scripts': {'build': 'vite build'}}))
        (root / 'web/index.html').write_text('<div id="app"></div><script type="module" src="/src/main.ts"></script>')
        (root / 'web/src/main.ts').write_text('document.getElementById("app")!.textContent = "current UI";')
        manifest = root / 'release/source-files.json'
        existing = json.loads(manifest.read_text()) if manifest.exists() else []
        manifest.write_text(json.dumps(sorted(set(existing + [
            'release/source-files.json', 'web/index.html', 'web/package.json',
            'web/src/main.ts', 'web/vite.config.ts', 'desk/lib/connect-assets.hoon',
        ]))))
        subprocess.run(['npm', '--prefix', str(root / 'web'), 'run', 'build'], check=True,
                       capture_output=True, text=True)

    def test_bundle_rejects_symlinked_dist_asset(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.owner_fixture(root)
            (root / 'private.env').write_text('SYNTHETIC_TEST_SECRET=only')
            (root / 'web/dist/leak.js').symlink_to(root / 'private.env')
            result = subprocess.run([sys.executable, str(root / 'scripts/bundle_web.py')],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'desk/lib/connect-assets.hoon').exists())

    def test_bundle_check_rebuilds_source_before_accepting_dist(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.owner_fixture(root)
            script = root / 'web/src/main.ts'
            subprocess.run([sys.executable, str(root / 'scripts/bundle_web.py')], check=True,
                           capture_output=True, text=True)
            script.write_text('document.getElementById("app")!.textContent = "changed UI";')
            result = subprocess.run([sys.executable, str(root / 'scripts/bundle_web.py'), '--check'],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)

    def test_web_build_does_not_copy_unreviewed_public_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ['web/src', 'web/public']:
                (root / name).mkdir(parents=True)
            (root / 'web/node_modules').symlink_to(ROOT / 'web/node_modules', target_is_directory=True)
            shutil.copy2(ROOT / 'web/vite.config.ts', root / 'web/vite.config.ts')
            (root / 'web/package.json').write_text(json.dumps({'type': 'module', 'scripts': {'build': 'vite build'}}))
            (root / 'web/index.html').write_text('<div id="app"></div><script type="module" src="/src/main.ts"></script>')
            (root / 'web/src/main.ts').write_text('document.getElementById("app")!.textContent = "current UI";')
            (root / 'private.env').write_text('SYNTHETIC_TEST_SECRET=only')
            (root / 'web/public/leak.js').symlink_to(root / 'private.env')
            subprocess.run(['npm', '--prefix', str(root / 'web'), 'run', 'build'], check=True,
                           capture_output=True, text=True)
            self.assertFalse((root / 'web/dist/leak.js').exists())

    def test_bundle_rejects_linked_tracked_web_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ['scripts', 'release', 'web/src', 'desk/lib', 'docs']:
                (root / name).mkdir(parents=True)
            shutil.copy2(ROOT / 'scripts/bundle_web.py', root / 'scripts/bundle_web.py')
            shutil.copy2(ROOT / 'scripts/source_safety.py', root / 'scripts/source_safety.py')
            shutil.copy2(ROOT / 'web/vite.config.ts', root / 'web/vite.config.ts')
            (root / 'web/node_modules').symlink_to(ROOT / 'web/node_modules', target_is_directory=True)
            (root / 'web/package.json').write_text(json.dumps({'type': 'module', 'scripts': {'build': 'vite build'}}))
            (root / 'web/index.html').write_text('<div id="app"></div><script type="module" src="/src/main.ts"></script>')
            (root / 'private.ts').write_text('document.getElementById("app")!.textContent = "SYNTHETIC_TEST_SECRET";')
            (root / 'web/src/main.ts').symlink_to(root / 'private.ts')
            (root / 'release/source-files.json').write_text(json.dumps([
                'release/source-files.json', 'web/index.html', 'web/package.json',
                'web/src/main.ts', 'web/vite.config.ts',
            ]))
            subprocess.run(['npm', '--prefix', str(root / 'web'), 'run', 'build'], check=True,
                           capture_output=True, text=True)
            result = subprocess.run([sys.executable, str(root / 'scripts/bundle_web.py')],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'desk/lib/connect-assets.hoon').exists())

    def desk_fixture(self, root):
        for name in ['desk', 'release', 'third_party/urbit', 'third_party/landscape']:
            (root / name).mkdir(parents=True)
        (root / 'desk/sys.kelvin').write_text('[%zuse 408]')
        (root / 'release/version.json').write_text(json.dumps({'version': 'test'}))
        (root / 'LICENSE').write_text('test license')
        (root / 'third_party/urbit/LICENSE.txt').write_text('test license')
        (root / 'third_party/landscape/NOTICE.md').write_text('test notice')
        (root / 'release/source-files.json').write_text(json.dumps([
            'LICENSE', 'desk/sys.kelvin', 'release/source-files.json',
            'release/version.json', 'third_party/landscape/NOTICE.md',
            'third_party/urbit/LICENSE.txt',
        ]))

    def test_desk_package_rejects_untracked_private_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.desk_fixture(root)
            (root / 'desk/.env').write_text('SYNTHETIC_TEST_SECRET=only')
            previous = package_desk.ROOT
            package_desk.ROOT = root
            try:
                with patch.object(package_desk, 'verify_web_bundle'), self.assertRaisesRegex(ValueError, 'unreviewed'):
                    package_desk.package()
                self.assertFalse((root / 'dist/connect-test.tgz').exists())
            finally:
                package_desk.ROOT = previous

    def test_desk_package_rejects_symlinked_notice(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.desk_fixture(root)
            (root / 'private.env').write_text('SYNTHETIC_TEST_SECRET=only')
            notice = root / 'third_party/urbit/LICENSE.txt'
            notice.unlink()
            notice.symlink_to(root / 'private.env')
            previous = package_desk.ROOT
            package_desk.ROOT = root
            try:
                with patch.object(package_desk, 'verify_web_bundle'), self.assertRaises((ValueError, OSError)):
                    package_desk.package()
                self.assertFalse((root / 'dist/connect-test.tgz').exists())
            finally:
                package_desk.ROOT = previous

    def test_bundle_check_rejects_stale_assets_without_rewriting_them(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.owner_fixture(root)
            asset = root / 'desk/lib/connect-assets.hoon'
            manifest = root / 'docs/web-assets.json'
            asset.write_text('stale asset')
            manifest.write_text('stale manifest')
            result = subprocess.run([sys.executable, str(root / 'scripts/bundle_web.py'), '--check'],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(asset.read_text(), 'stale asset')
            self.assertEqual(manifest.read_text(), 'stale manifest')

    def test_gitless_source_archive_excludes_unreviewed_private_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'web').mkdir()
            (root / 'release').mkdir()
            (root / 'web/app.ts').write_text('export const example = true;')
            (root / 'web/.env').write_text('SYNTHETIC_TEST_SECRET=only')
            (root / 'web/private-notes.txt').write_text('SYNTHETIC_TEST_SECRET=only')
            (root / 'LICENSE').write_text('test license')
            (root / 'release/source-files.json').write_text(json.dumps([
                'LICENSE', 'release/source-files.json', 'web/app.ts',
            ]))
            previous = release_check.ROOT
            release_check.ROOT = root
            try:
                output = root / 'source.tgz'
                release_check.archive(output, ['web'])
                with tarfile.open(output) as bundle:
                    names = set(bundle.getnames())
                self.assertIn('web/app.ts', names)
                self.assertNotIn('web/.env', names)
                self.assertNotIn('web/private-notes.txt', names)
            finally:
                release_check.ROOT = previous

    def test_desk_package_rejects_symlinked_file_before_archiving(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.desk_fixture(root)
            (root / 'private.txt').write_text('SYNTHETIC_TEST_SECRET=only')
            (root / 'desk/leak.txt').symlink_to(root / 'private.txt')
            previous = package_desk.ROOT
            package_desk.ROOT = root
            try:
                with self.assertRaisesRegex(ValueError, 'symlink'):
                    package_desk.package()
                self.assertFalse((root / 'dist/connect-test.tgz').exists())
            finally:
                package_desk.ROOT = previous

    def test_desk_package_rejects_stale_owner_bundle(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.desk_fixture(root)
            self.owner_fixture(root)
            (root / 'desk/lib/connect-assets.hoon').write_text('stale asset')
            (root / 'docs/web-assets.json').write_text('stale manifest')
            previous = package_desk.ROOT
            package_desk.ROOT = root
            try:
                with self.assertRaisesRegex(ValueError, 'stale'):
                    package_desk.package()
                self.assertFalse((root / 'dist/connect-test.tgz').exists())
            finally:
                package_desk.ROOT = previous

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

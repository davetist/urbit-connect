import hashlib
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import real_install


class InstallPreflight(unittest.TestCase):
    def bundle(self, root, kernel=b'[%zuse 408]\n', extra=None):
        contents = {'connect/sys.kelvin': kernel, 'connect/app/connect.hoon': b'test'}
        manifest = ''.join(hashlib.sha256(raw).hexdigest() + '  ' + name[8:] + '\n'
                           for name, raw in sorted(contents.items())).encode()
        contents['MANIFEST.sha256'] = manifest
        if extra: contents.update(extra)
        path = root / 'bundle.tgz'
        with tarfile.open(path, 'w:gz') as archive:
            for name, raw in contents.items():
                info = tarfile.TarInfo(name); info.size = len(raw)
                archive.addfile(info, io.BytesIO(raw))
        return path

    def test_incompatible_kernel_is_refused_before_staging(self):
        with tempfile.TemporaryDirectory() as folder:
            for kernel in [b'[%zuse 407]', b'[%zuse 409]', b'unknown']:
                with self.subTest(kernel=kernel), self.assertRaisesRegex(ValueError, 'Kelvin'):
                    real_install.inspect_bundle(self.bundle(Path(folder), kernel), 408)

    def test_traversal_and_unmanifested_payload_are_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            for extra in [{'../outside': b'x'}, {'unexpected': b'x'}, {'connect/extra': b'x'}]:
                with self.subTest(extra=extra), self.assertRaises(ValueError):
                    real_install.inspect_bundle(self.bundle(Path(folder), extra=extra), 408)

    def test_insufficient_space_does_not_touch_the_mounted_desk(self):
        with tempfile.TemporaryDirectory() as folder:
            mounted = Path(folder); original = mounted / 'sentinel'; original.write_bytes(b'keep')
            with patch.object(real_install.shutil, 'disk_usage') as usage:
                usage.return_value.free = 1024
                with self.assertRaisesRegex(ValueError, 'space'):
                    real_install.require_space(mounted, 1024)
            self.assertEqual(original.read_bytes(), b'keep')
            self.assertEqual(list(mounted.iterdir()), [original])

    def test_manifest_and_kernel_match_produce_bounded_staging_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            entries, names = real_install.inspect_bundle(self.bundle(Path(folder)), 408)
            self.assertEqual(names, {'sys.kelvin', 'app/connect.hoon'})
            self.assertEqual(entries['connect/sys.kelvin'], b'[%zuse 408]\n')

    def test_runtime_compatibility_uses_base_not_another_installed_desk(self):
        vats = '%connect\n  /sys/kelvin: [%zuse 408]\n::\n~test:dojo> %base\n  /sys/kelvin: [%zuse 409]\n'
        self.assertEqual(real_install.runtime_kernel(vats), 409)
        with self.assertRaises(ValueError):
            real_install.runtime_kernel('%connect\n  /sys/kelvin: [%zuse 408]\n')


if __name__ == '__main__': unittest.main()

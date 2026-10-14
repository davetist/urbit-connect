from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import real_load


class RuntimeResources(unittest.TestCase):
    def test_exact_pier_and_descendants_have_memory_partition_and_start_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); proc = root / 'proc'; pier = root / 'connect-dev'
            (pier / '.urb/log').mkdir(parents=True)
            boot = proc / 'sys/kernel/random/boot_id'; boot.parent.mkdir(parents=True); boot.write_text('fixture-boot\n')
            for pid, parent, path, rss, anon, ticks in [(51, 1, str(pier), 10, 3, 123),
                                                       (52, 51, 'worker', 20, 4, 124),
                                                       (53, 1, str(pier) + '-other', 9999, 9999, 125)]:
                entry = proc / str(pid); entry.mkdir()
                (entry / 'cmdline').write_bytes(b'vere\0' + path.encode() + b'\0')
                (entry / 'status').write_text(f'PPid:\t{parent}\nVmRSS:\t{rss} kB\nRssAnon:\t{anon} kB\nRssFile:\t{rss-anon} kB\n')
                (entry / 'stat').write_text(f'{pid} (vere worker) ' + ' '.join(['S', str(parent)] + ['0'] * 17 + [str(ticks)]))
            with patch.object(real_load, 'PROC', proc), patch.object(real_load.subprocess, 'check_output', return_value='1 path\n'):
                result = real_load.resource(SimpleNamespace(target={'pier': str(pier)}))
        self.assertEqual(result['runtimeRSSBytes'], 30 * 1024)
        self.assertEqual(result['runtimeAnonymousRSSBytes'], 7 * 1024)
        self.assertEqual(result['runtimeFileRSSBytes'], 23 * 1024)
        self.assertEqual(result['runtimeProcessCount'], 2)
        self.assertEqual(result['runtimeIdentity'], {'bootId': 'fixture-boot', 'processes': [
            {'pid': 51, 'parent': 1, 'startTicks': 123}, {'pid': 52, 'parent': 51, 'startTicks': 124}]})


if __name__ == '__main__': unittest.main()

import io
import json
from pathlib import Path
import runpy
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/real_owner_login.py'
APPROVED = 'https://ship.example:8443'
sys.path.insert(0, str(SCRIPT.parent))
from real_install import private_write


class OwnerLoginDestinationTests(unittest.TestCase):
    def test_private_owner_file_replaces_symlink_with_mode_600(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            victim = root / 'unrelated.txt'
            victim.write_text('unchanged')
            target = root / 'auth.json'
            target.symlink_to(victim)
            private_write(target, 'private credential fixture')
            self.assertFalse(target.is_symlink())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(target.read_text(), 'private credential fixture')
            self.assertEqual(victim.read_text(), 'unchanged')

    def test_approved_origin_retains_owner_login_flow(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = {'project': '/absolute/project',
                      'pier': '/mnt/harbor/piers/connect-dev', 'ship': '~zod',
                      'harborShipId': 'synthetic-test-ship'}
            (root / 'target.json').write_text(json.dumps(target))
            remote = ModuleType('real_install')
            remote.ROOT = root
            remote.request = lambda path: {'pierPath': target['pier'],
                                           'identity': target['ship'], 'state': 'running'}
            remote.command = lambda *args: '~abcdef-ghijkl-mnopqr-stuvwx'
            remote.private_write = private_write
            requests = []

            class Response(io.BytesIO):
                status = 200

            class Opener:
                def open(self, request, timeout):
                    url = request.full_url if hasattr(request, 'full_url') else request
                    requests.append(url)
                    if url.endswith('/connect/v1/info'):
                        return Response(json.dumps({'ship': target['ship'], 'development': False,
                                                    'protocolVersion': 1, 'configured': False}).encode())
                    if url.endswith('/~/login'):
                        self_data = request.data.decode()
                        self_test.assertIn('password=abcdef-ghijkl-mnopqr-stuvwx', self_data)
                        return Response(b'')
                    if url.endswith('/connect/owner/v1/bootstrap'):
                        return Response(b'{"csrf":"synthetic-csrf"}')
                    if url.endswith('/connect/owner/v1/configure'):
                        return Response(b'{}')
                    raise AssertionError('Unexpected destination')

            self_test = self
            jar = [SimpleNamespace(name='urbauth', value='synthetic-cookie')]
            with patch.dict(sys.modules, {'real_install': remote}), \
                 patch.object(sys, 'argv', [str(SCRIPT), APPROVED]), \
                 patch('http.cookiejar.CookieJar', return_value=jar), \
                 patch('urllib.request.build_opener', return_value=Opener()):
                runpy.run_path(str(SCRIPT), run_name='__main__')
            self.assertEqual(requests, [APPROVED + path for path in [
                '/connect/v1/info', '/~/login', '/connect/owner/v1/bootstrap',
                '/connect/owner/v1/configure']])
            auth = root / 'auth.json'
            self.assertEqual(auth.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(auth.read_text())['cookie'], 'urbauth=synthetic-cookie')

    def test_unapproved_origin_cannot_trigger_ship_code_request(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = {'project': '/absolute/project',
                      'pier': '/mnt/harbor/piers/connect-dev', 'ship': '~zod',
                      'harborShipId': 'synthetic-test-ship'}
            (root / 'target.json').write_text(json.dumps(target))
            remote = ModuleType('real_install')
            remote.ROOT = root
            remote.request = lambda path: {'pierPath': target['pier'],
                                           'identity': target['ship'], 'state': 'running'}
            code_requests = []
            def command(*args):
                code_requests.append(args)
                return '~abcdef-ghijkl-mnopqr-stuvwx'
            remote.command = command
            remote.private_write = private_write
            class RejectPost:
                def open(self, request, timeout):
                    raise AssertionError('Credential POST reached an unapproved origin')
            spoofed = {'ship': target['ship'], 'development': False,
                       'protocolVersion': 1, 'configured': False}
            for origin in ['https://attacker.example', 'http://ship.example:8443',
                           'https://ship.example:8444', APPROVED + '.attacker.example']:
                with self.subTest(origin=origin), patch.dict(sys.modules, {'real_install': remote}), \
                     patch.object(sys, 'argv', [str(SCRIPT), origin]), \
                     patch('urllib.request.urlopen', return_value=io.BytesIO(json.dumps(spoofed).encode())), \
                     patch('urllib.request.build_opener', return_value=RejectPost()):
                    with self.assertRaisesRegex(ValueError, 'approved HTTPS origin'):
                        runpy.run_path(str(SCRIPT), run_name='__main__')
                    self.assertEqual(code_requests, [])


if __name__ == '__main__':
    unittest.main()

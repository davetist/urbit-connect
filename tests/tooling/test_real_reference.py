import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from real_reference import Reference


class Response:
    def __init__(self, status, body): self.status = status; self.body = body
    def read(self, _): return json.dumps(self.body).encode()
    def getheaders(self): return [('Set-Cookie', 'private-response-canary')]


class Connection:
    def __init__(self, response): self.response = response
    def request(self, *args): pass
    def getresponse(self): return self.response
    def close(self): pass


class InterruptedResponse(Response):
    def read(self, _): raise OSError('private-body-failure-canary')


class OversizedResponse(Response):
    def read(self, _): return b'x' * (8 * 1024 * 1024 + 1)


class ReferenceDiagnostics(unittest.TestCase):
    def test_known_status_survives_interrupted_or_oversized_response_body(self):
        for response, exception, status in [(InterruptedResponse(503, {}), RuntimeError, 503),
                                             (OversizedResponse(200, {}), AssertionError, 200)]:
            with self.subTest(status=status):
                api = Reference.__new__(Reference)
                api.origin = 'https://ship.example'
                api.cookie = 'private-cookie-canary'; api.csrf = None
                api.connection = Connection(response)
                with self.assertRaises(exception):
                    api.request('/connect/v1/mutations', 'POST', b'{}', token='private-token-canary')
                self.assertEqual(api.last_request, {'category': 'mutation', 'method': 'POST',
                                                     'status': status, 'errorCode': None})

    def test_failure_metadata_classifies_boundary_without_request_or_response_secrets(self):
        for code, expected in [('owner_required', 'owner_required'),
                               ('private_response_canary', None)]:
            with self.subTest(code=code):
                api = Reference.__new__(Reference)
                api.origin = 'https://ship.example'
                api.cookie = 'private-cookie-canary'; api.csrf = 'private-csrf-canary'
                body = {'error': {'code': code}, 'token': 'private-response-token'}
                api.connection = Connection(Response(401, body))
                self.assertEqual(api.request('/connect/owner/v1/namespaces/private-namespace/documents',
                                             owner=True), (401, body))
                self.assertEqual(getattr(api, 'last_request', None),
                                 {'category': 'owner-documents', 'method': 'GET',
                                  'status': 401, 'errorCode': expected})


if __name__ == '__main__': unittest.main()

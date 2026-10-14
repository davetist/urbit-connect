"""Live regressions on the owned alpha fake ship, never the preserved demo."""
import concurrent.futures
import json
from pathlib import Path
import sys
import time
import unittest
from support import API, ROOT
from test_documents import mutation, put
sys.path.insert(0, str(ROOT / 'scripts'))
from dev_ship import rpc
from targets import TARGETS

C = 'connect-lifecycle-test'
R = 'org.example.connect.lifecycle:/callback'

class AlphaReliabilityTests(unittest.TestCase):
    def setUp(self):
        TARGETS.require_owned()
        self.api = API(); self.api.setup()
        self.space = self.api.register(C, R, 'Lifecycle tests')['namespace']
        self.assertEqual(self.api.request('/connect/owner/v1/namespaces/' + self.space + '/erase', 'POST', {'confirmNamespace': self.space}, owner=True)[0], 200)

    def test_reload_completes_pending_poll_with_retryable_restart(self):
        token = self.api.connect(C, R)['access_token']
        status, snapshot, _ = self.api.request('/connect/v1/snapshots', 'POST', {}, token=token)
        self.assertEqual(status, 200)
        target = TARGETS.state('dev') / 'zod/connect/app/connect.hoon'
        source = (ROOT / 'desk/app/connect.hoon').read_bytes()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                waiting = pool.submit(self.api.request, '/connect/v1/changes?after=' + snapshot['atCursor'] + '&wait=25', token=token)
                time.sleep(0.4)
                self.assertFalse(waiting.done(), 'The poll must actually be pending before reload')
                target.write_bytes(b':: Alpha pending-poll reload regression.\n' + source)
                rpc(TARGETS.state('dev'), 'command', command='|commit %connect', timeout=120)
                status, body, headers = waiting.result(timeout=35)
                report = {'status': status, 'contentType': headers.get('Content-Type', headers.get('content-type')), 'classification': body.get('error', {}).get('code') if isinstance(body, dict) else None}
                (ROOT / 'artifacts/alpha/reload-response.json').write_text(json.dumps(report, indent=2) + '\n')
                self.assertEqual(status, 503)
                self.assertEqual(body['error']['code'], 'server_restarting')
            self.assertEqual(self.api.request('/connect/v1/identity', token=token)[0], 200)
        finally:
            target.write_bytes(source)
            rpc(TARGETS.state('dev'), 'command', command='|commit %connect', timeout=120)

    def test_remove_registration_fences_old_consent_tokens_and_namespace(self):
        # Reuse a fixture slot, then restore its registration for the remaining suites.
        tokens = self.api.connect(C, R)
        pending, _, verifier = self.api.begin(C, R)
        callback = self.api.approve(pending)
        old_space = tokens['grant']['namespace']
        endpoint = '/connect/owner/v1/clients/' + C + '/remove'
        status, _, _ = self.api.request(endpoint, 'POST', {'confirmClientId': C, 'confirmNamespace': old_space}, owner=True)
        self.assertEqual(status, 200)
        self.assertEqual(self.api.request('/connect/v1/identity', token=tokens['access_token'])[0], 401)
        self.assertEqual(self.api.request('/connect/oauth/token', 'POST', {'grant_type': 'authorization_code', 'client_id': C, 'redirect_uri': R, 'code': callback['code'][0], 'code_verifier': verifier}, form=True)[0], 400)
        self.assertEqual(self.api.request('/connect/owner/v1/namespaces/' + old_space + '/documents', owner=True)[0], 404)
        fresh = self.api.register(C, R, 'Lifecycle tests')
        self.assertNotEqual(fresh['namespace'], old_space)
        self.assertEqual(self.api.request('/connect/oauth/token', 'POST', {'grant_type':'refresh_token', 'client_id':C, 'refresh_token':tokens['refresh_token']}, form=True)[0], 400)
    def test_partial_client_update_cannot_reenable_a_disabled_registration(self):
        path = '/connect/owner/v1/clients/' + C
        try:
            self.assertEqual(self.api.request(path, 'POST', {'enabled': False}, owner=True)[0], 200)
            status, app, _ = self.api.request(path, 'POST', {'name': 'Renamed while disabled'}, owner=True)
            self.assertEqual(status, 200); self.assertFalse(app['enabled']); self.assertEqual(app['name'], 'Renamed while disabled')
            self.assertEqual(self.api.begin(C, R)[0][0], 400)
            self.assertEqual(self.api.request(path, 'POST', {}, owner=True)[0], 400)
            status, app, _ = self.api.request(path, 'POST', {'enabled': True}, owner=True)
            self.assertEqual(status, 200); self.assertEqual(app['name'], 'Renamed while disabled')
        finally: self.api.request(path, 'POST', {'name': 'Lifecycle tests', 'enabled': True}, owner=True)
    def test_one_public_client_cannot_fill_all_pending_consent_slots(self):
        other = 'connect-import-test'; callback = 'org.example.connect.import:/callback'
        self.api.register(other, callback)
        try:
            for _ in range(4): self.assertEqual(self.api.begin(C, R)[0][0], 302)
            self.assertEqual(self.api.begin(C, R)[0][0], 429)
            self.assertEqual(self.api.begin(other, callback)[0][0], 302)
        finally:
            for client in [C, other]: self.api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)
    def test_snapshot_saturation_of_one_app_leaves_room_for_another_reader_writer(self):
        other = 'connect-import-test'; callback = 'org.example.connect.import:/callback'
        self.api.register(other, callback)
        for client in [C, other]: self.api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)
        try:
            sessions = [self.api.connect(C, R)['access_token'] for _ in range(4)]
            token = self.api.connect(other, callback)['access_token']
            statuses = [self.api.request('/connect/v1/snapshots', 'POST', {}, token=session)[0] for session in sessions]
            self.assertEqual(statuses, [200, 200, 429, 429])
            self.assertEqual(self.api.request('/connect/v1/snapshots', 'POST', {}, token=token)[0], 200)
            self.assertEqual(self.api.request('/connect/v1/mutations', 'POST', mutation(put(data={'fairness':'progress'})), token=token)[0], 200)
        finally:
            for client in [C, other]: self.api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)

if __name__ == '__main__': unittest.main()

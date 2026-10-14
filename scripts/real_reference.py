"""Remote-only reference-host qualification primitives; never export credentials.

Run on the explicitly authorized connect-dev host. Owner cookies stay here.
Only aggregate reports may be copied back to the workspace.
"""
import base64
import hashlib
import http.client
import json
import math
from pathlib import Path
import secrets
import ssl
import statistics
import time
import urllib.parse
import urllib.request
import uuid

ROOT = Path.home() / '.local/share/urbit-connect-alpha'
ORIGIN = 'https://ship.example:8443'
CLIENT = 'connect-reference-test'
REDIRECT = 'org.example.connect.reference:/callback'
DIAGNOSTIC_ERRORS = {'owner_required', 'invalid_token', 'invalid_grant', 'invalid_request',
                     'epoch_changed', 'conflict', 'quota_exceeded', 'rate_limited',
                     'receipt_capacity', 'tombstone_capacity', 'insufficient_scope',
                     'server_restarting', 'csrf_failed', 'document_too_large'}


def operation(data, id=None, revision=None):
    return {'type': 'put', 'collection': 'notes', 'id': id or str(uuid.uuid4()), 'expectedRevision': revision, 'data': data}


def mutation(*operations): return {'requestId': str(uuid.uuid4()), 'operations': list(operations)}


def distribution(values):
    values = sorted(values)
    return {'count': len(values), 'p50Ms': round(statistics.median(values) * 1000, 2), 'p95Ms': round(values[math.ceil(len(values) * .95) - 1] * 1000, 2), 'maxMs': round(max(values) * 1000, 2)}


def private_json(name, value):
    p = ROOT / name; p.write_text(json.dumps(value, indent=2) + '\n'); p.chmod(0o600)


class Reference:
    def __init__(self):
        self.target = json.loads((ROOT / 'target.json').read_text())
        assert self.target['project'] == '/absolute/project' and self.target['pier'] == '/mnt/harbor/piers/connect-dev'
        assert urllib.request.urlopen('http://127.0.0.1:8080/~/host', timeout=10).read().decode().strip() == self.target['ship']
        self.cookie = json.loads((ROOT / 'auth.json').read_text())['cookie']; self.csrf = None
        endpoint = urllib.parse.urlsplit(ORIGIN)
        self.connection = http.client.HTTPSConnection(endpoint.hostname, endpoint.port, context=ssl.create_default_context(), timeout=40)
        status, info = self.request('/connect/v1/info'); assert status == 200
        assert info['ship'] == self.target['ship'] and info['development'] is False and info['protocolVersion'] == 1 and info['issuer'] == ORIGIN + '/connect'
        status, body = self.request('/connect/owner/v1/bootstrap', owner=True); assert status == 200; self.csrf = body['csrf']
        self.info = info

    def request(self, path, method='GET', data=None, owner=False, token=None, form=False):
        category = ('owner-documents' if '/owner/' in path and '/documents' in path else
                    'mutation' if path == '/connect/v1/mutations' else
                    'token' if path == '/connect/oauth/token' else 'other-connect')
        self.last_request = {'category': category, 'method': method, 'status': None, 'errorCode': None}
        headers = {}
        if owner:
            headers = {'Cookie': self.cookie, 'Origin': ORIGIN}
            if self.csrf: headers['X-Connect-CSRF'] = self.csrf
        if token: headers['Authorization'] = 'Bearer ' + token
        if data is None: raw = None
        elif form: raw = urllib.parse.urlencode(data).encode(); headers['Content-Type'] = 'application/x-www-form-urlencoded'
        else: raw = data if isinstance(data, bytes) else json.dumps(data, separators=(',', ':')).encode(); headers['Content-Type'] = 'application/json'
        try:
            self.connection.request(method, path, raw, headers); response = self.connection.getresponse()
            self.last_request['status'] = response.status
            body = response.read(8 * 1024 * 1024 + 1)
        except (OSError, http.client.HTTPException):
            self.connection.close(); raise RuntimeError('Reference transport unavailable') from None
        assert len(body) <= 8 * 1024 * 1024
        try: value = json.loads(body)
        except (ValueError, UnicodeDecodeError): value = {'unparsed': True}
        error = value.get('error') if isinstance(value, dict) else None
        error = error.get('code') if isinstance(error, dict) else error
        self.last_request['errorCode'] = error if isinstance(error, str) and error in DIAGNOSTIC_ERRORS else None
        self.headers = dict(response.getheaders())
        return response.status, value

    def register(self, client=CLIENT, redirect=REDIRECT):
        status, result = self.request('/connect/owner/v1/clients', 'POST', {'id': client, 'name': 'Owned reference qualification', 'redirectURI': redirect}, owner=True)
        if status == 409:
            status, result = self.request('/connect/owner/v1/clients', owner=True); assert status == 200
            return next(row for row in result['clients'] if row['id'] == client)
        assert status == 200; return result

    def connect(self, client=CLIENT, redirect=REDIRECT, allow_capacity=False):
        verifier = secrets.token_urlsafe(32); state = secrets.token_urlsafe(32)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
        args = {'response_type': 'code', 'client_id': client, 'redirect_uri': redirect, 'scope': 'documents:read documents:write documents:delete', 'state': state, 'code_challenge': challenge, 'code_challenge_method': 'S256'}
        status, _ = self.request('/connect/oauth/authorize?' + urllib.parse.urlencode(args)); assert status == 302
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.headers.get('Location', self.headers.get('location', ''))).query)
        status, callback = self.request('/connect/owner/v1/consents/' + query['consent'][0], 'POST', {'decision': 'approve'}, owner=True); assert status == 200
        values = urllib.parse.parse_qs(urllib.parse.urlsplit(callback['redirect']).query); assert values['state'] == [state]
        status, grant = self.request('/connect/oauth/token', 'POST', {'grant_type': 'authorization_code', 'client_id': client, 'redirect_uri': redirect, 'code': values['code'][0], 'code_verifier': verifier}, form=True)
        if allow_capacity: return status, grant
        assert status == 200; return grant

    def erase(self, space):
        assert self.request('/connect/owner/v1/namespaces/' + space + '/erase', 'POST', {'confirmNamespace': space}, owner=True)[0] == 200

    def refresh(self, grant):
        status, result = self.request('/connect/oauth/token', 'POST', {'grant_type': 'refresh_token', 'client_id': grant['grant']['clientId'], 'refresh_token': grant['refresh_token']}, form=True)
        assert status == 200 and result['grant'] == grant['grant']; return result

    def documents(self, space):
        status, rows = self.request('/connect/owner/v1/namespaces/' + space + '/documents', owner=True); assert status == 200; return rows['documents']


def prepare():
    api = Reference(); app = api.register(); space = app['namespace']
    api.erase(space); grant = api.connect()
    body = json.dumps(mutation(operation({'check': 'acknowledged-before-update'})), separators=(',', ':')).encode()
    status, receipt = api.request('/connect/v1/mutations', 'POST', body, token=grant['access_token']); assert status == 200
    assert api.request('/connect/v1/mutations', 'POST', body, token=grant['access_token']) == (200, receipt)
    queued = json.dumps(mutation(operation({'check': 'unsent-before-update'})), separators=(',', ':')).encode()
    private_json('reference-state.json', {'target': api.target, 'namespace': space, 'grant': grant, 'info': api.info, 'acknowledgedBody': base64.b64encode(body).decode(), 'receipt': receipt, 'queuedBody': base64.b64encode(queued).decode()})
    print(json.dumps({'baselineGrantAndReceiptPrepared': True, 'acknowledgedRecords': 1, 'queuedRequestsHeldPrivately': 1, 'credentialsExported': False}))


def verify_update():
    api = Reference(); saved = json.loads((ROOT / 'reference-state.json').read_text()); assert saved['target'] == api.target
    assert (ROOT / 'update-install.json').is_file()
    for key in ['issuer', 'instanceId', 'syncEpoch', 'ship']: assert api.info[key] == saved['info'][key]
    grant = saved['grant']; status, _ = api.request('/connect/v1/identity', token=grant['access_token'])
    if status == 401: grant = api.refresh(grant)
    else: assert status == 200
    body = base64.b64decode(saved['acknowledgedBody']); assert api.request('/connect/v1/mutations', 'POST', body, token=grant['access_token']) == (200, saved['receipt'])
    queued = base64.b64decode(saved['queuedBody']); status, receipt = api.request('/connect/v1/mutations', 'POST', queued, token=grant['access_token']); assert status == 200
    assert api.request('/connect/v1/mutations', 'POST', queued, token=grant['access_token']) == (200, receipt)
    assert len(api.documents(saved['namespace'])) == 2
    report = {'passed': True, 'realShip': True, 'fromDeskVersion': '0.1.0', 'toDeskVersion': '0.2.0-alpha.1', 'baselineArchiveSHA256': json.loads((ROOT / 'baseline-install.json').read_text())['archiveSHA256'], 'updateArchiveSHA256': json.loads((ROOT / 'update-install.json').read_text())['archiveSHA256'], 'instanceAndGenerationRetained': True, 'sameSessionRetained': True, 'acknowledgedReceiptRetained': True, 'queuedCreateEffects': 1, 'normalSystemTLS': True, 'independentOperatorPending': True}
    private_json('reference-update.json', report); print(json.dumps(report))


if __name__ == '__main__':
    import sys
    if sys.argv[1] == 'prepare': prepare()
    elif sys.argv[1] == 'verify-update': verify_update()
    else: raise ValueError('Unknown reference action')

"""Live generic resource-contract tests on an explicitly owned disposable fake ship.

Requires Connect already installed/configured. Installs only grant-probe, whose
fixed response tests authorization plumbing rather than a complete notes app.
No adapter modules, credentials, endpoints, clients or defaults are used.
"""
import argparse
import base64
import hashlib
import json
import secrets
import ssl
import urllib.error
import urllib.parse
import urllib.request
from resource_fixture import Fixture, hoon_text

RESOURCE = 'resource-contract'
DOCUMENT = 'resource-document'
REDIRECT = 'http://localhost:18065/callback'
DOCUMENT_REDIRECT = 'org.example.resource-contract:/callback'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class API:
    def __init__(self, fixture):
        self.fixture = fixture
        self.cookie = json.loads(fixture.owner_file.read_text())['cookie'] + '; connect-fixture-tests=1'
        self.csrf = None
        self.opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(
            context=ssl.create_default_context(cafile=fixture.ca)))

    def call(self, path, data=None, *, owner=False, token=None, form=False):
        headers = {}
        if owner:
            headers.update(Cookie=self.cookie, Origin=self.fixture.origin)
            if self.csrf:
                headers['X-Connect-CSRF'] = self.csrf
        if token:
            headers['Authorization'] = 'Bearer ' + token
        raw = None
        if data is not None:
            headers['Content-Type'] = 'application/x-www-form-urlencoded' if form else 'application/json'
            raw = (urllib.parse.urlencode(data) if form else json.dumps(data)).encode()
        request = urllib.request.Request(self.fixture.origin + path, data=raw, headers=headers)
        try:
            response = self.opener.open(request, timeout=35)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read()
            try:
                body = json.loads(raw)
            except ValueError:
                body = None
            return response.status, body, dict(response.headers)

    def begin(self, client, redirect, scope):
        verifier = secrets.token_urlsafe(32)
        query = {'response_type': 'code', 'client_id': client, 'redirect_uri': redirect,
                 'scope': scope, 'state': secrets.token_urlsafe(32), 'code_challenge_method': 'S256',
                 'code_challenge': base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()}
        return self.call('/connect/oauth/authorize?' + urllib.parse.urlencode(query), owner=True), query, verifier

    def code(self, client, redirect, scope):
        (status, _, headers), query, verifier = self.begin(client, redirect, scope)
        require(status == 302, 'authorization redirect')
        consent = urllib.parse.parse_qs(urllib.parse.urlsplit(headers.get('Location', headers.get('location'))).query)['consent'][0]
        status, body, _ = self.call('/connect/owner/v1/consents/' + consent, {'decision': 'approve'}, owner=True)
        require(status == 200, 'owner approval')
        callback = urllib.parse.urlsplit(body['redirect'])
        require(callback._replace(query='').geturl() == redirect, 'approved exact callback')
        params = urllib.parse.parse_qs(callback.query)
        require(params['state'][0] == query['state'], 'callback state')
        return params['code'][0], verifier


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def exchange_payload(client, code, redirect, verifier):
    return {'grant_type': 'authorization_code', 'client_id': client, 'code': code,
            'redirect_uri': redirect, 'code_verifier': verifier}


def exchange(fixture, client, code, redirect, verifier):
    values = ' '.join(hoon_text(value) for value in ['contract-test', client, code, redirect, verifier])
    fixture.poke('grant-probe', 'connect-exchange', '[' + values + ']')
    return fixture.scry('grant-probe', 'result')


def run(fixture):
    fixture.verify_ship()
    api = API(fixture)
    status, info, _ = api.call('/connect/v1/info')
    require(status == 200 and info['development'] and info['protocolVersion'] == 1
            and info['configured'] and info['issuer'] == fixture.origin + '/connect',
            'configured development origin must match the selected fixture')
    status, body, _ = api.call('/connect/owner/v1/bootstrap', owner=True)
    require(status == 200, 'owner bootstrap')
    api.csrf = body['csrf']
    status, body, _ = api.call('/connect/owner/v1/clients', owner=True)
    require(status == 200, 'client inventory')
    require(not any(item['id'] in (RESOURCE, DOCUMENT) for item in body['clients']),
            'reserved test client IDs already exist; select a fresh fixture')
    require(len(body['clients']) <= 6, 'fixture needs two free client slots')
    fixture.install_probe()
    checks = []

    def passed(name):
        checks.append(name)
        print('PASS:', name, flush=True)

    created = []
    try:
        resource = {'id': RESOURCE, 'name': 'Generic resource contract', 'redirectURI': REDIRECT,
                    'integration': {'agent': 'grant-probe', 'scopes': ['notes:read'], 'redirectURIs': [REDIRECT]}}
        invalid = dict(resource, integration=dict(resource['integration'], scopes=['documents:read']))
        require(api.call('/connect/owner/v1/clients', invalid, owner=True)[0] == 400, 'document scope cannot be a resource scope')
        invalid = dict(resource, redirectURI=REDIRECT + '/')
        require(api.call('/connect/owner/v1/clients', invalid, owner=True)[0] == 400, 'primary callback must be allowlisted')
        status, registered, _ = api.call('/connect/owner/v1/clients', resource, owner=True)
        require(status == 200, 'resource registration')
        created.append(registered)
        document = {'id': DOCUMENT, 'name': 'Generic document contract', 'redirectURI': DOCUMENT_REDIRECT}
        status, registered, _ = api.call('/connect/owner/v1/clients', document, owner=True)
        require(status == 200, 'document registration')
        created.append(registered)
        for callback in [REDIRECT + '/', REDIRECT.replace('18065', '18066'), 'http://evil.example:18065/callback']:
            require(api.begin(RESOURCE, callback, 'notes:read')[0][0] == 400, 'callback binding')
        for scope in ['documents:read', 'api']:
            require(api.begin(RESOURCE, REDIRECT, scope)[0][0] == 400, 'resource scope binding')
        passed('registration, exact callback and resource scope binding')

        code, verifier = api.code(RESOURCE, REDIRECT, 'notes:read')
        require(api.call('/connect/oauth/token', exchange_payload(RESOURCE, code, REDIRECT, verifier), form=True)[0] == 400,
                'HTTP cannot exchange a resource authorization code')
        values = ' '.join(hoon_text(value) for value in ['wrong-caller', RESOURCE, code, REDIRECT, verifier])
        try:
            fixture.poke('connect', 'connect-exchange', '[' + values + ']')
        except RuntimeError:
            pass
        else:
            raise AssertionError('Direct Khan caller must not impersonate the registered Gall resource')
        for altered in [('unregistered-client', code, REDIRECT, verifier), (RESOURCE, code, REDIRECT + '/', verifier),
                        (RESOURCE, code, REDIRECT, 'A' * 43)]:
            result = exchange(fixture, *altered)
            require(result == 'exchange-rejected' or isinstance(result, dict) and result['status'] == 400,
                    'wrong client, callback or PKCE rejected')
        result = exchange(fixture, RESOURCE, code, REDIRECT, verifier)
        require(isinstance(result, dict) and result['status'] == 200, 'valid local resource exchange')
        sid = result['grant']['sessionId']
        require(exchange(fixture, RESOURCE, code, REDIRECT, verifier)['status'] == 400, 'single-use authorization code')
        require(fixture.scry('grant-probe', 'notes/' + sid) is not None, 'live resource access')
        require(fixture.scry('connect', 'integration/another-resource/' + sid) is None, 'other resource cannot use grant')
        # Forged %json replies must not replace the real Connect result.
        before = fixture.scry('grant-probe', 'result')
        try:
            fixture.poke('grant-probe', 'json', "[%s 'forged-result']")
        except RuntimeError:
            pass
        else:
            raise AssertionError('Resource accepted a response without /gall/connect provenance')
        require(fixture.scry('grant-probe', 'result') == before, 'forged reply left resource result unchanged')
        passed('local caller and response provenance, PKCE binding and single-use codes')

        legacy_token = fixture.json_expression("[%s (scot %uv (shas %access (need (slaw %uv " + hoon_text(sid) + "))))]")
        for path, data in [('/connect/v1/identity', None), ('/connect/oauth/revoke', {}),
                           ('/connect/v1/collections/notes/documents', None), ('/connect/v1/mutations', {}),
                           ('/connect/v1/snapshots', {}), ('/connect/v1/changes?after=1:1:0', None)]:
            for token in [sid, legacy_token]:
                require(api.call(path, data, token=token)[0] == 401, 'resource ID and legacy-derived token cannot access HTTP: ' + path)
        require(fixture.scry('grant-probe', 'notes/' + sid) is not None, 'HTTP revoke cannot revoke resource grant')
        passed('resource grant isolation from ordinary HTTP identity, revoke and document routes')

        code, verifier = api.code(DOCUMENT, DOCUMENT_REDIRECT, 'documents:read documents:write')
        status, auth, _ = api.call('/connect/oauth/token', exchange_payload(DOCUMENT, code, DOCUMENT_REDIRECT, verifier), form=True)
        require(status == 200, 'ordinary document exchange')
        status, identity, _ = api.call('/connect/v1/identity', token=auth['access_token'])
        require(status == 200, 'ordinary document identity')
        document_sid = identity['grant']['sessionId']
        fixture.poke('grant-probe', 'connect-revoke', '[%grant-probe ' + hoon_text(document_sid) + ']')
        require(api.call('/connect/v1/identity', token=auth['access_token'])[0] == 200, 'resource cannot revoke a document grant')
        fixture.poke('grant-probe', 'connect-revoke', '[%another-resource ' + hoon_text(sid) + ']')
        require(fixture.scry('grant-probe', 'notes/' + sid) is not None, 'resource cannot spoof revoke caller')
        fixture.poke('grant-probe', 'connect-revoke', '[%grant-probe ' + hoon_text(sid) + ']')
        require(fixture.scry('grant-probe', 'notes/' + sid) is None, 'own resource revoke')
        fixture.poke('grant-probe', 'connect-revoke', '[%grant-probe ' + hoon_text(sid) + ']')
        passed('resource scry and caller-bound idempotent revoke isolation')

        status, rotated, _ = api.call('/connect/oauth/token', {'grant_type': 'refresh_token', 'client_id': DOCUMENT,
                                                            'refresh_token': auth['refresh_token']}, form=True)
        require(status == 200, 'ordinary refresh')
        require(api.call('/connect/v1/identity', token=rotated['access_token'])[0] == 200, 'rotated document identity')
        require(api.call('/connect/oauth/revoke', {}, token=rotated['access_token'])[0] == 200, 'ordinary HTTP revoke')
        require(api.call('/connect/v1/identity', token=rotated['access_token'])[0] == 401, 'ordinary revoked token denied')
        code, verifier = api.code(DOCUMENT, DOCUMENT_REDIRECT, 'documents:read')
        status, auth, _ = api.call('/connect/oauth/token', exchange_payload(DOCUMENT, code, DOCUMENT_REDIRECT, verifier), form=True)
        require(status == 200, 'ordinary reauthorization')
        refresh = {'grant_type': 'refresh_token', 'client_id': DOCUMENT, 'refresh_token': auth['refresh_token']}
        status, rotated, _ = api.call('/connect/oauth/token', refresh, form=True)
        require(status == 200 and api.call('/connect/oauth/token', refresh, form=True)[0] == 400, 'strict refresh reuse rejection')
        require(api.call('/connect/v1/identity', token=rotated['access_token'])[0] == 401, 'refresh reuse revokes the grant')
        code, verifier = api.code(RESOURCE, REDIRECT, 'notes:read')
        result = exchange(fixture, RESOURCE, code, REDIRECT, verifier)
        require(result['status'] == 200, 'resource reauthorization')
        sid = result['grant']['sessionId']
        require(api.call('/connect/owner/v1/revoke', {'sessionId': sid}, owner=True)[0] == 200, 'owner revoke')
        require(fixture.scry('grant-probe', 'notes/' + sid) is None, 'owner revoke takes effect at the resource')
        passed('ordinary document identity, HTTP revoke, strict refresh reuse and owner resource revoke')
        return {'checks': checks, 'count': len(checks), 'consumer': 'grant-probe fixed-response test agent'}
    finally:
        for registered in reversed(created):
            status, _, _ = api.call('/connect/owner/v1/clients/' + registered['id'] + '/remove',
                                    {'confirmClientId': registered['id'], 'confirmNamespace': registered['namespace']}, owner=True)
            require(status == 200, 'cleanup of this run test registration')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['fixture-dir', 'fixture-id', 'origin', 'ca', 'owner-file', 'control-socket', 'vere']:
        parser.add_argument('--' + name, required=True)
    args = vars(parser.parse_args())
    args['directory'] = args.pop('fixture_dir')
    fixture = Fixture(**args)
    report = run(fixture)
    target = fixture.directory / 'generic-contract.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    target.chmod(0o600)
    print(f"PASS: {report['count']} generic resource-contract groups; private report saved")


if __name__ == '__main__':
    main()

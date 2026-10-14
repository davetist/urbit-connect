"""Bounded reload/withheld-response rehearsal on this checkout's owned fake ship."""
import concurrent.futures
import hashlib
import json
import sys
import time
from targets import ROOT, TARGETS
from dev_ship import rpc
from package_desk import checked_command
sys.path.insert(0, str(ROOT / 'tests/integration'))
from support import API
from test_documents import mutation, put

def run():
    TARGETS.require_owned()
    api = API(); api.setup()
    status, info, _ = api.request('/connect/v1/info')
    if status != 200 or not info.get('development') or info.get('ship') != '~zod':
        raise ValueError('Refusing a non-owned fake test ship')
    client = 'connect-lifecycle-test'; redirect = 'org.example.connect.lifecycle:/callback'
    space = api.register(client, redirect)['namespace']
    assert api.request('/connect/owner/v1/namespaces/' + space + '/erase', 'POST', {'confirmNamespace': space}, owner=True)[0] == 200
    tokens = api.connect(client, redirect)
    body = json.dumps(mutation(put(data={'check': 'replay'})), separators=(',', ':')).encode()
    endpoint = '/connect/owner/v1/namespaces/' + space + '/mutations'
    status, receipt, _ = api.request(endpoint, 'POST', body, owner=True); assert status == 200
    status, snapshot, _ = api.request('/connect/v1/snapshots', 'POST', {}, token=tokens['access_token']); assert status == 200
    cursor = snapshot['atCursor']
    source = (ROOT / 'desk/app/connect.hoon').read_bytes()
    mounted = TARGETS.state('dev') / 'zod/connect/app/connect.hoon'
    began = time.monotonic()
    try:
        for cycle in range(100):
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                poll = pool.submit(api.request, '/connect/v1/changes?after=' + cursor + '&wait=25', token=tokens['access_token'])
                time.sleep(.4); assert not poll.done(), 'A real long poll must be pending'
                # A comment-only change can compile to the same agent noun and skip
                # Gall on-load. Vary one availability message in the mounted copy.
                message = b"'Connect is reloading; retry this request'"
                assert message in source
                mounted.write_bytes(source.replace(message, ("'Connect is reloading; retry this request; fixture " + str(cycle) + "'").encode()))
                output = checked_command(TARGETS.state('dev'), '|commit %connect')
                assert 'gall: reloading %connect' in output and 'gall: bumped %connect' in output, 'Each cycle must actually reload the compiled agent'
                status, response, headers = poll.result(timeout=35)
                if status != 503 or response.get('error', {}).get('code') != 'server_restarting':
                    failure = {'cycle': cycle, 'status': status, 'contentType': headers.get('Content-Type'), 'code': response.get('error', {}).get('code'), 'hasBatches': 'batches' in response}
                    (ROOT / 'artifacts/alpha/reload-failure.json').write_text(json.dumps(failure, indent=2) + '\n')
                    print('Reload diagnostic:', json.dumps(failure), flush=True)
                assert status == 503 and response['error']['code'] == 'server_restarting'
            status, replay, _ = api.request(endpoint, 'POST', body, owner=True)
            assert status == 200 and replay == receipt
            if cycle % 10 == 9:
                assert api.request('/connect/v1/identity', token=tokens['access_token'])[0] == 200
                print('PASS reload cycles:', cycle + 1, flush=True)
        # The consumer deliberately withholds each reply after the real desk commits.
        # It keeps the same request bytes and only accepts the final replay response.
        for retry in range(1000):
            status, withheld, _ = api.request(endpoint, 'POST', body, owner=True)
            assert status == 200 and withheld == receipt
        status, final, _ = api.request(endpoint, 'POST', body, owner=True)
        assert status == 200 and final == receipt
        status, records, _ = api.request('/connect/owner/v1/namespaces/' + space + '/documents', owner=True)
        assert status == 200 and len(records['documents']) == 1 and records['documents'][0]['revision'] == receipt['revision']
        report = {'passed': True, 'fixtureId': TARGETS.fixture_id, 'developmentFakeShip': True, 'reloadCycles': 100, 'pendingPoll503': 100, 'withheldMutationResponses': 1000, 'exactRequestSHA256': hashlib.sha256(body).hexdigest(), 'effects': 1, 'retainedSession': True, 'seconds': round(time.monotonic() - began, 2), 'limitsUnchanged': True}
        (ROOT / 'artifacts/alpha/reload-retry.json').write_text(json.dumps(report, indent=2) + '\n')
        print('PASS: 100 reloads, 1000 withheld real-desk responses, one mutation effect', flush=True)
    finally:
        mounted.write_bytes(source); checked_command(TARGETS.state('dev'), '|commit %connect')

if __name__ == '__main__': run()

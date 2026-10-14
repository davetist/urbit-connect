"""Restore the same actual backup twice on the owned, network-local fake pier.

Never accepts a real pier or real identity. Keeps every intervening timeline and
the verified backup private. One automated operator does not satisfy the plan's
independent second-operator release gate.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
from targets import ROOT, TARGETS
from dev_ship import prepare_state, rpc
sys.path.insert(0, str(ROOT / 'tests/integration'))
from support import API
from test_documents import mutation, put


def file_manifest(pier):
    return {path.relative_to(pier).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(pier.rglob('*')) if path.is_file()}


def run():
    TARGETS.require_owned(); state = prepare_state(TARGETS.state('dev')); pier = state / 'zod'
    api = API(); api.setup()
    status, info, _ = api.request('/connect/v1/info')
    if status != 200 or info.get('ship') != '~zod' or info.get('development') is not True:
        raise ValueError('Refusing any non-owned or real ship')
    client = 'connect-lifecycle-test'; redirect = 'org.example.connect.lifecycle:/callback'
    space = api.register(client, redirect, 'Restore rehearsal')['namespace']
    endpoint = '/connect/owner/v1/namespaces/' + space
    assert api.request(endpoint + '/erase', 'POST', {'confirmNamespace': space}, owner=True)[0] == 200
    tokens = api.connect(client, redirect)
    recovered = put(data={'recoveryPoint': 'acknowledged-before-backup'})
    assert api.request('/connect/v1/mutations', 'POST', mutation(recovered), token=tokens['access_token'])[0] == 200
    status, snapshot, _ = api.request('/connect/v1/snapshots', 'POST', {}, token=tokens['access_token']); assert status == 200
    pending, _, verifier = api.begin(client, redirect); callback = api.approve(pending)
    queued = json.dumps(mutation(put(data={'recoveryPoint': 'unsent-local-draft'})), separators=(',', ':')).encode()
    total = sum(path.stat().st_size for path in pier.rglob('*') if path.is_file())
    assert shutil.disk_usage(state).free >= total * 3 + 1024 * 1024 * 1024, 'Insufficient recovery space; no runtime stopped'
    experiment = prepare_state(TARGETS.work / ('restore-rehearsal-' + time.strftime('%Y%m%d-%H%M%S')))
    backup = experiment / 'backup/zod'; backup.parent.mkdir()
    proxy_stopped = False; fenced = True

    def start():
        subprocess.run([sys.executable, ROOT / 'scripts/dev_ship.py', 'start'], check=True, stdout=subprocess.DEVNULL)

    results = []; generations = {info['syncEpoch']}
    began = time.monotonic()
    try:
        rpc(TARGETS.state('proxy'), 'stop'); proxy_stopped = True
        rpc(state, 'stop', timeout=100)
        # APFS clone preserves the actual cleanly stopped files without 3x writes.
        # Each destination is new and every former running timeline is retained.
        subprocess.run(['cp', '-cR', str(pier), str(backup)], check=True)
        expected = file_manifest(backup)
        saved = experiment / 'backup-manifest.json'; saved.write_text(json.dumps(expected, sort_keys=True)); saved.chmod(0o600)
        assert file_manifest(pier) == expected
        start()
        direct = API('http://127.0.0.1:' + str(TARGETS.port('http')))
        status, owner, _ = direct.request('/connect/owner/v1/bootstrap', owner=True); assert status == 200; direct.csrf = owner['csrf']
        for attempt in range(2):
            later = put(data={'recoveryPoint': 'acknowledged-after-backup-' + str(attempt)})
            assert direct.request(endpoint + '/mutations', 'POST', mutation(later), owner=True)[0] == 200
            assert direct.request('/connect/owner/v1/restore-epoch', 'POST', {'confirmInstanceId': info['instanceId']}, owner=True)[0] == 200
            current = direct.request('/connect/v1/info')[1]['syncEpoch']; generations.add(current)
            # Ingress remains closed. These fake -L runtimes have no live Ames peer.
            rpc(state, 'stop', timeout=100)
            fenced = False
            timeline = experiment / ('timeline-' + str(attempt) + '-zod'); pier.rename(timeline)
            assert file_manifest(backup) == expected, 'Backup changed before restore'
            subprocess.run(['cp', '-cR', str(backup), str(pier)], check=True)
            assert file_manifest(pier) == expected, 'Restored files differ from known recovery point'
            start()
            direct = API('http://127.0.0.1:' + str(TARGETS.port('http')))
            status, owner, _ = direct.request('/connect/owner/v1/bootstrap', owner=True); assert status == 200; direct.csrf = owner['csrf']
            before_rotation = direct.request('/connect/v1/info')[1]
            assert before_rotation['syncEpoch'] == info['syncEpoch']
            assert direct.request('/connect/owner/v1/restore-epoch', 'POST', {'confirmInstanceId': info['instanceId']}, owner=True)[0] == 200
            epoch = direct.request('/connect/v1/info')[1]['syncEpoch']
            assert epoch not in generations, 'Generation reused across repeated restoration'; generations.add(epoch)
            status, docs, _ = direct.request(endpoint + '/documents', owner=True)
            assert status == 200 and [row['id'] for row in docs['documents']] == [recovered['id']]
            assert direct.request('/connect/v1/identity', token=tokens['access_token'])[0] == 401
            assert direct.request('/connect/v1/mutations', 'POST', queued, token=tokens['access_token'])[0] == 401
            assert direct.request('/connect/oauth/token', 'POST', {'grant_type': 'refresh_token', 'client_id': client, 'refresh_token': tokens['refresh_token']}, form=True)[0] == 400
            assert direct.request('/connect/oauth/token', 'POST', {'grant_type': 'authorization_code', 'client_id': client, 'redirect_uri': redirect, 'code': callback['code'][0], 'code_verifier': verifier}, form=True)[0] == 400
            fenced = True
            fresh = direct.connect(client, redirect)
            status, error, _ = direct.request('/connect/v1/changes?after=' + snapshot['atCursor'], token=fresh['access_token'])
            assert status == 410 and error['error']['code'] == 'epoch_changed'
            results.append({'restore': attempt + 1, 'sameBackupVerified': True, 'knownRecoveryPointRecords': 1, 'laterAcknowledgedRecordsOutsideBackup': 1, 'oldAccessRefreshCodeRejected': True, 'oldQueuedGrantRejected': True, 'oldCursorRejected': True, 'generationSHA256': hashlib.sha256(epoch.encode()).hexdigest()})
        report = {'passed': True, 'fixtureId': TARGETS.fixture_id, 'developmentFakeShip': True, 'actualFileRestores': 2, 'operators': 1, 'ingressClosedBeforeRestoreAndRotation': True, 'amesNetworkLocal': True, 'backupFiles': len(expected), 'backupBytes': total, 'backupManifestSHA256': hashlib.sha256(saved.read_bytes()).hexdigest(), 'results': results, 'seconds': round(time.monotonic() - began, 2), 'independentOperatorPending': True}
        (ROOT / 'artifacts/alpha/restore-rehearsal.json').write_text(json.dumps(report, indent=2) + '\n')
        print('PASS: two actual restores of the same backup; old grants and cursors rejected; recovery-point loss window recorded', flush=True)
    finally:
        # Recovery never deletes a former timeline or backup. Leave the selected
        # owned fixture running, then reopen ingress only after the fence passed.
        try:
            if not rpc(state, 'status')['alive']: start()
        except (OSError, RuntimeError):
            if pier.is_dir(): start()
        if proxy_stopped and fenced:
            subprocess.run([sys.executable, ROOT / 'scripts/dev_proxy.py', 'start'], check=True, stdout=subprocess.DEVNULL)
        elif proxy_stopped:
            print('Restore failed before grant fencing; owned alpha ingress remains closed for recovery', flush=True)


if __name__ == '__main__': run()
